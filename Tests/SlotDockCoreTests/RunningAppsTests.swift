import Foundation
import Testing
@testable import SlotDockCore

@Suite("RunningIndicator")
struct RunningAppsTests {
    @Test("running by bundle id shows dot")
    func byBundle() {
        let slot = Slot(id: "sysdock:com.apple.Safari", label: "Safari", target: "/Applications/Safari.app")
        let running = RunningAppSnapshot(bundleIdentifiers: ["com.apple.Safari"], paths: [])
        #expect(RunningIndicator.shouldShowDot(for: slot, running: running) == true)
    }

    @Test("running by path shows dot")
    func byPath() {
        let slot = Slot(id: "c1", label: "Chrome", target: "/Applications/Google Chrome.app/")
        let running = RunningAppSnapshot(
            bundleIdentifiers: [],
            paths: ["/Applications/Google Chrome.app"]
        )
        #expect(RunningIndicator.shouldShowDot(for: slot, running: running) == true)
    }

    @Test("running path matching is separator-aware")
    func runningPathDoesNotMatchPrefixSibling() {
        let snapshot = RunningAppSnapshot(paths: ["/Applications/Foo.app2"])
        let identity = AppIdentity(path: "/Applications/Foo.app")
        #expect(snapshot.isRunning(identity) == false)
    }

    @Test("bundle matches the paired application path when copies share an id")
    func sameBundleUsesPathIdentity() {
        let slot = Slot(
            id: "sysdock:com.example.Editor:/Applications/Editor.app",
            label: "Editor",
            target: "/Applications/Editor.app"
        )
        let running = RunningAppSnapshot(
            bundleIdentifiers: ["com.example.Editor"],
            paths: ["/Volumes/Other/Editor.app"],
            apps: [RunningAppInfo(
                bundleIdentifier: "com.example.Editor",
                path: "/Volumes/Other/Editor.app",
                name: "Editor"
            )]
        )
        #expect(RunningIndicator.shouldShowDot(for: slot, running: running) == false)
    }

    @Test("not running does not show dot")
    func notRunning() {
        let slot = Slot(id: "c1", label: "Notes", target: "/System/Applications/Notes.app")
        let running = RunningAppSnapshot(bundleIdentifiers: ["com.apple.Safari"], paths: [])
        #expect(RunningIndicator.shouldShowDot(for: slot, running: running) == false)
    }

    @Test("dotsBySlotID maps mixed set")
    func mapMixed() {
        let slots = [
            Slot(id: "sysdock:com.apple.Safari", label: "Safari", target: "/Applications/Safari.app"),
            Slot(id: "notes", label: "Notes", target: "/System/Applications/Notes.app"),
        ]
        let running = RunningAppSnapshot(bundleIdentifiers: ["com.apple.Safari"], paths: [])
        let map = RunningIndicator.dotsBySlotID(slots: slots, running: running)
        #expect(map["sysdock:com.apple.Safari"] == true)
        #expect(map["notes"] == false)
    }

    @Test("AppIdentity.from extracts sysdock bundle")
    func identityFromSysdock() {
        let slot = Slot(id: "sysdock:com.google.Chrome", label: "Chrome", target: "/Applications/Google Chrome.app")
        let id = AppIdentity.from(slot: slot)
        #expect(id.bundleIdentifier == "com.google.Chrome")
        #expect(id.path == "/Applications/Google Chrome.app")
    }
}
