import Foundation
import Testing
@testable import SlotDockCore

@Suite("StripCustomReorder")
struct StripCustomReorderTests {
    private func slots(_ labels: [String]) -> [Slot] {
        labels.enumerated().map { i, label in
            Slot(id: "id-\(label)", label: label, target: "/Apps/\(label).app", sortOrder: i)
        }
    }

    @Test("move by index reorders and reindexes sortOrder")
    func moveByIndex() {
        let start = slots(["A", "B", "C", "D"])
        let next = StripCustomReorder.move(customSlots: start, draggedID: "id-A", toIndex: 2)
        #expect(next?.map(\.label) == ["B", "C", "A", "D"])
        #expect(next?.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test("move before id places correctly when dragging forward")
    func moveBeforeForward() {
        let start = slots(["A", "B", "C"])
        let next = StripCustomReorder.move(customSlots: start, draggedID: "id-A", beforeID: "id-C")
        #expect(next?.map(\.label) == ["B", "A", "C"])
    }

    @Test("system origin is not draggable")
    func systemNotDraggable() {
        #expect(StripCustomReorder.isDraggable(origin: .custom) == true)
        #expect(StripCustomReorder.isDraggable(origin: .systemDock) == false)
    }

    @Test("unknown id returns nil")
    func unknown() {
        let start = slots(["A"])
        #expect(StripCustomReorder.move(customSlots: start, draggedID: "missing", toIndex: 0) == nil)
    }
}

@Suite("StripPressSession click-vs-drag")
struct StripPressSessionTests {
    /// Helper: arm Command (required for drag by default).
    private func pressWithCommand(_ s: inout StripPressSession, x: Double = 0, y: Double = 0) {
        s.noteCommandHeld(true)
        #expect(s.handle(.mouseDown(x: x, y: y)) == .none)
    }

    @Test("mouseDown then mouseUp without move is a click, never beginDrag")
    func clickWithoutMove() {
        var s = StripPressSession(dragThreshold: 4)
        pressWithCommand(&s, x: 10, y: 10)
        #expect(s.phase == .pressing)
        // Sub-threshold drag still click
        #expect(s.handle(.mouseDragged(x: 12, y: 11)) == .none)
        #expect(s.phase == .pressing)
        #expect(s.handle(.mouseUp(x: 12, y: 11)) == .click)
        #expect(s.phase == .clicked)
    }

    @Test("Command + movement past threshold begins drag and mouseUp does not click")
    func dragPastThreshold() {
        var s = StripPressSession(dragThreshold: 4)
        pressWithCommand(&s)
        #expect(s.handle(.mouseDragged(x: 10, y: 0)) == .beginDrag)
        #expect(s.phase == .dragging)
        // Further drags are silent
        #expect(s.handle(.mouseDragged(x: 20, y: 0)) == .none)
        #expect(s.handle(.mouseUp(x: 20, y: 0)) == .none)
        #expect(s.phase == .idle)
    }

    @Test("without Command, large move still clicks (no stuck drag)")
    func noCommandNeverDrags() {
        var s = StripPressSession(dragThreshold: 4, allowsDrag: true, requiresCommand: true)
        s.noteCommandHeld(false)
        #expect(s.handle(.mouseDown(x: 0, y: 0)) == .none)
        #expect(s.handle(.mouseDragged(x: 40, y: 0)) == .none)
        #expect(s.phase == .pressing)
        #expect(s.handle(.mouseUp(x: 40, y: 0)) == .click)
    }

    @Test("plain press without noteCommandHeld defaults to no-Command → click")
    func defaultNoCommandIsClick() {
        var s = StripPressSession(dragThreshold: 4)
        // commandHeldAtDown defaults false; requiresCommand defaults true
        #expect(s.handle(.mouseDown(x: 0, y: 0)) == .none)
        #expect(s.handle(.mouseDragged(x: 30, y: 0)) == .none)
        #expect(s.handle(.mouseUp(x: 30, y: 0)) == .click)
    }

