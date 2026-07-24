import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#else
public typealias CGFloat = Double
public struct CGRect: Equatable, Sendable {
    public var origin: CGPoint
    public var size: CGSize
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        origin = CGPoint(x: x, y: y)
        size = CGSize(width: width, height: height)
    }
    public var minX: CGFloat { origin.x }
    public var minY: CGFloat { origin.y }
    public var maxX: CGFloat { origin.x + size.width }
    public var maxY: CGFloat { origin.y + size.height }
    public var width: CGFloat { size.width }
    public var height: CGFloat { size.height }
}
public struct CGPoint: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
}
public struct CGSize: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat
    public init(width: CGFloat, height: CGFloat) { self.width = width; self.height = height }
}
#endif

/// Screen geometry in AppKit bottom-left origin coordinates (matches NSWindow.frame).
public struct ScreenBottomBand: Equatable, Sendable {
    /// Visible frame of the screen (already excludes menu bar / system Dock when possible).
    public var visibleFrame: CGRect
    /// Height of the Slot Dock strip region that needs clearance (points).
    public var padHeight: CGFloat
    /// Extra gap above the strip.
    public var extraGap: CGFloat

    public init(visibleFrame: CGRect, padHeight: CGFloat, extraGap: CGFloat = 8) {
        self.visibleFrame = visibleFrame
        self.padHeight = max(0, padHeight)
        self.extraGap = max(0, extraGap)
    }

    /// Y threshold: windows whose bottom edge is below this may need padding.
    public var clearanceY: CGFloat {
        visibleFrame.minY + padHeight + extraGap
    }
}

/// One window under consideration for padding.
public struct WindowFrameSnapshot: Equatable, Sendable, Identifiable {
    public var id: String
    public var frame: CGRect
    /// Owning app bundle id (optional filter).
    public var bundleIdentifier: String?

