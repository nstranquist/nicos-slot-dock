import AppKit
import Foundation
import SlotDockCore

/// Live capture / restore of system Dock prefs Slot Dock may change.
/// Always user-triggered; auto-snapshot before first mutative helper in a session path.
@MainActor
enum SystemDockPrefsBackup {
    static var backupURL: URL { SystemDockPrefsSnapshot.defaultBackupURL }

    static var hasBackup: Bool {
        FileManager.default.fileExists(atPath: backupURL.path)
    }

    static func load() -> SystemDockPrefsSnapshot? {
        SystemDockPrefsSnapshot.load(from: backupURL)
    }

    /// Read current `com.apple.dock` values via CFPreferences.
    static func capture(note: String? = nil) -> SystemDockPrefsSnapshot {
        SystemDockPrefsSnapshot.capture(note: note) { key in
            CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString)
                .map { $0 as Any }
        }
    }

    @discardableResult
    static func saveSnapshot(note: String? = nil, force: Bool = false) -> SystemDockPrefsSnapshot? {
        if !force, hasBackup {
            return load()
        }
        let snap = capture(note: note)
        guard snap.save(to: backupURL) else { return nil }
        SlotDockTelemetry.preferences.info(
            "Saved system Dock prefs backup note=\(note ?? "", privacy: .public)"
        )
        return snap
    }

    /// Ensure a backup exists before mutating Dock prefs (does not overwrite existing).
    @discardableResult
    static func ensureBackupBeforeMutation(note: String) -> SystemDockPrefsSnapshot? {
        if let existing = load() { return existing }
        return saveSnapshot(note: note, force: true)
    }

    /// Build restore script from on-disk backup, if any.
    static func restoreScript() -> String? {
        load()?.restoreScript()
    }
}
