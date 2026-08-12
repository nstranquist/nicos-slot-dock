import Foundation

/// Identity used to decide whether a strip slot is “already open”.
public struct AppIdentity: Equatable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var path: String?

    public init(bundleIdentifier: String? = nil, path: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.path = path.map { SystemDockEntry.canonicalIdentityPath($0) }
    }

    public static func from(slot: Slot) -> AppIdentity {
        let path = SystemDockEntry.canonicalIdentityPath(slot.target)
        // sysdock:com.foo.bar → bundle id
        var bundle: String?
        if slot.id.hasPrefix("sysdock:") {
            let rest = String(slot.id.dropFirst("sysdock:".count))
            let candidate = rest.split(separator: ":", maxSplits: 1).first.map(String.init) ?? rest
            if candidate.contains(".") && !candidate.hasPrefix("/") {
                bundle = candidate
            }
        }
        return AppIdentity(
            bundleIdentifier: bundle,
            path: path.isEmpty || path.hasPrefix("http") ? nil : path
        )
    }
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

    public init(bundleIdentifier: String? = nil, path: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.path = SystemDockEntry.canonicalIdentityPath(path)
        self.name = name
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
}

/// Pure: running apps not already represented on the strip.
public enum TransientRunningApps {
    public static func extras(
        running: [RunningAppInfo],
        stripPaths: Set<String>,
        stripBundles: Set<String>
    ) -> [RunningAppInfo] {
        let paths = Set(stripPaths.map { SystemDockEntry.canonicalIdentityPath($0).lowercased() })
        let bundles = Set(stripBundles.map { $0.lowercased() })
        var out: [RunningAppInfo] = []
        var seen = Set<String>()
        for app in running {
            let pathKey = SystemDockEntry.canonicalIdentityPath(app.path).lowercased()
            if !pathKey.isEmpty, paths.contains(pathKey) { continue }
            if let b = app.bundleIdentifier?.lowercased(), !b.isEmpty, bundles.contains(b) {
                continue
            }
            let id = app.id
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            out.append(app)
        }
        return out
    }
}

/// Pure resolver: slot → show running indicator.
public enum RunningIndicator {
    public static func shouldShowDot(for slot: Slot, running: RunningAppSnapshot) -> Bool {
        running.isRunning(AppIdentity.from(slot: slot))
    }

    public static func dotsBySlotID(slots: [Slot], running: RunningAppSnapshot) -> [String: Bool] {
        var map: [String: Bool] = [:]
        for slot in slots {
            map[slot.id] = shouldShowDot(for: slot, running: running)
        }
        return map
    }
}