    public init(id: String, frame: CGRect, bundleIdentifier: String? = nil) {
        self.id = id
        self.frame = frame
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Ledger entry: window we previously padded.
public struct PadRecord: Equatable, Sendable, Identifiable {
    public var id: String { windowID }
    public var windowID: String
    /// Frame before any Slot Dock pad (restore target).
    public var originalFrame: CGRect
    /// Last applied frame after pad.
    public var paddedFrame: CGRect
    public var appliedDeltaY: CGFloat

    public init(windowID: String, originalFrame: CGRect, paddedFrame: CGRect, appliedDeltaY: CGFloat) {
        self.windowID = windowID
        self.originalFrame = originalFrame
        self.paddedFrame = paddedFrame
        self.appliedDeltaY = appliedDeltaY
    }
}

/// Whether the strip currently needs bottom inset for content visibility.
public enum SafeAreaNeed: String, Equatable, Sendable {
    case none
    /// Strip is pinned open or expanded while auto-hide is active.
    case active
}

public enum SafeAreaPolicy {
    /// Pad when option enabled and strip is open enough to cover content.
    public static func need(
        optionEnabled: Bool,
        pinOpen: Bool,
        autoHide: Bool,
        revealPhase: RevealPhase
    ) -> SafeAreaNeed {
        guard optionEnabled else { return .none }
        if pinOpen { return .active }
        // Expanded or expanding under auto-hide / normal reveal
        switch revealPhase {
        case .expanded, .expanding:
            return .active
        case .collapsed, .collapsing:
            return .none
        }
    }
}

/// Pure planner: decide apply/restore without touching windows.
public enum SafeAreaPlanner {
    public struct FrameChange: Equatable, Sendable {
        public var windowID: String
        public var from: CGRect
        public var to: CGRect
        public init(windowID: String, from: CGRect, to: CGRect) {
            self.windowID = windowID
            self.from = from
            self.to = to
        }
    }

    public struct RestoreChange: Equatable, Sendable {
        public var windowID: String
        public var to: CGRect
        public init(windowID: String, to: CGRect) {
            self.windowID = windowID
            self.to = to
        }
    }

    public struct Plan: Equatable, Sendable {
        /// Windows to move to new frames (apply or re-apply).
        public var apply: [FrameChange]
        /// Windows to restore to original frames.
        public var restore: [RestoreChange]
        /// Resulting ledger after applying this plan.
        public var nextLedger: [String: PadRecord]

        public init(
            apply: [FrameChange] = [],
            restore: [RestoreChange] = [],
            nextLedger: [String: PadRecord] = [:]
        ) {
            self.apply = apply
            self.restore = restore
            self.nextLedger = nextLedger
        }
    }

    /// Compute padded frame: raise bottom by delta so frame.minY >= clearanceY.
    public static func paddedFrame(for frame: CGRect, band: ScreenBottomBand) -> CGRect? {
        let targetMinY = band.clearanceY
        guard frame.minY < targetMinY else { return nil }
        let delta = targetMinY - frame.minY
        // Raise window (increase origin.y in AppKit coords).
        var next = frame
        next = CGRect(
            x: frame.minX,
            y: frame.minY + delta,
            width: frame.width,
            height: frame.height
        )
        // Keep top on-screen if possible
        let maxTop = band.visibleFrame.maxY
        if next.maxY > maxTop {
            let overflow = next.maxY - maxTop
            let newHeight = max(120, next.height - overflow)
            next = CGRect(x: next.minX, y: maxTop - newHeight, width: next.width, height: newHeight)
        }
        return next
    }

    /// Whether this window overlaps the bottom pad band enough to care.
    public static func needsPad(_ window: WindowFrameSnapshot, band: ScreenBottomBand) -> Bool {
        // Intersects horizontal span of visible frame and sits too low.
        let overlapsX = window.frame.maxX > band.visibleFrame.minX
            && window.frame.minX < band.visibleFrame.maxX
        guard overlapsX else { return false }
        return window.frame.minY < band.clearanceY
    }

    /// Build apply/restore plan.
    /// - Parameters:
    ///   - need: whether padding should be active now.
    ///   - windows: current on-screen windows (caller filters Slot Dock itself).
    ///   - band: strip geometry.
    ///   - ledger: prior pad records.
    public static func plan(
        need: SafeAreaNeed,
        windows: [WindowFrameSnapshot],
        band: ScreenBottomBand,
        ledger: [String: PadRecord]
    ) -> Plan {
        var nextLedger = ledger
        var apply: [FrameChange] = []
        var restore: [RestoreChange] = []

        if need == .none {
            // Restore every ledger entry we still know about; drop ledger.
            for (id, record) in ledger {
                restore.append(RestoreChange(windowID: id, to: record.originalFrame))
            }
            return Plan(apply: [], restore: restore, nextLedger: [:])
        }

        let windowByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        var handledIDs = Set<String>()

        // Ledger entries: decide KEEP vs RESTORE from **originalFrame**, never from the
        // already-padded live frame (which would look "clear" and undo the pad).
        for (id, record) in ledger {
            guard windowByID[id] != nil else {
                // Window gone — drop ledger entry (nothing to restore on screen)
                nextLedger.removeValue(forKey: id)
                continue
            }
            let originalSnap = WindowFrameSnapshot(id: id, frame: record.originalFrame)
            if !needsPad(originalSnap, band: band) {
                // Pad no longer required for the pre-pad geometry → restore original
                restore.append(RestoreChange(windowID: id, to: record.originalFrame))
                nextLedger.removeValue(forKey: id)
                handledIDs.insert(id)
                continue
            }
            // Still need pad: recompute target from original (no stacking on live)
            let live = windowByID[id]!
            guard let retarget = paddedFrame(for: record.originalFrame, band: band) else {
                restore.append(RestoreChange(windowID: id, to: record.originalFrame))
                nextLedger.removeValue(forKey: id)
                handledIDs.insert(id)
                continue
            }
            nextLedger[id] = PadRecord(
                windowID: id,
                originalFrame: record.originalFrame,
                paddedFrame: retarget,
                appliedDeltaY: retarget.minY - record.originalFrame.minY
            )
            if abs(live.frame.minY - retarget.minY) > 1
                || abs(live.frame.height - retarget.height) > 1
            {
                apply.append(FrameChange(windowID: id, from: live.frame, to: retarget))
            }
            handledIDs.insert(id)
        }

        // New windows not yet in ledger that currently sit under the strip.
        for window in windows {
            if handledIDs.contains(window.id) { continue }
            guard needsPad(window, band: band) else { continue }
            guard let target = paddedFrame(for: window.frame, band: band) else { continue }
            apply.append(FrameChange(windowID: window.id, from: window.frame, to: target))
            nextLedger[window.id] = PadRecord(
                windowID: window.id,
                originalFrame: window.frame,
                paddedFrame: target,
                appliedDeltaY: target.minY - window.frame.minY
            )
        }

        return Plan(apply: apply, restore: restore, nextLedger: nextLedger)
    }

    /// Whether the pre-pad geometry still requires padding (ledger keep decision).
    public static func originalStillNeedsPad(record: PadRecord, band: ScreenBottomBand) -> Bool {
        needsPad(WindowFrameSnapshot(id: record.windowID, frame: record.originalFrame), band: band)
    }

    /// Restore-only plan for option turned off (same as need.none).
    public static func restoreAll(ledger: [String: PadRecord]) -> Plan {
        plan(need: .none, windows: [], band: ScreenBottomBand(
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            padHeight: 0
        ), ledger: ledger)
    }
}
