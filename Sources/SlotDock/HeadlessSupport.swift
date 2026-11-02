import AppKit
import Darwin
import Foundation
import SlotDockCore

@MainActor
enum SlotDockHeadless {
    static let isHeadless: Bool = {
        guard let value = ProcessInfo.processInfo.environment["SLOT_DOCK_HEADLESS"] else { return false }
        return value == "1" || value.lowercased() == "true"
    }()

    static let isSelfTest: Bool = {
        ProcessInfo.processInfo.environment["SLOT_DOCK_SELFTEST"] == "1"
    }()

    private static let offscreenOrigin = NSPoint(x: -30_000, y: -30_000)

    static func parkOffscreenIfHeadless(_ window: NSWindow) {
        guard isHeadless, window.frame.origin != offscreenOrigin else { return }
        window.setFrameOrigin(offscreenOrigin)
    }

    static func surface(_ window: NSWindow) {
        if isHeadless {
            window.setFrameOrigin(offscreenOrigin)
        }
        // Never makeKeyAndOrderFront — the dock is a non-activating strip.
        // Stealing key window eats everyday typing in the frontmost app.
        window.orderFrontRegardless()
    }

    /// Headless smoke: boot app, open dock, write report, exit.
    static func runSelfTestAndExit(store: SlotDockStore, dockController: DockWindowController) {
        fputs("slot-dock: self-test begin\n", stderr)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            store.beginReveal()
            dockController.syncRevealAnimated(duration: 0.05)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                store.openSettings(tab: .options)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    let dockVisible = dockController.window?.isVisible == true
                    let phase = store.reveal.phase.rawValue
                    _ = store.refreshSystemDock()
                    let slotCount = store.slots.count
                    let displayCount = store.displayItems.count
                    let systemCount = store.systemDockEntries.count
                    let settingsValid = store.settingsOpen && store.settingsTab == .options
                    let uniqueDisplayIDs = Set(store.displayItems.map(\.id)).count == store.displayItems.count
                    let validOrigins = store.displayItems.allSatisfy { item in
                        switch item.origin {
                        case .custom, .systemDock, .running: return true
                        }
                    }
                    let compositionValid: Bool = {
                        let customCount = store.displayItems.filter { $0.origin == .custom }.count
                        let systemDisplayCount = store.displayItems.filter { $0.origin == .systemDock }.count
                        let runningDisplayCount = store.displayItems.filter { $0.origin == .running }.count
                        switch store.preferences.systemDockIntegration {
                        case .off:
                            return validOrigins && uniqueDisplayIDs
                                && customCount == slotCount
                                && systemDisplayCount == 0
                                && runningDisplayCount == 0
                                && displayCount == slotCount
                        case .mirror:
                            return validOrigins && uniqueDisplayIDs
                                && customCount == 0
                                && runningDisplayCount == 0
                                && systemDisplayCount == systemCount
                                && displayCount == systemCount
                                && store.displayItems.allSatisfy { $0.origin == .systemDock }
                        case .merge:
                            return validOrigins && uniqueDisplayIDs
                                && customCount == slotCount
                                && systemDisplayCount == systemCount
                                && displayCount == customCount + systemDisplayCount + runningDisplayCount
                        }
                    }()
                    let contextMenuValid = Self.contextMenusValid(store: store)
                    let ok = dockVisible
                        && phase == "expanded"
                        && store.reveal.progress >= 0.99
                        && settingsValid
                        && compositionValid
                        && contextMenuValid

                    let payload: [String: Any] = [
                        "ok": ok,
                        "dock_visible": dockVisible,
                        "reveal_phase": phase,
                        "reveal_progress": store.reveal.progress,
                        "slot_count": slotCount,
                        "display_count": displayCount,
                        "system_dock_count": systemCount,
                        "system_dock_mode": store.preferences.systemDockIntegration.rawValue,
                        "settings_open": store.settingsOpen,
                        "settings_tab": store.settingsTab.rawValue,
                        "settings_valid": settingsValid,
                        "composition_valid": compositionValid,
                        "context_menu_valid": contextMenuValid,
                        "icon_size": store.preferences.iconSize.rawValue,
                        "app": "nicos-slot-dock",
                    ]

                    var reportWritten = false
                    if let reportPath = ProcessInfo.processInfo.environment["SLOT_DOCK_SELFTEST_REPORT"],
                       !reportPath.isEmpty,
                       let data = try? JSONSerialization.data(
                        withJSONObject: payload,
                        options: [.prettyPrinted, .sortedKeys]
                       )
                    {
                        let url = URL(fileURLWithPath: reportPath)
                        try? FileManager.default.createDirectory(
                            at: url.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        do {
                            try data.write(to: url, options: .atomic)
                            reportWritten = true
                            fputs("slot-dock: wrote report\n", stderr)
                        } catch {
                            fputs("slot-dock: report write failed: \(error.localizedDescription)\n", stderr)
                        }
                    }

                    fputs("slot-dock: self-test ok=\(ok) phase=\(phase) slots=\(slotCount) report=\(reportWritten)\n", stderr)
                    Darwin.exit(ok && reportWritten ? 0 : 1)
                }
            }
        }
    }

    /// Build idle and running menus for strip tiles. Fail if Open / Get Info /
    /// Show All Windows / Hide Others / Relaunch are missing when required.
    static func contextMenusValid(store: SlotDockStore) -> Bool {
        let items = store.displayItems
        if items.isEmpty { return true }
        for item in items.prefix(12) {
            let request = LaunchResolver.resolve(slot: item.slot)
            let identity = AppIdentity.from(slot: item.slot)
            let isSelf = SlotAppMenuPolicy.isSelfApplication(
                bundleIdentifier: identity.bundleIdentifier
            )
            let idle = SlotContextMenuBuilder.buildSlotMenu(
                input: SlotContextMenuInput(
                    label: item.slot.label,
                    origin: item.origin,
                    kind: request.kind,
                    isRunning: false,
                    canOpenNewInstance: SlotContextMenuBuilder.canOpenNewInstance(
                        kind: request.kind,
                        path: request.resolvedTarget
                    ),
                    canImportAsCustom: item.origin != .custom,
                    customIndex: item.origin == .custom ? store.customIndex(of: item.slot.id) : nil,
                    customCount: store.slots.count,
                    bundleIdentifier: identity.bundleIdentifier,
                    isSelfApplication: isSelf
                )
            )
            guard idle.actionableItems.contains(where: { $0.action == .open }) else { return false }
            if SlotAppMenuPolicy.canGetInfo(kind: request.kind) {
                guard idle.actionableItems.contains(where: { $0.action == .getInfo }) else {
                    return false
                }
            }
            guard request.kind == .application else { continue }
            let running = SlotContextMenuBuilder.buildSlotMenu(
                input: SlotContextMenuInput(
                    label: item.slot.label,
                    origin: item.origin,
                    kind: request.kind,
                    isRunning: true,
                    canOpenNewInstance: SlotContextMenuBuilder.canOpenNewInstance(
                        kind: request.kind,
                        path: request.resolvedTarget
                    ),
                    canImportAsCustom: item.origin != .custom,
                    customIndex: item.origin == .custom ? store.customIndex(of: item.slot.id) : nil,
                    customCount: store.slots.count,
                    bundleIdentifier: identity.bundleIdentifier,
                    isSelfApplication: isSelf
                )
            )
            let actions = Set(running.actionableItems.compactMap(\.action))
            guard actions.contains(.showAllWindows), actions.contains(.hideOthers) else {
                return false
            }
            if !isSelf {
                guard actions.contains(.relaunchApplication) else { return false }
            }
        }
        return true
    }
}
