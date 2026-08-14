import AppKit
import QuartzCore
import SlotDockCore
import SwiftUI

/// Floating strip that never becomes key/main — avoids stealing typing from the frontmost app.
final class NonKeyDockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Borderless floating panel for the edge-aligned dock strip.
@MainActor
final class DockWindowController: NSObject {
    private(set) var window: NSPanel?
    private let store: SlotDockStore
    let runningApps: RunningAppsMonitor
    let badges: DockBadgeMonitor
    let safeArea: SafeAreaController
    private var hosting: NSHostingView<DockChrome>?
    private var settingsController: SettingsWindowController?
    private var hoverInside = false
    private var collapseWorkItem: DispatchWorkItem?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var settingsObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var windowBehaviorObserver: NSObjectProtocol?
    private var animationGeneration: UInt = 0
    /// Coalesce same-runloop double starts (begin* + onChange both fire sync).
    private var revealSyncCoalescePending = false
    private var revealSyncPreferredDuration: TimeInterval?
    /// Last pointer-over-strip-or-edge sample (debounce thrash on the boundary).
    private var pointerOverStrip = false
    /// Last processed mouse location (coalesce spammy global mouseMoved samples).
    private var lastMouseSample: CGPoint?
    /// Display currently hosting the strip. Ordinary relayouts must not jump to
    /// whichever display happens to contain the mouse; edge crossing explicitly
    /// changes this anchor.
    private weak var activeScreen: NSScreen?

    private let horizontalMargin: CGFloat = 24
    /// Full expand/collapse travel duration from prefs; short remaining distance scales down.
    private var revealBaseDuration: TimeInterval {
        store.preferences.revealBaseDuration
    }

    /// Collapsed tab chrome matches the configured edge-trigger hit height (default 28).
    private var collapsedHeight: CGFloat {
        CGFloat(store.preferences.edgeTriggerHeight)
    }

    private var expandedHeight: CGFloat {
        store.preferences.expandedStripHeight()
    }

    /// Height used for safe-area clearance (expanded strip).
    var stripPadHeight: CGFloat { expandedHeight }

