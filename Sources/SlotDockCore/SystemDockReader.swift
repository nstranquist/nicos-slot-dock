import Foundation

/// One item from the user's system macOS Dock (`com.apple.dock` persistent-apps).
public struct SystemDockEntry: Equatable, Sendable, Identifiable {
    public var id: String {
        let identity = bundleIdentifier.map { "bundle:\($0):\(identityPath)" } ?? "path:\(identityPath)"
        return guid.map { "dock:\($0):\(identity)" } ?? "dock:\(identity)"
    }
    public var label: String
    public var path: String
    public var bundleIdentifier: String?
    public var guid: Int?

    public init(label: String, path: String, bundleIdentifier: String? = nil, guid: Int? = nil) {
        self.label = label
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.guid = guid
    }

    /// Stable path key for dedupe (trailing slash stripped, file URL decoded).
    public var normalizedPath: String {
        Self.normalizePath(path)
    }

    /// Canonical path used for identity/deduplication while preserving
    /// `path` as the user-facing launch/display spelling.
    public var identityPath: String {
        Self.canonicalIdentityPath(path)
    }

    public static func normalizePath(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("file://") {
            if let url = URL(string: s) {
                s = url.path
            } else {
                s = s.replacingOccurrences(of: "file://", with: "")
                s = s.removingPercentEncoding ?? s
            }
        }
        while s.hasSuffix("/") && s.count > 1 {
            s.removeLast()
        }
        return s
    }

    /// Canonical path used only for identity/deduplication. Display and launch
    /// paths remain standardized-but-not-resolved so macOS firmlink mappings
    /// and explicit user spellings do not leak into Slot data.
    public static func canonicalIdentityPath(_ raw: String) -> String {
        let normalized = normalizePath(raw)
        guard normalized.hasPrefix("/") else { return normalized }
        let standardized = URL(fileURLWithPath: normalized).standardizedFileURL
        let resolved = FileManager.default.fileExists(atPath: standardized.path)
            ? standardized.resolvingSymlinksInPath()
            : standardized
        return resolved.path
    }
}

/// How Slot Dock composes system Dock apps with custom slots.
public enum SystemDockIntegration: String, Codable, CaseIterable, Sendable {
    /// Only custom slots (original behavior).
    case off
    /// Custom slots first, then system Dock apps (live, not already custom), then optional running extras.
    case merge
    /// Only system Dock apps (live mirror). Custom slots kept on disk but not shown.
    case mirror

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .merge: return "Merge"
        case .mirror: return "Mirror"
        }
    }

    public var helpText: String {
        switch self {
        case .off:
            return "Show only your custom slots."
        case .merge:
            return "Custom slots on the left, then system Dock apps (live), then optional open apps on the right."
        case .mirror:
            return "Show the system Dock apps only (live). Custom slots stay saved but hidden."
        }
    }
}

