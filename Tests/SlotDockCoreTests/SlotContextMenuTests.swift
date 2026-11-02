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
        #expect(actions.contains(.showAllWindows))
        #expect(actions.contains(.hideOthers))
        #expect(actions.contains(.relaunchApplication))
        #expect(actions.contains(.getInfo))
        #expect(!actions.contains(.copyBundleIdentifier))
        #expect(!actions.contains(.unhideApplication))

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

    @Test("composed trash menu opens, empties, and can hide")
    func trashTile() {
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Trash",
                origin: .trash,
                kind: .file,
                isRunning: false,
                canOpenNewInstance: false,
                canImportAsCustom: false,
                customIndex: nil,
                customCount: 0,
                isTrashSlot: true,
                trashIsEmpty: false
            )
        )
        let actions = Set(model.actionableItems.compactMap(\.action))
        #expect(actions.contains(.open))
        #expect(actions.contains(.emptyTrash))
        #expect(actions.contains(.hideTrash))
        #expect(actions.contains(.showInFinder))
        #expect(actions.contains(.getInfo))
        #expect(!actions.contains(.openNewInstance))
        #expect(!actions.contains(.importAsCustomSlot))
        #expect(!actions.contains(.removeFromSlotDock))
        #expect(!actions.contains(.quitApplication))
        let empty = model.actionableItems.first { $0.action == .emptyTrash }
        #expect(empty?.enabled == true)
        #expect(empty?.isDestructive == true)
    }

    @Test("empty trash disables Empty Trash")
    func trashEmptyDisablesEmpty() {
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Trash",
                origin: .trash,
                kind: .file,
                isRunning: false,
                canOpenNewInstance: false,
                canImportAsCustom: false,
                customIndex: nil,
                customCount: 0,
                isTrashSlot: true,
                trashIsEmpty: true
            )
        )
        let empty = model.actionableItems.first { $0.action == .emptyTrash }
        #expect(empty?.enabled == false)
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

    @Test("window raise matcher prefers number then title")
    func windowRaiseMatcher() {
        let candidates: [(windowNumber: Int?, title: String)] = [
            (11, "One"),
            (22, "Two"),
        ]
        #expect(SlotContextMenuBuilder.WindowRaiseMatcher.pickIndex(
            candidates: candidates,
            targetNumber: 22,
            targetTitle: "One"
        ) == 1)
        #expect(SlotContextMenuBuilder.WindowRaiseMatcher.pickIndex(
            candidates: candidates,
            targetNumber: nil,
            targetTitle: "One"
        ) == 0)
        #expect(SlotContextMenuBuilder.WindowRaiseMatcher.pickIndex(
            candidates: [],
            targetNumber: 1,
            targetTitle: "X"
        ) == nil)
    }

    @Test("two instance rows are distinct actionable targets")
    func instanceRowsAreTargetable() {
        let first = SlotInstanceRef(processID: 11, title: "Editor — 1")
        let second = SlotInstanceRef(processID: 22, windowNumber: 7, title: "Editor — 2")
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Editor",
                origin: .custom,
                kind: .application,
                isRunning: true,
                canOpenNewInstance: true,
                canImportAsCustom: false,
                customIndex: 0,
                customCount: 1,
                instances: [first, second]
            )
        )
        let activate = model.actionableItems.filter { $0.action == .activateInstance }
        #expect(activate.count == 2)
        #expect(activate.contains { $0.instance?.processID == 11 })
        #expect(activate.contains { $0.instance?.processID == 22 && $0.instance?.windowNumber == 7 })
        #expect(model.actionableItems.contains { $0.action == .hideInstance && $0.instance?.processID == 11 })
        #expect(model.actionableItems.contains { $0.action == .quitInstance && $0.instance?.processID == 22 })
        #expect(model.actionableItems.contains { $0.action == .hideApplication })
        #expect(model.actionableItems.contains { $0.action == .quitApplication })
    }

    @Test("canOpenNewInstance only for .app applications")
    func newInstanceGate() {
        #expect(SlotContextMenuBuilder.canOpenNewInstance(kind: .application, path: "/Apps/X.app") == true)
        #expect(SlotContextMenuBuilder.canOpenNewInstance(kind: .application, path: "/Apps/X.APP") == true)
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
        #expect(actions.contains(.getInfo))
        #expect(!actions.contains(.showAllWindows))
        #expect(!actions.contains(.relaunchApplication))
        #expect(!actions.contains(.hideOthers))
    }

    @Test("hidden running app offers Show instead of Hide")
    func hiddenShowsUnhide() {
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Notes",
                origin: .custom,
                kind: .application,
                isRunning: true,
                canOpenNewInstance: true,
                canImportAsCustom: false,
                customIndex: 0,
                customCount: 1,
                isHidden: true
            )
        )
        let actions = Set(model.actionableItems.compactMap(\.action))
        #expect(actions.contains(.unhideApplication))
        #expect(!actions.contains(.hideApplication))
        #expect(actions.contains(.showAllWindows))
    }

    @Test("copy bundle id only when identifier is present")
    func copyBundleWhenKnown() {
        let withID = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Safari",
                origin: .systemDock,
                kind: .application,
                isRunning: false,
                canOpenNewInstance: true,
                canImportAsCustom: true,
                customIndex: nil,
                customCount: 0,
                bundleIdentifier: "com.apple.Safari"
            )
        )
        #expect(withID.actionableItems.contains { $0.action == .copyBundleIdentifier })

        let withoutID = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Safari",
                origin: .systemDock,
                kind: .application,
                isRunning: false,
                canOpenNewInstance: true,
                canImportAsCustom: true,
                customIndex: nil,
                customCount: 0,
                bundleIdentifier: "  "
            )
        )
        #expect(!withoutID.actionableItems.contains { $0.action == .copyBundleIdentifier })
    }

    @Test("self application omits relaunch")
    func selfOmitsRelaunch() {
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Nicos Slot Dock",
                origin: .custom,
                kind: .application,
                isRunning: true,
                canOpenNewInstance: true,
                canImportAsCustom: false,
                customIndex: 0,
                customCount: 1,
                isSelfApplication: true
            )
        )
        let actions = Set(model.actionableItems.compactMap(\.action))
        #expect(!actions.contains(.relaunchApplication))
        #expect(actions.contains(.quitApplication))
        #expect(actions.contains(.showAllWindows))
    }

    @Test("url slot has no get info")
    func urlHasNoGetInfo() {
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Docs",
                origin: .custom,
                kind: .url,
                isRunning: false,
                canOpenNewInstance: false,
                canImportAsCustom: false,
                customIndex: 0,
                customCount: 1
            )
        )
        let actions = Set(model.actionableItems.compactMap(\.action))
        #expect(!actions.contains(.getInfo))
        #expect(!actions.contains(.showAllWindows))
        let finder = model.actionableItems.first { $0.action == .showInFinder }
        #expect(finder?.enabled == false)
    }

    @Test("running custom app menu has a stable outline")
    func runningCustomOutline() {
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Notes",
                origin: .custom,
                kind: .application,
                isRunning: true,
                canOpenNewInstance: true,
                canImportAsCustom: false,
                customIndex: 1,
                customCount: 3,
                bundleIdentifier: "com.apple.Notes"
            )
        )
        #expect(model.titleOutline == [
            "Open",
            "Open New Instance",
            "---",
            "Show in Finder",
            "Get Info",
            "Copy Path",
            "Copy Name",
            "Copy Bundle ID",
            "---",
            "Options/",
            "  Remove from Nicos Slot Dock",
            "  Edit Slot…",
            "  Move Left",
            "  Move Right",
            "---",
            "Show All Windows",
            "Hide",
            "Hide Others",
            "---",
            "Relaunch",
            "Quit",
            "Force Quit",
            "---",
            "Edit Slots…",
        ])
    }

    @Test("app menu policy gates")
    func appMenuPolicy() {
        #expect(SlotAppMenuPolicy.canGetInfo(kind: .application))
        #expect(SlotAppMenuPolicy.canGetInfo(kind: .file))
        #expect(!SlotAppMenuPolicy.canGetInfo(kind: .url))
        #expect(SlotAppMenuPolicy.canShowAllWindows(kind: .application, isRunning: true))
        #expect(!SlotAppMenuPolicy.canShowAllWindows(kind: .application, isRunning: false))
        #expect(!SlotAppMenuPolicy.canRelaunch(kind: .application, isRunning: true, isSelf: true))
        #expect(SlotAppMenuPolicy.canRelaunch(kind: .application, isRunning: true, isSelf: false))
        #expect(SlotAppMenuPolicy.isSelfApplication(bundleIdentifier: "com.nstranquist.nicos-slot-dock"))
        #expect(!SlotAppMenuPolicy.isSelfApplication(bundleIdentifier: "com.apple.Safari"))
        #expect(!SlotAppMenuPolicy.canCopyBundleIdentifier(nil))
        #expect(!SlotAppMenuPolicy.canCopyBundleIdentifier(" "))
        #expect(SlotAppMenuPolicy.canCopyBundleIdentifier("com.apple.Safari"))
    }
}
