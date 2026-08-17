import AppKit
import Foundation
import SlotDockCore
import SwiftUI

/// App-facing store: bridges pure SlotDockCore to UI + NSWorkspace launch.
@MainActor
final class SlotDockStore: ObservableObject {
    /// User-defined custom slots (persisted).
    @Published private(set) var slots: [Slot] = []
    /// Live system Dock apps (not persisted; re-read from com.apple.dock).
    @Published private(set) var systemDockEntries: [SystemDockEntry] = []
    /// Composed strip items (system + custom per integration mode).
    @Published private(set) var displayItems: [SlotComposer.Item] = []
    @Published private(set) var preferences: DockPreferences = .default
    @Published var reveal = RevealState.collapsed
    @Published var settingsOpen = false
    @Published var settingsTab: SettingsTab = .slots
    /// When set, Settings → Slots should focus this custom slot for editing.
    @Published var pendingEditSlotID: String?
    @Published var lastLaunchError: String?
    @Published var configurationError: String?
    @Published var safeAreaError: String?
    @Published var launchFlashSlotID: String?
    /// Last global-hotkey registration report (Carbon failures surface here for Settings).
    @Published private(set) var hotkeyReport = HotkeyRegistrationReport()

    enum SettingsTab: String, CaseIterable, Identifiable {
        case slots
        case options

        var id: String { rawValue }
        var title: String {
            switch self {
            case .slots: return "Slots"
            case .options: return "Options"
            }
        }
    }

    let core: SlotStore
    private let openHandler: (OpenPayload) -> Bool
    private let systemDockPlistURL: URL
    private var flashClearWork: DispatchWorkItem?

    var configurationReadOnly: Bool { core.isReadOnly }

    init(
        configURL: URL = SlotStore.defaultConfigURL(),
        openHandler: ((OpenPayload) -> Bool)? = nil,
        systemDockPlistURL: URL = SystemDockReader.defaultPlistURL
    ) {
        self.core = SlotStore(fileURL: configURL)
        self.openHandler = openHandler ?? Self.defaultOpen
        self.systemDockPlistURL = systemDockPlistURL
        self.slots = core.slots
        self.preferences = core.preferences
        self.configurationError = core.lastError?.localizedDescription
        if slots.isEmpty {
            seedDefaultsIfEmpty()
        }
        refreshSystemDock()
    }

    func reload() {
        _ = core.reload()
        slots = core.slots
        preferences = core.preferences
        configurationError = core.lastError?.localizedDescription
        refreshSystemDock()
    }

    /// Latest running snapshot used for optional transient strip icons (set by monitor).
    private var runningSnapshot = RunningAppSnapshot()

    /// Re-read `com.apple.dock` and recompose the strip.
    @discardableResult
    func refreshSystemDock() -> [SystemDockEntry] {
        SlotDockTelemetry.measure("refreshSystemDock", thresholdMS: 1, alwaysLog: false) {
            systemDockEntries = SystemDockReader.readPersistentApps(from: systemDockPlistURL)
            recomposeDisplay()
        }
        SlotDockTelemetry.systemDock.info(
            "System Dock apps=\(self.systemDockEntries.count, privacy: .public) mode=\(self.preferences.systemDockIntegration.rawValue, privacy: .public) display=\(self.displayItems.count, privacy: .public) transient=\(self.preferences.showTransientRunningApps, privacy: .public)"
        )
        return systemDockEntries
    }

    /// Apply a new running snapshot (from RunningAppsMonitor).
    /// - Returns: `true` when composed strip membership changed (needs geometry relayout).
    /// Recompose on any snapshot change: same-bundle other-path copies are
    /// independent of the transient-extras preference. Dots still update via
    /// the monitor `@Published` snapshot when membership is unchanged.
    @discardableResult
    func applyRunningSnapshot(_ snapshot: RunningAppSnapshot) -> Bool {
        let changed = snapshot != runningSnapshot
        runningSnapshot = snapshot
        guard changed else { return false }
        let before = displayItems
        recomposeDisplay()
        let stripChanged = before != displayItems
        SlotDockTelemetry.running.debug(
            "recompose from running display=\(self.displayItems.count, privacy: .public) stripChanged=\(stripChanged, privacy: .public)"
        )
        return stripChanged
    }

    private func recomposeDisplay() {
        displayItems = SlotDockTelemetry.measure("recomposeDisplay", thresholdMS: 0.5) {
            SlotComposer.compose(
                custom: slots,
                system: systemDockEntries,
                mode: preferences.systemDockIntegration,
                runningApps: runningSnapshot.apps,
                includeRunningExtras: preferences.showTransientRunningApps
            )
        }
    }

