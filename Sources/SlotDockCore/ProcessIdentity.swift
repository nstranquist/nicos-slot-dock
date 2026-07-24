import Foundation

/// Pure process-identity rules for Slot Dock (used by products runtime match + tests).
/// Keeps the Mac app's executable / bundle naming in one place.
public enum SlotDockProcessIdentity {
    public static let bundleIdentifier = "com.nstranquist.nicos-slot-dock"
    public static let executableName = "SlotDock"
    public static let appBundleName = "SlotDock.app"
    public static let installedAppName = "Slot Dock.app"

    /// Path suffixes / basenames that identify a live Slot Dock process in `ps` output.
    public static var processMatchKeys: [String] {
        [
            "\(appBundleName)/Contents/MacOS/\(executableName)",
            "\(installedAppName)/Contents/MacOS/\(executableName)",
            "/\(executableName)",
            executableName,
        ]
    }

    /// Whether a process command line is Slot Dock.
    /// Uses the full command string so paths with spaces (`Slot Dock.app`) still match.
    public static func matchesProcessCommand(_ command: String) -> Bool {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return false }
        for key in processMatchKeys {
            if key.contains("/") {
                if cmd.hasSuffix(key) { return true }
                if let r = cmd.range(of: key) {
                    let idx = cmd.distance(from: cmd.startIndex, to: r.lowerBound)
                    if idx > 0 {
                        let before = cmd[cmd.index(cmd.startIndex, offsetBy: idx - 1)]
                        if before != "/" { continue }
                    }
                    let end = cmd.index(cmd.startIndex, offsetBy: idx + key.count)
                    if end == cmd.endIndex || cmd[end].isWhitespace { return true }
                }
            } else if cmd.hasSuffix("/" + key) {
                return true
            } else if cmd == key {
                return true
            }
        }
        return false
    }
}