/// Pure reader for `com.apple.dock` preferences. Headless-safe.
public enum SystemDockReader {
    public static var defaultPlistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")
    }

    /// Read persistent Dock apps from a plist file (binary or XML).
    public static func readPersistentApps(
        from plistURL: URL = defaultPlistURL,
        fileManager: FileManager = .default
    ) -> [SystemDockEntry] {
        guard fileManager.fileExists(atPath: plistURL.path) else { return [] }
        guard let data = try? Data(contentsOf: plistURL) else { return [] }
        return parsePersistentApps(from: data)
    }

    /// Parse Dock plist bytes into ordered application entries. Finder folders,
    /// URLs, documents, and unresolved aliases are intentionally not launch
    /// targets for the app strip and are skipped.
    public static func parsePersistentApps(from data: Data) -> [SystemDockEntry] {
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            return []
        }
        guard let root = object as? [String: Any] else { return [] }
        guard let apps = root["persistent-apps"] as? [[String: Any]] else { return [] }

        var result: [SystemDockEntry] = []
        result.reserveCapacity(apps.count)

        for app in apps {
            let tileType = app["tile-type"] as? String ?? "file-tile"
            // Slot Dock models application tiles only. Keep folders/URLs out of
            // the app strip until they have an explicit launch policy.
            guard tileType == "file-tile" else { continue }

            guard let tile = app["tile-data"] as? [String: Any] else { continue }
            let guid = app["GUID"] as? Int

            var path = ""
            if let fileData = tile["file-data"] as? [String: Any],
               let urlString = fileData["_CFURLString"] as? String
            {
                path = SystemDockEntry.normalizePath(urlString)
            }
            if path.isEmpty,
               let fileData = tile["file-data"] as? [String: Any],
               let aliasData = fileData["_CFURLAliasData"] as? Data,
               let aliasPath = resolveAliasPath(aliasData)
            {
                path = aliasPath
            }
            if path.isEmpty,
               let fileData = tile["file-data"] as? [String: Any],
               let bookmarkData = fileData["_CFURLBookmarkData"] as? Data,
               let bookmarkPath = resolveBookmarkPath(bookmarkData)
            {
                path = bookmarkPath
            }
            // bookmarked apps without resolved URL — skip if no path
            guard !path.isEmpty else { continue }
            // `persistent-apps` can contain generic file tiles despite its key
            // name. Do not silently present a document/folder as an app slot.
            guard path.lowercased().hasSuffix(".app") else { continue }

            let label: String = {
                if let fileLabel = tile["file-label"] as? String, !fileLabel.isEmpty {
                    return fileLabel
                }
                return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            }()
            let bundleID = tile["bundle-identifier"] as? String

            result.append(
                SystemDockEntry(
                    label: label,
                    path: path,
                    bundleIdentifier: bundleID,
                    guid: guid
                )
            )
        }
        return result
    }

    private static func resolveAliasPath(_ aliasData: Data) -> String? {
        let aliasURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("slot-dock-alias-\(UUID().uuidString)", isDirectory: false)
        do {
            try aliasData.write(to: aliasURL, options: .atomic)
            defer {
                _ = try? FileManager.default.removeItem(at: aliasURL)
            }
            guard let url = try? URL(
                resolvingAliasFileAt: aliasURL,
                options: [.withoutMounting, .withoutUI]
            ) else { return nil }
            return SystemDockEntry.normalizePath(url.path)
        } catch {
            return nil
        }
    }

    private static func resolveBookmarkPath(_ bookmarkData: Data) -> String? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutMounting, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return SystemDockEntry.normalizePath(url.path)
    }

    /// Convert a system Dock entry into a Slot (stable id from path/bundle).
    public static func slot(from entry: SystemDockEntry) -> Slot {
        let identity = entry.bundleIdentifier.map { "\($0):\(entry.identityPath)" } ?? entry.identityPath
        let id = "sysdock:" + identity
        return Slot(
            id: id,
            label: entry.label,
            target: entry.path,
            iconPath: nil,
            sortOrder: 0
        )
    }
}

/// Composes system Dock + custom slots (+ optional transient running apps) for display. Pure.
public enum SlotComposer {
    public struct Item: Equatable, Sendable, Identifiable {
        public enum Origin: String, Sendable {
            case systemDock
            case custom
            /// Live running app not already on the strip (ephemeral; opt-in).
            case running
        }

        public var id: String { slot.id }
        public var slot: Slot
        public var origin: Origin

        public init(slot: Slot, origin: Origin) {
            self.slot = slot
            self.origin = origin
        }
    }