    @Test("cancel aborts without click")
    func cancel() {
        var s = StripPressSession()
        pressWithCommand(&s, x: 1, y: 1)
        #expect(s.handle(.cancel) == .none)
        #expect(s.phase == .cancelled)
        #expect(s.handle(.mouseUp(x: 1, y: 1)) == .none)
    }

    @Test("exactly at threshold with Command starts drag")
    func exactThreshold() {
        var s = StripPressSession(dragThreshold: 5)
        pressWithCommand(&s)
        #expect(s.handle(.mouseDragged(x: 5, y: 0)) == .beginDrag)
    }

    @Test("non-draggable press always clicks even after large movement")
    func nonDraggableAlwaysClicks() {
        // System Dock icons: allowsDrag=false — micro-move or large move still launch.
        var s = StripPressSession(dragThreshold: 4, allowsDrag: false)
        s.noteCommandHeld(true) // even with Command, system icons never drag
        #expect(s.handle(.mouseDown(x: 0, y: 0)) == .none)
        #expect(s.phase == .pressing)
        #expect(s.handle(.mouseDragged(x: 50, y: 30)) == .none)
        #expect(s.phase == .pressing) // never enters .dragging
        #expect(s.handle(.mouseUp(x: 50, y: 30)) == .click)
        #expect(s.phase == .clicked)
    }

    @Test("draggable false never returns beginDrag")
    func nonDraggableNoBeginDrag() {
        var s = StripPressSession(dragThreshold: 1, allowsDrag: false)
        s.noteCommandHeld(true)
        _ = s.handle(.mouseDown(x: 0, y: 0))
        for i in 1 ... 20 {
            #expect(s.handle(.mouseDragged(x: Double(i), y: 0)) == .none)
        }
        #expect(s.handle(.mouseUp(x: 20, y: 0)) == .click)
    }

    @Test("requiresCommand false still drags without Command (legacy path)")
    func optionalCommandOff() {
        var s = StripPressSession(dragThreshold: 4, allowsDrag: true, requiresCommand: false)
        #expect(s.handle(.mouseDown(x: 0, y: 0)) == .none)
        #expect(s.handle(.mouseDragged(x: 10, y: 0)) == .beginDrag)
    }
}

@Suite("KeepAsCustomPolicy")
struct KeepAsCustomPolicyTests {
    private func slot(_ label: String, path: String) -> Slot {
        Slot(id: "id-\(label)", label: label, target: path, sortOrder: 0)
    }

    @Test("available when path not in custom list")
    func available() {
        let custom = [slot("Notes", path: "/Apps/Notes.app")]
        let state = KeepAsCustomPolicy.state(
            origin: .systemDock,
            path: "/Apps/Safari.app",
            customSlots: custom
        )
        #expect(state == .available)
        #expect(KeepAsCustomPolicy.customSlotID(matchingPath: "/Apps/Safari.app", customSlots: custom) == nil)
    }

    @Test("kept when path matches custom (normalized)")
    func kept() {
        let custom = [slot("Safari", path: "/Apps/Safari.app/")]
        let state = KeepAsCustomPolicy.state(
            origin: .systemDock,
            path: "/Apps/Safari.app",
            customSlots: custom
        )
        #expect(state == .kept)
        #expect(KeepAsCustomPolicy.customSlotID(matchingPath: "/Apps/Safari.app", customSlots: custom) == "id-Safari")
    }

    @Test("custom origin is unavailable for keep policy")
    func customUnavailable() {
        #expect(
            KeepAsCustomPolicy.state(origin: .custom, path: "/Apps/X.app", customSlots: []) == .unavailable
        )
    }

