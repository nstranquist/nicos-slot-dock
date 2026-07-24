import Foundation
import Testing
@testable import SlotDockCore

@Suite("SlotContextMenuBuilder")
struct SlotContextMenuTests {
    @Test("custom slot menu has open, finder, remove, reorder")
    func customRunning() {
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Notes",
                origin: .custom,
                kind: .application,
                isRunning: true,
                canOpenNewInstance: true,
                canImportAsCustom: false,
                customIndex: 1,
                customCount: 3
            )
        )
        let actions = Set(model.actionableItems.compactMap(\.action))
        #expect(actions.contains(.open))
        #expect(actions.contains(.openNewInstance))
        #expect(actions.contains(.showInFinder))
        #expect(actions.contains(.copyPath))
        #expect(actions.contains(.removeFromSlotDock))
        #expect(actions.contains(.editSlot))
        #expect(actions.contains(.moveLeft))
        #expect(actions.contains(.moveRight))
        #expect(actions.contains(.quitApplication))
        #expect(actions.contains(.forceQuitApplication))
        #expect(actions.contains(.hideApplication))

        let moveLeft = model.actionableItems.first { $0.action == .moveLeft }
        let moveRight = model.actionableItems.first { $0.action == .moveRight }
        #expect(moveLeft?.enabled == true)
        #expect(moveRight?.enabled == true)
    }

    @Test("system dock item offers import not remove; edges disable move")
    func systemItem() {
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Safari",
                origin: .systemDock,
                kind: .application,
                isRunning: false,
                canOpenNewInstance: true,
                canImportAsCustom: true,
                isKeptAsCustom: false,
                customIndex: nil,
                customCount: 0
            )
        )
        let actions = Set(model.actionableItems.compactMap(\.action))
        #expect(actions.contains(.importAsCustomSlot))
        #expect(!actions.contains(.unkeepCustomSlot))
        #expect(!actions.contains(.removeFromSlotDock))
        #expect(!actions.contains(.quitApplication))
        #expect(actions.contains(.openNewInstance))
        let keep = model.actionableItems.first { $0.action == .importAsCustomSlot }
        #expect(keep?.enabled == true)
        #expect(keep?.isOn == false)
        #expect(keep?.title == "Keep as Custom Slot")
    }

    @Test("system item already kept offers reverse Keep toggle (on, enabled)")
    func systemItemKeptToggle() {
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Safari",
                origin: .systemDock,
                kind: .application,
                isRunning: false,
                canOpenNewInstance: true,
                canImportAsCustom: false,
                isKeptAsCustom: true,
                customIndex: nil,
                customCount: 1
            )
        )
        let actions = Set(model.actionableItems.compactMap(\.action))
        #expect(actions.contains(.unkeepCustomSlot))
        #expect(!actions.contains(.importAsCustomSlot))
        let unkeep = model.actionableItems.first { $0.action == .unkeepCustomSlot }
        #expect(unkeep?.enabled == true)
        #expect(unkeep?.isOn == true)
        #expect(unkeep?.title == "Keep as Custom Slot")
    }

    @Test("running origin can offer Keep when importable")
    func runningImport() {
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Preview",
                origin: .running,
                kind: .application,
                isRunning: true,
                canOpenNewInstance: true,
                canImportAsCustom: true,
                isKeptAsCustom: false,
                customIndex: nil,
                customCount: 0
            )
        )
        #expect(model.actionableItems.contains { $0.action == .importAsCustomSlot })
    }

    @Test("first custom slot cannot move left")
    func firstCannotMoveLeft() {
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "A",
                origin: .custom,
                kind: .file,
                isRunning: false,
                canOpenNewInstance: false,
                canImportAsCustom: false,
                customIndex: 0,
                customCount: 2
            )
        )
        let moveLeft = model.actionableItems.first { $0.action == .moveLeft }
        #expect(moveLeft?.enabled == false)
        #expect(!model.actionableItems.contains { $0.action == .openNewInstance })
    }

    @Test("chrome menu exposes pin and refresh")
    func chrome() {
        let model = SlotContextMenuBuilder.buildChromeMenu(
            isPinned: false,
            isRevealed: true,
            systemDockCount: 4
        )
        let actions = Set(model.actionableItems.compactMap(\.action))
        #expect(actions.contains(.pinOpen))
        #expect(actions.contains(.hideStrip))
        #expect(actions.contains(.refreshSystemDock))
        #expect(actions.contains(.openSlotsSettings))
        #expect(model.items.contains { $0.title.contains("4") })
    }

    @Test("canOpenNewInstance only for .app applications")
    func newInstanceGate() {
        #expect(SlotContextMenuBuilder.canOpenNewInstance(kind: .application, path: "/Apps/X.app") == true)
        #expect(SlotContextMenuBuilder.canOpenNewInstance(kind: .file, path: "/tmp/a.pdf") == false)
        #expect(SlotContextMenuBuilder.canOpenNewInstance(kind: .url, path: "https://x") == false)
    }

    @Test("open at login omitted when not eligible")
    func noLoginWhenIneligible() {
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Note",
                origin: .custom,
                kind: .file,
                isRunning: false,
                canOpenNewInstance: false,
                canImportAsCustom: false,
                customIndex: 0,
                customCount: 1,
                openAtLoginEligible: false,
                openAtLoginEnabled: nil
            )
        )
        let actions = Set(model.actionableItems.compactMap(\.action))
        #expect(!actions.contains(.enableOpenAtLogin))
        #expect(!actions.contains(.disableOpenAtLogin))
    }
}