    func setShowTransientRunningApps(_ on: Bool) {
        updatePreferences { $0.showTransientRunningApps = on }
        recomposeDisplay()
        SlotDockTelemetry.preferences.info("showTransientRunningApps=\(on, privacy: .public)")
    }

    private func afterSlotsChanged() {
        slots = core.slots
        configurationError = core.lastError?.localizedDescription
        recomposeDisplay()
    }

    // MARK: - Slots

    @discardableResult
    func addSlot(label: String, target: String, iconPath: String? = nil) -> Slot? {
        let slot = core.add(label: label, target: target, iconPath: iconPath)
        afterSlotsChanged()
        return core.lastError == nil ? slot : nil
    }

    @discardableResult
    func updateSlot(id: String, label: String?, target: String?, iconPath: String??) -> Slot? {
        let updated = core.update(id: id, label: label, target: target, iconPath: iconPath)
        afterSlotsChanged()
        return core.lastError == nil ? updated : nil
    }

    @discardableResult
    func removeSlot(id: String) -> Bool {
        let ok = core.remove(id: id)
        afterSlotsChanged()
        return ok
    }

    func reorder(from: Int, to: Int) {
        _ = core.reorder(from: from, to: to)
        afterSlotsChanged()
    }

    func replaceAll(_ next: [Slot]) {
        core.replaceAll(next)
        afterSlotsChanged()
    }

    /// System Dock entries not yet present as custom slots (for Slots-tab UI).
    var importableSystemDockEntries: [SystemDockEntry] {
        SlotComposer.importableSystemEntries(system: systemDockEntries, custom: slots)
    }

    func isSystemEntryAlreadyCustom(_ entry: SystemDockEntry) -> Bool {
        SlotComposer.isAlreadyCustom(entry: entry, custom: slots)
    }

    /// Copy one live system Dock app into durable custom slots (skip if duplicate).
    @discardableResult
    func importSystemDockEntry(_ entry: SystemDockEntry) -> Slot? {
        guard !SlotComposer.isAlreadyCustom(entry: entry, custom: slots) else { return nil }
        let slot = addSlot(label: entry.label, target: entry.path)
        guard let slot else { return nil }
        SlotDockTelemetry.systemDock.info("Imported system Dock app \(entry.label, privacy: .private)")
        return slot
    }

    /// Import from a drag payload (path or path+label) using live Dock metadata when possible.
    @discardableResult
    func importFromDockDragPayload(_ raw: String) -> Slot? {
        guard let decoded = SystemDockDragPayload.decode(raw) else { return nil }
        if let entry = SlotComposer.entryMatchingPath(decoded.path, in: systemDockEntries) {
            return importSystemDockEntry(entry)
        }
        // Not on system Dock list but a valid path — still allow as custom slot.
        guard !SlotComposer.isAlreadyCustom(
            entry: SystemDockEntry(label: decoded.label, path: decoded.path),
            custom: slots
        ) else { return nil }
        return addSlot(label: decoded.label, target: decoded.path)
    }

    /// Copy system Dock apps into durable custom slots (skip duplicates).
    @discardableResult
    func importSystemDockAsCustomSlots() -> Int {
        let importable = SlotComposer.importableSystemEntries(system: systemDockEntries, custom: slots)
        var imported = 0
        for entry in importable {
            if addSlot(label: entry.label, target: entry.path) != nil {
                imported += 1
            }
        }
        SlotDockTelemetry.systemDock.info("Imported \(imported, privacy: .public) system Dock apps as custom slots")
        return imported
    }

    // MARK: - Preferences

    @discardableResult
    func updatePreferences(_ mutate: (inout DockPreferences) -> Void) -> Bool {
        preferences = core.updatePreferences(mutate)
        configurationError = core.lastError?.localizedDescription
        recomposeDisplay()
        SlotDockTelemetry.preferences.debug("Preferences updated")
        return core.lastError == nil
    }

    func setSystemDockIntegration(_ mode: SystemDockIntegration) {
        updatePreferences { $0.systemDockIntegration = mode }
        refreshSystemDock()
    }

    func setShowSystemDockDivider(_ on: Bool) {
        updatePreferences { $0.showSystemDockDivider = on }
    }

    func setShowRunningDots(_ on: Bool) {
        updatePreferences { $0.showRunningDots = on }
        SlotDockTelemetry.preferences.info("showRunningDots=\(on, privacy: .public)")
    }

