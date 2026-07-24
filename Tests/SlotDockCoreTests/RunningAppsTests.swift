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
