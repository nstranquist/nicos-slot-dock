import AppKit
import Darwin
import SlotDockCore
import SwiftUI

/// Pure AppKit entry — avoids SwiftUI `Settings { EmptyView() }` which injects a phantom
/// Window/document menu item into the menu bar of whatever app is frontmost.
@main
enum SlotDockMain {
    static func main() {
        // Second-instance handoff before we build UI (skip under headless self-test).
        if ProcessInfo.processInfo.environment["SLOT_DOCK_ALLOW_MULTI"] != "1",
           ProcessInfo.processInfo.environment["SLOT_DOCK_SELFTEST"] != "1",
           ProcessInfo.processInfo.environment["SLOT_DOCK_HEADLESS"] != "1"
        {
            if !SingleInstanceGate.claimOrHandoff() {
                return
            }
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

/// AppKit adapter over `SingleInstancePolicy` (bundle-id peers + distributed focus).
enum SingleInstanceGate {
    /// A kernel-held advisory lock closes the check-then-launch race that a
    /// bundle-id process scan cannot prevent. The descriptor stays open for
    /// the process lifetime; the kernel releases it on crash/termination.
    nonisolated(unsafe) private static var lockFD: Int32 = -1
    private enum LockAttempt { case acquired, busy, unavailable }

    static func claimOrHandoff() -> Bool {
        switch acquireLock() {
        case .acquired:
            return true
        case .unavailable:
            fputs("slot-dock: could not claim the single-instance lock; refusing a second UI\n", stderr)
            return false
        case .busy:
            break
        }

        let bundleID = Bundle.main.bundleIdentifier ?? SlotDockProcessIdentity.bundleIdentifier
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .map { (pid: $0.processIdentifier, isFinished: $0.isTerminated) }
        switch SingleInstancePolicy.decide(selfPID: selfPID, peers: peers) {
        case .claim:
            // The kernel lock is authoritative. A busy lock with no discoverable
            // peer can be a launch race, a stale process scan, or an older build;
            // claiming here would recreate the duplicate-UI bug we are guarding.
            fputs("slot-dock: instance lock is busy but no peer was discoverable; refusing a second UI\n", stderr)
            return false
        case .handoff(let existingPID):
            SlotDockTelemetry.appLifecycle.info(
                "Second instance → handoff to pid=\(existingPID, privacy: .public)"
            )
            fputs("slot-dock: another instance is running (pid \(existingPID)); focusing it\n", stderr)
            if let app = NSRunningApplication(processIdentifier: existingPID) {
                app.activate(options: [.activateAllWindows])
            }
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name(SlotDockIPC.focusNotificationName),
                object: nil,
                userInfo: ["fromPID": selfPID],
                deliverImmediately: true
            )
            return false
        }
    }

    private static func acquireLock() -> LockAttempt {
        if lockFD >= 0 { return .acquired }
        let url = SlotStore.defaultConfigURL()
            .deletingLastPathComponent()
            .appendingPathComponent("instance.lock", isDirectory: false)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: url.deletingLastPathComponent().path
            )
        } catch {
            return .unavailable
        }
        let fd = open(url.path, O_RDWR | O_CREAT, mode_t(0o600))
        guard fd >= 0 else { return .unavailable }
        // `open` does not tighten permissions on an existing file.
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let busy = errno == EWOULDBLOCK || errno == EAGAIN
            close(fd)
            return busy ? .busy : .unavailable
        }
        lockFD = fd
        return .acquired
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var store: SlotDockStore = {
        SlotDockStore(configURL: Self.configURLFromEnvironment())
    }()
    private lazy var dockController: DockWindowController = {
        DockWindowController(store: store)
    }()
    private var statusItem: NSStatusItem?
    private let hotkeys = HotkeyManager()
    private var observers: [NSObjectProtocol] = []
    private var dockWatcher: DockPlistWatcher?
    private var focusObserver: NSObjectProtocol?

