import Foundation

/// Local metadata for Get Info. No AppKit and no network.
public struct SlotInfoSnapshot: Equatable, Sendable {
    public var label: String
    public var kind: LaunchRequest.Kind
    public var path: String
    public var bundleIdentifier: String?
    public var version: String?
    public var build: String?
    public var byteCount: Int64?
    public var exists: Bool

    public init(
        label: String,
        kind: LaunchRequest.Kind,
        path: String,
        bundleIdentifier: String? = nil,
        version: String? = nil,
        build: String? = nil,
        byteCount: Int64? = nil,
        exists: Bool
    ) {
        self.label = label
        self.kind = kind
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.build = build
        self.byteCount = byteCount
        self.exists = exists
    }
}

/// Builds a Get Info snapshot from disk. File access is injectable for tests.
public enum SlotInfoSnapshotBuilder {
    public static func infoPlistPath(appPath: String) -> String {
        (appPath as NSString).appendingPathComponent("Contents/Info.plist")
    }

    public static func build(
        label: String,
        kind: LaunchRequest.Kind,
        path: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        fileByteCount: (String) -> Int64? = { path in
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            if let allocated = values?.totalFileAllocatedSize, allocated > 0 {
                return Int64(allocated)
            }
            if let size = values?.fileSize, size > 0 {
                return Int64(size)
            }
            return nil
        },
        infoDictionary: (String) -> [String: Any]? = { path in
            let plistPath = SlotInfoSnapshotBuilder.infoPlistPath(appPath: path)
            guard FileManager.default.fileExists(atPath: plistPath),
                  let dict = NSDictionary(contentsOf: URL(fileURLWithPath: plistPath)) as? [String: Any]
            else {
                return nil
            }
            return dict
        }
    ) -> SlotInfoSnapshot {
        let exists = !path.isEmpty && fileExists(path)
        var bundleIdentifier: String?
        var version: String?
        var build: String?
        if kind == .application, !path.isEmpty, let info = infoDictionary(path) {
            bundleIdentifier = stringValue(info["CFBundleIdentifier"])
            version = stringValue(info["CFBundleShortVersionString"])
            build = stringValue(info["CFBundleVersion"])
        }
        if bundleIdentifier == nil {
            bundleIdentifier = AppIdentity.bundleIdentifier(forAppPath: path)
        }
        let bytes = exists ? fileByteCount(path) : nil
        return SlotInfoSnapshot(
            label: label,
            kind: kind,
            path: path,
            bundleIdentifier: bundleIdentifier,
            version: version,
            build: build,
            byteCount: bytes,
            exists: exists
        )
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
}

/// Operator-facing Get Info text. Local only.
public enum SlotInfoFormatting {
    public static func kindLabel(_ kind: LaunchRequest.Kind) -> String {
        switch kind {
        case .application: return "Application"
        case .file: return "File"
        case .url: return "URL"
        case .unknown: return "Unknown"
        }
    }

    public static func displayText(_ info: SlotInfoSnapshot) -> String {
        var lines: [String] = []
        lines.append("Kind: \(kindLabel(info.kind))")
        if let version = info.version, let build = info.build, version != build {
            lines.append("Version: \(version) (\(build))")
        } else if let version = info.version {
            lines.append("Version: \(version)")
        } else if let build = info.build {
            lines.append("Version: \(build)")
        }
        if let bundle = info.bundleIdentifier, !bundle.isEmpty {
            lines.append("Bundle ID: \(bundle)")
        }
        if !info.path.isEmpty {
            lines.append("Path: \(info.path)")
        }
        if let bytes = info.byteCount, bytes > 0 {
            lines.append("Size: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
        }
        if !info.exists {
            lines.append("Missing on disk")
        }
        return lines.joined(separator: "\n")
    }
}
