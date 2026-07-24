import AppKit
import Darwin
import Foundation

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
                    let ok = dockVisible && store.reveal.progress > 0 && displayCount >= 0

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
                        "icon_size": store.preferences.iconSize.rawValue,
                        "app": "nicos-slot-dock",
                    ]

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
                        try? data.write(to: url)
                        fputs("slot-dock: wrote report \(reportPath)\n", stderr)
                    }

                    fputs("slot-dock: self-test ok=\(ok) phase=\(phase) slots=\(slotCount)\n", stderr)
                    Darwin.exit(ok ? 0 : 1)
                }
            }
        }
    }
}
