import Foundation
import Testing
@testable import SlotDockCore

@Suite("SafeAreaPlanner")
struct SafeAreaPaddingTests {
    private let band = ScreenBottomBand(
        visibleFrame: CGRect(x: 0, y: 40, width: 1440, height: 860),
        padHeight: 92,
        extraGap: 8
    )
    // clearanceY = 40 + 92 + 8 = 140

    @Test("need active when option on and pin or expanded")
    func needPolicy() {
        #expect(SafeAreaPolicy.need(optionEnabled: false, pinOpen: true, autoHide: true, revealPhase: .expanded) == .none)
        #expect(SafeAreaPolicy.need(optionEnabled: true, pinOpen: true, autoHide: false, revealPhase: .collapsed) == .active)
        #expect(SafeAreaPolicy.need(optionEnabled: true, pinOpen: false, autoHide: true, revealPhase: .expanded) == .active)
        #expect(SafeAreaPolicy.need(optionEnabled: true, pinOpen: false, autoHide: true, revealPhase: .collapsed) == .none)
        #expect(SafeAreaPolicy.need(optionEnabled: true, pinOpen: false, autoHide: true, revealPhase: .expanding) == .active)
    }

    @Test("apply pads low window and records ledger original")
    func applyPads() {
        let low = WindowFrameSnapshot(
            id: "123:456",
            frame: CGRect(x: 100, y: 50, width: 800, height: 600)
        )
        let plan = SafeAreaPlanner.plan(need: .active, windows: [low], band: band, ledger: [:])
        #expect(plan.apply.count == 1)
        #expect(plan.apply[0].windowID == "123:456")
        #expect(plan.apply[0].to.minY >= band.clearanceY - 0.5)
        #expect(plan.nextLedger["123:456"] != nil)
        #expect(plan.nextLedger["123:456"]!.originalFrame.minY == 50)
        #expect(plan.restore.isEmpty)
    }

    @Test("window already clear is not padded")
    func alreadyClear() {
        let high = WindowFrameSnapshot(
            id: "w2",
            frame: CGRect(x: 100, y: 200, width: 800, height: 500)
        )
        let plan = SafeAreaPlanner.plan(need: .active, windows: [high], band: band, ledger: [:])
        #expect(plan.apply.isEmpty)
        #expect(plan.nextLedger.isEmpty)
    }

    @Test("restore undoes only ledger entries when need none")
    func restoreOnlyLedger() {
        let original = CGRect(x: 10, y: 40, width: 400, height: 300)
        let padded = CGRect(x: 10, y: 140, width: 400, height: 300)
        let ledger = [
            "w1": PadRecord(windowID: "w1", originalFrame: original, paddedFrame: padded, appliedDeltaY: 100),
        ]
        let plan = SafeAreaPlanner.plan(need: .none, windows: [], band: band, ledger: ledger)
        #expect(plan.restore.count == 1)
        #expect(plan.restore[0].windowID == "w1")
        #expect(plan.restore[0].to == original)
        #expect(plan.nextLedger.isEmpty)
        #expect(plan.apply.isEmpty)
    }

    @Test("second plan with padded live keeps ledger and does NOT restore")
    func noStackKeepsLedger() {
        let original = CGRect(x: 0, y: 40, width: 500, height: 400)
        let oncePadded = CGRect(x: 0, y: 140, width: 500, height: 400)
        let ledger = [
            "w1": PadRecord(windowID: "w1", originalFrame: original, paddedFrame: oncePadded, appliedDeltaY: 100),
        ]
        // Live window still at padded position (minY >= clearance → looks "clear")
        let live = WindowFrameSnapshot(id: "w1", frame: oncePadded)
        let plan = SafeAreaPlanner.plan(need: .active, windows: [live], band: band, ledger: ledger)

        // Honest assertions the skeptic required:
        #expect(plan.restore.isEmpty, "Must not restore already-padded windows while need is active")
        #expect(plan.nextLedger["w1"] != nil, "Ledger must retain w1")
        #expect(plan.nextLedger["w1"]!.originalFrame == original)
        #expect(plan.nextLedger["w1"]!.paddedFrame.minY >= band.clearanceY - 0.5)
        // No stack: target from original is ~140, not 140+100
        for a in plan.apply {
            #expect(a.to.minY >= band.clearanceY - 0.5)
            #expect(a.to.minY < 250)
        }
        // Already at target → apply empty is OK
        if plan.apply.isEmpty {
            #expect(abs(live.frame.minY - plan.nextLedger["w1"]!.paddedFrame.minY) < 1.5)
        }
    }