    func setShowNotificationBadges(_ on: Bool) {
        updatePreferences { $0.showNotificationBadges = on }
        SlotDockTelemetry.preferences.info("showNotificationBadges=\(on, privacy: .public)")
    }

    func setSafeAreaPadding(_ on: Bool) {
        if updatePreferences({ $0.safeAreaPadding = on }) {
            NotificationCenter.default.post(name: .slotDockSafeAreaPreferenceDidChange, object: nil)
        }
    }

    func setSafeAreaExtraGap(_ gap: Double) {
        if updatePreferences({ $0.safeAreaExtraGap = gap }) {
            NotificationCenter.default.post(name: .slotDockSafeAreaPreferenceDidChange, object: nil)
        }
    }

    func dismissCollisionGuide() {
        updatePreferences { $0.collisionGuideDismissed = true }
    }

    func setIconSize(_ size: DockPreferences.IconSize) {
        updatePreferences { $0.iconSize = size }
    }

    func setAutoHide(_ on: Bool) {
        let persisted = updatePreferences { $0.autoHide = on }
        if persisted, preferences.autoHide {
            NotificationCenter.default.post(name: .slotDockCollisionPromptMayNeed, object: nil)
        }
    }

    func setPinOpen(_ on: Bool) {
        let persisted = updatePreferences {
            $0.pinOpen = on
            if on { $0.autoHide = false }
        }
        if preferences.pinOpen, !reveal.isRevealed {
            beginReveal()
        }
        if persisted {
            NotificationCenter.default.post(name: .slotDockSafeAreaPreferenceDidChange, object: nil)
        }
        if persisted, preferences.pinOpen {
            NotificationCenter.default.post(name: .slotDockCollisionPromptMayNeed, object: nil)
        }
    }

    func setEdgeHover(_ on: Bool) {
        updatePreferences { $0.edgeHover = on }
    }

    func setEdgeTriggerHeight(_ height: Double) {
        let clamped = DockPreferences.clampEdgeTriggerHeight(height)
        updatePreferences { $0.edgeTriggerHeight = clamped }
        SlotDockTelemetry.preferences.info("edgeTriggerHeight=\(clamped, privacy: .public)pt")
    }

    func setEdgeHorizontalOvershoot(_ overshoot: Double) {
        let clamped = DockPreferences.clampEdgeHorizontalOvershoot(overshoot)
        updatePreferences { $0.edgeHorizontalOvershoot = clamped }
        SlotDockTelemetry.preferences.info("edgeHorizontalOvershoot=\(clamped, privacy: .public)pt")
    }

    func setRevealBaseDuration(_ duration: Double) {
        let clamped = DockPreferences.clampRevealBaseDuration(duration)
        updatePreferences { $0.revealBaseDuration = clamped }
        SlotDockTelemetry.preferences.info("revealBaseDuration=\(clamped, privacy: .public)s")
    }

    func setIconSpacing(_ spacing: Double) {
        let clamped = DockPreferences.clampIconSpacing(spacing)
        updatePreferences { $0.iconSpacing = clamped }
        SlotDockTelemetry.preferences.info("iconSpacing=\(clamped, privacy: .public)pt")
    }

    func setShowLabels(_ on: Bool) {
        updatePreferences { $0.showLabels = on }
    }

    func setShowIconTooltips(_ on: Bool) {
        updatePreferences { $0.showIconTooltips = on }
        SlotDockTelemetry.preferences.info("showIconTooltips=\(on, privacy: .public)")
    }

