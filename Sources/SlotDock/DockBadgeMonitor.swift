import AppKit
import ApplicationServices
import Darwin
import SlotDockCore

/// Live Dock notification badges.
///
/// Launch Services `StatusLabel` is the same source `lsappinfo` exposes and does
/// not need Accessibility. Messages / WhatsApp often omit that key; when the
/// process is already trusted we fill those holes from Dock `AXStatusLabel`
/// plus `AXURL` (path/bundle match, not title-only).
///
/// There is no public badge-changed notification, so a 1s timer is the honest
/// refresh path. Reads are coalesced and publish only on change.
@MainActor
final class DockBadgeMonitor: ObservableObject {
    @Published private(set) var snapshot = DockBadgeSnapshot.empty
    /// Canonical app path → sidecar token (`chatgpt`, `codex-dark`, …).
    @Published private(set) var liveIconTokens: [String: String] = [:]
    /// Date+locale key so Calendar tiles redraw at midnight without a relaunch.
    @Published private(set) var calendarIconKey = CalendarDockIcon.iconCacheKey()

    /// Prompt for Accessibility when Messages/WhatsApp badges need Dock AX.
    var onRequestAccessibility: (() -> Void)?

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var running = false
    private var collectBadges = true
    private var lastAXEntries: [DockAXBadgeEntry] = []
    private var axRefreshCounter = 0
    private var refreshCount = 0
    private var publishCount = 0
    private var didPromptAccessibility = false
    private var stripIdentities: [AppIdentity] = []
    private let interval: TimeInterval = 1.0
    private static let accessibilityPromptDefaultsKey = "badgeAccessibilityPrompted"

    /// Always-on live icon tokens (ChatGPT ↔ Codex). Badge collection is optional.
    func start() {
        guard !running else { return }
        running = true
        refresh(reason: "start")
        startTimer()
        startObservers()
    }

    func setCollectBadges(_ on: Bool) {
        let changed = collectBadges != on
        collectBadges = on
        if !on {
            lastAXEntries = []
            if snapshot != .empty { snapshot = .empty }
        }
        if running, changed {
            refresh(reason: on ? "badges-on" : "badges-off")
            if on { requestAccessibilityIfNeeded() }
        }
    }

    func setEnabled(_ on: Bool) {
        if on {
            start()
            setCollectBadges(true)
        } else {
            setCollectBadges(false)
        }
    }

    func invalidate() {
        running = false
        collectBadges = false
        stopTimer()
        stopObservers()
        lastAXEntries = []
        if snapshot != .empty { snapshot = .empty }
        if !liveIconTokens.isEmpty { liveIconTokens = [:] }
        SlotDockTelemetry.badge.info("DockBadgeMonitor stopped")
    }

    func refresh(reason: String = "manual") {
        guard running else { return }
        refreshCount += 1
        let next: DockBadgeSnapshot
        if collectBadges {
            axRefreshCounter += 1
            let includeAX = axRefreshCounter % 3 == 1
            next = SlotDockTelemetry.measure("badge.refresh", thresholdMS: 12) {
                if includeAX {
                    lastAXEntries = AXIsProcessTrusted() ? DockAXBadges.entries() : []
                } else if !AXIsProcessTrusted() {
                    lastAXEntries = []
                }
                return DockBadgeMerge.merging(
                    launchServices: LaunchServicesBadges.snapshot(),
                    accessibility: lastAXEntries
                )
            }
        } else {
            next = .empty
        }
        let tokens = SlotDockTelemetry.measure("icon.liveToken", thresholdMS: 12) {
            AppBundleIconResolver.liveTokensForRunningApps()
        }
        var changed = false
        if next != snapshot {
            snapshot = next
            changed = true
        }
        if tokens != liveIconTokens {
            liveIconTokens = tokens
            changed = true
        }
        let nextCalendarKey = CalendarDockIcon.iconCacheKey()
        if nextCalendarKey != calendarIconKey {
            calendarIconKey = nextCalendarKey
            SlotIconCache.invalidateAll()
            changed = true
            SlotDockTelemetry.iconCache.info(
                "calendar icon key=\(nextCalendarKey, privacy: .public)"
            )
        }
        requestAccessibilityIfNeeded()
        if changed {
            publishCount += 1
            if publishCount == 1 || publishCount % 10 == 0 {
                SlotDockTelemetry.badge.info(
                    "badges bundles=\(next.byBundle.count, privacy: .public) titles=\(next.byTitle.count, privacy: .public) liveIcons=\(tokens.count, privacy: .public) reason=\(reason, privacy: .public)"
                )
            }
        }
    }

