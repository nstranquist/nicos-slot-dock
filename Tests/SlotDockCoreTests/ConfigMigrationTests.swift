import Foundation
import Testing
@testable import SlotDockCore

@Suite("Config migration (versioned slots.json)")
struct ConfigMigrationTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("slot-dock-migrate-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("slots.json")
    }

    private func fixture(_ name: String) -> URL {
        // Tests live next to Fixtures/ under SlotDockCoreTests.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
    }

    @Test("v1 document without preferences loads modern defaults and bumps version")
    func v1NoPrefsMigrates() throws {
        let src = fixture("slots-v1-no-prefs.json")
        #expect(FileManager.default.fileExists(atPath: src.path))
        let data = try Data(contentsOf: src)
        #expect(ConfigMigration.isLegacyV1Document(data))

        let dest = tempURL()
        defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: dest)

        let store = SlotStore(fileURL: dest)
        #expect(store.slots.count == 2)
        #expect(store.slots[0].label == "Finder")
        #expect(store.document.version == ConfigDocumentVersion.current)
        // Modern defaults present after migration
        #expect(store.preferences.showRunningDots == true)
        #expect(store.preferences.systemDockIntegration == .merge)
        #expect(store.preferences.launchAtLogin == false)
        #expect(store.preferences.showTransientRunningApps == false)
        #expect(store.preferences.autoHideDelay >= DockPreferences.minAutoHideDelay)

        // Reload from disk — version stayed modern
        let reloaded = SlotStore(fileURL: dest)
        #expect(reloaded.document.version == ConfigDocumentVersion.current)
        #expect(reloaded.slots.count == 2)
    }

    @Test("v1 partial preferences clamps delay and fills missing modern fields")
    func v1PartialPrefsMigrates() throws {
        let src = fixture("slots-v1-partial-prefs.json")
        let data = try Data(contentsOf: src)
        let dest = tempURL()
        defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: dest)

        let store = SlotStore(fileURL: dest)
        #expect(store.slots.count == 1)
        #expect(store.preferences.iconSize == .large)
        // 0.05 must clamp to min
        #expect(store.preferences.autoHideDelay == DockPreferences.minAutoHideDelay)
        #expect(store.document.version == ConfigDocumentVersion.current)
        #expect(store.preferences.showIconTooltips == true)
        #expect(store.preferences.hotkeys.globalEnabled == false)
    }

    @Test("migratePreferences pure helper marks legacy versions")
    func pureMigrate() {
        let (v, prefs, migrated) = ConfigMigration.migratePreferences(
            documentVersion: 1,
            preferences: nil
        )
        #expect(v == ConfigDocumentVersion.current)
        #expect(migrated == true)
        #expect(prefs.systemDockIntegration == .merge)

        let (_, _, notMigrated) = ConfigMigration.migratePreferences(
            documentVersion: ConfigDocumentVersion.current,
            preferences: .default
        )
        #expect(notMigrated == false)
    }
}
