import Foundation
import Testing
@testable import SlotDockCore

@Suite("TransientRunningApps + compose")
struct TransientRunningAppsTests {
    @Test("extras excludes paths and bundles already on strip")
    func extrasFilter() {
        let running = [
            RunningAppInfo(bundleIdentifier: "com.a", path: "/Apps/A.app", name: "A"),
            RunningAppInfo(bundleIdentifier: "com.b", path: "/Apps/B.app", name: "B"),
            RunningAppInfo(bundleIdentifier: "com.c", path: "/Apps/C.app", name: "C"),
        ]
        let extras = TransientRunningApps.extras(
            running: running,
            stripPaths: ["/Apps/A.app"],
            stripBundles: ["com.b"]
        )
        #expect(extras.count == 1)
        #expect(extras[0].name == "C")
    }

    @Test("compose with includeRunningExtras appends after custom and system")
    func composeRunning() {
        let custom = [Slot(id: "c1", label: "Notes", target: "/System/Applications/Notes.app", sortOrder: 0)]
        let system = [SystemDockEntry(label: "Safari", path: "/Applications/Safari.app", bundleIdentifier: "com.apple.Safari")]
        let running = [
            RunningAppInfo(bundleIdentifier: "com.apple.Safari", path: "/Applications/Safari.app", name: "Safari"),
            RunningAppInfo(bundleIdentifier: "com.todesktop.cursor", path: "/Applications/Cursor.app", name: "Cursor"),
        ]
        let items = SlotComposer.compose(
            custom: custom,
            system: system,
            mode: .merge,
            runningApps: running,
            includeRunningExtras: true
        )
        // Notes (custom), Safari (system), Cursor (running) — Safari not duplicated as running
        #expect(items.count == 3)
        #expect(items[0].origin == .custom)
        #expect(items[0].slot.label == "Notes")
        #expect(items[1].origin == .systemDock)
        #expect(items[1].slot.label == "Safari")
        #expect(items[2].origin == .running)
        #expect(items[2].slot.label == "Cursor")
        #expect(items[2].slot.id.hasPrefix("running:"))
    }

    @Test("compose without includeRunningExtras ignores running list")
    func composeWithout() {
        let running = [
            RunningAppInfo(bundleIdentifier: "com.x", path: "/Apps/X.app", name: "X"),
        ]
        let items = SlotComposer.compose(
            custom: [],
            system: [],
            mode: .off,
            runningApps: running,
            includeRunningExtras: false
        )
        #expect(items.isEmpty)
    }
}