    private static func configURLFromEnvironment() -> URL {
        if let override = ProcessInfo.processInfo.environment["SLOT_DOCK_CONFIG"],
           !override.isEmpty
        {
            return URL(fileURLWithPath: override)
        }
        return SlotStore.defaultConfigURL()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["SLOT_DOCK_REGULAR"] == "1" {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

        store.syncLaunchAtLoginFromPreferences()
        dockController.show()

        installFocusHandoffListener()
        syncStatusItem()
        reinstallHotkeys()
        installDockWatcher()

        observers.append(NotificationCenter.default.addObserver(
            forName: .slotDockHotkeysDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reinstallHotkeys() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .slotDockStatusItemPreferenceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncStatusItem() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .slotDockSafeAreaPreferenceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dockController.syncSafeArea() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .slotDockRequestAccessibility,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dockController.safeArea.requestTrustIfNeeded() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .slotDockCollisionPromptMayNeed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                CollisionGuidePrompt.presentIfNeeded(store: self.store)
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .slotDockOpenCollisionGuide,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dockController.openSettings(tab: .options) }
        })

        if SlotDockHeadless.isSelfTest {
            SlotDockHeadless.runSelfTestAndExit(store: store, dockController: dockController)
        } else if !SlotDockHeadless.isHeadless {
            // Start collapsed so launch never produces an unsolicited reveal /
            // hide animation. A deliberately persistent configuration still
            // honors its intent and opens immediately.
            if store.preferences.pinOpen || !store.preferences.autoHide {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self else { return }
                    self.store.beginReveal()
                    self.dockController.syncRevealAnimated(duration: 0.25)
                    self.dockController.syncSafeArea()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                // One-shot compatibility prompt (not every launch if dismissed).
                CollisionGuidePrompt.presentIfNeeded(store: self.store)
            }
        }

        SlotDockTelemetry.appLifecycle.info(
            "Launched custom=\(self.store.slots.count, privacy: .public) system=\(self.store.systemDockEntries.count, privacy: .public) display=\(self.store.displayItems.count, privacy: .public) mode=\(self.store.preferences.systemDockIntegration.rawValue, privacy: .public) transientRunning=\(self.store.preferences.showTransientRunningApps, privacy: .public) tooltips=\(self.store.preferences.showIconTooltips, privacy: .public)"
        )
        fputs(
            "slot-dock: launched custom=\(store.slots.count) system=\(store.systemDockEntries.count) display=\(store.displayItems.count) mode=\(store.preferences.systemDockIntegration.rawValue)\n",
            stderr
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Cheap reconciliation when focus returns (missed terminate, Dock edit while away).
        SlotDockTelemetry.appLifecycle.debug("applicationDidBecomeActive — reconcile dock + running")
        _ = store.refreshSystemDock()
        dockController.runningApps.refresh(reason: "app-active", immediate: true)
        dockController.relayout(animated: true)
    }

    private func installDockWatcher() {
        let watcher = DockPlistWatcher { [weak store, weak dockController] in
            Task { @MainActor in
                SlotDockTelemetry.systemDock.debug("Dock plist changed — refresh")
                _ = store?.refreshSystemDock()
                dockController?.relayout(animated: true)
            }
        }
        watcher.start(watching: SystemDockReader.defaultPlistURL)
        dockWatcher = watcher
    }

    func applicationWillTerminate(_ notification: Notification) {
        dockController.invalidate()
        dockWatcher?.stop()
        hotkeys.invalidate()
        if let focusObserver {
            DistributedNotificationCenter.default().removeObserver(focusObserver)
            self.focusObserver = nil
        }
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        SlotDockTelemetry.appLifecycle.info("Terminated")
    }

    // MARK: - Status item (right side of menu bar only)

    private func syncStatusItem() {
        if store.preferences.showStatusItem {
            if statusItem == nil {
                installStatusItem()
            }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // Distinct from document icons; template so it matches system bar.
            button.image = NSImage(
                systemSymbolName: "rectangle.stack.fill",
                accessibilityDescription: "Slot Dock"
            )
            button.image?.isTemplate = true
            button.toolTip = "Slot Dock"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildStatusMenu(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildStatusMenu(menu)
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let hk = store.preferences.hotkeys

        let showTitle = store.reveal.isRevealed ? "Hide Dock" : "Show Dock"
        addBoundItem(menu, title: showTitle, action: #selector(toggleDock), binding: hk.toggleDock)

        let pin = addBoundItem(menu, title: "Pin Open", action: #selector(togglePin), binding: hk.pinOpen)
        pin.state = store.preferences.pinOpen ? .on : .off

        if let message = [store.configurationError, store.safeAreaError, store.lastLaunchError].compactMap({ $0 }).first {
            let problem = NSMenuItem(title: "⚠ (message)", action: #selector(openSettings), keyEquivalent: "")
            problem.target = self
            problem.toolTip = message
            menu.addItem(problem)
        }

        menu.addItem(.separator())

        if store.displayItems.isEmpty {
            let empty = NSMenuItem(title: "No Apps", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let launchHeader = NSMenuItem(title: "Launch", action: nil, keyEquivalent: "")
            launchHeader.isEnabled = false
            menu.addItem(launchHeader)
            for (index, composed) in store.displayItems.enumerated() {
                var digitBinding = KeyBinding.unbound
                if hk.launchSlotDigits.isBound, index < 9 {
                    digitBinding = hk.launchSlotDigits
                    digitBinding.keyEquivalent = "\(index + 1)"
                    digitBinding.enabled = true
                }
                let suffix = composed.origin == .systemDock ? "" : ""
                let item = addBoundItem(
                    menu,
                    title: "  \(composed.slot.label)\(suffix)",
                    action: #selector(launchSlot(_:)),
                    binding: digitBinding
                )
                item.representedObject = composed.slot.id
                if let icon = statusIcon(for: composed.slot) {
                    icon.size = NSSize(width: 16, height: 16)
                    item.image = icon
                }
            }
        }

        menu.addItem(.separator())

        // Options submenu (no key equivalents)
        let options = NSMenu(title: "Options")
        let sizeMenu = NSMenu(title: "Icon Size")
        for size in DockPreferences.IconSize.allCases {
            let item = NSMenuItem(title: size.displayName, action: #selector(setIconSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            item.state = store.preferences.iconSize == size ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeRoot = NSMenuItem(title: "Icon Size", action: nil, keyEquivalent: "")
        sizeRoot.submenu = sizeMenu
        options.addItem(sizeRoot)

        let alignMenu = NSMenu(title: "Position")
        for align in DockPreferences.Alignment.allCases {
            let item = NSMenuItem(title: align.displayName, action: #selector(setAlignment(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = align.rawValue
            item.state = store.preferences.alignment == align ? .on : .off
            alignMenu.addItem(item)
        }
        let alignRoot = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        alignRoot.submenu = alignMenu
        options.addItem(alignRoot)

        options.addItem(.separator())
        let autoHide = NSMenuItem(title: "Auto-Hide", action: #selector(toggleAutoHide), keyEquivalent: "")
        autoHide.target = self
        autoHide.state = store.preferences.autoHide ? .on : .off
        autoHide.isEnabled = !store.preferences.pinOpen
        options.addItem(autoHide)

        let edge = NSMenuItem(title: "Edge Hover", action: #selector(toggleEdgeHover), keyEquivalent: "")
        edge.target = self
        edge.state = store.preferences.edgeHover ? .on : .off
        options.addItem(edge)

        let labels = NSMenuItem(title: "Show Labels", action: #selector(toggleLabels), keyEquivalent: "")
        labels.target = self
        labels.state = store.preferences.showLabels ? .on : .off
        options.addItem(labels)

        let tooltips = NSMenuItem(title: "Icon Tooltips", action: #selector(toggleIconTooltips), keyEquivalent: "")
        tooltips.target = self
        tooltips.state = store.preferences.showIconTooltips ? .on : .off
        options.addItem(tooltips)

        let feedback = NSMenuItem(title: "Launch Feedback", action: #selector(toggleFeedback), keyEquivalent: "")
        feedback.target = self
        feedback.state = store.preferences.launchFeedback ? .on : .off
        options.addItem(feedback)

        options.addItem(.separator())
        let sysMenu = NSMenu(title: "System Dock")
        let macSettings = NSMenuItem(title: "Mac Dock Settings…", action: #selector(openMacDockSettings), keyEquivalent: "")
        macSettings.target = self
        macSettings.toolTip = "Open System Settings → Desktop & Dock"
        sysMenu.addItem(macSettings)
        sysMenu.addItem(.separator())
        for mode in SystemDockIntegration.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(setSystemDockMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = store.preferences.systemDockIntegration == mode ? .on : .off
            sysMenu.addItem(item)
        }
        sysMenu.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh from Dock", action: #selector(refreshSystemDock), keyEquivalent: "")
        refresh.target = self
        sysMenu.addItem(refresh)
        let importItem = NSMenuItem(title: "Import as Custom Slots", action: #selector(importSystemDock), keyEquivalent: "")
        importItem.target = self
        sysMenu.addItem(importItem)
        let sysRoot = NSMenuItem(title: "System Dock", action: nil, keyEquivalent: "")
        sysRoot.submenu = sysMenu
        options.addItem(sysRoot)

        options.addItem(.separator())
        let allOpts = NSMenuItem(title: "All Options…", action: #selector(openOptions), keyEquivalent: "")
        allOpts.target = self
        options.addItem(allOpts)

        let optionsRoot = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        optionsRoot.submenu = options
        menu.addItem(optionsRoot)

        addBoundItem(menu, title: "Edit Settings…", action: #selector(openSettings), binding: hk.openSettings)

        menu.addItem(.separator())
        addBoundItem(menu, title: "Quit Slot Dock", action: #selector(NSApplication.terminate(_:)), binding: hk.quit)
    }

    @discardableResult
    private func addBoundItem(
        _ menu: NSMenu,
        title: String,
        action: Selector?,
        binding: KeyBinding
    ) -> NSMenuItem {
        let (key, mask) = HotkeyManager.menuKey(for: binding)
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mask
        item.target = self
        menu.addItem(item)
        return item
    }

    private func reinstallHotkeys() {
        hotkeys.onReportChange = { [weak self] report in
            self?.store.applyHotkeyReport(report)
        }
        let hk = store.preferences.hotkeys
        hotkeys.apply(hotkeys: hk, handlers: [
            .toggleDock: { [weak self] in self?.toggleDock() },
            .openSettings: { [weak self] in self?.openSettings() },
            .pinOpen: { [weak self] in self?.togglePin() },
            .quit: { NSApp.terminate(nil) },
            .slot1: { [weak self] in self?.launchSlotIndex(0) },
            .slot2: { [weak self] in self?.launchSlotIndex(1) },
            .slot3: { [weak self] in self?.launchSlotIndex(2) },
            .slot4: { [weak self] in self?.launchSlotIndex(3) },
            .slot5: { [weak self] in self?.launchSlotIndex(4) },
            .slot6: { [weak self] in self?.launchSlotIndex(5) },
            .slot7: { [weak self] in self?.launchSlotIndex(6) },
            .slot8: { [weak self] in self?.launchSlotIndex(7) },
            .slot9: { [weak self] in self?.launchSlotIndex(8) },
        ])
        store.applyHotkeyReport(hotkeys.lastReport)
        if let menu = statusItem?.menu {
            rebuildStatusMenu(menu)
        }
    }

    private func installFocusHandoffListener() {
        focusObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(SlotDockIPC.focusNotificationName),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                SlotDockTelemetry.appLifecycle.info("Focus handoff received — reveal strip")
                self.store.beginReveal()
                self.dockController.syncRevealAnimated()
                self.dockController.show()
                if self.store.preferences.showStatusItem {
                    // Nudge activation for accessory apps
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    private func launchSlotIndex(_ index: Int) {
        guard store.displayItems.indices.contains(index) else { return }
        _ = store.launch(slotID: store.displayItems[index].slot.id)
    }

    @objc private func setSystemDockMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = SystemDockIntegration(rawValue: raw) else { return }
        store.setSystemDockIntegration(mode)
        dockController.relayout(animated: true)
    }

    @objc private func refreshSystemDock() {
        _ = store.refreshSystemDock()
        dockController.relayout(animated: true)
    }

    @objc private func importSystemDock() {
        _ = store.importSystemDockAsCustomSlots()
        dockController.relayout(animated: true)
    }

    private func statusIcon(for slot: Slot) -> NSImage? {
        let request = LaunchResolver.resolve(slot: slot)
        if request.kind == .application || request.kind == .file, !request.resolvedTarget.isEmpty {
            return NSWorkspace.shared.icon(forFile: request.resolvedTarget)
        }
        if request.kind == .url {
            return NSImage(systemSymbolName: "link", accessibilityDescription: slot.label)
        }
        return nil
    }

    // MARK: - Actions

    @objc private func toggleDock() {
        store.toggleReveal()
        dockController.syncRevealAnimated()
        dockController.show()
    }

    @objc private func openSettings() {
        dockController.openSettings(tab: .slots)
    }

    @objc private func openOptions() {
        dockController.openSettings(tab: .options)
    }

    @objc private func togglePin() {
        store.setPinOpen(!store.preferences.pinOpen)
        if store.preferences.pinOpen {
            store.beginReveal()
            dockController.syncRevealAnimated()
        }
        dockController.relayout(animated: true)
    }

    @objc private func toggleAutoHide() {
        store.setAutoHide(!store.preferences.autoHide)
    }

    @objc private func toggleEdgeHover() {
        store.setEdgeHover(!store.preferences.edgeHover)
    }

    @objc private func toggleLabels() {
        store.setShowLabels(!store.preferences.showLabels)
        dockController.relayout(animated: true)
    }

    @objc private func toggleIconTooltips() {
        store.setShowIconTooltips(!store.preferences.showIconTooltips)
    }

    @objc private func openMacDockSettings() {
        store.openMacDockSettings()
    }

    @objc private func toggleFeedback() {
        store.setLaunchFeedback(!store.preferences.launchFeedback)
    }

    @objc private func setIconSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = DockPreferences.IconSize(rawValue: raw) else { return }
        store.setIconSize(size)
        dockController.relayout(animated: true)
    }

    @objc private func setAlignment(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let align = DockPreferences.Alignment(rawValue: raw) else { return }
        store.setAlignment(align)
        dockController.relayout(animated: true)
    }

    @objc private func launchSlot(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        _ = store.launch(slotID: id)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
