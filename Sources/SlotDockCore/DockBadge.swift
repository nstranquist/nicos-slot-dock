import Foundation

/// Notification badge shown on a Dock tile (count or mark-only).
public struct DockBadge: Equatable, Hashable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        case count(Int)
        case mark
    }

    public var kind: Kind
    public var rawLabel: String

    public init(kind: Kind, rawLabel: String) {
        self.kind = kind
        self.rawLabel = rawLabel
    }

    public var count: Int? {
        if case .count(let value) = kind { return value }
        return nil
    }
}

/// Pure formatting for the red badge overlay and VoiceOver.
public enum DockBadgeFormatting {
    public static let overflowAt = 100

    public static func displayText(_ badge: DockBadge, overflowAt: Int = overflowAt) -> String {
        switch badge.kind {
        case .count(let value) where value >= overflowAt:
            return "\(overflowAt - 1)+"
        case .count(let value):
            return "\(value)"
        case .mark:
            return ""
        }
    }

    public static func accessibilityText(_ badge: DockBadge) -> String {
        switch badge.kind {
        case .count(1):
            return "1 notification"
        case .count(let value):
            return "\(value) notifications"
        case .mark:
            return "unread notifications"
        }
    }
}

/// Parses Launch Services `StatusLabel` dictionaries and AX `AXStatusLabel` strings.
public enum DockBadgeParser {
    public static func parseStatusLabel(_ value: Any?) -> DockBadge? {
        guard let value, !(value is NSNull) else { return nil }
        if let dict = value as? [String: Any] {
            return parseLabelValue(dict["label"])
        }
        if let dict = value as? [AnyHashable: Any] {
            return parseLabelValue(dict["label"])
        }
        return parseLabelValue(value)
    }

    public static func parseLabelValue(_ value: Any?) -> DockBadge? {
        guard let value, !(value is NSNull) else { return nil }
        if let number = value as? Int {
            return number > 0 ? DockBadge(kind: .count(number), rawLabel: String(number)) : nil
        }
        if let number = value as? Int64, number > 0, number <= Int64(Int.max) {
            return DockBadge(kind: .count(Int(number)), rawLabel: String(number))
        }
        if let number = value as? NSNumber {
            let parsed = number.intValue
            return parsed > 0 ? DockBadge(kind: .count(parsed), rawLabel: number.stringValue) : nil
        }
        if let string = value as? String {
            return parseString(string)
        }
        return nil
    }

    /// Dock tile download progress. Values in (0, 1) or (0, 100] become 0...1.
    public static func parseProgress(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        let raw: Double
        if let number = value as? NSNumber {
            raw = number.doubleValue
        } else if let number = value as? Double {
            raw = number
        } else if let number = value as? Int {
            raw = Double(number)
        } else {
            return nil
        }
        guard raw.isFinite, raw > 0 else { return nil }
        let normalized = raw > 1 ? raw / 100 : raw
        guard normalized > 0, normalized < 1 else { return nil }
        return normalized
    }

    public static func parseString(_ raw: String) -> DockBadge? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let number = Int(trimmed), number > 0 {
            return DockBadge(kind: .count(number), rawLabel: trimmed)
        }
        return DockBadge(kind: .mark, rawLabel: trimmed)
    }
}

/// Latest badges keyed for strip lookup. Pure; AppKit fills it.
public struct DockBadgeSnapshot: Equatable, Sendable {
    public var byBundle: [String: DockBadge]
    public var byPath: [String: DockBadge]
    public var byTitle: [String: DockBadge]
    public var progressByBundle: [String: Double]
    public var progressByPath: [String: Double]

    public static let empty = DockBadgeSnapshot()

    public init(
        byBundle: [String: DockBadge] = [:],
        byPath: [String: DockBadge] = [:],
        byTitle: [String: DockBadge] = [:],
        progressByBundle: [String: Double] = [:],
        progressByPath: [String: Double] = [:]
    ) {
        self.byBundle = Self.uniqued(byBundle.map { ($0.key.lowercased(), $0.value) })
        self.byPath = Self.uniqued(
            byPath.map { (SystemDockEntry.canonicalIdentityPath($0.key).lowercased(), $0.value) }
        )
        self.byTitle = Self.uniqued(byTitle.map { ($0.key.lowercased(), $0.value) })
        self.progressByBundle = Self.uniquedProgress(progressByBundle.map { ($0.key.lowercased(), $0.value) })
        self.progressByPath = Self.uniquedProgress(
            progressByPath.map { (SystemDockEntry.canonicalIdentityPath($0.key).lowercased(), $0.value) }
        )
    }

