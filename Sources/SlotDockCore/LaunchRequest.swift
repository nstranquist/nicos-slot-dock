import Foundation

/// Resolved launch payload for a slot. Pure: no `NSWorkspace` calls.
public struct LaunchRequest: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case application
        case file
        case url
        case unknown
    }

    public let slotID: String
    public let label: String
    public let kind: Kind
    /// Absolute file path for app/file, or absolute URL string for `url`.
    public let resolvedTarget: String
    public let isValid: Bool

    public init(slotID: String, label: String, kind: Kind, resolvedTarget: String, isValid: Bool) {
        self.slotID = slotID
        self.label = label
        self.kind = kind
        self.resolvedTarget = resolvedTarget
        self.isValid = isValid
    }
}

/// Builds a `LaunchRequest` from a slot without performing the open.
public enum LaunchResolver {
    /// Resolve a launch request for the given slot.
    /// - Parameter fileExists: injectable existence check for tests.
    public static func resolve(
        slot: Slot,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        fileIsDirectory: (String) -> Bool = { path in
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return isDirectory.boolValue
        }
    ) -> LaunchRequest {
        let trimmed = slot.target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LaunchRequest(
                slotID: slot.id,
                label: slot.label,
                kind: .unknown,
                resolvedTarget: "",
                isValid: false
            )
        }

        // URL schemes (http, https, file, custom). Syntax is validated here;
        // NSWorkspace remains the authority for whether a handler is installed.
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme != "file",
           scheme.count >= 2,
           !trimmed.hasPrefix("/"),
           (scheme != "http" && scheme != "https" || url.host != nil)
        {
            return LaunchRequest(
                slotID: slot.id,
                label: slot.label,
                kind: .url,
                resolvedTarget: url.absoluteString,
                isValid: true
            )
        }

        // Expand ~
        let expanded: String
        if trimmed.hasPrefix("~") {
            expanded = (trimmed as NSString).expandingTildeInPath
        } else {
            expanded = trimmed
        }

        // file:// URL
        if let url = URL(string: expanded), url.isFileURL {
            let path = url.standardizedFileURL.path
            let kind: LaunchRequest.Kind = Self.applicationKind(
                path: path,
                fileExists: fileExists,
                fileIsDirectory: fileIsDirectory
            )
            return LaunchRequest(
                slotID: slot.id,
                label: slot.label,
                kind: kind,
                resolvedTarget: path,
                isValid: fileExists(path)
            )
        }

        let wasAbsolutePath = expanded.hasPrefix("/")
        let normalizedPath = URL(fileURLWithPath: expanded).standardizedFileURL.path
        let kind: LaunchRequest.Kind = wasAbsolutePath
            ? Self.applicationKind(
                path: normalizedPath,
                fileExists: fileExists,
                fileIsDirectory: fileIsDirectory
            )
            // Keep the semantic kind useful for the error UI, but never let
            // a cwd-dependent relative target become a valid launch request.
            : (Self.isApplicationPath(normalizedPath) ? .application : .file)
        return LaunchRequest(
            slotID: slot.id,
            label: slot.label,
            kind: kind,
            resolvedTarget: normalizedPath,
            // Slot paths are documented as absolute. Refuse cwd-dependent
            // relative paths rather than persisting an unstable launch target.
            isValid: wasAbsolutePath && fileExists(normalizedPath)
        )
    }

    private static func isApplicationPath(_ path: String) -> Bool {
        path.lowercased().hasSuffix(".app")
    }

    private static func applicationKind(
        path: String,
        fileExists: (String) -> Bool,
        fileIsDirectory: (String) -> Bool
    ) -> LaunchRequest.Kind {
        guard isApplicationPath(path) else { return .file }
        // Preserve application classification for missing `.app` targets so
        // the UI can explain a missing app, but never launch a regular file as
        // an application when the path exists.
        return !fileExists(path) || fileIsDirectory(path) ? .application : .file
    }

    /// Open invocation payload — what the UI layer would hand to NSWorkspace / open.
    public static func openPayload(for request: LaunchRequest) -> OpenPayload? {
        guard request.isValid else { return nil }
        switch request.kind {
        case .url:
            guard let url = URL(string: request.resolvedTarget) else { return nil }
            return OpenPayload(url: url, path: nil, kind: .url)
        case .application, .file:
            let url = URL(fileURLWithPath: request.resolvedTarget)
            return OpenPayload(url: url, path: request.resolvedTarget, kind: request.kind)
        case .unknown:
            return nil
        }
    }
}

/// Concrete open call description for tests and the AppKit bridge.
public struct OpenPayload: Equatable, Sendable {
    public let url: URL
    public let path: String?
    public let kind: LaunchRequest.Kind

    public init(url: URL, path: String?, kind: LaunchRequest.Kind) {
        self.url = url
        self.path = path
        self.kind = kind
    }
}