    init(
        store: SlotDockStore,
        runningApps: RunningAppsMonitor? = nil,
        badges: DockBadgeMonitor? = nil,
        safeArea: SafeAreaController? = nil
    ) {
        self.store = store
        self.runningApps = runningApps ?? RunningAppsMonitor()
        self.badges = badges ?? DockBadgeMonitor()
        self.safeArea = safeArea ?? SafeAreaController()
        super.init()
        // Event-driven: recompose only when transient strip membership changes.
        // Running dots update via RunningAppsMonitor @Published — no window animation.
        self.runningApps.onSnapshotChange = { [weak store, weak self] in
            guard let self, let store else { return }
            let stripChanged = store.applyRunningSnapshot(self.runningApps.snapshot)
            if stripChanged {
                SlotDockTelemetry.dock.info(
                    "relayout after running strip change display=\(store.displayItems.count, privacy: .public)"
                )
                self.relayout(animated: true)
            }
        }
        _ = store.applyRunningSnapshot(self.runningApps.snapshot)
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .slotDockRequestOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let raw = (note.userInfo?["tab"] as? String) ?? "slots"
            // Main queue already — hop only if needed for MainActor isolation.
            MainActor.assumeIsolated {
                let tab = SlotDockStore.SettingsTab(rawValue: raw) ?? .slots
                self?.presentSettingsWindow(tab: tab)
            }
        }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let active = self.activeScreen,
                   !NSScreen.screens.contains(where: { $0 === active })
                {
                    self.activeScreen = self.screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first
                }
                self.relayout(animated: false)
                self.syncSafeArea()
            }
        }
        windowBehaviorObserver = NotificationCenter.default.addObserver(
            forName: .slotDockWindowBehaviorDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyWindowBehavior() }
        }
    }

    func invalidate() {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
        if let windowBehaviorObserver {
            NotificationCenter.default.removeObserver(windowBehaviorObserver)
            self.windowBehaviorObserver = nil
        }
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        runningApps.invalidate()
        badges.invalidate()
        safeArea.restoreAllTracked()
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        guard let window else { return }
        if activeScreen == nil {
            activeScreen = screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first
        }
        positionOnScreen(animated: false)
        SlotDockHeadless.surface(window)
        installMouseMonitor()
    }

    /// Coalesce multiple reveal sync requests in the same turn (phase onChange + explicit call).
    func requestRevealSync(duration: TimeInterval? = nil) {
        if let duration {
            // Prefer an explicit duration when provided; keep the shortest positive one.
            if let existing = revealSyncPreferredDuration {
                revealSyncPreferredDuration = min(existing, duration)
            } else {
                revealSyncPreferredDuration = duration
            }
        }
        guard !revealSyncCoalescePending else { return }
        revealSyncCoalescePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.revealSyncCoalescePending = false
            let dur = self.revealSyncPreferredDuration
            self.revealSyncPreferredDuration = nil
            self.syncRevealAnimated(duration: dur)
        }
    }

    func syncRevealAnimated(duration: TimeInterval? = nil) {
        guard let window else { return }

        let travel = max(expandedHeight - collapsedHeight, 1)
        let liveHeight = window.frame.height
        // Prefer live frame (mid-flight reverse); fall back to model when window is brand-new.
        // Use *linear* height ratio (not eased) so reverse mid-flight matches the real frame.
        let startHeight: CGFloat = {
            if liveHeight > 1 {
                return min(max(liveHeight, collapsedHeight * 0.5), max(expandedHeight, liveHeight))
            }
            // Model progress is linear; height() applies smoothstep — avoid that double-ease for start.
            let linear = collapsedHeight + (expandedHeight - collapsedHeight) * CGFloat(store.reveal.progress)
            return linear
        }()
        // Keep pure model progress aligned with the window so positionOnScreen mid-flight is sane.
        let liveRatio = Double((startHeight - collapsedHeight) / travel)
        store.alignRevealProgress(to: liveRatio)

        let targetHeight = store.reveal.destinationHeight(
            collapsed: collapsedHeight,
            expanded: expandedHeight
        )
        let targetFrame = frameForHeight(targetHeight)
        let startFrame = frameForHeight(startHeight)

        let heightDelta = abs(targetHeight - startHeight)
        let widthDelta = abs(targetFrame.width - window.frame.width)
        let xDelta = abs(targetFrame.origin.x - window.frame.origin.x)

        window.alphaValue = 1.0

        guard heightDelta > 0.5 || widthDelta > 0.5 || xDelta > 0.5 else {
            store.finishRevealAnimation()
            // Only re-root SwiftUI when settled — not every tick.
            refreshChrome()
            positionOnScreen(animated: false)
            syncSafeArea()
            return
        }

        // Distance-scaled duration: reverse mid-collapse is short; full travel uses base.
        // No hard 0.07 floor — low base values stay snappy (see DockPreferences.scaledRevealDuration).
        let fraction = min(1.0, Double(heightDelta / travel))
        let base = duration ?? revealBaseDuration
        let resolvedDuration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? 0
            : DockPreferences.scaledRevealDuration(base: base, heightFraction: fraction)

        animationGeneration &+= 1
        let generation = animationGeneration
        let phase = store.reveal.phase
        let collapsing = phase == .collapsing
        let animStartedAt = CFAbsoluteTimeGetCurrent()

        // Debug only — high frequency during hover thrash; dogfood uses reveal.complete ms.
        SlotDockTelemetry.dock.debug(
            "reveal anim phase=\(phase.rawValue, privacy: .public) Δh=\(heightDelta, privacy: .public) dur=\(resolvedDuration, privacy: .public)s frac=\(fraction, privacy: .public)"
        )

        if DockPreferences.shouldSnapReveal(duration: resolvedDuration) {
            window.setFrame(targetFrame, display: true)
            store.finishRevealAnimation()
            refreshChrome()
            positionOnScreen(animated: false)
            syncSafeArea()
            return
        }

        // Snap presentation to the live start without a full chrome rebuild (avoids jank at 0.1s hide).
        if abs(window.frame.height - startHeight) > 0.5
            || abs(window.frame.origin.x - startFrame.origin.x) > 0.5
            || abs(window.frame.width - startFrame.width) > 0.5
        {
            window.setFrame(startFrame, display: false)
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = resolvedDuration
            // Collapse: gentle ease-in-out (no mid-curve plateau). Expand: slightly snappy ease-out.
            // Prior controlPoints (0.2, 0.9, …) spent too long near mid-travel → felt like a stutter.
            if collapsing {
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            } else {
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
            }
            // Avoid implicit nested animations on subviews fighting the frame travel.
            ctx.allowsImplicitAnimation = false
            window.animator().setFrame(targetFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.animationGeneration == generation else { return }
                self.store.finishRevealAnimation()
                // Re-root once settled so collapsed tab / full strip swap cleanly.
                self.refreshChrome()
                self.positionOnScreen(animated: false)
                self.syncSafeArea()
                let wallMS = (CFAbsoluteTimeGetCurrent() - animStartedAt) * 1000
                // Sparse dogfood: wall time vs planned duration shows hitch (wall ≫ planned).
                SlotDockTelemetry.performance.info(
                    "⏱ reveal.complete phase=\(self.store.reveal.phase.rawValue, privacy: .public) wall=\(wallMS, format: .fixed(precision: 1), privacy: .public)ms planned=\(resolvedDuration * 1000, format: .fixed(precision: 0), privacy: .public)ms Δh=\(heightDelta, privacy: .public)"
                )
            }
        })
    }

    func relayout(animated: Bool = true) {
        guard window != nil else { return }
        SlotDockTelemetry.measure("DockWindow.relayout", thresholdMS: 2) {
            if store.reveal.isAnimating {
                // Don't force a full-duration restart mid-flight; scale to remaining distance.
                requestRevealSync(duration: animated ? revealBaseDuration : 0)
            } else {
                positionOnScreen(animated: animated && store.reveal.phase == .expanded)
                refreshChrome()
                syncSafeArea()
            }
        }
    }

    /// Apply or restore window safe-area padding based on prefs + strip state.
    func syncSafeArea() {
        let need = SafeAreaPolicy.need(
            optionEnabled: store.preferences.safeAreaPadding,
            pinOpen: store.preferences.pinOpen,
            autoHide: store.preferences.autoHide,
            revealPhase: store.reveal.phase
        )
        if !store.preferences.safeAreaPadding {
            // Option off: restore only windows we previously moved.
            safeArea.restoreAllTracked()
            store.safeAreaError = safeArea.lastError
            return
        }
        safeArea.sync(
            need: need,
            padHeight: stripPadHeight,
            extraGap: CGFloat(store.preferences.safeAreaExtraGap),
            screen: window?.screen ?? NSScreen.main
        )
        store.safeAreaError = safeArea.lastError
    }

    func openSettings(tab: SlotDockStore.SettingsTab = .slots) {
        store.openSettings(tab: tab)
    }

    /// Actually show the settings NSWindow (safe to call more than once).
    func presentSettingsWindow(tab: SlotDockStore.SettingsTab) {
        if settingsController == nil {
            settingsController = SettingsWindowController(store: store)
        }
        settingsController?.show(tab: tab)
        if store.reveal.phase == .collapsed || store.reveal.phase == .collapsing {
            store.beginReveal()
            requestRevealSync()
        }
    }

    // MARK: - Build

    private func buildWindow() {
        let panel = NonKeyDockPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: collapsedHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        self.window = panel
        applyWindowBehavior()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // Explicit NSAnimationContext owns expand/collapse — avoid system utility animations fighting us.
        panel.animationBehavior = .none
        panel.worksWhenModal = true

        let chrome = DockChrome(store: store, runningApps: runningApps, badges: badges, controller: self)
        let host = NSHostingView(rootView: chrome)
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.hosting = host
    }

    private func applyWindowBehavior() {
        guard let panel = window else { return }
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary]
        if store.preferences.showInFullScreen {
            behavior.insert(.fullScreenAuxiliary)
        }
        panel.collectionBehavior = behavior
    }

    private func refreshChrome() {
        hosting?.rootView = DockChrome(store: store, runningApps: runningApps, badges: badges, controller: self)
    }

    // MARK: - Geometry

    private func positionOnScreen(animated: Bool) {
        guard let window else { return }
        let height = store.reveal.height(collapsed: collapsedHeight, expanded: expandedHeight)
        let frame = frameForHeight(height)
        if animated {
            window.animator().setFrame(frame, display: true)
        } else {
            window.setFrame(frame, display: true)
        }
        SlotDockHeadless.parkOffscreenIfHeadless(window)
    }

    private func frameForHeight(_ height: CGFloat) -> NSRect {
        frameForHeight(height, on: activeScreen ?? screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first)
    }

    private func frameForHeight(_ height: CGFloat, on screen: NSScreen?) -> NSRect {
        guard let screen else {
            return NSRect(x: 100, y: 40, width: 400, height: height)
        }
        let visible = screen.visibleFrame
        let width = min(max(slotBarWidth(), 200), max(200, visible.width - horizontalMargin * 2))
        let align: ScreenGeometry.Alignment = {
            switch store.preferences.alignment {
            case .leading: return .leading
            case .center: return .center
            case .trailing: return .trailing
            }
        }()
        let pure = ScreenGeometry.stripFrame(
            visible: visible,
            height: height,
            width: width,
            alignment: align,
            horizontalMargin: horizontalMargin,
            bottomInset: 10
        )
        return NSRect(x: pure.origin.x, y: pure.origin.y, width: pure.size.width, height: pure.size.height)
    }

    /// Prefer the display under the mouse for multi-monitor setups.
    private func screenUnderPointer() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
    }

    private func slotBarWidth() -> CGFloat {
        let icon = store.preferences.iconSize.pointSize
        let count = max(store.displayItems.count, 1)
        let spacing = store.preferences.effectiveIconSpacing()
        // icons + controls (gear + menu + divider) + padding
        let iconsWidth = DockPreferences.stripIconsWidth(count: count, iconSize: icon, spacing: spacing)
        let controls: CGFloat = 28 + 28 + 16 + 24
        let labelsPad: CGFloat = store.preferences.showLabels ? CGFloat(count) * 4 : 0
        let sectionDivider: CGFloat =
            (store.preferences.systemDockIntegration == .merge && store.preferences.showSystemDockDivider)
            || store.preferences.showTransientRunningApps
            ? 12 : 0
        return iconsWidth + controls + labelsPad + sectionDivider + 40
    }

    // MARK: - Hover / edge reveal

    private func installMouseMonitor() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown]
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                Task { @MainActor in
                    if event.type == .rightMouseDown {
                        self?.handleStripRightClick(event)
                    } else {
                        self?.handleMouse(event)
                    }
                }
            }
        }
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                if event.type == .rightMouseDown {
                    Task { @MainActor in
                        self?.handleStripRightClick(event)
                    }
                    // Let StripIconHitView also receive; chrome menu only if not on an icon.
                    return event
                }
                Task { @MainActor in
                    self?.handleMouse(event)
                }
                return event
            }
        }
    }

    /// Chrome right-click when the hit view is not a strip icon (icons handle their own menus).
    private func handleStripRightClick(_ event: NSEvent) {
        guard let window, store.reveal.isRevealed else { return }
        let loc = event.locationInWindow
        // If an icon hit-view owns this point, it will present its own menu.
        if let hit = window.contentView?.hitTest(loc), hit is StripIconHitView {
            return
        }
        guard window.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) else { return }
        guard let content = window.contentView else { return }
        let model = SlotContextMenuBuilder.buildChromeMenu(
            isPinned: store.preferences.pinOpen,
            isRevealed: store.reveal.isRevealed,
            systemDockCount: store.systemDockEntries.count
        )
        NativeContextMenu.popUp(model: model, with: event, for: content) { [weak self] action, instance in
            _ = self?.store.performContextAction(action, slotID: nil, instance: instance)
            if action == .hideStrip || action == .showStrip || action == .pinOpen || action == .unpinOpen {
                self?.requestRevealSync()
            }
            if action == .refreshSystemDock {
                self?.relayout(animated: true)
            }
        }
    }

    private func handleMouse(_ event: NSEvent) {
        guard let window else { return }
        let loc = NSEvent.mouseLocation

        // Clicks always process (outside-click collapse). Coalesce only pure moves
        // so high-rate mouseMoved does not re-hit-test identical positions.
        if event.type == .mouseMoved,
           let last = lastMouseSample,
           abs(last.x - loc.x) < 0.5,
           abs(last.y - loc.y) < 0.5
        {
            return
        }
        lastMouseSample = loc

        // Multi-display: hit-test against the screen under the pointer, not only main.
        let pointerScreen = screenUnderPointer() ?? window.screen ?? NSScreen.main
        guard let screen = pointerScreen else { return }
        let visible = screen.visibleFrame
        let overStrip = isPointerOverStripContent(point: loc, window: window)
        // Use the frame the strip would have on the pointer's display. The
        // current window can still belong to the previous display during the
        // edge-crossing sample.
        let pointerFrame = frameForHeight(window.frame.height, on: screen)
        let mid = pointerFrame.midX
        let half = DockPreferences.edgeHitHalfWidth(
            stripWidth: pointerFrame.width,
            overshoot: store.preferences.edgeHorizontalOvershoot
        )
        let nearBottom = store.preferences.edgeHover && ScreenGeometry.isNearBottomEdge(
            point: loc,
            visible: visible,
            threshold: CGFloat(store.preferences.edgeTriggerHeight),
            stripMidX: mid,
            stripHalfWidth: half
        )

        // If the pointer is on another display's bottom edge, re-home the strip there.
        if nearBottom, let under = screenUnderPointer(), under !== activeScreen {
            activeScreen = under
            let pointerFrame = frameForHeight(window.frame.height, on: under)
            window.setFrame(pointerFrame, display: true)
        }

        // Snappy auto-hide: click outside the strip collapses (does not quit the app).
        // Use leave-margin zone (not edge band) so outside-click matches leave semantics.
        if event.type == .leftMouseDown, !overStrip {
            if collapseFromOutsideClickIfNeeded() {
                // Still track pointer as outside so leave-timer state stays coherent.
                pointerOverStrip = false
                return
            }
        }

        // Leave margin only holds while expanded; edge-hover re-opens when collapsed.
        let over = AutoHideCollapsePolicy.shouldHoldStripOpen(
            overStrip: overStrip,
            nearBottomEdge: nearBottom,
            edgeHoverEnabled: store.preferences.edgeHover,
            phase: store.reveal.phase
        )
        applyPointerOver(over)
    }

    /// Leave hit-test against bottom-aligned **content** bar + leave margin (not full window Spacer).
    private func isPointerOverStripContent(point: CGPoint, window: NSWindow) -> Bool {
        DockPreferences.isPointerOverStrip(
            point: point,
            windowFrame: window.frame,
            leaveMargin: store.preferences.autoHideLeaveMargin,
            contentHeight: store.preferences.contentBarHeight()
        )
    }

    /// Collapse the strip when delay ≤ 0.3s and the user clicks outside (not hide/quit).
    @discardableResult
    private func collapseFromOutsideClickIfNeeded() -> Bool {
        guard AutoHideCollapsePolicy.collapsesOnOutsideClick(
            autoHide: store.preferences.autoHide,
            pinOpen: store.preferences.pinOpen,
            settingsOpen: store.settingsOpen,
            autoHideDelay: store.preferences.autoHideDelay,
            isRevealed: store.reveal.isRevealed
        ) else {
            return false
        }
        cancelScheduledCollapse()
        // Expanding or fully open → collapse; already collapsing/collapsed is a no-op.
        guard store.reveal.phase == .expanded || store.reveal.phase == .expanding else {
            return true
        }
        // User-driven sparse event — keep at info for dogfood.
        SlotDockTelemetry.dock.info("auto-hide outside-click collapse")
        store.beginHide()
        requestRevealSync()
        return true
    }

    /// Shared enter/leave path for mouse monitors and SwiftUI hover.
    private func applyPointerOver(_ over: Bool) {
        // Edge hysteresis: ignore flapping while state unchanged (every mouseMoved used to
        // re-arm the hide timer → strip never collapsed during continuous movement).
        if over == pointerOverStrip {
            if over {
                // Still over: keep countdown cancelled; expand if we were mid-collapse.
                cancelScheduledCollapse()
                if store.reveal.phase == .collapsed || store.reveal.phase == .collapsing {
                    store.beginReveal()
                    requestRevealSync()
                }
            }
            return
        }
        pointerOverStrip = over

        if over {
            cancelScheduledCollapse()
            if store.reveal.phase == .collapsed || store.reveal.phase == .collapsing {
                store.beginReveal()
                requestRevealSync()
            }
        } else if shouldAutoHide {
            // Only start the delay once on leave — do not reset on every mouseMoved outside.
            scheduleCollapseIfNeeded()
        }
    }

    private var shouldAutoHide: Bool {
        AutoHideCollapsePolicy.shouldArmLeaveTimer(
            autoHide: store.preferences.autoHide,
            pinOpen: store.preferences.pinOpen,
            settingsOpen: store.settingsOpen
        )
    }

    /// Arm auto-hide once. Subsequent mouse samples while still outside do not reset the clock.
    private func scheduleCollapseIfNeeded() {
        guard shouldAutoHide else { return }
        guard collapseWorkItem == nil else { return }
        // Already collapsing toward closed — don't restart.
        if store.reveal.phase == .collapsing || store.reveal.phase == .collapsed { return }
        guard store.reveal.isRevealed else { return }

        let delay = store.preferences.autoHideDelay
        SlotDockTelemetry.dock.debug("auto-hide armed delay=\(delay, privacy: .public)s")
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWorkItem = nil
            guard self.shouldAutoHide, !self.pointerOverStrip else { return }
            self.store.beginHide()
            self.requestRevealSync()
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelScheduledCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    func userHoveredDock(_ hovering: Bool) {
        hoverInside = hovering
        if hovering {
            applyPointerOver(true)
            return
        }
        // Leave from SwiftUI only when the shared hold policy says we're off-strip
        // (leave margin + phase-aware edge-hover). Global monitor owns continuous tracking.
        guard let window else {
            applyPointerOver(false)
            return
        }
        let loc = NSEvent.mouseLocation
        let overStrip = isPointerOverStripContent(point: loc, window: window)
        let screen = screenUnderPointer() ?? window.screen ?? NSScreen.main
        let nearBottom: Bool = {
            guard store.preferences.edgeHover, let screen else { return false }
            let mid = window.frame.midX
            let half = DockPreferences.edgeHitHalfWidth(
                stripWidth: window.frame.width,
                overshoot: store.preferences.edgeHorizontalOvershoot
            )
            return ScreenGeometry.isNearBottomEdge(
                point: loc,
                visible: screen.visibleFrame,
                threshold: CGFloat(store.preferences.edgeTriggerHeight),
                stripMidX: mid,
                stripHalfWidth: half
            )
        }()
        let hold = AutoHideCollapsePolicy.shouldHoldStripOpen(
            overStrip: overStrip,
            nearBottomEdge: nearBottom,
            edgeHoverEnabled: store.preferences.edgeHover,
            phase: store.reveal.phase
        )
        applyPointerOver(hold)
    }

    func userClickedTab() {
        store.toggleReveal()
        requestRevealSync()
    }
}