    private static func uniqued(_ pairs: [(String, DockBadge)]) -> [String: DockBadge] {
        Dictionary(pairs, uniquingKeysWith: { _, latest in latest })
    }

    private static func uniquedProgress(_ pairs: [(String, Double)]) -> [String: Double] {
        Dictionary(pairs, uniquingKeysWith: { _, latest in latest })
    }

    public var isEmpty: Bool {
        byBundle.isEmpty && byPath.isEmpty && byTitle.isEmpty
            && progressByBundle.isEmpty && progressByPath.isEmpty
    }

    public func badge(for identity: AppIdentity, label: String? = nil) -> DockBadge? {
        if let path = identity.path {
            let key = SystemDockEntry.canonicalIdentityPath(path).lowercased()
            if let badge = byPath[key] {
                return badge
            }
        }
        if let bundle = identity.bundleIdentifier?.lowercased(), !bundle.isEmpty,
           let badge = byBundle[bundle]
        {
            return badge
        }
        if let label, let badge = byTitle[label.lowercased()] {
            return badge
        }
        return nil
    }

    public func badge(for slot: Slot) -> DockBadge? {
        let path = SystemDockEntry.canonicalIdentityPath(slot.target)
        if !path.isEmpty, let badge = byPath[path.lowercased()] {
            return badge
        }
        if let badge = byTitle[slot.label.lowercased()] {
            return badge
        }
        if let badge = badge(for: AppIdentity.from(slot: slot, resolveBundleFromDisk: false), label: nil) {
            return badge
        }
        return badge(for: AppIdentity.from(slot: slot, resolveBundleFromDisk: true), label: nil)
    }

    public func progress(for slot: Slot) -> Double? {
        let path = SystemDockEntry.canonicalIdentityPath(slot.target)
        if !path.isEmpty, let value = progressByPath[path.lowercased()] {
            return value
        }
        let identity = AppIdentity.from(slot: slot, resolveBundleFromDisk: true)
        if let bundle = identity.bundleIdentifier?.lowercased(),
           let value = progressByBundle[bundle]
        {
            return value
        }
        return nil
    }
}

/// Pure matcher for `icon-<token>.png` sidecars (ChatGPT ↔ Codex, other Electron apps).
public enum DockIconSidecar {
    public static func tokens(from title: String) -> [String] {
        let lowered = title.lowercased()
        var parts = lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let compact = lowered.filter(\.isLetter)
        if !compact.isEmpty { parts.append(compact) }
        return parts.filter { $0.count >= 3 }
    }

    public static func token(fromResourceName name: String) -> String {
        var base = (name as NSString).deletingPathExtension.lowercased()
        if base.hasPrefix("icon-") {
            base = String(base.dropFirst("icon-".count))
        }
        return base
    }

    public static func preferredToken(titles: [String], available: Set<String>, dark: Bool) -> String {
        let lowered = Set(available.map { $0.lowercased() })
        for token in titles.flatMap(tokens(from:)) {
            if dark {
                if lowered.contains("\(token)-dark-color") { return "\(token)-dark-color" }
                if lowered.contains("\(token)-dark") { return "\(token)-dark" }
            } else if lowered.contains("\(token)-light") {
                return "\(token)-light"
            }
            if lowered.contains(token) { return token }
        }
        return ""
    }
}

public enum DockBadgeMerge {
    /// Launch Services is authoritative when it publishes a label; AX titles fill holes
    /// (Messages / WhatsApp often omit `StatusLabel`).
    public static func merging(
        launchServices: DockBadgeSnapshot,
        accessibilityByTitle: [String: DockBadge]
    ) -> DockBadgeSnapshot {
        var titles = launchServices.byTitle
        for (key, badge) in accessibilityByTitle {
            let lowered = key.lowercased()
            if titles[lowered] == nil {
                titles[lowered] = badge
            }
        }
        return DockBadgeSnapshot(
            byBundle: launchServices.byBundle,
            byPath: launchServices.byPath,
            byTitle: titles,
            progressByBundle: launchServices.progressByBundle,
            progressByPath: launchServices.progressByPath
        )
    }
}