    func badge(for slot: Slot) -> DockBadge? {
        snapshot.badge(for: slot)
    }

    func liveIconToken(for slot: Slot) -> String {
        let path = SystemDockEntry.canonicalIdentityPath(slot.target).lowercased()
        return liveIconTokens[path] ?? ""
    }

    func progress(for slot: Slot) -> Double? {
        snapshot.progress(for: slot)
    }

    func noteStripIdentities(_ identities: [AppIdentity]) {
        stripIdentities = identities
        requestAccessibilityIfNeeded()
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(reason: "timer")
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startObservers() {
        stopObservers()
        func observe(_ name: Notification.Name, center: NotificationCenter = .default, reason: String) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh(reason: reason)
                }
            }
            observers.append(token)
        }
        observe(
            Notification.Name("AppleInterfaceThemeChangedNotification"),
            center: DistributedNotificationCenter.default(),
            reason: "appearance"
        )
        observe(.NSCalendarDayChanged, reason: "calendar-day")
        observe(.NSSystemClockDidChange, reason: "clock")
        observe(NSLocale.currentLocaleDidChangeNotification, reason: "locale")
    }

    private func stopObservers() {
        let center = NotificationCenter.default
        let distributed = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
            distributed.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func requestAccessibilityIfNeeded() {
        guard running, collectBadges, !didPromptAccessibility else { return }
        guard !SlotDockHeadless.isHeadless else { return }
        guard !AXIsProcessTrusted() else { return }
        let runningIDs = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        guard DockBadgeAXFill.shouldRequestAccessibility(
            stripIdentities: stripIdentities,
            runningBundleIDs: runningIDs
        ) else { return }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.accessibilityPromptDefaultsKey) { return }
        didPromptAccessibility = true
        defaults.set(true, forKey: Self.accessibilityPromptDefaultsKey)
        SlotDockTelemetry.badge.info("requesting Accessibility for Messages/WhatsApp Dock badges")
        onRequestAccessibility?()
    }

}

// MARK: - Launch Services StatusLabel

enum LaunchServicesBadges {
    private static let sessionID: Int32 = -2
    private typealias CopyRunning = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopyItem = @convention(c) (Int32, UnsafeRawPointer, CFString) -> Unmanaged<CFTypeRef>?

    private static let copyRunning: CopyRunning? = {
        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/LaunchServices",
            RTLD_LAZY
        ), let symbol = dlsym(handle, "_LSCopyRunningApplicationArray") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CopyRunning.self)
    }()

    private static let copyItem: CopyItem? = {
        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/LaunchServices",
            RTLD_LAZY
        ), let symbol = dlsym(handle, "_LSCopyApplicationInformationItem") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CopyItem.self)
    }()

    static func snapshot() -> DockBadgeSnapshot {
        guard let copyRunning, let copyItem else { return .empty }
        guard let raw = copyRunning(sessionID)?.takeRetainedValue() else { return .empty }
        let asns = raw as [AnyObject]
        var byBundle: [String: DockBadge] = [:]
        var byPath: [String: DockBadge] = [:]
        var byTitle: [String: DockBadge] = [:]
        var progressByBundle: [String: Double] = [:]
        var progressByPath: [String: Double] = [:]
        let selfBundle = Bundle.main.bundleIdentifier?.lowercased()

        for asnObject in asns {
            let asn = Unmanaged.passUnretained(asnObject).toOpaque()
            let bundle = (copyItem(sessionID, asn, "CFBundleIdentifier" as CFString)?.takeRetainedValue() as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let bundle, let selfBundle, bundle.lowercased() == selfBundle { continue }

            let status = copyItem(sessionID, asn, "StatusLabel" as CFString)?.takeRetainedValue()
            let badge = DockBadgeParser.parseStatusLabel(status)
            let progress = DockBadgeParser.parseProgress(
                copyItem(sessionID, asn, "ProgressPercent" as CFString)?.takeRetainedValue()
            )
            guard badge != nil || progress != nil else { continue }

            let path = copyItem(sessionID, asn, "LSBundlePath" as CFString)?.takeRetainedValue() as? String
            let title = copyItem(sessionID, asn, "LSDisplayName" as CFString)?.takeRetainedValue() as? String
            if let badge {
                if let bundle, !bundle.isEmpty { byBundle[bundle] = badge }
                if let path, path.lowercased().hasSuffix(".app") { byPath[path] = badge }
                if let title, !title.isEmpty { byTitle[title] = badge }
            }
            if let progress {
                if let bundle, !bundle.isEmpty { progressByBundle[bundle] = progress }
                if let path, path.lowercased().hasSuffix(".app") { progressByPath[path] = progress }
            }
        }
        return DockBadgeSnapshot(
            byBundle: byBundle,
            byPath: byPath,
            byTitle: byTitle,
            progressByBundle: progressByBundle,
            progressByPath: progressByPath
        )
    }
}

