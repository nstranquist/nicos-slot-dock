import Foundation

/// Pure single-instance decision (no AppKit). App layer applies handoff.
public enum SingleInstanceDecision: Equatable, Sendable {
    /// No other instance — continue launching.
    case claim
    /// Another live instance exists — activate it and exit this process.
    case handoff(existingPID: Int32)
}

public enum SingleInstancePolicy {
    /// Decide whether this process should own the UI or hand off.
    /// - Parameters:
    ///   - selfPID: this process id
    ///   - peers: other processes with the same bundle id (pid + optionally finished flag)
    public static func decide(
        selfPID: Int32,
        peers: [(pid: Int32, isFinished: Bool)]
    ) -> SingleInstanceDecision {
        let live = peers.filter { $0.pid != selfPID && !$0.isFinished }
        guard let first = live.first else { return .claim }
        // Prefer lowest PID as the "primary" (oldest) instance.
        let primary = live.map(\.pid).min() ?? first.pid
        return .handoff(existingPID: primary)
    }
}

/// Distributed notification for second-instance → primary reveal/focus.
public enum SlotDockIPC {
    public static let focusNotificationName = "com.nstranquist.nicos-slot-dock.focus"
}
