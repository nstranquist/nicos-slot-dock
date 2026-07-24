import Foundation
import Testing
@testable import SlotDockCore

@Suite("ScreenGeometry")
struct ScreenGeometryTests {
    private let screenA = ScreenGeometry.ScreenBox(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 40, width: 1440, height: 830)
    )
    private let screenB = ScreenGeometry.ScreenBox(
        frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1440, y: 50, width: 1920, height: 1000)
    )

    @Test("picks screen containing pointer")
    func containing() {
        let screens = [screenA, screenB]
        #expect(ScreenGeometry.screenIndex(containing: CGPoint(x: 100, y: 100), screens: screens) == 0)
        #expect(ScreenGeometry.screenIndex(containing: CGPoint(x: 1600, y: 200), screens: screens) == 1)
    }

    @Test("stripFrame centers on visible rect")
    func stripCenter() {
        let f = ScreenGeometry.stripFrame(
            visible: screenA.visibleFrame,
            height: 80,
            width: 400,
            alignment: .center,
            horizontalMargin: 24,
            bottomInset: 10
        )
        #expect(abs(f.midX - screenA.visibleFrame.midX) < 1)
        #expect(abs(f.minY - (screenA.visibleFrame.minY + 10)) < 0.5)
        #expect(f.size.height == 80)
    }

    @Test("stripFrame trailing alignment")
    func stripTrailing() {
        let f = ScreenGeometry.stripFrame(
            visible: screenB.visibleFrame,
            height: 64,
            width: 300,
            alignment: .trailing,
            horizontalMargin: 20,
            bottomInset: 8
        )
        #expect(abs(f.maxX - (screenB.visibleFrame.maxX - 20)) < 1)
    }

    @Test("near bottom edge hit test")
    func nearBottom() {
        let v = screenA.visibleFrame
        let near = CGPoint(x: v.midX, y: v.minY + 10)
        let far = CGPoint(x: v.midX, y: v.minY + 100)
        #expect(ScreenGeometry.isNearBottomEdge(
            point: near, visible: v, threshold: 28, stripMidX: v.midX, stripHalfWidth: 200
        ))
        #expect(!ScreenGeometry.isNearBottomEdge(
            point: far, visible: v, threshold: 28, stripMidX: v.midX, stripHalfWidth: 200
        ))
    }

    @Test("edge hit half-width overshoot changes lateral acceptance")
    func overshootLateralBand() {
        let v = screenA.visibleFrame
        let stripMid = v.midX
        let stripWidth: CGFloat = 400
        let defaultHalf = DockPreferences.edgeHitHalfWidth(stripWidth: stripWidth, overshoot: 48)
        let tightHalf = DockPreferences.edgeHitHalfWidth(stripWidth: stripWidth, overshoot: 0)
        // Point just outside tight half but inside default overshoot.
        let x = stripMid + tightHalf + 20
        let p = CGPoint(x: x, y: v.minY + 10)
        #expect(!ScreenGeometry.isNearBottomEdge(
            point: p, visible: v, threshold: 28, stripMidX: stripMid, stripHalfWidth: tightHalf
        ))
        #expect(ScreenGeometry.isNearBottomEdge(
            point: p, visible: v, threshold: 28, stripMidX: stripMid, stripHalfWidth: defaultHalf
        ))
        #expect(defaultHalf == stripWidth / 2 + 48)
        #expect(tightHalf == stripWidth / 2)
    }

    @Test("non-default edge trigger threshold changes hit band")
    func nonDefaultThreshold() {
        let v = screenA.visibleFrame
        // 40 pt above minY: outside default 28, inside taller 48.
        let midBand = CGPoint(x: v.midX, y: v.minY + 40)
        #expect(!ScreenGeometry.isNearBottomEdge(
            point: midBand, visible: v, threshold: 28, stripMidX: v.midX, stripHalfWidth: 200
        ))
        #expect(ScreenGeometry.isNearBottomEdge(
            point: midBand, visible: v, threshold: 48, stripMidX: v.midX, stripHalfWidth: 200
        ))
        // Still outside even the tall threshold.
        let aboveTall = CGPoint(x: v.midX, y: v.minY + 60)
        #expect(!ScreenGeometry.isNearBottomEdge(
            point: aboveTall, visible: v, threshold: 48, stripMidX: v.midX, stripHalfWidth: 200
        ))
        // Preference clamp feeds geometry: use real clamp + default constants.
        let clamped = DockPreferences.clampEdgeTriggerHeight(48)
        #expect(clamped == 48)
        #expect(ScreenGeometry.isNearBottomEdge(
            point: midBand, visible: v, threshold: CGFloat(clamped), stripMidX: v.midX, stripHalfWidth: 200
        ))
        let tiny = DockPreferences.clampEdgeTriggerHeight(1)
        #expect(tiny == 1)
        #expect(tiny == DockPreferences.minEdgeTriggerHeight)
        // At threshold=1: y <= minY+1 is inside; y = minY+2 is outside.
        let justInsideTiny = CGPoint(x: v.midX, y: v.minY + 1)
        let justOutsideTiny = CGPoint(x: v.midX, y: v.minY + 2)
        #expect(ScreenGeometry.isNearBottomEdge(
            point: justInsideTiny, visible: v, threshold: CGFloat(tiny), stripMidX: v.midX, stripHalfWidth: 200
        ))
        #expect(!ScreenGeometry.isNearBottomEdge(
            point: justOutsideTiny, visible: v, threshold: CGFloat(tiny), stripMidX: v.midX, stripHalfWidth: 200
        ))
    }
}
