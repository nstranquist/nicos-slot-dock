import Foundation
import Testing
@testable import SlotDockCore

@Suite("TransientRunningApps + compose")
struct TransientRunningAppsTests {
    @Test("extras excludes paths already on the strip but keeps same-bundle other path")
    func extrasFilter() {
        let running = [
            RunningAppInfo(bundleIdentifier: "com.a", path: "/Apps/A.app", name: "A"),
            RunningAppInfo(bundleIdentifier: "com.b", path: "/Apps/B.app", name: "B"),
            RunningAppInfo(bundleIdentifier: "com.b", path: "/Volumes/Other/B.app", name: "B Other"),
            RunningAppInfo(bundleIdentifier: "com.c", path: "/Apps/C.app", name: "C"),
        ]
        let extras = TransientRunningApps.extras(
            running: running,
            stripPaths: ["/Apps/A.app"]
        )
        #expect(extras.map(\.name) == ["B", "B Other", "C"])
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

    @Test("same-bundle other path becomes its own running tile")
    func composeAddsExtraTileForOtherPath() {
        let system = [SystemDockEntry(
            label: "Editor",
            path: "/Applications/Editor.app",
            bundleIdentifier: "com.example.Editor"
        )]
        let running = [RunningAppInfo(
            bundleIdentifier: "com.example.Editor",
            path: "/Volumes/Other/Editor.app",
            name: "Editor",
            processIDs: [42]
        )]
        let snapshot = RunningAppSnapshot(
            bundleIdentifiers: ["com.example.Editor"],
            paths: ["/Volumes/Other/Editor.app"],
            apps: running
        )
        let items = SlotComposer.compose(
            custom: [],
            system: system,
            mode: .merge,
            runningApps: running,
            includeRunningExtras: false
        )
        #expect(items.count == 2)
        #expect(items[0].origin == .systemDock)
        #expect(items[1].origin == .running)
        #expect(items[1].slot.target.contains("Other"))
        #expect(RunningIndicator.shouldShowDot(for: items[0].slot, running: snapshot) == false)
        #expect(RunningIndicator.shouldShowDot(for: items[1].slot, running: snapshot) == true)
    }

    @Test("same path twice in the running list is one tile with a stacked mark")
    func composeGroupsSamePathInstances() {
        let running = [
            RunningAppInfo(
                bundleIdentifier: "com.example.Editor",
                path: "/Applications/Editor.app",
                name: "Editor",
                processIDs: [10]
            ),
            RunningAppInfo(
                bundleIdentifier: "com.example.Editor",
                path: "/Applications/Editor.app",
                name: "Editor",
                processIDs: [11]
            ),
        ]
        let grouped = RunningAppGrouping.group(running)
        #expect(grouped.count == 1)
        #expect(grouped[0].instanceCount == 2)
        let snapshot = RunningAppSnapshot(
            bundleIdentifiers: ["com.example.Editor"],
            paths: ["/Applications/Editor.app"],
            apps: grouped
        )
        let items = SlotComposer.compose(
            custom: [],
            system: [],
            mode: .off,
            runningApps: running,
            includeRunningExtras: true
        )
        #expect(items.count == 1)
        let mark = RunningIndicator.presentation(for: items[0].slot, running: snapshot)
        #expect(mark.isRunning)
        #expect(mark.instanceCount == 2)
        #expect(mark.showsStackedMark)
    }

    @Test("same path already on the strip is not duplicated as a transient")
    func composeDoesNotDuplicateSystemBundle() {
        let system = [SystemDockEntry(
            label: "Safari",
            path: "/Applications/Safari.app",
            bundleIdentifier: "com.apple.Safari"
        )]
        let running = [RunningAppInfo(
            bundleIdentifier: "com.apple.Safari",
            path: "/Applications/Safari.app",
            name: "Safari"
        )]
        let items = SlotComposer.compose(
            custom: [],
            system: system,
            mode: .merge,
            runningApps: running,
            includeRunningExtras: true
        )
        #expect(items.count == 1)
        #expect(items[0].origin == .systemDock)
    }
}
