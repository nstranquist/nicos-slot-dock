import Foundation

/// Finder Trash tile. The system Dock draws this as a special item, not a
/// `persistent-apps` entry; Nicos Slot Dock composes it on the right.
public enum TrashSlot {
    public static let slotID = "trash"
    public static let label = "Trash"

    public static func canonicalPath(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        if let url = try? fileManager.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            return SystemDockEntry.normalizePath(url.path)
        }
        return SystemDockEntry.normalizePath(
            homeDirectory.appendingPathComponent(".Trash", isDirectory: true).path
        )
    }

    public static func slot(path: String, sortOrder: Int = 0) -> Slot {
        Slot(
            id: slotID,
            label: label,
            target: SystemDockEntry.normalizePath(path),
            iconPath: nil,
            sortOrder: sortOrder
        )
    }

    public static func matches(path: String, canonicalPath: String) -> Bool {
        let want = SystemDockEntry.canonicalIdentityPath(canonicalPath).lowercased()
        guard !want.isEmpty else { return false }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let url = URL(string: trimmed), url.isFileURL {
            let got = SystemDockEntry.canonicalIdentityPath(url.path).lowercased()
            if got == want { return true }
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return SystemDockEntry.canonicalIdentityPath(expanded).lowercased() == want
    }

    public static func matches(slot: Slot, canonicalPath: String) -> Bool {
        matches(path: slot.target, canonicalPath: canonicalPath)
    }

    /// Home Trash plus other-volume trash folders. `trashDirectoryForVolume`
    /// is injectable so tests do not need real mounts.
    public static func liveDirectoryPaths(fileManager: FileManager = .default) -> [String] {
        let home = canonicalPath(fileManager: fileManager)
        let volumes = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []
        return directoryPaths(homeTrash: home, volumeRoots: volumes.map(\.path))
    }

    public static func directoryPaths(
        homeTrash: String,
        volumeRoots: [String] = [],
        trashDirectoryForVolume: (String) -> String? = { root in
            let url = URL(fileURLWithPath: root, isDirectory: true)
            return (try? FileManager.default.url(
                for: .trashDirectory,
                in: .userDomainMask,
                appropriateFor: url,
                create: false
            )).map { SystemDockEntry.normalizePath($0.path) }
        }
    ) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        func add(_ raw: String) {
            let normalized = SystemDockEntry.normalizePath(raw)
            guard !normalized.isEmpty else { return }
            if seen.insert(normalized.lowercased()).inserted {
                out.append(normalized)
            }
        }
        add(homeTrash)
        for root in volumeRoots {
            if let path = trashDirectoryForVolume(root) {
                add(path)
            }
        }
        return out
    }

    public static func isIgnorableListingName(_ name: String) -> Bool {
        name == ".DS_Store" || name == ".localized" || name == "Icon\r"
    }

    public static func isEmpty(
        at paths: [String],
        contentsOfDirectory: (String) throws -> [String] = {
            try FileManager.default.contentsOfDirectory(atPath: $0)
        }
    ) -> Bool {
        for path in paths {
            let names = (try? contentsOfDirectory(path)) ?? []
            if names.contains(where: { !isIgnorableListingName($0) }) {
                return false
            }
        }
        return true
    }

    public static func iconCacheKey(isEmpty: Bool) -> String {
        isEmpty ? "empty" : "full"
    }

    /// Paths inside trash directories that Empty Trash should delete.
    public static func itemsToRemove(
        in directories: [String],
        contentsOfDirectory: (String) throws -> [String] = {
            try FileManager.default.contentsOfDirectory(atPath: $0)
        }
    ) -> [String] {
        var out: [String] = []
        for directory in directories {
            let names = (try? contentsOfDirectory(directory)) ?? []
            for name in names {
                out.append((directory as NSString).appendingPathComponent(name))
            }
        }
        return out
    }
}

/// Which dropped paths may move to Trash (not the Trash folder itself).
public enum TrashRecyclePolicy {
    public static func acceptedPaths(
        _ raws: [String],
        trashDirectories: [String]
    ) -> [String] {
        let trashKeys = Set(
            trashDirectories
                .map { SystemDockEntry.canonicalIdentityPath($0).lowercased() }
                .filter { !$0.isEmpty }
        )
        var seen = Set<String>()
        var out: [String] = []
        for raw in raws {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let expanded = (trimmed as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else { continue }
            let canonical = SystemDockEntry.canonicalIdentityPath(expanded)
            let key = canonical.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            if trashKeys.contains(key) { continue }
            if trashKeys.contains(where: { key.hasPrefix($0 + "/") }) { continue }
            out.append(SystemDockEntry.normalizePath(expanded))
        }
        return out
    }
}
