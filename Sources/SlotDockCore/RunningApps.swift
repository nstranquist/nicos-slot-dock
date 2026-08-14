import Foundation

/// Identity used to decide whether a strip slot is “already open”.
public struct AppIdentity: Equatable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var path: String?

    public init(bundleIdentifier: String? = nil, path: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.path = path.map { SystemDockEntry.canonicalIdentityPath($0) }
    }

    public static func from(slot: Slot, resolveBundleFromDisk: Bool = true) -> AppIdentity {
        let path = SystemDockEntry.canonicalIdentityPath(slot.target)
        var bundle = bundleIdentifier(fromSlotID: slot.id)
        if bundle == nil, resolveBundleFromDisk {
            bundle = bundleIdentifier(forAppPath: path)
        }
        return AppIdentity(
            bundleIdentifier: bundle,
            path: path.isEmpty || path.hasPrefix("http") ? nil : path
        )
    }

    /// `sysdock:<bundle>:<path>` / `running:<bundle>:<path>` ids carry the bundle
    /// without touching the filesystem.
    public static func bundleIdentifier(fromSlotID id: String) -> String? {
        let prefixes = ["sysdock:", "running:"]
        guard let prefix = prefixes.first(where: { id.hasPrefix($0) }) else { return nil }
        let rest = String(id.dropFirst(prefix.count))
        let candidate = rest.split(separator: ":", maxSplits: 1).first.map(String.init) ?? rest
        if candidate.contains(".") && !candidate.hasPrefix("/") {
            return candidate
        }
        return nil
    }

    /// Reads `CFBundleIdentifier` from an `.app` wrapper. Missing / non-app paths return nil.
    public static func bundleIdentifier(forAppPath path: String) -> String? {
        let canonical = SystemDockEntry.canonicalIdentityPath(path)
        guard canonical.lowercased().hasSuffix(".app") else { return nil }
        bundleCacheLock.lock()
        if let cached = bundleCache[canonical] {
            bundleCacheLock.unlock()
            return cached.isEmpty ? nil : cached
        }
        bundleCacheLock.unlock()
        let resolved = Bundle(url: URL(fileURLWithPath: canonical))?.bundleIdentifier ?? ""
        bundleCacheLock.lock()
        bundleCache[canonical] = resolved
        bundleCacheLock.unlock()
        return resolved.isEmpty ? nil : resolved
    }

    private static let bundleCacheLock = NSLock()
    private nonisolated(unsafe) static var bundleCache: [String: String] = [:]
}

/// One running GUI app (for optional transient strip icons).
public struct RunningAppInfo: Equatable, Sendable, Identifiable {
    public var id: String {
        if let b = bundleIdentifier, !b.isEmpty {
            let normalized = SystemDockEntry.canonicalIdentityPath(path)
            return normalized.isEmpty ? "running:\(b)" : "running:\(b):\(normalized)"
        }
        return "running:\(SystemDockEntry.canonicalIdentityPath(path))"
    }

    public var bundleIdentifier: String?
    public var path: String
    public var name: String
    /// Live PIDs for this bundle+path. Empty in compact test fixtures.
    public var processIDs: [Int32]
    /// Used when `processIDs` is empty so two listed copies still count as 2.
    public var listedCopies: Int

    public var instanceCount: Int {
        if !processIDs.isEmpty { return processIDs.count }
        return max(1, listedCopies)
    }

    public init(
        bundleIdentifier: String? = nil,
        path: String,
        name: String,
        processIDs: [Int32] = [],
        listedCopies: Int = 1
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.path = SystemDockEntry.canonicalIdentityPath(path)
        self.name = name
        self.processIDs = processIDs
        self.listedCopies = max(1, listedCopies)
    }

    public func asSlot(sortOrder: Int) -> Slot {
        Slot(
            id: id,
            label: name,
            target: path,
            iconPath: nil,
            sortOrder: sortOrder
        )
    }
}

/// Snapshot of currently running regular apps (testable without NSWorkspace).
public struct RunningAppSnapshot: Equatable, Sendable {
    public var bundleIdentifiers: Set<String>
    public var paths: Set<String>
    /// Ordered list of regular GUI apps (for optional transient strip section).
    public var apps: [RunningAppInfo]

    public init(
        bundleIdentifiers: Set<String> = [],
        paths: Set<String> = [],
        apps: [RunningAppInfo] = []
    ) {
        self.bundleIdentifiers = Set(bundleIdentifiers.map { $0.lowercased() })
        self.paths = Set(paths.map { SystemDockEntry.canonicalIdentityPath($0).lowercased() })
        self.apps = apps
    }

    public func isRunning(_ identity: AppIdentity) -> Bool {
        if let b = identity.bundleIdentifier?.lowercased(), !b.isEmpty,
           bundleIdentifiers.contains(b)
        {
            // A bundle id is not globally unique on disk: multiple app copies
            // can be open at once. Prefer the paired bundle/path record when the
            // slot carries a concrete path; fall back to bundle-only matching
            // only when the slot has no path identity.
            if let p = identity.path?.lowercased(), !p.isEmpty {
                let sameBundle = apps.filter { app in
                    app.bundleIdentifier?.lowercased() == b
                }
                guard !sameBundle.isEmpty else {
                    // Tests and callers may provide only the legacy bundle set;
                    // do not turn that compact representation into a false
                    // negative.
                    return true
                }
                return sameBundle.contains { app in
                    return SystemDockEntry.canonicalIdentityPath(app.path).lowercased() == p
                }
            }
            return true
        }
        if let p = identity.path?.lowercased(), !p.isEmpty, paths.contains(p) {
            return true
        }
        // Path may be .app bundle; also check without trailing variations
        if let p = identity.path {
            let lower = SystemDockEntry.canonicalIdentityPath(p).lowercased()
            if paths.contains(where: { $0 == lower || $0.hasPrefix(lower + "/") || lower.hasPrefix($0 + "/") }) {
                return true
            }
        }
        return false
    }

