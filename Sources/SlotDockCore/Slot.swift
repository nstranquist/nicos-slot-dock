import Foundation

/// A single custom application/icon slot on the dock strip.
public struct Slot: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    /// Launch target: absolute `.app` path, file path, or URL string.
    public var target: String
    /// Optional custom icon path (PNG/ICNS/JPEG). When nil/empty, the app resolves an icon from `target`.
    public var iconPath: String?
    public var sortOrder: Int

    public init(
        id: String = UUID().uuidString,
        label: String,
        target: String,
        iconPath: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.label = label
        self.target = target
        self.iconPath = iconPath
        self.sortOrder = sortOrder
    }
}

/// On-disk document for the ordered slot list + dock preferences.
public struct SlotDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var slots: [Slot]
    public var preferences: DockPreferences

    public init(
        version: Int = 2,
        slots: [Slot] = [],
        preferences: DockPreferences = .default
    ) {
        self.version = version
        self.slots = slots
        self.preferences = preferences
    }

    public static let empty = SlotDocument(version: 2, slots: [], preferences: .default)

    // Backward-compatible decode: v1 files omit preferences.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        slots = try container.decodeIfPresent([Slot].self, forKey: .slots) ?? []
        var prefs = try container.decodeIfPresent(DockPreferences.self, forKey: .preferences) ?? .default
        prefs.sanitize()
        preferences = prefs
    }

    private enum CodingKeys: String, CodingKey {
        case version, slots, preferences
    }
}