    /// Open macOS System Settings → Desktop & Dock (user-facing shortcut).
    func openMacDockSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Desktop-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.dock",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                SlotDockTelemetry.preferences.info("Opened Mac Dock settings")
                return
            }
        }
        // Fallback: open System Settings app
        let fallback = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        if !NSWorkspace.shared.open(fallback) {
            lastLaunchError = "Could not open macOS System Settings."
        }
    }

    func setAlignment(_ alignment: DockPreferences.Alignment) {
        updatePreferences { $0.alignment = alignment }
    }

    func setAutoHideDelay(_ delay: Double) {
        let clamped = DockPreferences.clampDelay(delay)
        updatePreferences { $0.autoHideDelay = clamped }
        SlotDockTelemetry.preferences.info("autoHideDelay=\(clamped, privacy: .public)s")
    }

    func setAutoHideLeaveMargin(_ margin: Double) {
        let clamped = DockPreferences.clampAutoHideLeaveMargin(margin)
        updatePreferences { $0.autoHideLeaveMargin = clamped }
        SlotDockTelemetry.preferences.info("autoHideLeaveMargin=\(clamped, privacy: .public)pt")
    }

    func setLaunchFeedback(_ on: Bool) {
        updatePreferences { $0.launchFeedback = on }
    }

    func setShowStatusItem(_ on: Bool) {
        if updatePreferences({ $0.showStatusItem = on }) {
            NotificationCenter.default.post(name: .slotDockStatusItemPreferenceDidChange, object: nil)
        }
    }

    func setShowInFullScreen(_ on: Bool) {
        if updatePreferences({ $0.showInFullScreen = on }) {
            NotificationCenter.default.post(name: .slotDockWindowBehaviorDidChange, object: nil)
        }
    }

    /// Persist launch-at-login desire and apply SMAppService when possible.
    /// Returns an optional user-facing status/error string.
    @discardableResult
    func setLaunchAtLogin(_ on: Bool) -> String? {
        guard !core.isReadOnly else {
            let message = core.lastError?.localizedDescription ?? "Configuration is read-only."
            configurationError = message
            return message
        }
        updatePreferences { $0.launchAtLogin = on }
        if let error = core.lastError {
            let message = error.localizedDescription
            configurationError = message
            lastLaunchError = message
            return message
        }
        let msg = LaunchAtLogin.applyPreference(on)
        if let msg, !msg.isEmpty {
            lastLaunchError = msg
        } else if configurationError == nil {
            lastLaunchError = nil
        }
        SlotDockTelemetry.preferences.info(
            "launchAtLogin=\(on, privacy: .public) status=\(LaunchAtLogin.status.description, privacy: .public)"
        )
        return msg
    }

    /// Apply persisted preference at launch (no write if already matching).
    func syncLaunchAtLoginFromPreferences() {
        guard !core.isReadOnly else {
            configurationError = core.lastError?.localizedDescription
            return
        }
        let msg = LaunchAtLogin.applyPreference(preferences.launchAtLogin)
        if let msg, !msg.isEmpty {
            lastLaunchError = msg
            SlotDockTelemetry.preferences.warning("Launch-at-login sync failed: \(msg, privacy: .private)")
        }
    }

    /// Drop handler: resolve raw path/URL and append custom slot (skip exact target dupes).
    @discardableResult
    func addSlotFromDrop(_ raw: String) -> DropPathResolver.Outcome {
        let outcome = DropPathResolver.resolve(raw)
        switch outcome {
        case .accept(let c):
            let norm = SystemDockEntry.canonicalIdentityPath(c.target).lowercased()
            if slots.contains(where: { SystemDockEntry.canonicalIdentityPath($0.target).lowercased() == norm }) {
                lastLaunchError = "Already on strip: \(c.label)"
                return .reject("Already on strip: \(c.label)")
            }
            guard addSlot(label: c.label, target: c.target) != nil else {
                let reason = configurationError ?? "Could not save the dropped slot."
                lastLaunchError = reason
                return .reject(reason)
            }
            lastLaunchError = nil
            return outcome
        case .reject(let reason):
            lastLaunchError = reason
            return outcome
        }
    }

    @discardableResult
    func addSlotsFromDrops(_ raws: [String]) -> Int {
        var n = 0
        for raw in raws {
            if case .accept = addSlotFromDrop(raw) { n += 1 }
        }
        return n
    }

    func revealInFinder(slotID: String) {
        guard let slot = slot(for: slotID) else { return }
        let request = LaunchResolver.resolve(slot: slot)
        let path = request.resolvedTarget
        guard !path.isEmpty else { return }
        if request.kind == .url {
            lastLaunchError = "URLs cannot be revealed in Finder. Use Open instead."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func slot(for slotID: String) -> Slot? {
        if let item = displayItems.first(where: { $0.slot.id == slotID }) {
            return item.slot
        }
        return slots.first(where: { $0.id == slotID })
    }

    func displayItem(for slotID: String) -> SlotComposer.Item? {
        displayItems.first(where: { $0.slot.id == slotID })
            ?? slots.first(where: { $0.id == slotID }).map { SlotComposer.Item(slot: $0, origin: .custom) }
    }

    /// Index of a custom slot in the persisted list (for reorder menu).
    func customIndex(of slotID: String) -> Int? {
        slots.firstIndex(where: { $0.id == slotID })
    }

    // MARK: - Context menu actions

    @discardableResult
    func performContextAction(
        _ action: SlotContextAction,
        slotID: String?,
        instance: SlotInstanceRef? = nil
    ) -> Bool {
        switch action {
        case .open:
            guard let slotID else { return false }
            return launch(slotID: slotID)
        case .openNewInstance:
            guard let slotID else { return false }
            return openNewInstance(slotID: slotID)
        case .showInFinder:
            guard let slotID else { return false }
            revealInFinder(slotID: slotID)
            return true
        case .copyPath:
            guard let slotID, let slot = slot(for: slotID) else { return false }
            copyToPasteboard(LaunchResolver.resolve(slot: slot).resolvedTarget)
            return true
        case .copyLabel:
            guard let slotID, let slot = slot(for: slotID) else { return false }
            copyToPasteboard(slot.label)
            return true
        case .hideApplication:
            guard let slotID else { return false }
            return hideRunning(slotID: slotID)
        case .quitApplication:
            guard let slotID else { return false }
            return terminateRunning(slotID: slotID, force: false)
        case .forceQuitApplication:
            guard let slotID else { return false }
            return terminateRunning(slotID: slotID, force: true)
        case .removeFromSlotDock:
            guard let slotID else { return false }
            return removeSlot(id: slotID)
        case .importAsCustomSlot:
            // System Dock or live running app → durable custom keep.
            guard let slotID, let item = displayItem(for: slotID) else { return false }
            guard item.origin == .systemDock || item.origin == .running else { return false }
            let entry = SystemDockEntry(label: item.slot.label, path: item.slot.target)
            return importSystemDockEntry(entry) != nil
        case .unkeepCustomSlot:
            // Reverse of Keep: remove the durable custom slot matching this strip item’s path.
            guard let slotID, let item = displayItem(for: slotID) else { return false }
            guard item.origin != .custom else {
                // Pure custom strip row uses Remove from Nicos Slot Dock instead.
                return false
            }
            guard let customID = KeepAsCustomPolicy.customSlotID(
                matchingPath: item.slot.target,
                customSlots: slots
            ) else {
                return false
            }
            return removeSlot(id: customID)
        case .editSlot:
            if let slotID {
                pendingEditSlotID = slotID
            }
            openSettings(tab: .slots)
            return true
        case .moveLeft:
            guard let slotID, let idx = customIndex(of: slotID), idx > 0 else { return false }
            reorder(from: idx, to: idx - 1)
            return true
        case .moveRight:
            guard let slotID, let idx = customIndex(of: slotID), idx < slots.count - 1 else {
                return false
            }
            reorder(from: idx, to: idx + 1)
            return true
        case .openSlotsSettings:
            openSettings(tab: .slots)
            return true
        case .openOptionsSettings:
            openSettings(tab: .options)
            return true
        case .pinOpen:
            setPinOpen(true)
            return true
        case .unpinOpen:
            setPinOpen(false)
            return true
        case .hideStrip:
            reveal.beginCollapse()
            return true
        case .showStrip:
            beginReveal()
            return true
        case .refreshSystemDock:
            _ = refreshSystemDock()
            return true
        case .enableOpenAtLogin:
            guard let slotID else { return false }
            return setOpenAtLogin(slotID: slotID, enabled: true)
        case .disableOpenAtLogin:
            guard let slotID else { return false }
            return setOpenAtLogin(slotID: slotID, enabled: false)
        case .activateInstance:
            return activateInstance(instance)
        case .hideInstance:
            return hideInstance(instance)
        case .quitInstance:
            return quitInstance(instance)
        }
    }

    /// Open-at-login query for menu state (`nil` = unknown / Automation blocked).
    func openAtLoginState(slotID: String) -> Bool? {
        guard let slot = slot(for: slotID) else { return nil }
        let request = LaunchResolver.resolve(slot: slot)
        guard AppOpenAtLoginPolicy.isEligible(kind: request.kind, path: request.resolvedTarget) else {
            return false
        }
        return TargetAppLoginItem.isEnabled(appPath: request.resolvedTarget)
    }

    @discardableResult
    func setOpenAtLogin(slotID: String, enabled: Bool) -> Bool {
        guard let slot = slot(for: slotID) else { return false }
        let request = LaunchResolver.resolve(slot: slot)
        guard AppOpenAtLoginPolicy.isEligible(kind: request.kind, path: request.resolvedTarget) else {
            lastLaunchError = "Open at Login is only available for applications."
            return false
        }
        let path = request.resolvedTarget
        lastLaunchError = "Updating Open at Login…"
        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                TargetAppLoginItem.setEnabled(appPath: path, enabled: enabled)
            }.value
            self?.finishOpenAtLogin(result, slot: slot, enabled: enabled)
        }
        return true
    }

    private func finishOpenAtLogin(
        _ result: Result<Void, TargetAppLoginItem.LoginError>,
        slot: Slot,
        enabled: Bool
    ) {
        switch result {
        case .success:
            lastLaunchError = nil
            SlotDockTelemetry.preferences.info(
                "Open at Login \(enabled ? "on" : "off") for \(slot.label, privacy: .private)"
            )
        case .failure(let err):
            let message = err.errorDescription ?? "Open at Login failed"
            lastLaunchError = message
            if err.isAutomationDenied {
                // Actionable path: open Privacy so grant is one click away.
                TargetAppLoginItem.openAutomationPrivacySettings()
                SlotDockTelemetry.preferences.info(
                    "Open at Login needs Automation permission for \(slot.label, privacy: .private)"
                )
            } else {
                SlotDockTelemetry.preferences.warning(
                    "Open at Login failed: \(message, privacy: .private)"
                )
            }
        }
    }

    /// Strip drag-reorder: only custom slots. System items return false.
    @discardableResult
    func reorderCustomSlot(draggedID: String, beforeID: String?) -> Bool {
        guard slots.contains(where: { $0.id == draggedID }) else { return false }
        // Reject if dragged id is only a system display id without custom backing.
        if let item = displayItems.first(where: { $0.slot.id == draggedID }), item.origin != .custom {
            return false
        }
        guard let next = StripCustomReorder.move(
            customSlots: slots,
            draggedID: draggedID,
            beforeID: beforeID
        ) else { return false }
        core.replaceAll(next)
        afterSlotsChanged()
        return core.lastError == nil
    }

    @discardableResult
    func reorderCustomSlot(draggedID: String, toIndex: Int) -> Bool {
        guard slots.contains(where: { $0.id == draggedID }) else { return false }
        guard let next = StripCustomReorder.move(
            customSlots: slots,
            draggedID: draggedID,
            toIndex: toIndex
        ) else { return false }
        core.replaceAll(next)
        afterSlotsChanged()
        return core.lastError == nil
    }

    @discardableResult
    func openNewInstance(slotID: String) -> Bool {
        guard let slot = slot(for: slotID) else { return false }
        let request = LaunchResolver.resolve(slot: slot)
        guard SlotContextMenuBuilder.canOpenNewInstance(kind: request.kind, path: request.resolvedTarget)
        else {
            return launch(slotID: slotID)
        }
        let url = URL(fileURLWithPath: request.resolvedTarget)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        if preferences.launchFeedback {
            flashLaunch(slotID: slotID)
        }
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.lastLaunchError = error.localizedDescription
                } else {
                    self?.lastLaunchError = nil
                }
            }
        }
        return true
    }

    @discardableResult
    func hideRunning(slotID: String) -> Bool {
        let apps = runningApplications(for: slotID)
        guard !apps.isEmpty else { return false }
        for app in apps {
            app.hide()
        }
        return true
    }

    @discardableResult
    func terminateRunning(slotID: String, force: Bool) -> Bool {
        let apps = runningApplications(for: slotID)
        guard !apps.isEmpty else { return false }
        for app in apps {
            if force {
                app.forceTerminate()
            } else {
                app.terminate()
            }
        }
        return true
    }

    func runningInstances(for slotID: String) -> [SlotInstanceRef] {
        let apps = runningApplications(for: slotID)
        var rows: [SlotInstanceRef] = []
        for app in apps {
            let windows = DockAXWindowTitles.windows(for: app)
            if windows.isEmpty {
                let name = app.localizedName ?? "PID \(app.processIdentifier)"
                rows.append(
                    SlotInstanceRef(processID: app.processIdentifier, title: name)
                )
            } else {
                for window in windows {
                    rows.append(
                        SlotInstanceRef(
                            processID: app.processIdentifier,
                            windowNumber: window.windowNumber,
                            title: window.title
                        )
                    )
                }
            }
        }
        return rows
    }

    @discardableResult
    func activateInstance(_ instance: SlotInstanceRef?) -> Bool {
        guard let instance, let app = NSRunningApplication(processIdentifier: instance.processID) else {
            return false
        }
        app.unhide()
        let activated = app.activate(options: [.activateAllWindows])
        let raised = DockAXWindowTitles.raise(
            app: app,
            windowNumber: instance.windowNumber,
            title: instance.title
        )
        return activated || raised
    }

    @discardableResult
    func hideInstance(_ instance: SlotInstanceRef?) -> Bool {
        guard let instance, let app = NSRunningApplication(processIdentifier: instance.processID) else {
            return false
        }
        return app.hide()
    }

    @discardableResult
    func quitInstance(_ instance: SlotInstanceRef?) -> Bool {
        guard let instance, let app = NSRunningApplication(processIdentifier: instance.processID) else {
            return false
        }
        return app.terminate()
    }

    func runningApplications(for slotID: String) -> [NSRunningApplication] {
        guard let slot = slot(for: slotID) else { return [] }
        let identity = AppIdentity.from(slot: slot)
        let running = NSWorkspace.shared.runningApplications
        if let path = identity.path?.lowercased(), !path.isEmpty {
            let exact = running.filter { app in
                guard let url = app.bundleURL else { return false }
                return SystemDockEntry.normalizePath(url.path).lowercased() == path
            }
            // A system Dock identity may carry both bundle and path. Do not
            // hide/quit every copy sharing the bundle when one exact target is
            // available; fall back to bundle matching only if the path is stale.
            if !exact.isEmpty { return exact }
        }
        guard let bundle = identity.bundleIdentifier?.lowercased(), !bundle.isEmpty else {
            return []
        }
        return running.filter { $0.bundleIdentifier?.lowercased() == bundle }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func setHotkeys(_ hotkeys: DockHotkeys) {
        let persisted = updatePreferences {
            var h = hotkeys
            h.sanitize()
            $0.hotkeys = h
        }
        if persisted { notifyHotkeysChanged() }
    }

    func setHotkeysGlobal(_ on: Bool) {
        if updatePreferences({ $0.hotkeys.globalEnabled = on }) {
            notifyHotkeysChanged()
        }
    }

    func notifyHotkeysChanged() {
        NotificationCenter.default.post(name: .slotDockHotkeysDidChange, object: nil)
    }

    /// Called by AppDelegate after Carbon register pass.
    func applyHotkeyReport(_ report: HotkeyRegistrationReport) {
        hotkeyReport = report
        if report.hasProblems {
            SlotDockTelemetry.hotkey.warning("store hotkey report: \(report.userSummary, privacy: .private)")
        }
    }

    func resetPreferences() {
        let persisted = core.setPreferences(.default)
        preferences = core.preferences
        configurationError = core.lastError?.localizedDescription
        recomposeDisplay()
        _ = refreshSystemDock()
        guard persisted else { return }
        syncLaunchAtLoginFromPreferences()
        notifyHotkeysChanged()
        NotificationCenter.default.post(name: .slotDockStatusItemPreferenceDidChange, object: nil)
        NotificationCenter.default.post(name: .slotDockWindowBehaviorDidChange, object: nil)
        NotificationCenter.default.post(name: .slotDockSafeAreaPreferenceDidChange, object: nil)
        NotificationCenter.default.post(name: .slotDockCollisionPromptMayNeed, object: nil)
    }

    // MARK: - Launch

    @discardableResult
    func launch(slotID: String) -> Bool {
        // Resolve from composed display (system or custom), not custom-only.
        guard let item = displayItems.first(where: { $0.slot.id == slotID })
                ?? slots.first(where: { $0.id == slotID }).map({ SlotComposer.Item(slot: $0, origin: .custom) })
        else {
            lastLaunchError = "Slot not found"
            SlotDockTelemetry.launch.error("Launch miss id=\(slotID, privacy: .private)")
            return false
        }
        let slot = item.slot
        let request = LaunchResolver.resolve(slot: slot)
        guard let payload = LaunchResolver.openPayload(for: request) else {
            lastLaunchError = "Cannot open “\(slot.label)”: invalid target"
            SlotDockTelemetry.launch.warning("Invalid target for \(slot.label, privacy: .private)")
            return false
        }
        if preferences.launchFeedback {
            flashLaunch(slotID: slotID)
        }
        let ok = openHandler(payload)
        if !ok {
            lastLaunchError = "Failed to open “\(slot.label)”"
            SlotDockTelemetry.launch.error("Open failed \(slot.label, privacy: .private)")
        } else {
            lastLaunchError = nil
            SlotDockTelemetry.launch.info(
                "Launched \(slot.label, privacy: .private) origin=\(item.origin.rawValue, privacy: .public)"
            )
        }
        return ok
    }

    func launchRequest(for slotID: String) -> LaunchRequest? {
        if let item = displayItems.first(where: { $0.slot.id == slotID }) {
            return LaunchResolver.resolve(slot: item.slot)
        }
        guard let slot = slots.first(where: { $0.id == slotID }) else { return nil }
        return LaunchResolver.resolve(slot: slot)
    }

    private func flashLaunch(slotID: String) {
        flashClearWork?.cancel()
        launchFlashSlotID = slotID
        let work = DispatchWorkItem { [weak self] in
            self?.launchFlashSlotID = nil
        }
        flashClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    // MARK: - Reveal

    func beginReveal() {
        reveal.beginExpand()
        SlotDockTelemetry.dock.debug("reveal expand phase=\(self.reveal.phase.rawValue, privacy: .public)")
    }

    func beginHide() {
        if preferences.pinOpen { return }
        reveal.beginCollapse()
        SlotDockTelemetry.dock.debug("reveal collapse phase=\(self.reveal.phase.rawValue, privacy: .public)")
    }

    func toggleReveal() {
        if reveal.isRevealed, preferences.pinOpen {
            // Allow explicit collapse even when pinned (user intent).
            reveal.beginCollapse()
            return
        }
        reveal.toggle()
    }

    func finishRevealAnimation() {
        reveal.finish()
    }

    /// Sync model progress to the live panel height ratio (mid-flight reverse).
    func alignRevealProgress(to liveRatio: Double) {
        reveal.alignProgress(to: liveRatio)
    }

    func advanceReveal(by delta: Double) {
        reveal.advance(by: delta)
    }

    // MARK: - Settings

    /// Updates settings state and posts `.slotDockRequestOpenSettings` so the
    /// window controller can actually present the settings window. Calling this
    /// alone never shows UI — DockWindowController observes the notification.
    func openSettings(tab: SettingsTab = .slots) {
        settingsTab = tab
        settingsOpen = true
        if !reveal.isRevealed {
            beginReveal()
        }
        NotificationCenter.default.post(
            name: .slotDockRequestOpenSettings,
            object: nil,
            userInfo: ["tab": tab.rawValue]
        )
    }

    func closeSettings() {
        settingsOpen = false
        pendingEditSlotID = nil
    }

    func consumePendingEditSlotID() -> String? {
        let id = pendingEditSlotID
        pendingEditSlotID = nil
        return id
    }

    // MARK: - Private

    private func seedDefaultsIfEmpty() {
        // Prefer live system Dock when present so first launch mirrors the user's Dock.
        let system = SystemDockReader.readPersistentApps(from: systemDockPlistURL)
        if !system.isEmpty {
            // Leave custom empty — merge mode will show the system Dock.
            // Optional: do not seed hardcoded Finder/Safari that ignore the real Dock.
            slots = core.slots
            SlotDockTelemetry.appLifecycle.info(
                "Empty config; will merge \(system.count, privacy: .public) system Dock apps"
            )
            return
        }
        let candidates: [(String, String)] = [
            ("Finder", "/System/Library/CoreServices/Finder.app"),
            ("Safari", "/Applications/Safari.app"),
            ("Terminal", "/System/Applications/Utilities/Terminal.app"),
            ("System Settings", "/System/Applications/System Settings.app"),
        ]
        for (label, path) in candidates where FileManager.default.fileExists(atPath: path) {
            _ = core.add(label: label, target: path)
        }
        slots = core.slots
    }

    private static func defaultOpen(_ payload: OpenPayload) -> Bool {
        if payload.kind == .url,
           NSWorkspace.shared.urlForApplication(toOpen: payload.url) == nil
        {
            return false
        }
        return NSWorkspace.shared.open(payload.url)
    }
}

extension Notification.Name {
    static let slotDockHotkeysDidChange = Notification.Name("slotDockHotkeysDidChange")
    static let slotDockStatusItemPreferenceDidChange = Notification.Name("slotDockStatusItemPreferenceDidChange")
    static let slotDockWindowBehaviorDidChange = Notification.Name("slotDockWindowBehaviorDidChange")
    static let slotDockSafeAreaPreferenceDidChange = Notification.Name("slotDockSafeAreaPreferenceDidChange")
    static let slotDockCollisionPromptMayNeed = Notification.Name("slotDockCollisionPromptMayNeed")
    static let slotDockRequestAccessibility = Notification.Name("slotDockRequestAccessibility")
    /// userInfo["tab"] = SettingsTab.rawValue — DockWindowController presents the window.
    static let slotDockRequestOpenSettings = Notification.Name("slotDockRequestOpenSettings")
}
