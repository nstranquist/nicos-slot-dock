import Foundation

public enum SlotStoreError: Error, Equatable, LocalizedError, Sendable {
    case readFailed(String)
    case decodeFailed(String)
    case futureVersion(Int)
    case writeFailed(String)
    case invalidSlot(String)

    public var errorDescription: String? {
        switch self {
        case .readFailed(let message): return "Could not read Slot Dock configuration: \(message)"
        case .decodeFailed(let message): return "Slot Dock configuration is invalid: \(message)"
        case .futureVersion(let version):
            return "Slot Dock configuration version \(version) is newer than this app supports. It is read-only until upgraded."
        case .writeFailed(let message): return "Could not save Slot Dock configuration: \(message)"
        case .invalidSlot(let message): return message
        }
    }
}

/// Pure slot list mutations + JSON persistence. Headless-safe (no AppKit).
public final class SlotStore {
    public private(set) var document: SlotDocument
    public let fileURL: URL
    public private(set) var lastError: SlotStoreError?
    public private(set) var isReadOnly: Bool

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private var readOnlyError: SlotStoreError?

    private struct LoadResult {
        var document: SlotDocument?
        var error: SlotStoreError?
        var readOnly: Bool
    }

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.document = .empty
        self.lastError = nil
        self.isReadOnly = false
        self.readOnlyError = nil
        install(Self.load(from: fileURL, decoder: decoder, fileManager: fileManager), persistMigration: true)
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
        guard canMutate() else { return document.preferences }
        let previous = document
        var next = document.preferences
        mutate(&next)
        next.sanitize()
        document.preferences = next
        if document.version < 2 { document.version = 2 }
        if !save() { document = previous }
        return document.preferences
    }

    @discardableResult
    public func setPreferences(_ preferences: DockPreferences) -> Bool {
        guard canMutate() else { return false }
        let previous = document
        var next = preferences
        next.sanitize()
        document.preferences = next
        if document.version < 2 { document.version = 2 }
        guard save() else {
            document = previous
            return false
        }
        return true
    }

    // MARK: - CRUD

    @discardableResult
    public func add(
        label: String,
        target: String,
        iconPath: String? = nil,
        id: String = UUID().uuidString
    ) -> Slot? {
        let normalizedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedIcon = iconPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTarget.isEmpty else {
            lastError = .invalidSlot("A Slot Dock target is required.")
            return nil
        }
        guard canMutate() else { return nil }
        guard !document.slots.contains(where: { Self.targetKey($0.target) == Self.targetKey(normalizedTarget) }) else {
            lastError = .invalidSlot("That target is already on the Slot Dock.")
            return nil
        }
        let order = (document.slots.map(\.sortOrder).max() ?? -1) + 1
        let uniqueID = id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || document.slots.contains(where: { $0.id == id })
            ? UUID().uuidString
            : id
        let displayLabel = normalizedLabel.isEmpty ? Self.fallbackLabel(for: normalizedTarget) : normalizedLabel
        let slot = Slot(id: uniqueID, label: displayLabel, target: normalizedTarget, iconPath: normalizedIcon, sortOrder: order)
        let previous = document
        document.slots.append(slot)
        guard save() else {
            document = previous
            return nil
        }
        return slot
    }

    @discardableResult
    public func update(
        id: String,
        label: String? = nil,
        target: String? = nil,
        iconPath: String?? = nil
    ) -> Slot? {
        guard canMutate() else { return nil }
        guard let index = document.slots.firstIndex(where: { $0.id == id }) else { return nil }
        let previous = document
        if let label { document.slots[index].label = label }
        if let target { document.slots[index].target = target }
        if let iconPath {
            document.slots[index].iconPath = iconPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        document.slots[index].label = document.slots[index].label.trimmingCharacters(in: .whitespacesAndNewlines)
        document.slots[index].target = document.slots[index].target.trimmingCharacters(in: .whitespacesAndNewlines)
        if document.slots[index].target != previous.slots[index].target,
           document.slots.contains(where: {
               $0.id != id && Self.targetKey($0.target) == Self.targetKey(document.slots[index].target)
           })
        {
            document = previous
            lastError = .invalidSlot("That target is already on the Slot Dock.")
            return nil
        }
        if document.slots[index].label.isEmpty {
            document.slots[index].label = Self.fallbackLabel(for: document.slots[index].target)
        }
        guard !document.slots[index].target.isEmpty else {
            document = previous
            lastError = .invalidSlot("A Slot Dock target is required.")
            return nil
        }
        guard save() else {
            document = previous
            return nil
        }
        return document.slots[index]
    }

    @discardableResult
    public func remove(id: String) -> Bool {
        guard canMutate() else { return false }
        let previous = document
        let before = document.slots.count
        document.slots.removeAll { $0.id == id }
        guard document.slots.count < before else { return false }
        normalizeOrder()
        if !save() { document = previous; return false }
        return true
    }

    /// Move slot at `fromIndex` (in sorted order) to `toIndex` (clamped).
    @discardableResult
    public func reorder(from fromIndex: Int, to toIndex: Int) -> [Slot] {
        guard canMutate() else { return slots }
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
        let previous = document
        if !save() { document = previous }
        return slots
    }

    /// Replace entire ordered list (used by settings bulk save).
    public func replaceAll(_ slots: [Slot]) {
        guard canMutate() else { return }
        var next = [Slot]()
        var ids = Set<String>()
        var targets = Set<String>()
        for var slot in slots {
            slot.id = slot.id.trimmingCharacters(in: .whitespacesAndNewlines)
            slot.label = slot.label.trimmingCharacters(in: .whitespacesAndNewlines)
            slot.target = slot.target.trimmingCharacters(in: .whitespacesAndNewlines)
            slot.iconPath = slot.iconPath?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slot.target.isEmpty else {
                lastError = .invalidSlot("A Slot Dock target is required for every slot.")
                return
            }
            let targetKey = Self.targetKey(slot.target)
            guard targets.insert(targetKey).inserted else {
                lastError = .invalidSlot("Each Slot Dock target must be unique.")
                return
            }
            if slot.label.isEmpty { slot.label = Self.fallbackLabel(for: slot.target) }
            if slot.id.isEmpty || ids.contains(slot.id) { slot.id = UUID().uuidString }
            ids.insert(slot.id)
            next.append(slot)
        }
        for i in next.indices {
            next[i].sortOrder = i
        }
        let previous = document
        document.slots = next
        if !save() { document = previous }
    }

    // MARK: - Persistence

    @discardableResult
    public func save() -> Bool {
        guard !isReadOnly else {
            lastError = readOnlyError ?? .futureVersion(document.version)
            return false
        }
        var tempURL: URL?
        defer {
            if let tempURL, fileManager.fileExists(atPath: tempURL.path) {
                _ = try? fileManager.removeItem(at: tempURL)
            }
        }
        do {
            let dir = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            let data = try encoder.encode(document)
            let nextTempURL = dir.appendingPathComponent(".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString)")
            tempURL = nextTempURL
            try data.write(to: nextTempURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: nextTempURL.path)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(
                    fileURL,
                    withItemAt: nextTempURL,
                    backupItemName: "\(fileURL.lastPathComponent).bak"
                )
            } else {
                try fileManager.moveItem(at: nextTempURL, to: fileURL)
            }
            lastError = nil
            return true
        } catch {
            lastError = .writeFailed(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    public func reload() -> Bool {
        install(Self.load(from: fileURL, decoder: decoder, fileManager: fileManager), persistMigration: true)
        return lastError == nil
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

    private func canMutate() -> Bool {
        guard !isReadOnly else {
            lastError = readOnlyError ?? .futureVersion(document.version)
            return false
        }
        return true
    }

    private func install(_ result: LoadResult, persistMigration: Bool) {
        lastError = result.error
        isReadOnly = result.readOnly
        readOnlyError = result.readOnly ? result.error : nil
        guard var loaded = result.document else {
            document = .empty
            normalizeOrder()
            return
        }
        if !result.readOnly, let duplicateTarget = Self.duplicateTarget(in: loaded.slots) {
            let error = SlotStoreError.decodeFailed(
                "Configuration contains duplicate target \(duplicateTarget). It is read-only until repaired."
            )
            lastError = error
            isReadOnly = true
            readOnlyError = error
            document = loaded
            return
        }
        let migration = ConfigMigration.migratePreferences(
            documentVersion: loaded.version,
            preferences: loaded.preferences
        )
        let slotsNormalized = isReadOnly ? false : Self.normalizeSlots(&loaded.slots)
        let needsMigration = migration.migrated
            || loaded.version < ConfigDocumentVersion.current
            || slotsNormalized
        if !isReadOnly && needsMigration {
            loaded.version = migration.version
            loaded.preferences = migration.preferences
        }
        document = loaded
        if !isReadOnly {
            normalizeOrder()
        }
        if persistMigration && !isReadOnly && needsMigration {
            _ = save()
        }
    }

    private static func load(from url: URL, decoder: JSONDecoder, fileManager: FileManager) -> LoadResult {
        guard fileManager.fileExists(atPath: url.path) else {
            return LoadResult(document: nil, error: nil, readOnly: false)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return LoadResult(document: nil, error: .readFailed(error.localizedDescription), readOnly: true)
        }
        var doc: SlotDocument
        do {
            doc = try decoder.decode(SlotDocument.self, from: data)
        } catch {
            return LoadResult(document: nil, error: .decodeFailed(error.localizedDescription), readOnly: true)
        }
        // Decode already fills missing preferences via DockPreferences init(from:);
        // still sanitize delay clamps etc.
        if doc.version > ConfigDocumentVersion.current {
            return LoadResult(document: doc, error: .futureVersion(doc.version), readOnly: true)
        }
        doc.preferences.sanitize()
        return LoadResult(document: doc, error: nil, readOnly: false)
    }

    private static func fallbackLabel(for target: String) -> String {
        if target.hasPrefix("/") || target.lowercased().hasPrefix("file://") {
            let filePath: String
            if let url = URL(string: target), url.isFileURL {
                filePath = url.path
            } else {
                filePath = target
            }
            let fileURL = URL(fileURLWithPath: filePath)
            let path = fileURL.lastPathComponent
            let name = fileURL.deletingPathExtension().lastPathComponent
            return name.isEmpty ? (path.isEmpty ? "Slot" : path) : name
        }
        if let url = URL(string: target) {
            if let host = url.host, !host.isEmpty { return host }
            if !url.lastPathComponent.isEmpty { return url.lastPathComponent }
        }
        let path = URL(fileURLWithPath: target).lastPathComponent
        let name = URL(fileURLWithPath: target).deletingPathExtension().lastPathComponent
        return name.isEmpty ? (path.isEmpty ? "Slot" : path) : name
    }

    private static func duplicateTarget(in slots: [Slot]) -> String? {
        var targets = Set<String>()
        for slot in slots {
            let target = slot.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { continue }
            let key = targetKey(target)
            guard targets.insert(key).inserted else { return target }
        }
        return nil
    }

    /// Stable duplicate key for both filesystem targets and URL targets.
    /// Filesystem normalization is case-preserving in storage, while the key
    /// follows the macOS default case-insensitive behavior used by Finder.
    private static func targetKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme != "file"
        {
            return url.absoluteString.lowercased()
        }
        return SystemDockEntry.canonicalIdentityPath(trimmed).lowercased()
    }

    /// Repair harmless semantic drift in decodable documents before the UI sees
    /// it: duplicate/blank IDs break SwiftUI identity, and whitespace-only
    /// fields create confusing launch and edit behavior. Empty targets remain in
    /// place so the user can repair them rather than losing saved intent.
    @discardableResult
    private static func normalizeSlots(_ slots: inout [Slot]) -> Bool {
        var changed = false
        var ids = Set<String>()
        for index in slots.indices {
            let before = slots[index]
            slots[index].id = slots[index].id.trimmingCharacters(in: .whitespacesAndNewlines)
            while slots[index].id.isEmpty || ids.contains(slots[index].id) {
                slots[index].id = UUID().uuidString
            }
            ids.insert(slots[index].id)
            slots[index].label = slots[index].label.trimmingCharacters(in: .whitespacesAndNewlines)
            slots[index].target = slots[index].target.trimmingCharacters(in: .whitespacesAndNewlines)
            slots[index].iconPath = slots[index].iconPath?.trimmingCharacters(in: .whitespacesAndNewlines)
            if slots[index].label.isEmpty {
                slots[index].label = fallbackLabel(for: slots[index].target)
            }
            slots[index].sortOrder = index
            changed = changed || slots[index] != before
        }
        return changed
    }
}
