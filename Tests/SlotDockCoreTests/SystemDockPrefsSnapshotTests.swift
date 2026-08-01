import Foundation
import Testing
@testable import SlotDockCore

@Suite("SystemDockPrefsSnapshot")
struct SystemDockPrefsSnapshotTests {
    @Test("capture reads present and absent keys")
    func capture() {
        let values: [String: Any] = [
            "autohide": true,
            "autohide-delay": 0.5,
        ]
        let snap = SystemDockPrefsSnapshot.capture(note: "test") { key in
            values[key]
        }
        #expect(snap.autohide == true)
        #expect(snap.autohidePresent == true)
        #expect(snap.autohideDelay == 0.5)
        #expect(snap.autohideDelayPresent == true)
        #expect(snap.autohideTimeModifierPresent == false)
        #expect(snap.note == "test")
    }

    @Test("restoreScript writes present keys and deletes absent ones")
    func restoreScript() {
        let snap = SystemDockPrefsSnapshot(
            autohide: false,
            autohidePresent: true,
            autohideDelay: nil,
            autohideDelayPresent: false,
            autohideTimeModifier: 0.4,
            autohideTimeModifierPresent: true
        )
        let script = snap.restoreScript()
        #expect(script.contains("defaults write com.apple.dock autohide -bool false"))
        #expect(script.contains("defaults delete com.apple.dock autohide-delay"))
        #expect(script.contains("defaults write com.apple.dock autohide-time-modifier -float 0.4"))
        #expect(script.contains("killall Dock"))
    }

    @Test("restoreScript keeps multiline notes as comments and rejects nonfinite numbers")
    func restoreScriptIsFailClosed() {
        let snap = SystemDockPrefsSnapshot(
            autohideDelay: .nan,
            autohideDelayPresent: true,
            note: "operator note\n/usr/bin/touch /tmp/should-not-run"
        )
        let script = snap.restoreScript()
        #expect(script.hasPrefix("set -euo pipefail\n"))
        #expect(script.contains("# note: operator note"))
        #expect(script.contains("# note: /usr/bin/touch /tmp/should-not-run"))
        #expect(!script.contains("\n/usr/bin/touch /tmp/should-not-run"))
        #expect(script.contains("defaults delete com.apple.dock autohide-delay"))
        #expect(!script.contains("-float nan"))
    }

    @Test("capture preserves presence while rejecting nonfinite values")
    func captureRejectsNonfinite() {
        let snapshot = SystemDockPrefsSnapshot.capture { key in
            key == "autohide-delay" ? Double.infinity : nil
        }
        #expect(snapshot.autohideDelay == nil)
        #expect(snapshot.autohideDelayPresent == true)
    }

    @Test("managed value comparison ignores backup metadata")
    func managedValueComparison() {
        let base = SystemDockPrefsSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1),
            autohide: true,
            autohidePresent: true,
            autohideDelay: 5,
            autohideDelayPresent: true,
            note: "old"
        )
        let sameValues = SystemDockPrefsSnapshot(
            capturedAt: Date(timeIntervalSince1970: 2),
            autohide: true,
            autohidePresent: true,
            autohideDelay: 5,
            autohideDelayPresent: true,
            note: "new"
        )
        let changed = SystemDockPrefsSnapshot(
            autohide: false,
            autohidePresent: true,
            autohideDelay: 5,
            autohideDelayPresent: true
        )
        #expect(base.managedValuesEqual(to: sameValues))
        #expect(!base.managedValuesEqual(to: changed))
    }

    @Test("round-trip JSON save/load")
    func jsonRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slot-dock-snap-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent("backup.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = SystemDockPrefsSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            autohide: true,
            autohidePresent: true,
            autohideDelay: 5,
            autohideDelayPresent: true,
            autohideTimeModifierPresent: false,
            note: "unit"
        )
        #expect(original.save(to: url) == true)
        let loaded = SystemDockPrefsSnapshot.load(from: url)
        #expect(loaded != nil)
        #expect(loaded?.autohide == true)
        #expect(loaded?.autohideDelay == 5)
        #expect(loaded?.autohideDelayPresent == true)
        #expect(loaded?.autohideTimeModifierPresent == false)
        #expect(loaded?.note == "unit")
    }

    @Test("recommended script matches raise delay")
    func recommended() {
        let s = SystemDockRecommended.applyScript()
        #expect(s.contains("autohide -bool true"))
        #expect(s.contains("autohide-delay -float 5"))
        #expect(s.contains("killall Dock"))
    }
}
