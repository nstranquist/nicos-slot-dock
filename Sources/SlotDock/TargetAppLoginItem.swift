import AppKit
import Foundation
import SlotDockCore

/// Query/set Open at Login for arbitrary `.app` bundles via System Events.
/// Fail-closed: returns errors instead of claiming success when Automation is denied.
///
/// Caches Automation availability so menu open does not re-run AppleScript (and spam logs)
/// after a denied prompt (-1743).
enum TargetAppLoginItem {
    enum LoginError: Error, Equatable, LocalizedError, Sendable {
        case notEligible
        case automationDenied(String)
        case scriptFailed(String)
        case pathMissing

        var errorDescription: String? {
            switch self {
            case .notEligible:
                return "Only application targets support Open at Login."
            case .automationDenied:
                return "Allow Nicos Slot Dock to control System Events (System Settings → Privacy & Security → Automation), then try again."
            case .scriptFailed(let s):
                return s
            case .pathMissing:
                return "Application path is missing."
            }
        }

        /// Whether the failure is the expected fail-closed Automation path.
        var isAutomationDenied: Bool {
            if case .automationDenied = self { return true }
            return false
        }
    }

    /// `nil` unknown, `true` System Events OK, `false` denied (skip further queries).
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var automationOK: Bool?
        var didLogAutomationDenied = false
        var cachedPaths: [String]?
    }

    private static let state = State()

    /// Reset cache (tests / after user may have flipped Privacy settings).
    static func resetAutomationCache() {
        state.lock.lock()
        state.automationOK = nil
        state.didLogAutomationDenied = false
        state.cachedPaths = nil
        state.lock.unlock()
    }

    /// Open Privacy → Automation so the user can grant System Events control.
    static func openAutomationPrivacySettings() {
        // Prefer modern Settings deep link; fall back to legacy pane id.
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                SlotDockTelemetry.preferences.info("Opened Privacy → Automation for Open at Login")
                return
            }
        }
    }

    /// Parse AppleScript `"ERROR:num:msg"` channel or NSAppleScript dictionary.
    static func classifyScriptFailure(_ raw: String) -> LoginError {
        if isAutomationDenial(raw) {
            return .automationDenied(raw)
        }
        return .scriptFailed(raw)
    }

    static func isAutomationDenial(_ message: String) -> Bool {
        AppOpenAtLoginPolicy.isAutomationDenialMessage(message)
    }

    private static func noteAutomationDenied(_ detail: String) {
        state.lock.lock()
        state.automationOK = false
        let shouldLog = !state.didLogAutomationDenied
        state.didLogAutomationDenied = true
        state.cachedPaths = nil
        state.lock.unlock()
        guard shouldLog else { return }
        // Once per process — expected until user grants Automation.
        SlotDockTelemetry.preferences.info(
            "Open at Login blocked: Automation denied for System Events (\(detail, privacy: .private)). Further queries suppressed."
        )
    }

    private static func noteAutomationOK() {
        state.lock.lock()
        state.automationOK = true
        state.lock.unlock()
    }

    private static func cachedAutomationOK() -> Bool? {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.automationOK
    }

    private static func cachedPaths() -> [String]? {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.cachedPaths
    }

    private static func cachePaths(_ paths: [String]) {
        state.lock.lock()
        state.cachedPaths = paths
        state.lock.unlock()
    }

    /// Refresh the menu-state cache without blocking the main actor. A nil
    /// result remains fail-closed and is retried on explicit user action.
    static func refreshAsync() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = loginItemPaths()
        }
    }

    /// Best-effort: list login item paths. `nil` when System Events is unavailable/denied.
    static func loginItemPaths() -> [String]? {
        if cachedAutomationOK() == false { return nil }

        let source = """
        try
          tell application "System Events"
            set out to {}
            repeat with li in login items
              try
                set end of out to POSIX path of (path of li as alias)
              end try
            end repeat
            return out
          end tell
        on error errMsg number errNum
          return "ERROR:" & errNum & ":" & errMsg
        end try
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            let msg = (error[NSAppleScript.errorMessage] as? String)
                ?? String(describing: error[NSAppleScript.errorNumber] ?? "unknown")
            if isAutomationDenial(msg) {
                noteAutomationDenied(msg)
            } else {
                SlotDockTelemetry.preferences.warning(
                    "login items query failed: \(msg, privacy: .private)"
                )
            }
            return nil
        }
        // Single string error channel
        if let s = result.stringValue, s.hasPrefix("ERROR:") {
            if isAutomationDenial(s) {
                noteAutomationDenied(s)
            } else {
                SlotDockTelemetry.preferences.warning("login items query: \(s, privacy: .private)")
            }
            return nil
        }
        noteAutomationOK()
        // List of paths
        var paths: [String] = []
        let count = result.numberOfItems
        if count == 0, let single = result.stringValue, !single.isEmpty, !single.hasPrefix("ERROR:") {
            paths.append(single)
            cachePaths(paths)
            return paths
        }
        for i in AppOpenAtLoginPolicy.appleScriptItemIndices(count: count) {
            if let item = result.atIndex(i), let s = item.stringValue, !s.isEmpty {
                paths.append(s)
            }
        }
        cachePaths(paths)
        return paths
    }

    static func isEnabled(appPath: String) -> Bool? {
        guard AppOpenAtLoginPolicy.isEligible(kind: .application, path: appPath) else {
            return false
        }
        guard let paths = cachedPaths() else {
            refreshAsync()
            return nil
        }
        return AppOpenAtLoginPolicy.isEnabled(targetPath: appPath, loginItemPaths: paths)
    }

    @discardableResult
    static func setEnabled(appPath: String, enabled: Bool) -> Result<Void, LoginError> {
        guard AppOpenAtLoginPolicy.isEligible(kind: .application, path: appPath) else {
            return .failure(.notEligible)
        }
        let path = SystemDockEntry.normalizePath(appPath)
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure(.pathMissing)
        }
        // User is explicitly acting — allow one more attempt even if we cached denied
        // (they may have just flipped Privacy).
        state.lock.lock()
        if state.automationOK == false { state.automationOK = nil }
        state.cachedPaths = nil
        state.lock.unlock()

        let escapedPath = escapedAppleScriptString(path)

        let source: String
        if enabled {
            source = """
            try
              tell application "System Events"
                set targetPath to "\(escapedPath)"
                set found to false
                repeat with li in login items
                  try
                    if (POSIX path of (path of li as alias)) is targetPath then
                      set found to true
                    end if
                  end try
                end repeat
                if not found then
                  make login item at end with properties {path:"\(escapedPath)", hidden:false}
                end if
              end tell
              return "OK"
            on error errMsg number errNum
              return "ERROR:" & errNum & ":" & errMsg
            end try
            """
        } else {
            source = """
            try
              tell application "System Events"
                set targetPath to "\(escapedPath)"
                repeat with li in login items
                  try
                    if (POSIX path of (path of li as alias)) is targetPath then
                      delete li
                    end if
                  end try
                end repeat
              end tell
              return "OK"
            on error errMsg number errNum
              return "ERROR:" & errNum & ":" & errMsg
            end try
            """
        }

        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(.scriptFailed("Could not create AppleScript."))
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let msg = (error[NSAppleScript.errorMessage] as? String) ?? "Automation denied"
            let classified = classifyScriptFailure(msg)
            if classified.isAutomationDenied {
                noteAutomationDenied(msg)
            }
            return .failure(classified)
        }
        if let s = result.stringValue, s.hasPrefix("ERROR:") {
            let classified = classifyScriptFailure(s)
            if classified.isAutomationDenied {
                noteAutomationDenied(s)
            }
            return .failure(classified)
        }
        noteAutomationOK()
        guard let paths = loginItemPaths(),
              AppOpenAtLoginPolicy.isEnabled(targetPath: path, loginItemPaths: paths) == enabled
        else {
            return .failure(.scriptFailed("System Events did not confirm the requested Open at Login state."))
        }
        return .success(())
    }

    private static func escapedAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