    @Test("empty path is unavailable")
    func emptyPath() {
        #expect(
            KeepAsCustomPolicy.state(origin: .running, path: "", customSlots: []) == .unavailable
        )
    }

    @Test("import then reverse path id is stable")
    func importThenReverseID() {
        var custom: [Slot] = []
        let path = "/Applications/Calendar.app"
        #expect(KeepAsCustomPolicy.state(origin: .systemDock, path: path, customSlots: custom) == .available)
        custom.append(slot("Calendar", path: path))
        #expect(KeepAsCustomPolicy.state(origin: .systemDock, path: path, customSlots: custom) == .kept)
        if let id = KeepAsCustomPolicy.customSlotID(matchingPath: path, customSlots: custom) {
            custom.removeAll { $0.id == id }
        }
        #expect(KeepAsCustomPolicy.state(origin: .systemDock, path: path, customSlots: custom) == .available)
    }
}

@Suite("AppOpenAtLoginPolicy")
struct AppOpenAtLoginPolicyTests {
    @Test("only .app application kinds are eligible")
    func eligibility() {
        #expect(AppOpenAtLoginPolicy.isEligible(kind: .application, path: "/Applications/Safari.app") == true)
        #expect(AppOpenAtLoginPolicy.isEligible(kind: .application, path: "/Applications/Safari.app/") == true)
        #expect(AppOpenAtLoginPolicy.isEligible(kind: .file, path: "/tmp/a.pdf") == false)
        #expect(AppOpenAtLoginPolicy.isEligible(kind: .url, path: "https://example.com") == false)
        #expect(AppOpenAtLoginPolicy.isEligible(kind: .application, path: "https://x.app") == false)
    }

    @Test("login item path match is normalized")
    func pathMatch() {
        let paths = ["/Applications/Safari.app/", "/System/Applications/Notes.app"]
        #expect(AppOpenAtLoginPolicy.isEnabled(targetPath: "/Applications/Safari.app", loginItemPaths: paths) == true)
        #expect(AppOpenAtLoginPolicy.isEnabled(targetPath: "/Applications/Chrome.app", loginItemPaths: paths) == false)
    }

    @Test("display name strips .app")
    func displayName() {
        #expect(AppOpenAtLoginPolicy.loginItemDisplayName(path: "/Applications/Google Chrome.app") == "Google Chrome")
    }

    @Test("automation denial detection for -1743 / not authorized")
    func automationDenial() {
        #expect(
            AppOpenAtLoginPolicy.isAutomationDenialMessage(
                "ERROR:-1743:Not authorized to send Apple events to System Events."
            )
        )
        #expect(
            AppOpenAtLoginPolicy.isAutomationDenialMessage(
                "Not authorized to send Apple events to System Events."
            )
        )
        #expect(!AppOpenAtLoginPolicy.isAutomationDenialMessage("ERROR:-1728:something else"))
        #expect(!AppOpenAtLoginPolicy.isAutomationDenialMessage("OK"))
    }

    @Test("menu includes open-at-login when eligible")
    func menuIncludesLogin() {
        let model = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Safari",
                origin: .custom,
                kind: .application,
                isRunning: false,
                canOpenNewInstance: true,
                canImportAsCustom: false,
                customIndex: 0,
                customCount: 1,
                openAtLoginEligible: true,
                openAtLoginEnabled: false
            )
        )
        let actions = Set(model.actionableItems.compactMap(\.action))
        #expect(actions.contains(.enableOpenAtLogin))
        #expect(!actions.contains(.disableOpenAtLogin))

        let on = SlotContextMenuBuilder.buildSlotMenu(
            input: SlotContextMenuInput(
                label: "Safari",
                origin: .custom,
                kind: .application,
                isRunning: false,
                canOpenNewInstance: true,
                canImportAsCustom: false,
                customIndex: 0,
                customCount: 1,
                openAtLoginEligible: true,
                openAtLoginEnabled: true
            )
        )
        #expect(on.actionableItems.contains { $0.action == .disableOpenAtLogin })
    }
}
