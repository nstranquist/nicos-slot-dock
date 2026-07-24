import Foundation
import Testing
@testable import SlotDockCore

@Suite("DockPreferences")
struct DockPreferencesTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("slot-dock-prefs-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("slots.json")
    }

    @Test("default preferences are sensible")
    func defaults() {
        let p = DockPreferences.default
        #expect(p.iconSize == .medium)
        #expect(p.autoHide == true)
        #expect(p.pinOpen == false)
        #expect(p.edgeHover == true)
        #expect(p.edgeTriggerHeight == DockPreferences.defaultEdgeTriggerHeight)
        #expect(p.edgeTriggerHeight == 28)
        #expect(p.edgeHorizontalOvershoot == 48)
        #expect(p.edgeHorizontalOvershoot == DockPreferences.defaultEdgeHorizontalOvershoot)
        #expect(p.autoHideLeaveMargin == 8)
        #expect(p.autoHideLeaveMargin == DockPreferences.defaultAutoHideLeaveMargin)
        #expect(p.revealBaseDuration == 0.22)
        #expect(p.revealBaseDuration == DockPreferences.defaultRevealBaseDuration)
        #expect(p.iconSpacing == 8)
        #expect(p.iconSpacing == DockPreferences.defaultIconSpacing)
        #expect(p.effectiveIconSpacing() == 8)
        #expect(p.showLabels == false)
        #expect(p.alignment == .center)
        #expect(p.iconSize.pointSize == 44)
        #expect(DockPreferences.IconSize.small.pointSize == 36)
        #expect(DockPreferences.IconSize.large.pointSize == 52)
        #expect(p.showStatusItem == true)
        #expect(p.launchAtLogin == false)
        #expect(p.hotkeys.globalEnabled == false)
        #expect(p.hotkeys.toggleDock.enabled == false)
        #expect(KeyBinding.unbound.displayString == "Off")
        #expect(KeyBinding(keyEquivalent: "d", command: true, enabled: true).displayString == "⌘D")
    }

    @Test("clamp edge overshoot, reveal duration, icon spacing")
    func clampHitFeelPrefs() {
        #expect(DockPreferences.clampEdgeHorizontalOvershoot(48) == 48)
        #expect(DockPreferences.clampEdgeHorizontalOvershoot(-5) == 0)
        #expect(DockPreferences.clampEdgeHorizontalOvershoot(999) == DockPreferences.maxEdgeHorizontalOvershoot)
        #expect(DockPreferences.clampRevealBaseDuration(0.22) == 0.22)
        #expect(DockPreferences.clampRevealBaseDuration(0) == 0)
        #expect(DockPreferences.clampRevealBaseDuration(-1) == 0)
        #expect(DockPreferences.clampRevealBaseDuration(5) == DockPreferences.maxRevealBaseDuration)
        #expect(DockPreferences.clampIconSpacing(8) == 8)
        #expect(DockPreferences.clampIconSpacing(0) == 0)
        #expect(DockPreferences.clampIconSpacing(-3) == 0)
        #expect(DockPreferences.clampIconSpacing(100) == DockPreferences.maxIconSpacing)
    }

    @Test("edgeHitHalfWidth and stripIconsWidth use real clamp helpers")
    func pureLayoutHelpers() {
        // Prior path: stripWidth/2 + 48 — compare as Double (CGFloat vs Int fails Testing equality).
        #expect(Double(DockPreferences.edgeHitHalfWidth(stripWidth: 400, overshoot: 48)) == 248)
        #expect(Double(DockPreferences.edgeHitHalfWidth(stripWidth: 400, overshoot: 0)) == 200)
        #expect(
            Double(DockPreferences.edgeHitHalfWidth(stripWidth: 400, overshoot: 999))
                == 200 + DockPreferences.maxEdgeHorizontalOvershoot
        )
        // Non-default overshoot changes lateral band.
        #expect(Double(DockPreferences.edgeHitHalfWidth(stripWidth: 300, overshoot: 80)) == 230)

        #expect(Double(DockPreferences.stripIconsWidth(count: 5, iconSize: 44, spacing: 8)) == 260)
        #expect(Double(DockPreferences.stripIconsWidth(count: 0, iconSize: 44, spacing: 8)) == 52)

        var labeled = DockPreferences.default
        labeled.showLabels = true
        #expect(Double(labeled.effectiveIconSpacing()) == 10) // 8 + 2
        labeled.iconSpacing = 12
        #expect(Double(labeled.effectiveIconSpacing()) == 14)
        labeled.showLabels = false
        #expect(Double(labeled.effectiveIconSpacing()) == 12)
    }

    @Test("autoHideLeaveMargin expands hover frame and arms leave only outside")
    func leaveMarginHoverZone() {
        #expect(DockPreferences.clampAutoHideLeaveMargin(-3) == 0)
        #expect(DockPreferences.clampAutoHideLeaveMargin(8) == 8)
        #expect(DockPreferences.clampAutoHideLeaveMargin(2) == 2)
        #expect(DockPreferences.clampAutoHideLeaveMargin(999) == DockPreferences.maxAutoHideLeaveMargin)

        let frame = CGRect(x: 100, y: 40, width: 400, height: 80)
        // 12 pt above the strip top (frame.maxY = 120) → inside margin 20, outside margin 8 / 2.
        let above = CGPoint(x: 300, y: 120 + 12)
        #expect(DockPreferences.isPointerOverStrip(point: above, windowFrame: frame, leaveMargin: 20))
        #expect(!DockPreferences.isPointerOverStrip(point: above, windowFrame: frame, leaveMargin: 8))
        #expect(!DockPreferences.isPointerOverStrip(point: above, windowFrame: frame, leaveMargin: 2))
        // CoreGraphics CGRect.contains treats maxX/maxY as exclusive, so y == maxY+margin is out.
        // 1 pt above strip is inside margin 2; 2 pt above is on the expanded max edge → outside.
        let justInside2 = CGPoint(x: 300, y: 120 + 1)
        let justOutside2 = CGPoint(x: 300, y: 120 + 2)
        #expect(DockPreferences.isPointerOverStrip(point: justInside2, windowFrame: frame, leaveMargin: 2))
        #expect(!DockPreferences.isPointerOverStrip(point: justOutside2, windowFrame: frame, leaveMargin: 2))
        #expect(DockPreferences.isPointerOverStrip(point: justOutside2, windowFrame: frame, leaveMargin: 8))
        // Exact frame edge stays over at margin 0.
        #expect(DockPreferences.isPointerOverStrip(point: CGPoint(x: 100, y: 40), windowFrame: frame, leaveMargin: 0))
        #expect(!DockPreferences.isPointerOverStrip(point: CGPoint(x: 99, y: 40), windowFrame: frame, leaveMargin: 0))

        let expanded = DockPreferences.pointerOverStripFrame(windowFrame: frame, leaveMargin: 8)
        #expect(Double(expanded.minX) == 92)
        #expect(Double(expanded.maxY) == 128)
        let tight = DockPreferences.pointerOverStripFrame(windowFrame: frame, leaveMargin: 2)
        #expect(Double(tight.maxY) == 122)

        // Missing field decodes as prior 8 pt.
        let decoded = try! JSONDecoder().decode(DockPreferences.self, from: Data(#"{"autoHide":true}"#.utf8))
        #expect(decoded.autoHideLeaveMargin == 8)

        // End-to-end policy: expanded + 3pt above strip with margin 2 → leave (do not hold).
        let above3 = CGPoint(x: 300, y: 123)
        let over2 = DockPreferences.isPointerOverStrip(point: above3, windowFrame: frame, leaveMargin: 2)
        let over8 = DockPreferences.isPointerOverStrip(point: above3, windowFrame: frame, leaveMargin: 8)
        #expect(!over2)
        #expect(over8)
        #expect(
            !AutoHideCollapsePolicy.shouldHoldStripOpen(
                overStrip: over2,
                nearBottomEdge: true, // even if still in bottom edge band…
                edgeHoverEnabled: true,
                phase: .expanded
            )
        )
        #expect(
            AutoHideCollapsePolicy.shouldHoldStripOpen(
                overStrip: over8,
                nearBottomEdge: true,
                edgeHoverEnabled: true,
                phase: .expanded
            )
        )
    }

    @Test("leave margin uses content bar not window Spacer dead zone")
    func leaveMarginContentVsWindowSpacer() {
        // Window is taller than content (DockChrome top Spacer ≈ expandedChromeExtra).
        let window = CGRect(x: 0, y: 40, width: 400, height: 120) // maxY = 160
        let contentH: CGFloat = 92 // maxY content = 132
        // 10 pt above visual content (y=142): outside content+margin2, still inside full window+margin2.
        let aboveContent = CGPoint(x: 200, y: 132 + 10)
        #expect(
            DockPreferences.isPointerOverStrip(
                point: aboveContent, windowFrame: window, leaveMargin: 2, contentHeight: contentH
            ) == false
        )
        // Full-window test would incorrectly still hold (window maxY 160 + 2).
        #expect(
            DockPreferences.isPointerOverStrip(
                point: aboveContent, windowFrame: window, leaveMargin: 2, contentHeight: nil
            ) == true
        )
        // Content + margin 20 holds the same point.
        #expect(
            DockPreferences.isPointerOverStrip(
                point: aboveContent, windowFrame: window, leaveMargin: 20, contentHeight: contentH
            ) == true
        )
        // 2 vs 8 differ relative to content top (maxY=132): y=135 is out for 2, in for 8.
        let y135 = CGPoint(x: 200, y: 135)
        #expect(
            !DockPreferences.isPointerOverStrip(
                point: y135, windowFrame: window, leaveMargin: 2, contentHeight: contentH
            )
        )
        #expect(
            DockPreferences.isPointerOverStrip(
                point: y135, windowFrame: window, leaveMargin: 8, contentHeight: contentH
            )
        )

        var p = DockPreferences.default
        p.showRunningDots = false
        p.showLabels = false
        // medium 44 + pad 10*2 = 64 content; +28 chrome = 92 window height.
        #expect(Double(p.contentBarHeight()) == 64)
        #expect(Double(p.expandedStripHeight()) == 92)
        let content = DockPreferences.bottomAlignedContentFrame(
            windowFrame: CGRect(x: 0, y: 0, width: 100, height: 92),
            contentHeight: p.contentBarHeight()
        )
        #expect(Double(content.height) == 64)
        #expect(Double(content.minY) == 0)
    }

    @Test("scaledRevealDuration has no hard 0.07 floor")
    func scaledRevealDurationProportional() {
        // Full travel uses base.
        #expect(abs(DockPreferences.scaledRevealDuration(base: 0.22, heightFraction: 1) - 0.22) < 1e-9)
        // Short reverse is 40% of base.
        #expect(abs(DockPreferences.scaledRevealDuration(base: 0.22, heightFraction: 0) - 0.088) < 1e-9)
        // Low base (0.05) full travel stays 0.05 — not floored to 0.07.
        #expect(abs(DockPreferences.scaledRevealDuration(base: 0.05, heightFraction: 1) - 0.05) < 1e-9)
        #expect(abs(DockPreferences.scaledRevealDuration(base: 0.05, heightFraction: 0) - 0.02) < 1e-9)
        // Snap at zero base.
        #expect(DockPreferences.scaledRevealDuration(base: 0, heightFraction: 1) == 0)
        #expect(DockPreferences.shouldSnapReveal(duration: 0))
        #expect(DockPreferences.shouldSnapReveal(duration: 0.01))
        #expect(!DockPreferences.shouldSnapReveal(duration: 0.05))
    }

    @Test("chrome pad and expandedStripHeight stay single-sourced")
    func chromeAndExpandedHeight() {
        var p = DockPreferences.default
        #expect(p.showRunningDots == true) // default on
        #expect(Double(p.chromeVerticalPad()) == DockPreferences.chromePadWithoutLabels)
        // content: 44 + 10*2 + 6 dots = 70; window: +28 = 98
        #expect(Double(p.contentBarHeight()) == 70)
        #expect(Double(p.expandedStripHeight()) == 98)

        p.showRunningDots = false
        #expect(Double(p.contentBarHeight()) == 64) // 44+20
        #expect(Double(p.expandedStripHeight()) == 92) // 64+28

        p.showLabels = true
        p.showRunningDots = true
        #expect(Double(p.chromeVerticalPad()) == DockPreferences.chromePadWithLabels)
        // content 44+16+14+6 = 80; window 108
        #expect(Double(p.contentBarHeight()) == 80)
        #expect(Double(p.expandedStripHeight()) == 108)
    }

    @Test("hit/feel prefs missing decode defaults + round-trip")
    func hitFeelPrefsPersist() throws {
        let raw = """
        {"edgeHover": true}
        """
        let decoded = try JSONDecoder().decode(DockPreferences.self, from: Data(raw.utf8))
        #expect(decoded.edgeHorizontalOvershoot == 48)
        #expect(decoded.revealBaseDuration == 0.22)
        #expect(decoded.iconSpacing == 8)

        let over = try JSONDecoder().decode(
            DockPreferences.self,
            from: Data(#"{"edgeHorizontalOvershoot":500,"revealBaseDuration":9,"iconSpacing":-2}"#.utf8)
        )
        #expect(over.edgeHorizontalOvershoot == DockPreferences.maxEdgeHorizontalOvershoot)
        #expect(over.revealBaseDuration == DockPreferences.maxRevealBaseDuration)
        #expect(over.iconSpacing == DockPreferences.minIconSpacing)

        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = SlotStore(fileURL: url)
        _ = writer.updatePreferences {
            $0.edgeHorizontalOvershoot = 72
            $0.revealBaseDuration = 0.4
            $0.iconSpacing = 14
        }
        let reader = SlotStore(fileURL: url)
        #expect(reader.preferences.edgeHorizontalOvershoot == 72)
        #expect(abs(reader.preferences.revealBaseDuration - 0.4) < 0.001)
        #expect(reader.preferences.iconSpacing == 14)
    }

    @Test("clampDelay bounds values")
    func clampDelay() {
        #expect(DockPreferences.clampDelay(0.1) == 0.1)
        #expect(DockPreferences.clampDelay(0.05) == 0.1)
        #expect(DockPreferences.clampDelay(0) == 0.1)
        #expect(DockPreferences.clampDelay(5) == 3.0)
        #expect(DockPreferences.clampDelay(1.2) == 1.2)
        #expect(DockPreferences.minAutoHideDelay == 0.1)
        #expect(DockPreferences.maxAutoHideDelay == 3.0)
    }

    @Test("clampEdgeTriggerHeight bounds values")
    func clampEdgeTriggerHeight() {
        #expect(DockPreferences.clampEdgeTriggerHeight(28) == 28)
        #expect(DockPreferences.clampEdgeTriggerHeight(1) == 1)
        #expect(DockPreferences.clampEdgeTriggerHeight(12) == 12)
        #expect(DockPreferences.clampEdgeTriggerHeight(72) == 72)
        #expect(DockPreferences.clampEdgeTriggerHeight(0) == DockPreferences.minEdgeTriggerHeight)
        #expect(DockPreferences.clampEdgeTriggerHeight(-4) == DockPreferences.minEdgeTriggerHeight)
        #expect(DockPreferences.clampEdgeTriggerHeight(200) == 200)
        #expect(DockPreferences.clampEdgeTriggerHeight(999) == DockPreferences.maxEdgeTriggerHeight)
        #expect(DockPreferences.minEdgeTriggerHeight == 1)
        #expect(DockPreferences.maxEdgeTriggerHeight == 200)
        #expect(DockPreferences.defaultEdgeTriggerHeight == 28)
    }

    @Test("edgeTriggerHeight sanitizes on init and decode")
    func edgeTriggerHeightSanitize() throws {
        let over = DockPreferences(edgeTriggerHeight: 999)
        #expect(over.edgeTriggerHeight == DockPreferences.maxEdgeTriggerHeight)
        let one = DockPreferences(edgeTriggerHeight: 1)
        #expect(one.edgeTriggerHeight == 1)
        var under = DockPreferences(edgeTriggerHeight: 0)
        #expect(under.edgeTriggerHeight == DockPreferences.minEdgeTriggerHeight)
        under.edgeTriggerHeight = 500
        under.sanitize()
        #expect(under.edgeTriggerHeight == DockPreferences.maxEdgeTriggerHeight)

        // JSON with sub-min value clamps on decode.
        let raw = """
        {"edgeTriggerHeight": 0}
        """
        let data = Data(raw.utf8)
        let decoded = try JSONDecoder().decode(DockPreferences.self, from: data)
        #expect(decoded.edgeTriggerHeight == DockPreferences.minEdgeTriggerHeight)
    }

    @Test("preferences persist round-trip with slots")
    func prefsRoundTrip() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = SlotStore(fileURL: url)
        _ = writer.add(label: "Safari", target: "/Applications/Safari.app", id: "s")
        _ = writer.updatePreferences {
            $0.iconSize = .large
            $0.pinOpen = true
            $0.showLabels = true
            $0.alignment = .trailing
            $0.autoHideDelay = 1.5
            $0.edgeTriggerHeight = 48
        }
        #expect(writer.preferences.iconSize == .large)
        #expect(writer.preferences.alignment == .trailing)
        #expect(writer.preferences.edgeTriggerHeight == 48)

        let reader = SlotStore(fileURL: url)
        #expect(reader.slots.count == 1)
        #expect(reader.preferences.iconSize == .large)
        #expect(reader.preferences.pinOpen == true)
        #expect(reader.preferences.showLabels == true)
        #expect(reader.preferences.alignment == .trailing)
        #expect(abs(reader.preferences.autoHideDelay - 1.5) < 0.001)
        #expect(reader.preferences.edgeTriggerHeight == 48)
        #expect(reader.document.version >= 2)
    }

    @Test("missing edgeTriggerHeight decodes as prior 28-pt default")
    func edgeTriggerHeightMissingDefaults() throws {
        let raw = """
        {"edgeHover": true, "autoHide": true}
        """
        let decoded = try JSONDecoder().decode(DockPreferences.self, from: Data(raw.utf8))
        #expect(decoded.edgeTriggerHeight == 28)
        #expect(decoded.edgeTriggerHeight == DockPreferences.defaultEdgeTriggerHeight)
    }

    @Test("v1 document without preferences decodes with defaults")
    func v1BackwardCompatible() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let v1 = """
        {
          "version": 1,
          "slots": [
            { "id": "a", "label": "A", "target": "/a", "sortOrder": 0 }
          ]
        }
        """
        try v1.write(to: url, atomically: true, encoding: .utf8)

        let store = SlotStore(fileURL: url)
        #expect(store.slots.count == 1)
        #expect(store.slots[0].label == "A")
        #expect(store.preferences == .default)
    }

    @Test("setPreferences replaces whole struct")
    func setPreferences() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SlotStore(fileURL: url)
        var custom = DockPreferences.default
        custom.iconSize = .small
        custom.edgeHover = false
        custom.autoHideDelay = 0.05 // will clamp to 0.1
        store.setPreferences(custom)
        #expect(store.preferences.iconSize == .small)
        #expect(store.preferences.edgeHover == false)
        #expect(store.preferences.autoHideDelay == 0.1)
    }

    @Test("launchAtLogin defaults off and persists")
    func launchAtLoginPersist() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = SlotStore(fileURL: url)
        #expect(writer.preferences.launchAtLogin == false)
        _ = writer.updatePreferences { $0.launchAtLogin = true }
        #expect(writer.preferences.launchAtLogin == true)
        let reader = SlotStore(fileURL: url)
        #expect(reader.preferences.launchAtLogin == true)
    }
}
