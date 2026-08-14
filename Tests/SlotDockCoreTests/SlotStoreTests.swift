import Foundation
import Testing
@testable import SlotDockCore

@Suite("SlotStore")
struct SlotStoreTests {
    private func tempURL(_ name: String = "slots.json") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("slot-dock-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }

    @Test("add creates ordered slots with stable ids")
    func addCreatesOrderedSlots() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SlotStore(fileURL: url)

        let a = store.add(label: "Safari", target: "/Applications/Safari.app", id: "slot-a")
        let b = store.add(label: "Terminal", target: "/System/Applications/Utilities/Terminal.app", id: "slot-b")

        #expect(a?.id == "slot-a")
        #expect(b?.id == "slot-b")
        #expect(store.slots.count == 2)
        #expect(store.slots[0].label == "Safari")
        #expect(store.slots[1].label == "Terminal")
        #expect(store.slots[0].sortOrder == 0)
        #expect(store.slots[1].sortOrder == 1)
    }

    @Test("update mutates label target icon")
    func updateMutatesFields() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SlotStore(fileURL: url)
        _ = store.add(label: "Old", target: "/tmp/old", iconPath: nil, id: "x")

        let updated = store.update(id: "x", label: "New", target: "/tmp/new", iconPath: .some("/tmp/icon.png"))
        #expect(updated?.label == "New")
        #expect(updated?.target == "/tmp/new")
        #expect(updated?.iconPath == "/tmp/icon.png")
        #expect(store.slots.first?.label == "New")
    }

    @Test("remove deletes by id and renumbers")
    func removeDeletesAndRenumbers() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SlotStore(fileURL: url)
        _ = store.add(label: "A", target: "/a", id: "a")
        _ = store.add(label: "B", target: "/b", id: "b")
        _ = store.add(label: "C", target: "/c", id: "c")

        #expect(store.remove(id: "b") == true)
        #expect(store.remove(id: "missing") == false)
        #expect(store.slots.map(\.id) == ["a", "c"])
        #expect(store.slots.map(\.sortOrder) == [0, 1])
    }

    @Test("reorder moves slot between indices")
    func reorderMoves() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SlotStore(fileURL: url)
        _ = store.add(label: "A", target: "/a", id: "a")
        _ = store.add(label: "B", target: "/b", id: "b")
        _ = store.add(label: "C", target: "/c", id: "c")

        let after = store.reorder(from: 0, to: 2)
        #expect(after.map(\.id) == ["b", "c", "a"])
        #expect(after.map(\.sortOrder) == [0, 1, 2])

        let back = store.reorder(from: 2, to: 0)
        #expect(back.map(\.id) == ["a", "b", "c"])
    }

    @Test("persistence round-trip write then read same slots")
    func persistenceRoundTrip() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slot-dock-rt-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent("slots.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = SlotStore(fileURL: url)
        _ = writer.add(label: "Notes", target: "/Applications/Notes.app", iconPath: "/tmp/n.png", id: "notes")
        _ = writer.add(label: "Docs", target: "https://example.com/docs", id: "docs")
        #expect(writer.save() == true)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let reader = SlotStore(fileURL: url)
        #expect(reader.slots.count == 2)
        #expect(reader.slots[0].id == "notes")
        #expect(reader.slots[0].label == "Notes")
        #expect(reader.slots[0].target == "/Applications/Notes.app")
        #expect(reader.slots[0].iconPath == "/tmp/n.png")
        #expect(reader.slots[1].id == "docs")
        #expect(reader.slots[1].target == "https://example.com/docs")
        #expect(reader.document.version == 2)
    }

    @Test("replaceAll rewrites full ordered list")
    func replaceAllRewrites() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SlotStore(fileURL: url)
        _ = store.add(label: "A", target: "/a", id: "a")
        store.replaceAll([
            Slot(id: "z", label: "Zed", target: "/z", sortOrder: 99),
            Slot(id: "y", label: "Why", target: "/y", sortOrder: 50),
        ])
        #expect(store.slots.map(\.id) == ["z", "y"])
        #expect(store.slots.map(\.sortOrder) == [0, 1])
    }

    @Test("defaultConfigURL is under ~/.config/nicos-slot-dock")
    func defaultConfigURLPath() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let url = SlotStore.defaultConfigURL(home: home)
        #expect(url.path == "/Users/test/.config/nicos-slot-dock/slots.json")
    }

    @Test("empty target is rejected and duplicate ids are made unique")
    func validatesMutations() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SlotStore(fileURL: url)
        _ = store.add(label: "", target: "/Applications/Notes.app", id: "same")
        let duplicate = store.add(label: "Again", target: "/Applications/Other.app", id: "same")
        let invalid = store.add(label: "No target", target: "", id: "invalid")

        #expect(store.slots.count == 2)
        #expect(duplicate?.id != "same")
        #expect(invalid == nil)
        #expect(store.lastError == .invalidSlot("A Nicos Slot Dock target is required."))
    }

    @Test("duplicate targets are rejected for paths and URLs")
    func duplicateTargetsRejected() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SlotStore(fileURL: url)
        #expect(store.add(label: "Docs", target: "https://Example.com/docs", id: "docs") != nil)
        #expect(store.add(label: "Docs again", target: "https://example.com/docs", id: "other") == nil)
        #expect(store.slots.count == 1)

        #expect(store.add(label: "App", target: "/Applications/Notes.app", id: "app") != nil)
        #expect(store.add(label: "App again", target: "/Applications/Notes.app/", id: "app-2") == nil)
        #expect(store.add(label: "File URL duplicate", target: "file:///Applications/Notes.app/", id: "app-3") == nil)
        #expect(store.slots.count == 2)
    }

    @Test("future schema is readable but read-only")
    func futureSchemaIsReadOnly() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let future = SlotDocument(version: ConfigDocumentVersion.current + 1)
        let data = try JSONEncoder().encode(future)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)

        let store = SlotStore(fileURL: url)
        #expect(store.isReadOnly)
        #expect(store.lastError == .futureVersion(ConfigDocumentVersion.current + 1))
        _ = store.add(label: "Ignored", target: "/Applications/Notes.app", id: "ignored")
        #expect(store.slots.isEmpty)
    }

    @Test("corrupt configuration is preserved and not overwritten")
    func corruptConfigFailsClosed() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = Data("not-json".utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: url)

        let store = SlotStore(fileURL: url)
        #expect(store.isReadOnly)
        #expect(store.lastError != nil)
        let preserved = try Data(contentsOf: url)
        #expect(preserved == original)
    }

    @Test("duplicate loaded targets stay preserved and read-only")
    func duplicateLoadedTargetsFailClosed() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = SlotDocument(
            version: ConfigDocumentVersion.current,
            slots: [
                Slot(id: "one", label: "One", target: "/Applications/Notes.app", sortOrder: 0),
                Slot(id: "two", label: "Two", target: "file:///Applications/Notes.app/", sortOrder: 1),
            ]
        )
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = try JSONEncoder().encode(document)
        try original.write(to: url)

        let store = SlotStore(fileURL: url)
        #expect(store.isReadOnly)
        #expect(store.lastError?.localizedDescription.contains("duplicate target") == true)
        #expect(store.slots.count == 2)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test("loaded slots repair identity and whitespace drift")
    func normalizesLoadedSlots() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = SlotDocument(
            version: ConfigDocumentVersion.current,
            slots: [
                Slot(id: "same", label: "  ", target: "  /Applications/Notes.app  ", sortOrder: 40),
                Slot(id: "same", label: "Other", target: "/Applications/Other.app", sortOrder: 2),
            ]
        )
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(document).write(to: url)

        let store = SlotStore(fileURL: url)
        #expect(store.slots.count == 2)
        #expect(Set(store.slots.map(\.id)).count == 2)
        #expect(store.slots[0].label == "Notes")
        #expect(store.slots[0].target == "/Applications/Notes.app")
        #expect(store.slots.map(\.sortOrder) == [0, 1])
    }
}
