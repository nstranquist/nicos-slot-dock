import Foundation

/// Pure slot list mutations + JSON persistence. Headless-safe (no AppKit).
public final class SlotStore: @unchecked Sendable {
    public private(set) var document: SlotDocument
    public let fileURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        var loaded = Self.load(from: fileURL, decoder: decoder, fileManager: fileManager) ?? .empty
        let migration = ConfigMigration.migratePreferences(
            documentVersion: loaded.version,
            preferences: loaded.preferences
        )
        if migration.migrated || loaded.version < ConfigDocumentVersion.current {
            loaded.version = migration.version
            loaded.preferences = migration.preferences
            self.document = loaded
            normalizeOrder()
            // Persist upgraded schema so reloads stay on the modern shape.
            _ = save()
        } else {
            self.document = loaded
            normalizeOrder()
        }
    }

    public var slots: [Slot] {
        document.slots.sorted { $0.sortOrder < $1.sortOrder }
    }

    public var preferences: DockPreferences {
        document.preferences
    }

    // MARK: - Preferences

    @discardableResult
    public func updatePreferences(_ mutate: (inout DockPreferences) -> Void) -> DockPreferences {
        var next = document.preferences
        mutate(&next)
        next.sanitize()
        document.preferences = next
        if document.version < 2 { document.version = 2 }
        save()
        return document.preferences
    }

    public func setPreferences(_ preferences: DockPreferences) {
        var next = preferences
        next.sanitize()
        document.preferences = next
        if document.version < 2 { document.version = 2 }
        save()
    }

    // MARK: - CRUD

    @discardableResult
    public func add(
        label: String,
        target: String,
        iconPath: String? = nil,
        id: String = UUID().uuidString
    ) -> Slot {
        let order = (document.slots.map(\.sortOrder).max() ?? -1) + 1
        let slot = Slot(id: id, label: label, target: target, iconPath: iconPath, sortOrder: order)
        document.slots.append(slot)
        save()
        return slot
    }

    @discardableResult
    public func update(
        id: String,
        label: String? = nil,
        target: String? = nil,
        iconPath: String?? = nil
    ) -> Slot? {
        guard let index = document.slots.firstIndex(where: { $0.id == id }) else { return nil }
        if let label { document.slots[index].label = label }
        if let target { document.slots[index].target = target }
        if let iconPath { document.slots[index].iconPath = iconPath }
        save()
        return document.slots[index]
    }

    @discardableResult
    public func remove(id: String) -> Bool {
        let before = document.slots.count
        document.slots.removeAll { $0.id == id }
        guard document.slots.count < before else { return false }
        normalizeOrder()
        save()
        return true
    }

    /// Move slot at `fromIndex` (in sorted order) to `toIndex` (clamped).
    @discardableResult
    public func reorder(from fromIndex: Int, to toIndex: Int) -> [Slot] {
        var ordered = slots
        guard ordered.indices.contains(fromIndex) else { return ordered }
        let clamped = min(max(toIndex, 0), ordered.count - 1)
        guard fromIndex != clamped else { return ordered }
        let item = ordered.remove(at: fromIndex)
        ordered.insert(item, at: clamped)
        for (i, slot) in ordered.enumerated() {
            if let idx = document.slots.firstIndex(where: { $0.id == slot.id }) {
                document.slots[idx].sortOrder = i
            }
        }
        save()
        return slots
    }

    /// Replace entire ordered list (used by settings bulk save).
    public func replaceAll(_ slots: [Slot]) {
        var next = slots
        for i in next.indices {
            next[i].sortOrder = i
        }
        document.slots = next
        save()
    }

    // MARK: - Persistence

    @discardableResult
    public func save() -> Bool {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try encoder.encode(document)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func reload() {
        document = Self.load(from: fileURL, decoder: decoder, fileManager: fileManager) ?? .empty
        normalizeOrder()
    }

    public static func defaultConfigURL(home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) -> URL {
        home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("nicos-slot-dock", isDirectory: true)
            .appendingPathComponent("slots.json", isDirectory: false)
    }

    // MARK: - Private

    private func normalizeOrder() {
        let ordered = document.slots.sorted { $0.sortOrder < $1.sortOrder }
        for (i, slot) in ordered.enumerated() {
            if let idx = document.slots.firstIndex(where: { $0.id == slot.id }) {
                document.slots[idx].sortOrder = i
            }
        }
    }

    private static func load(from url: URL, decoder: JSONDecoder, fileManager: FileManager) -> SlotDocument? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard var doc = try? decoder.decode(SlotDocument.self, from: data) else { return nil }
        // Decode already fills missing preferences via DockPreferences init(from:);
        // still sanitize delay clamps etc.
        doc.preferences.sanitize()
        return doc
    }
}
