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

        #expect(a.id == "slot-a")
        #expect(b.id == "slot-b")
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
}