    /// - Parameters:
    ///   - custom: User-defined slots (ordered).
    ///   - system: Live system Dock apps (ordered as in Dock).
    ///   - mode: off / merge / mirror.
    ///   - runningApps: GUI apps currently running (for optional transient section).
    ///   - includeRunningExtras: when true, append running apps not already on the strip.
    public static func compose(
        custom: [Slot],
        system: [SystemDockEntry],
        mode: SystemDockIntegration,
        runningApps: [RunningAppInfo] = [],
        includeRunningExtras: Bool = false
    ) -> [Item] {
        var items: [Item]
        switch mode {
        case .off:
            items = custom.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated().map { i, slot in
                var s = slot
                s.sortOrder = i
                return Item(slot: s, origin: .custom)
            }

        case .mirror:
            items = system.enumerated().map { index, entry in
                var s = SystemDockReader.slot(from: entry)
                s.sortOrder = index
                return Item(slot: s, origin: .systemDock)
            }

        case .merge:
            // Left → right: custom slots · system Dock (live) · (running extras appended below).
            items = []
            var seenPaths = Set<String>()
            var order = 0

            for slot in custom.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let key = SystemDockEntry.canonicalIdentityPath(slot.target).lowercased()
                if !key.isEmpty, seenPaths.contains(key) { continue }
                if !key.isEmpty { seenPaths.insert(key) }
                var s = slot
                s.sortOrder = order
                order += 1
                items.append(Item(slot: s, origin: .custom))
            }

            for entry in system {
                let key = entry.identityPath.lowercased()
                // Skip system apps already represented by a custom slot (or prior system entry).
                guard !seenPaths.contains(key) else { continue }
                seenPaths.insert(key)
                // Also skip if this sysdock id was already imported as a custom row above.
                let sysID = SystemDockReader.slot(from: entry).id
                if items.contains(where: { $0.slot.id == sysID }) { continue }
                var s = SystemDockReader.slot(from: entry)
                s.sortOrder = order
                order += 1
                items.append(Item(slot: s, origin: .systemDock))
            }
        }

        guard includeRunningExtras, !runningApps.isEmpty else { return items }

        var stripPaths = Set(items.map { SystemDockEntry.normalizePath($0.slot.target).lowercased() }.filter { !$0.isEmpty })
        var stripBundles = Set<String>()
        for item in items {
            if let bundle = AppIdentity.from(slot: item.slot).bundleIdentifier {
                stripBundles.insert(bundle.lowercased())
            }
        }

        let extras = TransientRunningApps.extras(
            running: runningApps,
            stripPaths: stripPaths,
            stripBundles: stripBundles
        )
        var order = items.count
        for app in extras {
            let s = app.asSlot(sortOrder: order)
            order += 1
            items.append(Item(slot: s, origin: .running))
            if !app.path.isEmpty {
                stripPaths.insert(app.path.lowercased())
            }
        }
        return items
    }

    /// Import system entries as durable custom slots (paths not already present).
    public static func importableSystemEntries(
        system: [SystemDockEntry],
        custom: [Slot]
    ) -> [SystemDockEntry] {
        let existing = customPathKeys(custom)
        return system.filter { !existing.contains($0.identityPath.lowercased()) }
    }

    /// Whether this system Dock path is already a custom slot.
    public static func isAlreadyCustom(
        entry: SystemDockEntry,
        custom: [Slot]
    ) -> Bool {
        customPathKeys(custom).contains(entry.identityPath.lowercased())
    }

    /// Resolve a dragged path (or path+label payload) against live system Dock entries.
    public static func entryMatchingPath(
        _ path: String,
        in system: [SystemDockEntry]
    ) -> SystemDockEntry? {
        let key = SystemDockEntry.canonicalIdentityPath(path).lowercased()
        return system.first { $0.identityPath.lowercased() == key }
    }

    private static func customPathKeys(_ custom: [Slot]) -> Set<String> {
        Set(custom.map { SystemDockEntry.canonicalIdentityPath($0.target).lowercased() }.filter { !$0.isEmpty })
    }
}

/// Drag/drop payload helpers for the Slots tab (path-first; optional label).
public enum SystemDockDragPayload {
    private static let separator = "\u{1F}"

    public static func encode(path: String, label: String) -> String {
        "\(SystemDockEntry.normalizePath(path))\(separator)\(label)"
    }

    public static func encode(_ entry: SystemDockEntry) -> String {
        encode(path: entry.path, label: entry.label)
    }

    public static func decode(_ raw: String) -> (path: String, label: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(separator) {
            let parts = trimmed.split(separator: Character(separator), maxSplits: 1, omittingEmptySubsequences: false)
                .map(String.init)
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            let path = SystemDockEntry.normalizePath(parts[0])
            let label = parts[1].isEmpty
                ? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                : parts[1]
            return (path, label)
        }
        // Plain path (Finder drop or path-only drag).
        let path = SystemDockEntry.normalizePath(trimmed)
        guard path.hasPrefix("/") else { return nil }
        let label = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return (path, label)
    }
}
