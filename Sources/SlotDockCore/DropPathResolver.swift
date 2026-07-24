import Foundation

/// Pure mapping from a dropped path/URL string to a custom slot label+target.
/// Used by the strip drop target and unit-tested without AppKit.
public enum DropPathResolver {
    public struct Candidate: Equatable, Sendable {
        public var label: String
        public var target: String
        public init(label: String, target: String) {
            self.label = label
            self.target = target
        }
    }

    public enum Outcome: Equatable, Sendable {
        case accept(Candidate)
        case reject(String)
    }

    /// Resolve a filesystem path, `file://` URL, or http(s) URL into a slot candidate.
    public static func resolve(_ raw: String) -> Outcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .reject("Empty drop") }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" {
                let host = url.host ?? "Link"
                return .accept(Candidate(label: host, target: trimmed))
            }
            if scheme == "file" {
                return resolveFilePath(url.path)
            }
        }

        // Bare path (possibly with file:// already expanded by pasteboard)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            return resolveFilePath(expanded)
        }

        // Last resort: treat as URL string if it looks like one
        if trimmed.contains("://") {
            return .accept(Candidate(label: "Link", target: trimmed))
        }
        return .reject("Unsupported drop (need app, file, or URL)")
    }

    /// Resolve multiple pasteboard-style strings; first accept wins, else combined reject.
    public static func resolveFirst(of candidates: [String]) -> Outcome {
        var lastReject = "Nothing to add"
        for raw in candidates {
            switch resolve(raw) {
            case .accept(let c): return .accept(c)
            case .reject(let r): lastReject = r
            }
        }
        return .reject(lastReject)
    }

    private static func resolveFilePath(_ path: String) -> Outcome {
        let normalized = (path as NSString).standardizingPath
        guard !normalized.isEmpty else { return .reject("Empty path") }

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: normalized, isDirectory: &isDir)
        let name = (normalized as NSString).lastPathComponent

        if normalized.hasSuffix(".app") || (exists && isDir.boolValue && name.hasSuffix(".app")) {
            let label = (name as NSString).deletingPathExtension
            return .accept(Candidate(label: label.isEmpty ? name : label, target: normalized))
        }

        if exists {
            let label = (name as NSString).deletingPathExtension
            return .accept(Candidate(
                label: label.isEmpty ? name : label,
                target: normalized
            ))
        }

        // Allow non-existent paths that look intentional (user may fix later)
        if name.hasSuffix(".app") {
            let label = (name as NSString).deletingPathExtension
            return .accept(Candidate(label: label, target: normalized))
        }
        return .reject("Path not found: \(name)")
    }
}
