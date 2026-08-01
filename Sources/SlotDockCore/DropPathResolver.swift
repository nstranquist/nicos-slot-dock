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
                guard let host = url.host, !host.isEmpty else {
                    return .reject("URL needs a host")
                }
                return .accept(Candidate(label: host, target: trimmed))
            }
            if scheme == "file" {
                return resolveFilePath(url.path)
            }
            return .accept(Candidate(
                label: url.host?.isEmpty == false ? (url.host ?? scheme) : scheme,
                target: url.absoluteString
            ))
        }

        // Bare path (possibly with file:// already expanded by pasteboard)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            return resolveFilePath(expanded)
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

        // Finder can drop an Internet Shortcut file instead of its resolved URL.
        // Decode it explicitly so malformed/non-UTF-8 input is visible rather
        // than being accepted as an opaque file or silently discarded.
        if name.lowercased().hasSuffix(".url"), exists, !isDir.boolValue {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: normalized)),
                  let contents = String(data: data, encoding: .utf8)
            else {
                return .reject("Internet Shortcut is not valid UTF-8: \(name)")
            }
            let target = contents
                .split(whereSeparator: \.isNewline)
                .compactMap { line -> String? in
                    let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                    guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "url" else {
                        return nil
                    }
                    return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .first
            guard let target,
                  let url = URL(string: target),
                  let scheme = url.scheme?.lowercased(),
                  !scheme.isEmpty,
                  (scheme == "http" || scheme == "https" ? url.host?.isEmpty == false : true)
            else {
                return .reject("Internet Shortcut has no valid URL: \(name)")
            }
            let label = (name as NSString).deletingPathExtension
            return .accept(Candidate(label: label.isEmpty ? name : label, target: url.absoluteString))
        }

        let isApp = name.lowercased().hasSuffix(".app")
        if isApp && exists && !isDir.boolValue {
            return .reject("Application bundle is not a directory: \(name)")
        }
        if isApp {
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
        if name.lowercased().hasSuffix(".app") {
            let label = (name as NSString).deletingPathExtension
            return .accept(Candidate(label: label, target: normalized))
        }
        return .reject("Path not found: \(name)")
    }
}
