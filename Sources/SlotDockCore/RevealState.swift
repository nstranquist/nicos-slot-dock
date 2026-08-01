import Foundation

/// Dock strip reveal/hide animation state machine (pure, headless).
public enum RevealPhase: String, Equatable, Sendable {
    case collapsed
    case expanding
    case expanded
    case collapsing
}

/// Tracks compact ↔ revealed progress with discrete phase transitions.
/// Progress is 0 (collapsed) … 1 (fully revealed). UI maps progress to height/opacity.
public struct RevealState: Equatable, Sendable {
    public private(set) var phase: RevealPhase
    public private(set) var progress: Double

    public static let collapsed = RevealState(phase: .collapsed, progress: 0)
    public static let expanded = RevealState(phase: .expanded, progress: 1)

    public init(phase: RevealPhase = .collapsed, progress: Double = 0) {
        self.phase = phase
        self.progress = Self.clamp(progress)
    }

    public var isRevealed: Bool {
        phase == .expanded || phase == .expanding
    }

    public var isAnimating: Bool {
        phase == .expanding || phase == .collapsing
    }

    /// Begin expand from collapsed/collapsing (or no-op if already expanded/expanding).
    public mutating func beginExpand() {
        switch phase {
        case .expanded, .expanding:
            return
        case .collapsed, .collapsing:
            phase = .expanding
            if progress <= 0 { progress = 0 }
        }
    }

    /// Begin collapse from expanded/expanding (or no-op if already collapsed/collapsing).
    public mutating func beginCollapse() {
        switch phase {
        case .collapsed, .collapsing:
            return
        case .expanded, .expanding:
            phase = .collapsing
            if progress >= 1 { progress = 1 }
        }
    }

    /// Toggle direction based on current phase.
    public mutating func toggle() {
        if isRevealed {
            beginCollapse()
        } else {
            beginExpand()
        }
    }

    /// Advance animation by `delta` (0…1 fraction of full travel). Returns true if phase changed.
    @discardableResult
    public mutating func advance(by delta: Double) -> Bool {
        let previous = phase
        let d = delta.isFinite ? abs(delta) : 0
        switch phase {
        case .expanding:
            progress = Self.clamp(progress + d)
            if progress >= 1 {
                progress = 1
                phase = .expanded
            }
        case .collapsing:
            progress = Self.clamp(progress - d)
            if progress <= 0 {
                progress = 0
                phase = .collapsed
            }
        case .collapsed, .expanded:
            break
        }
        return previous != phase
    }

    /// Jump to a finished state (used when animation completes or for tests).
    public mutating func finish() {
        switch phase {
        case .expanding:
            progress = 1
            phase = .expanded
        case .collapsing:
            progress = 0
            phase = .collapsed
        case .collapsed, .expanded:
            break
        }
    }

    /// Align model progress with a live 0…1 height ratio (e.g. mid-AppKit animation before reverse).
    public mutating func alignProgress(to liveRatio: Double) {
        progress = Self.clamp(liveRatio)
    }

    /// Snap without intermediate animation.
    public mutating func snap(to target: RevealPhase) {
        switch target {
        case .collapsed, .collapsing:
            phase = .collapsed
            progress = 0
        case .expanded, .expanding:
            phase = .expanded
            progress = 1
        }
    }

    /// Ease progress for UI (smoothstep). Pure math — AppKit uses this for frame height.
    public var easedProgress: Double {
        // Smoothstep: 3t² − 2t³
        let t = progress
        return t * t * (3 - 2 * t)
    }

    /// Height for a dock bar given collapsed/expanded extents and **current** eased progress
    /// (where the strip is right now — use as the animation *start* frame).
    public func height(collapsed: CGFloat, expanded: CGFloat) -> CGFloat {
        collapsed + (expanded - collapsed) * CGFloat(easedProgress)
    }

    /// Progress the animation should land on for the active phase.
    /// Expanding/expanded → 1; collapsing/collapsed → 0.
    /// This is the value UI must animate *toward* — not the current `progress`.
    public var destinationProgress: Double {
        Self.animationTargetProgress(for: phase)
    }

    /// Height the dock panel should animate **to** for the active phase.
    /// After `beginExpand()`, current `height(...)` is still collapsed; this returns expanded.
    /// After `beginCollapse()`, current `height(...)` is still expanded; this returns collapsed.
    public func destinationHeight(collapsed: CGFloat, expanded: CGFloat) -> CGFloat {
        collapsed + (expanded - collapsed) * CGFloat(destinationProgress)
    }

    /// Pure phase → animation end progress. Tested independently of live progress.
    public static func animationTargetProgress(for phase: RevealPhase) -> Double {
        switch phase {
        case .collapsed, .collapsing:
            return 0
        case .expanded, .expanding:
            return 1
        }
    }

    /// Pure phase → destination height for panel frame animation.
    public static func animationTargetHeight(
        phase: RevealPhase,
        collapsed: CGFloat,
        expanded: CGFloat
    ) -> CGFloat {
        collapsed + (expanded - collapsed) * CGFloat(animationTargetProgress(for: phase))
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

// MARK: - Auto-hide collapse policy (pure)

/// When/how the strip collapses under auto-hide (no AppKit).
public enum AutoHideCollapsePolicy {
    /// Outside click collapses when hide delay is at or below this (seconds).
    public static let outsideClickMaxDelay: Double = 0.3

    /// Pointer-leave timer may arm auto-hide.
    public static func shouldArmLeaveTimer(
        autoHide: Bool,
        pinOpen: Bool,
        settingsOpen: Bool
    ) -> Bool {
        autoHide && !pinOpen && !settingsOpen
    }

    /// Click outside the strip should collapse immediately (snappy delays only).
    /// Does **not** quit/hide the app — only collapse the strip.
    public static func collapsesOnOutsideClick(
        autoHide: Bool,
        pinOpen: Bool,
        settingsOpen: Bool,
        autoHideDelay: Double,
        isRevealed: Bool
    ) -> Bool {
        guard shouldArmLeaveTimer(autoHide: autoHide, pinOpen: pinOpen, settingsOpen: settingsOpen) else {
            return false
        }
        guard isRevealed else { return false }
        return autoHideDelay <= outsideClickMaxDelay + 1e-9
    }

    /// Whether the pointer should keep the strip open / cancel the leave timer.
    ///
    /// - `overStrip` = inside strip window expanded by `autoHideLeaveMargin`.
    /// - `nearBottomEdge` = edge-hover hit band (screen bottom).
    ///
    /// **While fully expanded**, only `overStrip` holds the strip open so leave
    /// margin is meaningful. Edge-hover alone must not mask leave (old bug:
    /// `overStrip || nearBottom` made leave margin feel inert).
    /// **While collapsed / collapsing / expanding**, edge-hover may still open
    /// or reverse collapse from the bottom edge.
    public static func shouldHoldStripOpen(
        overStrip: Bool,
        nearBottomEdge: Bool,
        edgeHoverEnabled: Bool,
        phase: RevealPhase
    ) -> Bool {
        if overStrip { return true }
        guard edgeHoverEnabled, nearBottomEdge else { return false }
        switch phase {
        case .expanded:
            return false
        case .collapsed, .collapsing, .expanding:
            return true
        }
    }
}

// CGFloat without importing CoreGraphics on Linux-ish toolchains — macOS has it via Foundation.
#if canImport(CoreGraphics)
import CoreGraphics
#else
public typealias CGFloat = Double
#endif
