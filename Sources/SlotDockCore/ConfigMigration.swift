import Foundation

/// Versioned slots.json document shape + migration helpers (pure, testable).
public enum ConfigDocumentVersion {
    /// Current on-disk schema version written by SlotStore.
    public static let current = 2
}

/// Applies forward migrations so older fixtures load with sane modern defaults.
public enum ConfigMigration {
    /// Normalize a decoded document dict (version + preferences presence).
    public static func migratePreferences(
        documentVersion: Int,
        preferences: DockPreferences?
    ) -> (version: Int, preferences: DockPreferences, migrated: Bool) {
        var prefs = preferences ?? .default
        prefs.sanitize()
        let migrated = documentVersion < ConfigDocumentVersion.current || preferences == nil
        return (ConfigDocumentVersion.current, prefs, migrated)
    }

    /// Whether a raw JSON payload looks like a pre-preferences v1 document.
    public static func isLegacyV1Document(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let version = obj["version"] as? Int ?? 1
        if version >= 2 { return false }
        return obj["preferences"] == nil
    }
}
