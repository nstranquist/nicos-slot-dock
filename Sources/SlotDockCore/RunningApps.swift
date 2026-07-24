import Foundation

/// Identity used to decide whether a strip slot is “already open”.
public struct AppIdentity: Equatable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var path: String?

    public init(bundleIdentifier: String? = nil, path: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.path = path.map { SystemDockEntry.normalizePath($0) }
    }

    public static func from(slot: Slot) -> AppIdentity {
        let path = SystemDockEntry.normalizePath(slot.target)
        // sysdock:com.foo.bar → bundle id
        var bundle: String?
        if slot.id.hasPrefix("sysdock:") {
            let rest = String(slot.id.dropFirst("sysdock:".count))
            if rest.contains(".") && !rest.hasPrefix("/") {
                bundle = rest
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
        if let b = bundleIdentifier, !b.isEmpty { return "running:\(b)" }
        return "running:\(SystemDockEntry.normalizePath(path))"
    }

    public var bundleIdentifier: String?
    public var path: String
    public var name: String

    public init(bundleIdentifier: String? = nil, path: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.path = SystemDockEntry.normalizePath(path)
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
        self.paths = Set(paths.map { SystemDockEntry.normalizePath($0).lowercased() })
        self.apps = apps
    }

    public func isRunning(_ identity: AppIdentity) -> Bool {
        if let b = identity.bundleIdentifier?.lowercased(), !b.isEmpty, bundleIdentifiers.contains(b) {
            return true
        }
        if let p = identity.path?.lowercased(), !p.isEmpty, paths.contains(p) {
            return true
        }
        // Path may be .app bundle; also check without trailing variations
        if let p = identity.path {
            let lower = SystemDockEntry.normalizePath(p).lowercased()
            if paths.contains(where: { $0 == lower || $0.hasPrefix(lower + "/") || lower.hasPrefix($0) }) {
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
        let paths = Set(stripPaths.map { SystemDockEntry.normalizePath($0).lowercased() })
        let bundles = Set(stripBundles.map { $0.lowercased() })
        var out: [RunningAppInfo] = []
        var seen = Set<String>()
        for app in running {
            let pathKey = app.path.lowercased()
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
