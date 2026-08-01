import AppKit
import Foundation
import SlotDockCore

/// Live running-app snapshot from NSWorkspace + launch/terminate notifications.
///
/// Performance design:
/// - **Event-driven only** (no polling timer).
/// - Listens to **launch + terminate** only — `didActivate` is ignored because activation
///   does not change membership / running dots / transient icons.
/// - **Coalesces** bursts (login storms) into one snapshot rebuild (~50ms).
/// - Publishes / calls `onSnapshotChange` **only when the snapshot actually changes**.
/// - Snapshot build is O(n) over regular GUI apps only (filters helpers/agents).
@MainActor
final class RunningAppsMonitor: ObservableObject {
    @Published private(set) var snapshot = RunningAppSnapshot()

    /// Called after a real snapshot change (for strip recompose when transient running is on).
    var onSnapshotChange: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var coalesceWork: DispatchWorkItem?
    /// Coalesce interval for launch/terminate bursts (login, multi-app quit).
    private let coalesceInterval: TimeInterval = 0.05
    private var lastReason = "init"
    /// Telemetry counters (session-local).
    private(set) var refreshCount = 0
    private(set) var skipUnchangedCount = 0
    private(set) var publishCount = 0

    init() {
        refresh(reason: "init", immediate: true)
        let center = NSWorkspace.shared.notificationCenter
        // Activate does not change the running set — skip it (major win under app switching).
        let names: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                // Capture a Sendable String before hopping to MainActor Task (Swift 6).
                let reason = note.name.rawValue
                Task { @MainActor in
                    self?.scheduleRefresh(reason: reason)
                }
            }
            observers.append(token)
        }
        SlotDockTelemetry.running.info(
            "RunningAppsMonitor started listeners=launch+terminate coalesceMS=\(Int(self.coalesceInterval * 1000), privacy: .public)"
        )
    }

    func invalidate() {
        coalesceWork?.cancel()
        coalesceWork = nil
        let center = NSWorkspace.shared.notificationCenter
        for token in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
        onSnapshotChange = nil
        SlotDockTelemetry.running.info(
            "RunningAppsMonitor stopped refresh=\(self.refreshCount, privacy: .public) publish=\(self.publishCount, privacy: .public) skip=\(self.skipUnchangedCount, privacy: .public)"
        )
    }

    /// Schedule a coalesced refresh (default for notifications).
    func scheduleRefresh(reason: String) {
        lastReason = reason
        coalesceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refresh(reason: reason, immediate: true)
        }
        coalesceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + coalesceInterval, execute: work)
    }

    /// Immediate refresh (init, preference toggle, app-active reconciliation).
    func refresh(reason: String = "manual", immediate: Bool = true) {
        if !immediate {
            scheduleRefresh(reason: reason)
            return
        }
        coalesceWork?.cancel()
        coalesceWork = nil
        lastReason = reason
        refreshCount += 1

        // Only log slow refreshes (common path is sub-ms / a few ms).
        let next = SlotDockTelemetry.measure("RunningAppsMonitor.refresh", thresholdMS: 8) {
            buildSnapshot()
        }
        guard next != snapshot else {
            skipUnchangedCount += 1
            // Quiet: unchanged is the common path after coalesce; avoid log spam.
            SlotDockTelemetry.running.debug(
                "running snapshot unchanged reason=\(reason, privacy: .public) apps=\(next.apps.count, privacy: .public)"
            )
            return
        }
        snapshot = next
        publishCount += 1
        // Info only every N publishes (or first) — launch/terminate storm would otherwise flood.
        if publishCount == 1 || publishCount % 5 == 0 {
            SlotDockTelemetry.running.info(
                "running snapshot apps=\(next.apps.count, privacy: .public) bundles=\(next.bundleIdentifiers.count, privacy: .public) reason=\(reason, privacy: .public) publish#=\(self.publishCount, privacy: .public)"
            )
        } else {
            SlotDockTelemetry.running.debug(
                "running snapshot apps=\(next.apps.count, privacy: .public) reason=\(reason, privacy: .public) publish#=\(self.publishCount, privacy: .public)"
            )
        }
        onSnapshotChange?()
    }

    func isRunning(slot: Slot) -> Bool {
        RunningIndicator.shouldShowDot(for: slot, running: snapshot)
    }

    private func buildSnapshot() -> RunningAppSnapshot {
        var bundles = Set<String>()
        var paths = Set<String>()
        var apps: [RunningAppInfo] = []
        var seenIDs = Set<String>()

        for app in NSWorkspace.shared.runningApplications {
            // Only apps that participate in the Dock / user-facing UI.
            guard app.activationPolicy == .regular else { continue }
            guard !app.isTerminated else { continue }
            // Skip ourselves
            if app.bundleIdentifier == Bundle.main.bundleIdentifier { continue }

            let path = app.bundleURL.map { SystemDockEntry.normalizePath($0.path) } ?? ""
            let name = app.localizedName
                ?? (path.isEmpty ? "App" : URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
            let bundle = app.bundleIdentifier

            if let b = bundle, !b.isEmpty {
                bundles.insert(b)
            }
            if !path.isEmpty {
                paths.insert(path)
            }

            // Only .app bundles as transient strip icons (not helpers without a path).
            guard path.lowercased().hasSuffix(".app"), !path.isEmpty else { continue }
            let info = RunningAppInfo(bundleIdentifier: bundle, path: path, name: name)
            guard !seenIDs.contains(info.id) else { continue }
            seenIDs.insert(info.id)
            apps.append(info)
        }

        // Stable order: by name then path (avoid jitter on every rebuild).
        apps.sort {
            let n = $0.name.localizedCaseInsensitiveCompare($1.name)
            if n != .orderedSame { return n == .orderedAscending }
            return $0.path < $1.path
        }

        return RunningAppSnapshot(bundleIdentifiers: bundles, paths: paths, apps: apps)
    }
}
