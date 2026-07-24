import Foundation

/// Snapshot of the system Dock preference keys Slot Dock may change.
/// Pure encode/decode + script generation — no shell execution here.
public struct SystemDockPrefsSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var capturedAt: Date
    /// `com.apple.dock` autohide (nil = key was absent at capture).
    public var autohide: Bool?
    public var autohidePresent: Bool
    public var autohideDelay: Double?
    public var autohideDelayPresent: Bool
    public var autohideTimeModifier: Double?
    public var autohideTimeModifierPresent: Bool
    /// Optional note (e.g. "before raise-dock-delay-5s").
    public var note: String?

    public init(
        version: Int = 1,
        capturedAt: Date = Date(),
        autohide: Bool? = nil,
        autohidePresent: Bool = false,
        autohideDelay: Double? = nil,
        autohideDelayPresent: Bool = false,
        autohideTimeModifier: Double? = nil,
        autohideTimeModifierPresent: Bool = false,
        note: String? = nil
    ) {
        self.version = version
        self.capturedAt = capturedAt
        self.autohide = autohide
        self.autohidePresent = autohidePresent
        self.autohideDelay = autohideDelay
        self.autohideDelayPresent = autohideDelayPresent
        self.autohideTimeModifier = autohideTimeModifier
        self.autohideTimeModifierPresent = autohideTimeModifierPresent
        self.note = note
    }

    public static var defaultBackupURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".config/nicos-slot-dock/system-dock-prefs-backup.json")
    }

    /// Capture from an injectable reader: key → Optional value (Bool/Double/Int/String).
    public static func capture(
        note: String? = nil,
        now: Date = Date(),
        read: (String) -> Any?
    ) -> SystemDockPrefsSnapshot {
        let (ah, ahP) = readBool(read("autohide"))
        let (delay, delayP) = readDouble(read("autohide-delay"))
        let (mod, modP) = readDouble(read("autohide-time-modifier"))
        return SystemDockPrefsSnapshot(
            capturedAt: now,
            autohide: ah,
            autohidePresent: ahP,
            autohideDelay: delay,
            autohideDelayPresent: delayP,
            autohideTimeModifier: mod,
            autohideTimeModifierPresent: modP,
            note: note
        )
    }

    /// Shell that restores this snapshot then restarts Dock.
    public func restoreScript() -> String {
        var lines: [String] = [
            "# Restore com.apple.dock prefs from Slot Dock snapshot",
            "# captured \(ISO8601DateFormatter().string(from: capturedAt))",
        ]
        if let note, !note.isEmpty {
            lines.append("# note: \(note)")
        }

        if autohidePresent, let autohide {
            lines.append("defaults write com.apple.dock autohide -bool \(autohide ? "true" : "false")")
        } else {
            lines.append("defaults delete com.apple.dock autohide 2>/dev/null || true")
        }

        if autohideDelayPresent, let autohideDelay {
            lines.append("defaults write com.apple.dock autohide-delay -float \(autohideDelay)")
        } else {
            lines.append("defaults delete com.apple.dock autohide-delay 2>/dev/null || true")
        }

        if autohideTimeModifierPresent, let autohideTimeModifier {
            lines.append("defaults write com.apple.dock autohide-time-modifier -float \(autohideTimeModifier)")
        } else {
            lines.append("defaults delete com.apple.dock autohide-time-modifier 2>/dev/null || true")
        }

        lines.append("killall Dock")
        return lines.joined(separator: "\n") + "\n"
    }

    public var summaryText: String {
        var lines: [String] = []
        lines.append("Captured: \(ISO8601DateFormatter().string(from: capturedAt))")
        if let note { lines.append("Note: \(note)") }
        lines.append("autohide: \(describe(present: autohidePresent, value: autohide.map { $0 ? "true" : "false" }))")
        lines.append("autohide-delay: \(describe(present: autohideDelayPresent, value: autohideDelay.map { String($0) }))")
        lines.append("autohide-time-modifier: \(describe(present: autohideTimeModifierPresent, value: autohideTimeModifier.map { String($0) }))")
        return lines.joined(separator: "\n")
    }

    private func describe(present: Bool, value: String?) -> String {
        if present, let value { return value }
        return "(key absent)"
    }

    // MARK: - JSON file

    public static func load(from url: URL = defaultBackupURL) -> SystemDockPrefsSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(SystemDockPrefsSnapshot.self, from: data)
    }

    @discardableResult
    public func save(to url: URL = defaultBackupURL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            let data = try enc.encode(self)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func readBool(_ any: Any?) -> (Bool?, Bool) {
        guard let any else { return (nil, false) }
        if let b = any as? Bool { return (b, true) }
        if let n = any as? NSNumber { return (n.boolValue, true) }
        if let s = any as? String {
            let l = s.lowercased()
            if l == "1" || l == "true" || l == "yes" { return (true, true) }
            if l == "0" || l == "false" || l == "no" { return (false, true) }
        }
        return (nil, true)
    }

    private static func readDouble(_ any: Any?) -> (Double?, Bool) {
        guard let any else { return (nil, false) }
        if let d = any as? Double { return (d, true) }
        if let i = any as? Int { return (Double(i), true) }
        if let n = any as? NSNumber { return (n.doubleValue, true) }
        if let s = any as? String, let d = Double(s) { return (d, true) }
        return (nil, true)
    }
}

/// Recommended Slot Dock-friendly system Dock prefs (auto-hide + 5s show delay).
public enum SystemDockRecommended {
    public static let delaySeconds: Double = 5

    public static func applyScript() -> String {
        CollisionGuide.scriptRaiseDelay(seconds: delaySeconds)
    }
}
