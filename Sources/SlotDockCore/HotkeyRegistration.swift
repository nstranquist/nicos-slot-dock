import Foundation

/// Result of attempting to register one global hotkey (pure; AppKit maps OSStatus → this).
public struct HotkeyRegistrationFailure: Equatable, Sendable, Identifiable {
    public var id: String { "\(actionID)-\(statusCode)" }
    public var actionID: UInt32
    public var actionLabel: String
    public var statusCode: Int32
    public var message: String

    public init(actionID: UInt32, actionLabel: String, statusCode: Int32, message: String) {
        self.actionID = actionID
        self.actionLabel = actionLabel
        self.statusCode = statusCode
        self.message = message
    }
}

/// Aggregated registration outcome for Settings / status surfaces.
public struct HotkeyRegistrationReport: Equatable, Sendable {
    public var globalEnabled: Bool
    public var registeredCount: Int
    public var failures: [HotkeyRegistrationFailure]
    public var handlerInstallFailed: Bool
    public var handlerStatusCode: Int32?

    public init(
        globalEnabled: Bool = false,
        registeredCount: Int = 0,
        failures: [HotkeyRegistrationFailure] = [],
        handlerInstallFailed: Bool = false,
        handlerStatusCode: Int32? = nil
    ) {
        self.globalEnabled = globalEnabled
        self.registeredCount = registeredCount
        self.failures = failures
        self.handlerInstallFailed = handlerInstallFailed
        self.handlerStatusCode = handlerStatusCode
    }

    public var hasProblems: Bool {
        handlerInstallFailed || !failures.isEmpty
    }

    /// User-facing summary (empty when healthy).
    public var userSummary: String {
        guard hasProblems else { return "" }
        var parts: [String] = []
        if handlerInstallFailed {
            let code = handlerStatusCode.map(String.init) ?? "?"
            parts.append("Hotkey event handler failed to install (status \(code)).")
        }
        for f in failures {
            parts.append("“\(f.actionLabel)” failed to register (status \(f.statusCode)): \(f.message)")
        }
        return parts.joined(separator: " ")
    }

    /// Map Carbon OSStatus to a short explanation (no AppKit).
    public static func explainStatus(_ status: Int32) -> String {
        switch status {
        case 0: return "ok"
        case -9878: return "hotkey already in use by another app"
        case -50: return "invalid parameter"
        case -10001: return "key is not supported by the Carbon keyboard map"
        case -10002: return "shortcut conflicts with another Nicos Slot Dock action"
        case -108: return "memory full"
        default: return "Carbon error \(status)"
        }
    }

    /// Pure label for action ids used by HotkeyManager.
    public static func label(forActionID id: UInt32) -> String {
        switch id {
        case 1: return "Show / hide dock"
        case 2: return "Open settings"
        case 3: return "Pin open"
        case 4: return "Quit"
        case 11...19: return "Launch slot \(id - 10)"
        default: return "Action \(id)"
        }
    }
}