// MARK: - Dock AXStatusLabel (trusted processes only)

enum DockAXBadges {
    static func entries() -> [DockAXBadgeEntry] {
        guard AXIsProcessTrusted() else { return [] }
        let docks = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
        guard let dock = docks.first, !dock.isTerminated else { return [] }

        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let list = firstChild(of: app, role: "AXList") else { return [] }
        guard let children = copyAttribute(list, kAXChildrenAttribute as String) as? [AXUIElement] else {
            return []
        }

        var out: [DockAXBadgeEntry] = []
        for item in children {
            let role = copyAttribute(item, kAXRoleAttribute as String) as? String
            guard role == "AXDockItem" || role == nil else { continue }
            let subrole = copyAttribute(item, kAXSubroleAttribute as String) as? String
            if subrole == "AXSeparatorDockItem" || subrole == "AXTrashDockItem" { continue }
            guard let title = copyAttribute(item, kAXTitleAttribute as String) as? String,
                  !title.isEmpty
            else { continue }
            let raw = copyAttribute(item, "AXStatusLabel")
            guard let badge = DockBadgeParser.parseStatusLabel(raw) else { continue }
            let path = appPath(from: copyAttribute(item, kAXURLAttribute as String))
            let bundle = path.flatMap { AppIdentity.bundleIdentifier(forAppPath: $0) }
            out.append(
                DockAXBadgeEntry(
                    title: title,
                    path: path,
                    bundleIdentifier: bundle,
                    badge: badge
                )
            )
        }
        return out
    }

    private static func appPath(from raw: Any?) -> String? {
        let path: String?
        if let url = raw as? URL {
            path = url.path
        } else if let url = raw as? NSURL {
            path = url.path
        } else if let string = raw as? String {
            if string.hasPrefix("file://"), let url = URL(string: string) {
                path = url.path
            } else {
                path = string
            }
        } else {
            path = nil
        }
        guard let path, !path.isEmpty else { return nil }
        let canonical = SystemDockEntry.canonicalIdentityPath(path)
        guard canonical.lowercased().hasSuffix(".app") else { return nil }
        return canonical
    }

    private static func firstChild(of element: AXUIElement, role: String) -> AXUIElement? {
        guard let children = copyAttribute(element, kAXChildrenAttribute as String) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let childRole = copyAttribute(child, kAXRoleAttribute as String) as? String, childRole == role {
                return child
            }
        }
        return children.first
    }

    private static func copyAttribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success else { return nil }
        return value
    }
}

enum DockAXWindowTitles {
    struct Window {
        var title: String
        var windowNumber: Int?
        var element: AXUIElement
    }

    @MainActor
    static func titles(for app: NSRunningApplication) -> [String] {
        windows(for: app).map(\.title)
    }

    @MainActor
    static func windows(for app: NSRunningApplication) -> [Window] {
        guard AXIsProcessTrusted(), !app.isTerminated else { return [] }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        guard error == .success, let windows = value as? [AXUIElement] else { return [] }
        var out: [Window] = []
        for window in windows {
            var raw: AnyObject?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &raw) == .success,
                  let title = raw as? String,
                  !title.isEmpty
            else { continue }
            var number: Int?
            var numRef: AnyObject?
            if AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &numRef) == .success {
                number = numRef as? Int ?? (numRef as? NSNumber)?.intValue
            }
            out.append(Window(title: title, windowNumber: number, element: window))
        }
        return out
    }

    @MainActor
    @discardableResult
    static func raise(app: NSRunningApplication, windowNumber: Int?, title: String) -> Bool {
        let listed = windows(for: app)
        let candidates = listed.map { (windowNumber: $0.windowNumber, title: $0.title) }
        guard let index = SlotContextMenuBuilder.WindowRaiseMatcher.pickIndex(
            candidates: candidates,
            targetNumber: windowNumber,
            targetTitle: title
        ), listed.indices.contains(index)
        else { return false }
        let error = AXUIElementPerformAction(listed[index].element, kAXRaiseAction as CFString)
        return error == .success
    }

    @MainActor
    @discardableResult
    static func raiseAll(app: NSRunningApplication) -> Bool {
        let listed = windows(for: app)
        var any = false
        for window in listed {
            if AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) == .success {
                any = true
            }
        }
        return any
    }
}
