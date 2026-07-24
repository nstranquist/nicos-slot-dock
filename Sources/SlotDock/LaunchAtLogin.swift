import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for opt-in launch at login.
/// Preference `launchAtLogin` is the source of truth in slots.json; this applies it.
enum LaunchAtLogin {
    enum Status: Equatable {
        case enabled
        case notRegistered
        case requiresApproval
        case notFound
        case unknown

        var isEnabled: Bool { self == .enabled }

        var description: String {
            switch self {
            case .enabled: "Enabled — launches at login"
            case .notRegistered: "Not registered"
            case .requiresApproval: "Needs approval in System Settings › General › Login Items"
            case .notFound: "Unavailable (install to /Applications via make install)"
            case .unknown: "Unknown"
            }
        }
    }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .notRegistered
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }

    /// Register or unregister. Throws when the binary is not a proper app bundle.
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }

    /// Best-effort sync: apply preference; return human status string (empty on quiet success).
    @discardableResult
    static func applyPreference(_ wantEnabled: Bool) -> String? {
        do {
            try setEnabled(wantEnabled)
            if wantEnabled, status == .requiresApproval {
                return Status.requiresApproval.description
            }
            if wantEnabled, status == .notFound {
                return Status.notFound.description
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