    public func matchingApps(_ identity: AppIdentity) -> [RunningAppInfo] {
        apps.filter { app in
            if let b = identity.bundleIdentifier?.lowercased(), !b.isEmpty {
                guard app.bundleIdentifier?.lowercased() == b else { return false }
                if let p = identity.path?.lowercased(), !p.isEmpty {
                    return SystemDockEntry.canonicalIdentityPath(app.path).lowercased() == p
                }
                return true
            }
            if let p = identity.path?.lowercased(), !p.isEmpty {
                return SystemDockEntry.canonicalIdentityPath(app.path).lowercased() == p
            }
            return false
        }
    }

    public func instanceCount(for identity: AppIdentity) -> Int {
        matchingApps(identity).reduce(0) { $0 + $1.instanceCount }
    }
}

/// Merge same bundle+path rows so several PIDs become one tile with a count.
public enum RunningAppGrouping {
    public static func group(_ apps: [RunningAppInfo]) -> [RunningAppInfo] {
        var order: [String] = []
        var map: [String: RunningAppInfo] = [:]
        for app in apps {
            let key = app.id
            if var existing = map[key] {
                for pid in app.processIDs where !existing.processIDs.contains(pid) {
                    existing.processIDs.append(pid)
                }
                existing.listedCopies += app.listedCopies
                map[key] = existing
            } else {
                order.append(key)
                map[key] = app
            }
        }
        return order.compactMap { map[$0] }
    }
}

/// Pure: running apps not already represented on the strip.
/// Identity is **path**. A second copy of the same bundle from another path
/// is an extra tile (system Dock behavior), not a collapsed duplicate.
public enum TransientRunningApps {
    public static func extras(
        running: [RunningAppInfo],
        stripPaths: Set<String>
    ) -> [RunningAppInfo] {
        let paths = Set(stripPaths.map { SystemDockEntry.canonicalIdentityPath($0).lowercased() })
        let grouped = RunningAppGrouping.group(running)
        var out: [RunningAppInfo] = []
        var seen = Set<String>()
        for app in grouped {
            let pathKey = SystemDockEntry.canonicalIdentityPath(app.path).lowercased()
            if !pathKey.isEmpty, paths.contains(pathKey) { continue }
            let id = app.id
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            out.append(app)
        }
        return out
    }

    /// Same bundle as a strip tile, but a different path — always a distinct
    /// tile (system Dock behavior). Independent of the unrelated-transient pref.
    public static func otherPathCopies(
        running: [RunningAppInfo],
        stripPaths: Set<String>,
        stripBundles: Set<String>
    ) -> [RunningAppInfo] {
        let paths = Set(stripPaths.map { SystemDockEntry.canonicalIdentityPath($0).lowercased() })
        let bundles = Set(stripBundles.map { $0.lowercased() }.filter { !$0.isEmpty })
        let grouped = RunningAppGrouping.group(running)
        var out: [RunningAppInfo] = []
        var seen = Set<String>()
        for app in grouped {
            let pathKey = SystemDockEntry.canonicalIdentityPath(app.path).lowercased()
            if !pathKey.isEmpty, paths.contains(pathKey) { continue }
            guard let bundle = app.bundleIdentifier?.lowercased(), bundles.contains(bundle) else {
                continue
            }
            guard !seen.contains(app.id) else { continue }
            seen.insert(app.id)
            out.append(app)
        }
        return out
    }
}

/// Running mark for a strip tile: boolean plus instance count for stacked dots.
public struct RunningPresentation: Equatable, Sendable {
    public var isRunning: Bool
    public var instanceCount: Int

    public var showsStackedMark: Bool { instanceCount > 1 }

    public init(isRunning: Bool, instanceCount: Int) {
        self.isRunning = isRunning
        self.instanceCount = instanceCount
    }
}

/// Pure resolver: slot → show running indicator.
public enum RunningIndicator {
    public static func shouldShowDot(for slot: Slot, running: RunningAppSnapshot) -> Bool {
        presentation(for: slot, running: running).isRunning
    }

    public static func presentation(for slot: Slot, running: RunningAppSnapshot) -> RunningPresentation {
        let identity = AppIdentity.from(slot: slot)
        let count = running.instanceCount(for: identity)
        if count > 0 {
            return RunningPresentation(isRunning: true, instanceCount: count)
        }
        if running.isRunning(identity) {
            return RunningPresentation(isRunning: true, instanceCount: 1)
        }
        return RunningPresentation(isRunning: false, instanceCount: 0)
    }

    public static func dotsBySlotID(slots: [Slot], running: RunningAppSnapshot) -> [String: Bool] {
        var map: [String: Bool] = [:]
        for slot in slots {
            map[slot.id] = shouldShowDot(for: slot, running: running)
        }
        return map
    }
}
