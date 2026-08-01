import Foundation
import Testing
@testable import SlotDockCore

@Suite("SystemDockReader + SlotComposer")
struct SystemDockReaderTests {
    @Test("normalization resolves existing symlinks")
    func resolvesSymlinkIdentity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("slot-dock-symlink-\(UUID().uuidString)")
        let target = root.appendingPathComponent("target")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("target".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(SystemDockEntry.canonicalIdentityPath(link.path) == target.path)
    }

    /// Minimal XML plist fixture matching Dock persistent-apps shape.
    private func fixturePlistData() throws -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>persistent-apps</key>
          <array>
            <dict>
              <key>GUID</key>
              <integer>100</integer>
              <key>tile-type</key>
              <string>file-tile</string>
              <key>tile-data</key>
              <dict>
                <key>file-label</key>
                <string>Safari</string>
                <key>bundle-identifier</key>
                <string>com.apple.Safari</string>
                <key>file-data</key>
                <dict>
                  <key>_CFURLString</key>
                  <string>file:///Applications/Safari.app/</string>
                  <key>_CFURLStringType</key>
                  <integer>15</integer>
                </dict>
              </dict>
            </dict>
            <dict>
              <key>GUID</key>
              <integer>101</integer>
              <key>tile-type</key>
              <string>spacer-tile</string>
              <key>tile-data</key>
              <dict/>
            </dict>
            <dict>
              <key>GUID</key>
              <integer>102</integer>
              <key>tile-type</key>
              <string>file-tile</string>
              <key>tile-data</key>
              <dict>
                <key>file-label</key>
                <string>Chrome</string>
                <key>bundle-identifier</key>
                <string>com.google.Chrome</string>
                <key>file-data</key>
                <dict>
                  <key>_CFURLString</key>
                  <string>file:///Applications/Google%20Chrome.app/</string>
                  <key>_CFURLStringType</key>
                  <integer>15</integer>
                </dict>
              </dict>
            </dict>
          </array>
        </dict>
        </plist>
        """
        return Data(xml.utf8)
    }

    @Test("parses persistent-apps, skips spacers, normalizes paths")
    func parsesApps() throws {
        let entries = SystemDockReader.parsePersistentApps(from: try fixturePlistData())
        #expect(entries.count == 2)
        #expect(entries[0].label == "Safari")
        #expect(entries[0].path == "/Applications/Safari.app")
        #expect(entries[0].bundleIdentifier == "com.apple.Safari")
        #expect(entries[0].guid == 100)
        #expect(entries[1].label == "Chrome")
        #expect(entries[1].path == "/Applications/Google Chrome.app")
        #expect(entries[1].normalizedPath == "/Applications/Google Chrome.app")
    }

    @Test("normalizePath strips file URL and trailing slash")
    func normalizePath() {
        #expect(
            SystemDockEntry.normalizePath("file:///Applications/Safari.app/")
                == "/Applications/Safari.app"
        )
        #expect(
            SystemDockEntry.normalizePath("/Applications/Foo.app/")
                == "/Applications/Foo.app"
        )
    }

    @Test("skips folders and generic file tiles")
    func skipsNonApplicationTiles() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>persistent-apps</key>
          <array>
            <dict>
              <key>tile-type</key><string>file-tile</string>
              <key>tile-data</key><dict>
                <key>file-label</key><string>Document</string>
                <key>file-data</key><dict>
                  <key>_CFURLString</key><string>file:///Users/me/readme.pdf</string>
                </dict>
              </dict>
            </dict>
            <dict>
              <key>tile-type</key><string>directory-tile</string>
              <key>tile-data</key><dict/>
            </dict>
          </array>
        </dict>
        </plist>
        """
        // A Dock plist can contain file and folder tiles under adjacent keys;
        // Slot Dock must not present those as launchable application slots.
        let entries = SystemDockReader.parsePersistentApps(from: Data(xml.utf8))
        #expect(entries.isEmpty)
    }

    @Test("system Dock identities include path and do not collide on bundle id")
    func systemIdentityIncludesPath() {
        let a = SystemDockEntry(label: "A", path: "/Applications/A.app", bundleIdentifier: "com.example.same", guid: 1)
        let b = SystemDockEntry(label: "B", path: "/Volumes/Other/A.app", bundleIdentifier: "com.example.same", guid: 2)
        #expect(a.id != b.id)
        #expect(SystemDockReader.slot(from: a).id != SystemDockReader.slot(from: b).id)
    }

    @Test("compose off shows only custom")
    func composeOff() {
        let custom = [Slot(id: "c1", label: "Custom", target: "/c", sortOrder: 0)]
        let system = [SystemDockEntry(label: "Safari", path: "/Applications/Safari.app")]
        let items = SlotComposer.compose(custom: custom, system: system, mode: .off)
        #expect(items.count == 1)
        #expect(items[0].origin == .custom)
        #expect(items[0].slot.id == "c1")
    }

    @Test("compose mirror shows only system in Dock order")
    func composeMirror() {
        let custom = [Slot(id: "c1", label: "Custom", target: "/c", sortOrder: 0)]
        let system = [
            SystemDockEntry(label: "Safari", path: "/Applications/Safari.app"),
            SystemDockEntry(label: "Chrome", path: "/Applications/Google Chrome.app"),
        ]
        let items = SlotComposer.compose(custom: custom, system: system, mode: .mirror)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.origin == .systemDock })
        #expect(items[0].slot.label == "Safari")
        #expect(items[1].slot.label == "Chrome")
        #expect(items[0].slot.id.hasPrefix("sysdock:"))
    }

    @Test("compose merge: custom left, system Dock next; dedupes path")
    func composeMerge() {
        let custom = [
            Slot(id: "c1", label: "My Safari", target: "/Applications/Safari.app/", sortOrder: 0),
            Slot(id: "c2", label: "Notes", target: "/System/Applications/Notes.app", sortOrder: 1),
        ]
        let system = [
            SystemDockEntry(label: "Safari", path: "/Applications/Safari.app"),
            SystemDockEntry(label: "Chrome", path: "/Applications/Google Chrome.app"),
        ]
        let items = SlotComposer.compose(custom: custom, system: system, mode: .merge)
        // My Safari (custom), Notes (custom), Chrome (system) — system Safari deduped by custom path
        #expect(items.count == 3)
        #expect(items[0].origin == .custom)
        #expect(items[0].slot.label == "My Safari")
        #expect(items[1].origin == .custom)
        #expect(items[1].slot.label == "Notes")
        #expect(items[2].origin == .systemDock)
        #expect(items[2].slot.label == "Chrome")
    }

    @Test("importableSystemEntries excludes paths already custom")
    func importable() {
        let custom = [Slot(id: "c", label: "S", target: "/Applications/Safari.app", sortOrder: 0)]
        let system = [
            SystemDockEntry(label: "Safari", path: "/Applications/Safari.app/"),
            SystemDockEntry(label: "Chrome", path: "/Applications/Google Chrome.app"),
        ]
        let imp = SlotComposer.importableSystemEntries(system: system, custom: custom)
        #expect(imp.count == 1)
        #expect(imp[0].label == "Chrome")
        #expect(SlotComposer.isAlreadyCustom(entry: system[0], custom: custom) == true)
        #expect(SlotComposer.isAlreadyCustom(entry: system[1], custom: custom) == false)
        #expect(SlotComposer.entryMatchingPath("/Applications/Safari.app/", in: system)?.label == "Safari")
    }

    @Test("SystemDockDragPayload round-trips path and label")
    func dragPayload() {
        let entry = SystemDockEntry(label: "Safari", path: "/Applications/Safari.app/")
        let encoded = SystemDockDragPayload.encode(entry)
        let decoded = SystemDockDragPayload.decode(encoded)
        #expect(decoded?.path == "/Applications/Safari.app")
        #expect(decoded?.label == "Safari")
        // Plain path drop (Finder).
        let plain = SystemDockDragPayload.decode("file:///Applications/Notes.app/")
        #expect(plain?.path == "/Applications/Notes.app")
        #expect(plain?.label == "Notes")
    }

    @Test("read from missing file returns empty")
    func missingFile() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-slot-dock-\(UUID().uuidString).plist")
        #expect(SystemDockReader.readPersistentApps(from: url).isEmpty)
    }

    @Test("read real Dock plist when present")
    func readLiveDockIfPresent() {
        let url = SystemDockReader.defaultPlistURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            // CI / headless without Dock prefs — skip soft
            return
        }
        let entries = SystemDockReader.readPersistentApps(from: url)
        // User machine has Dock apps; assert parse doesn't crash and paths look absolute.
        for e in entries {
            #expect(e.path.hasPrefix("/"))
            #expect(!e.label.isEmpty)
        }
    }

    @Test("compose-after-dock-change updates strip without restart")
    func composeAfterDockChange() throws {
        // Simulate two Dock membership snapshots (plist re-read).
        let before = SystemDockReader.parsePersistentApps(from: try fixturePlistData())
        #expect(before.count == 2)

        let afterXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>persistent-apps</key>
          <array>
            <dict>
              <key>GUID</key><integer>1</integer>
              <key>tile-type</key><string>file-tile</string>
              <key>tile-data</key>
              <dict>
                <key>file-label</key><string>Notes</string>
                <key>file-data</key>
                <dict>
                  <key>_CFURLString</key>
                  <string>file:///System/Applications/Notes.app/</string>
                  <key>_CFURLStringType</key><integer>15</integer>
                </dict>
              </dict>
            </dict>
          </array>
        </dict>
        </plist>
        """
        let after = SystemDockReader.parsePersistentApps(from: Data(afterXML.utf8))
        #expect(after.count == 1)
        #expect(after[0].label == "Notes")

        let custom = [Slot(id: "c", label: "Custom", target: "/opt/custom.app", sortOrder: 0)]
        let itemsBefore = SlotComposer.compose(custom: custom, system: before, mode: .merge)
        let itemsAfter = SlotComposer.compose(custom: custom, system: after, mode: .merge)
        #expect(itemsBefore.count == 3) // Custom, Safari, Chrome
        #expect(itemsAfter.count == 2) // Custom, Notes
        #expect(itemsBefore[0].origin == .custom)
        #expect(itemsBefore[0].slot.label == "Custom")
        #expect(itemsAfter[0].origin == .custom)
        #expect(itemsAfter[0].slot.label == "Custom")
        #expect(itemsAfter.map(\.slot.label).contains("Notes"))
        // Prove recompose is a pure function of latest system snapshot (no restart needed).
        #expect(itemsBefore.map(\.slot.label) != itemsAfter.map(\.slot.label))
    }
}