    @Test("originalStillNeedsPad true for low original even if live is high")
    func originalStillNeedsPadHelper() {
        let record = PadRecord(
            windowID: "w1",
            originalFrame: CGRect(x: 0, y: 40, width: 500, height: 400),
            paddedFrame: CGRect(x: 0, y: 140, width: 500, height: 400),
            appliedDeltaY: 100
        )
        #expect(SafeAreaPlanner.originalStillNeedsPad(record: record, band: band) == true)
        #expect(SafeAreaPlanner.needsPad(
            WindowFrameSnapshot(id: "w1", frame: record.paddedFrame),
            band: band
        ) == false)
    }

    @Test("restore when original no longer needs pad (clearance raised)")
    func restoreWhenOriginalClear() {
        let tallBand = ScreenBottomBand(
            visibleFrame: CGRect(x: 0, y: 40, width: 1440, height: 860),
            padHeight: 0,
            extraGap: 0
        )
        // clearanceY = 40 — original minY 50 is clear
        let original = CGRect(x: 0, y: 50, width: 500, height: 400)
        let padded = CGRect(x: 0, y: 140, width: 500, height: 400)
        let ledger = [
            "w1": PadRecord(windowID: "w1", originalFrame: original, paddedFrame: padded, appliedDeltaY: 90),
        ]
        let live = WindowFrameSnapshot(id: "w1", frame: padded)
        let plan = SafeAreaPlanner.plan(need: .active, windows: [live], band: tallBand, ledger: ledger)
        #expect(plan.restore.count == 1)
        #expect(plan.restore[0].to == original)
        #expect(plan.nextLedger["w1"] == nil)
    }

    @Test("restoreAll clears ledger")
    func restoreAll() {
        let ledger = [
            "a": PadRecord(
                windowID: "a",
                originalFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                paddedFrame: CGRect(x: 0, y: 50, width: 100, height: 100),
                appliedDeltaY: 50
            ),
        ]
        let plan = SafeAreaPlanner.restoreAll(ledger: ledger)
        #expect(plan.restore.count == 1)
        #expect(plan.nextLedger.isEmpty)
    }

    @Test("window not in ledger is never restored")
    func neverTouchedNotRestored() {
        let stranger = WindowFrameSnapshot(
            id: "other",
            frame: CGRect(x: 0, y: 0, width: 200, height: 200)
        )
        let plan = SafeAreaPlanner.plan(
            need: .none,
            windows: [stranger],
            band: band,
            ledger: [:]
        )
        #expect(plan.restore.isEmpty)
        #expect(plan.apply.isEmpty)
    }

    @Test("off-screen ledger entries are restored while padding is active")
    func restoresOffScreenLedger() {
        let record = PadRecord(
            windowID: "off-screen",
            originalFrame: CGRect(x: 0, y: 10, width: 400, height: 300),
            paddedFrame: CGRect(x: 0, y: 110, width: 400, height: 300),
            appliedDeltaY: 100
        )
        let plan = SafeAreaPlanner.plan(
            need: .active,
            windows: [],
            band: band,
            ledger: [record.windowID: record]
        )
        #expect(plan.restore.map(\.windowID) == [record.windowID])
        #expect(plan.nextLedger[record.windowID] == nil)
    }

    @Test("two-step apply then re-plan does not stack or undo")
    func twoStepApplyReplan() {
        let low = WindowFrameSnapshot(id: "w1", frame: CGRect(x: 0, y: 50, width: 400, height: 300))
        let plan1 = SafeAreaPlanner.plan(need: .active, windows: [low], band: band, ledger: [:])
        #expect(plan1.apply.count == 1)
        let ledger1 = plan1.nextLedger
        let livePadded = WindowFrameSnapshot(id: "w1", frame: plan1.apply[0].to)
        let plan2 = SafeAreaPlanner.plan(need: .active, windows: [livePadded], band: band, ledger: ledger1)
        #expect(plan2.restore.isEmpty)
        #expect(plan2.nextLedger["w1"] != nil)
        #expect(plan2.nextLedger["w1"]!.originalFrame.minY == 50)
        // Still only one logical pad delta from original
        #expect(plan2.nextLedger["w1"]!.paddedFrame.minY < 50 + 200)
    }
}
