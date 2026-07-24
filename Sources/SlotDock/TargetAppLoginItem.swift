import AppKit
import Foundation
import SlotDockCore

/// Query/set Open at Login for arbitrary `.app` bundles via System Events.
/// Fail-closed: returns errors instead of claiming success when Automation is denied.
///
/// Caches Automation availability so menu open does not re-run AppleScript (and spam logs)
/// after a denied prompt (-1743).
@MainActor
enum TargetAppLoginItem {
    enum LoginError: Error, Equatable, LocalizedError {
        case notEligible
        case automationDenied(String)
        case scriptFailed(String)
        case pathMissing

        var errorDescription: String? {
            switch self {
            case .notEligible:
                return "Only application targets support Open at Login."
            case .automationDenied:
                return "Allow Slot Dock to control System Events (System Settings → Privacy & Security → Automation), then try again."
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
    private static var automationOK: Bool?
    private static var didLogAutomationDenied = false

    /// Reset cache (tests / after user may have flipped Privacy settings).
    static func resetAutomationCache() {
        automationOK = nil
        didLogAutomationDenied = false
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
        automationOK = false
        guard !didLogAutomationDenied else { return }
        didLogAutomationDenied = true
        // Once per process — expected until user grants Automation.
        SlotDockTelemetry.preferences.info(
            "Open at Login blocked: Automation denied for System Events (\(detail, privacy: .public)). Further queries suppressed."
        )
    }

    private static func noteAutomationOK() {
        automationOK = true
    }

    /// Best-effort: list login item paths. `nil` when System Events is unavailable/denied.
    static func loginItemPaths() -> [String]? {
        if automationOK == false { return nil }

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
                    "login items query failed: \(msg, privacy: .public)"
                )
            }
            return nil
        }
        // Single string error channel
        if let s = result.stringValue, s.hasPrefix("ERROR:") {
            if isAutomationDenial(s) {
                noteAutomationDenied(s)
            } else {
                SlotDockTelemetry.preferences.warning("login items query: \(s, privacy: .public)")
            }
            return nil
        }
        noteAutomationOK()
        // List of paths
        var paths: [String] = []
        let count = result.numberOfItems
        if count == 0, let single = result.stringValue, !single.isEmpty, !single.hasPrefix("ERROR:") {
            paths.append(single)
            return paths
        }
        for i in 1 ... max(count, 0) {
            if let item = result.atIndex(i), let s = item.stringValue, !s.isEmpty {
                paths.append(s)
            }
        }
        return paths
    }

    static func isEnabled(appPath: String) -> Bool? {
        guard AppOpenAtLoginPolicy.isEligible(kind: .application, path: appPath) else {
            return false
        }
        guard let paths = loginItemPaths() else { return nil }
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
        if automationOK == false {
            automationOK = nil
        }

        let name = AppOpenAtLoginPolicy.loginItemDisplayName(path: path)
        let escapedPath = path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedName = name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let source: String
        if enabled {
            source = """
            try
              tell application "System Events"
                if not (exists login item "\(escapedName)") then
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
                if exists login item "\(escapedName)" then
                  delete login item "\(escapedName)"
                end if
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
        return .success(())
    }
}