struct DockChrome: View {
    @ObservedObject var store: SlotDockStore
    @ObservedObject var runningApps: RunningAppsMonitor
    @ObservedObject var badges: DockBadgeMonitor
    weak var controller: DockWindowController?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if store.reveal.phase == .collapsed {
                CollapsedTabView()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        controller?.userClickedTab()
                    }
                    .onHover { controller?.userHoveredDock($0) }
            } else {
                // Bottom-aligned strip; window clips from the top during collapse so
                // SwiftUI does not reflow icons mid-animation (half-travel stutter).
                DockView(
                    store: store,
                    runningApps: runningApps,
                    badges: badges,
                    onHoverChange: { hovering in
                        controller?.userHoveredDock(hovering)
                    },
                    onOpenSettings: { tab in
                        controller?.openSettings(tab: tab)
                    }
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .clipped()
        .onChange(of: store.displayItems.count) { _, _ in
            controller?.relayout(animated: true)
        }
        .onChange(of: store.displayItems.map(\.id)) { _, _ in
            controller?.relayout(animated: false)
        }
        .onChange(of: store.preferences) { _, _ in
            controller?.relayout(animated: true)
            controller?.syncSafeArea()
        }
        .onAppear {
            _ = store.refreshSystemDock()
            runningApps.refresh()
            badges.start()
            badges.setCollectBadges(store.preferences.showNotificationBadges)
            controller?.syncSafeArea()
        }
        .onChange(of: store.preferences.showNotificationBadges) { _, on in
            badges.setCollectBadges(on)
        }
        .onChange(of: store.reveal.phase) { _, phase in
            // Controls menu / store-only phase flips: coalesce with any explicit request.
            if phase == .expanding || phase == .collapsing {
                controller?.requestRevealSync()
            }
            // Defer safe-area restore/apply until settled — mid-collapse window moves
            // were a major source of halfway jank when other windows shifted.
            if phase == .expanded || phase == .collapsed {
                controller?.syncSafeArea()
            }
        }
    }
}
