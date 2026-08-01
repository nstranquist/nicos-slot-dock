import Foundation
import Testing
@testable import SlotDockCore

@Suite("RevealState")
struct RevealStateTests {
    @Test("starts collapsed at progress 0")
    func startsCollapsed() {
        let state = RevealState.collapsed
        #expect(state.phase == .collapsed)
        #expect(state.progress == 0)
        #expect(state.isRevealed == false)
        #expect(state.isAnimating == false)
    }

    @Test("beginExpand then advance reaches expanded")
    func expandTransition() {
        var state = RevealState.collapsed
        state.beginExpand()
        #expect(state.phase == .expanding)
        #expect(state.isRevealed == true)
        #expect(state.isAnimating == true)

        // Intermediate step
        let changedMid = state.advance(by: 0.4)
        #expect(state.phase == .expanding)
        #expect(state.progress == 0.4)
        #expect(changedMid == false)

        let changedEnd = state.advance(by: 0.7)
        #expect(state.progress == 1)
        #expect(state.phase == .expanded)
        #expect(changedEnd == true)
        #expect(state.isAnimating == false)
    }

    @Test("beginCollapse then advance reaches collapsed")
    func collapseTransition() {
        var state = RevealState.expanded
        state.beginCollapse()
        #expect(state.phase == .collapsing)
        #expect(state.isRevealed == false)

        _ = state.advance(by: 0.3)
        #expect(state.phase == .collapsing)
        #expect(abs(state.progress - 0.7) < 0.0001)

        _ = state.advance(by: 1.0)
        #expect(state.phase == .collapsed)
        #expect(state.progress == 0)
    }

    @Test("non-finite progress and deltas fail closed")
    func nonFiniteInputs() {
        var state = RevealState(phase: .expanding, progress: .nan)
        #expect(state.progress == 0)
        _ = state.advance(by: .infinity)
        #expect(state.progress == 0)
    }

    @Test("toggle flips direction")
    func toggleFlips() {
        var state = RevealState.collapsed
        state.toggle()
        #expect(state.phase == .expanding)
        state.finish()
        #expect(state.phase == .expanded)
        state.toggle()
        #expect(state.phase == .collapsing)
        state.finish()
        #expect(state.phase == .collapsed)
    }

    @Test("finish snaps mid-animation to end state")
    func finishSnaps() {
        var expanding = RevealState(phase: .expanding, progress: 0.3)
        expanding.finish()
        #expect(expanding.phase == .expanded)
        #expect(expanding.progress == 1)

        var collapsing = RevealState(phase: .collapsing, progress: 0.8)
        collapsing.finish()
        #expect(collapsing.phase == .collapsed)
        #expect(collapsing.progress == 0)
    }

    @Test("alignProgress clamps live height ratio for mid-flight reverse")
    func alignProgress() {
        var state = RevealState(phase: .collapsing, progress: 1)
        state.alignProgress(to: 0.45)
        #expect(abs(state.progress - 0.45) < 0.0001)
        state.alignProgress(to: -1)
        #expect(state.progress == 0)
        state.alignProgress(to: 2)
        #expect(state.progress == 1)
    }

    @Test("snap jumps without intermediate phase")
    func snapJumps() {
        var state = RevealState.collapsed
        state.snap(to: .expanded)
        #expect(state.phase == .expanded)
        #expect(state.progress == 1)
        state.snap(to: .collapsed)
        #expect(state.phase == .collapsed)
        #expect(state.progress == 0)
    }

    @Test("easedProgress smoothstep and height interpolation")
    func easedAndHeight() {
        var state = RevealState(phase: .expanding, progress: 0)
        #expect(state.easedProgress == 0)
        #expect(state.height(collapsed: 10, expanded: 90) == 10)

        state = RevealState(phase: .expanding, progress: 1)
        #expect(state.easedProgress == 1)
        #expect(state.height(collapsed: 10, expanded: 90) == 90)

        state = RevealState(phase: .expanding, progress: 0.5)
        let eased = state.easedProgress
        // smoothstep(0.5) = 0.5
        #expect(abs(eased - 0.5) < 0.0001)
        let h = state.height(collapsed: 10, expanded: 90)
        #expect(abs(h - 50) < 0.001)
    }

    @Test("beginExpand is no-op when already expanding or expanded")
    func beginExpandIdempotent() {
        var state = RevealState.expanded
        state.beginExpand()
        #expect(state.phase == .expanded)

        state = RevealState(phase: .expanding, progress: 0.2)
        state.beginExpand()
        #expect(state.phase == .expanding)
        #expect(state.progress == 0.2)
    }

    @Test("full cycle collapsed → expanded → collapsed with intermediate states")
    func fullCycle() {
        var state = RevealState.collapsed
        let phases: [RevealPhase] = {
            var seen: [RevealPhase] = [state.phase]
            state.beginExpand()
            seen.append(state.phase)
            while state.phase == .expanding {
                _ = state.advance(by: 0.25)
                seen.append(state.phase)
            }
            state.beginCollapse()
            seen.append(state.phase)
            while state.phase == .collapsing {
                _ = state.advance(by: 0.25)
                seen.append(state.phase)
            }
            return seen
        }()

        #expect(phases.contains(.collapsed))
        #expect(phases.contains(.expanding))
        #expect(phases.contains(.expanded))
        #expect(phases.contains(.collapsing))
        #expect(phases.first == .collapsed)
        #expect(phases.last == .collapsed)
    }

    // MARK: - Animation destination (UI frame target — the bug class AC2 guards)

    @Test("animationTargetProgress: expanding/expanded → 1, collapsing/collapsed → 0")
    func animationTargetProgressByPhase() {
        #expect(RevealState.animationTargetProgress(for: .collapsed) == 0)
        #expect(RevealState.animationTargetProgress(for: .collapsing) == 0)
        #expect(RevealState.animationTargetProgress(for: .expanding) == 1)
        #expect(RevealState.animationTargetProgress(for: .expanded) == 1)
    }
}

@Suite("AutoHideCollapsePolicy")
struct AutoHideCollapsePolicyTests {
    @Test("outside click only when auto-hide, not pinned, delay ≤ 0.3, revealed")
    func outsideClickGates() {
        #expect(
            AutoHideCollapsePolicy.collapsesOnOutsideClick(
                autoHide: true,
                pinOpen: false,
                settingsOpen: false,
                autoHideDelay: 0.3,
                isRevealed: true
            )
        )
        #expect(
            AutoHideCollapsePolicy.collapsesOnOutsideClick(
                autoHide: true,
                pinOpen: false,
                settingsOpen: false,
                autoHideDelay: 0.1,
                isRevealed: true
            )
        )
        // Above threshold → timer only, no outside-click collapse
        #expect(
            !AutoHideCollapsePolicy.collapsesOnOutsideClick(
                autoHide: true,
                pinOpen: false,
                settingsOpen: false,
                autoHideDelay: 0.31,
                isRevealed: true
            )
        )
        #expect(
            !AutoHideCollapsePolicy.collapsesOnOutsideClick(
                autoHide: true,
                pinOpen: false,
                settingsOpen: false,
                autoHideDelay: 0.85,
                isRevealed: true
            )
        )
        // Pinned / settings / not revealed / autoHide off
        #expect(
            !AutoHideCollapsePolicy.collapsesOnOutsideClick(
                autoHide: true,
                pinOpen: true,
                settingsOpen: false,
                autoHideDelay: 0.2,
                isRevealed: true
            )
        )
        #expect(
            !AutoHideCollapsePolicy.collapsesOnOutsideClick(
                autoHide: true,
                pinOpen: false,
                settingsOpen: true,
                autoHideDelay: 0.2,
                isRevealed: true
            )
        )
        #expect(
            !AutoHideCollapsePolicy.collapsesOnOutsideClick(
                autoHide: false,
                pinOpen: false,
                settingsOpen: false,
                autoHideDelay: 0.2,
                isRevealed: true
            )
        )
        #expect(
            !AutoHideCollapsePolicy.collapsesOnOutsideClick(
                autoHide: true,
                pinOpen: false,
                settingsOpen: false,
                autoHideDelay: 0.2,
                isRevealed: false
            )
        )
    }

    @Test("leave timer arm matches auto-hide gates")
    func leaveTimer() {
        #expect(
            AutoHideCollapsePolicy.shouldArmLeaveTimer(
                autoHide: true,
                pinOpen: false,
                settingsOpen: false
            )
        )
        #expect(
            !AutoHideCollapsePolicy.shouldArmLeaveTimer(
                autoHide: true,
                pinOpen: true,
                settingsOpen: false
            )
        )
    }

    @Test("outsideClickMaxDelay is 0.3")
    func thresholdConstant() {
        #expect(abs(AutoHideCollapsePolicy.outsideClickMaxDelay - 0.3) < 0.0001)
    }

    @Test("leave margin holds while expanded; edge band does not mask leave")
    func leaveMarginNotMaskedByEdgeWhileExpanded() {
        // Expanded + off strip + still near bottom edge → must NOT hold open
        // (old bug: overStrip || nearBottom made leave margin inert).
        #expect(
            !AutoHideCollapsePolicy.shouldHoldStripOpen(
                overStrip: false,
                nearBottomEdge: true,
                edgeHoverEnabled: true,
                phase: .expanded
            )
        )
        // Expanded + inside leave margin → hold.
        #expect(
            AutoHideCollapsePolicy.shouldHoldStripOpen(
                overStrip: true,
                nearBottomEdge: false,
                edgeHoverEnabled: true,
                phase: .expanded
            )
        )
        // Collapsed + near bottom → re-open via edge hover.
        #expect(
            AutoHideCollapsePolicy.shouldHoldStripOpen(
                overStrip: false,
                nearBottomEdge: true,
                edgeHoverEnabled: true,
                phase: .collapsed
            )
        )
        // Collapsed + edge hover off → no hold without strip.
        #expect(
            !AutoHideCollapsePolicy.shouldHoldStripOpen(
                overStrip: false,
                nearBottomEdge: true,
                edgeHoverEnabled: false,
                phase: .collapsed
            )
        )
        // Expanding still uses edge band so mid-reveal from edge is not aborted.
        #expect(
            AutoHideCollapsePolicy.shouldHoldStripOpen(
                overStrip: false,
                nearBottomEdge: true,
                edgeHoverEnabled: true,
                phase: .expanding
            )
        )
    }
}

// Continuation of RevealState destination tests (kept adjacent for the animation AC suite).
extension RevealStateTests {
    @Test("after beginExpand, current height is collapsed but destination is expanded")
    func expandDestinationNotCurrent() {
        let collapsed: CGFloat = 28
        let expanded: CGFloat = 92
        var state = RevealState.collapsed
        #expect(state.height(collapsed: collapsed, expanded: expanded) == collapsed)

        state.beginExpand()
        // Live progress still 0 — this is the animation START, not the end.
        #expect(state.phase == .expanding)
        #expect(state.progress == 0)
        #expect(state.height(collapsed: collapsed, expanded: expanded) == collapsed)
        // UI must animate toward destinationHeight, not current height.
        #expect(state.destinationProgress == 1)
        #expect(state.destinationHeight(collapsed: collapsed, expanded: expanded) == expanded)
        #expect(
            RevealState.animationTargetHeight(phase: state.phase, collapsed: collapsed, expanded: expanded)
                == expanded
        )
        // Destination must differ from current when expand just began (real motion delta).
        #expect(
            state.destinationHeight(collapsed: collapsed, expanded: expanded)
                != state.height(collapsed: collapsed, expanded: expanded)
        )
    }

    @Test("after beginCollapse, current height is expanded but destination is collapsed")
    func collapseDestinationNotCurrent() {
        let collapsed: CGFloat = 28
        let expanded: CGFloat = 92
        var state = RevealState.expanded
        #expect(state.height(collapsed: collapsed, expanded: expanded) == expanded)

        state.beginCollapse()
        #expect(state.phase == .collapsing)
        #expect(state.progress == 1)
        #expect(state.height(collapsed: collapsed, expanded: expanded) == expanded)
        #expect(state.destinationProgress == 0)
        #expect(state.destinationHeight(collapsed: collapsed, expanded: expanded) == collapsed)
        #expect(
            RevealState.animationTargetHeight(phase: state.phase, collapsed: collapsed, expanded: expanded)
                == collapsed
        )
        #expect(
            state.destinationHeight(collapsed: collapsed, expanded: expanded)
                != state.height(collapsed: collapsed, expanded: expanded)
        )
    }

    @Test("syncReveal frame plan: expand targets expandedHeight, collapse targets collapsedHeight")
    func syncRevealFramePlanMatchesUIWiring() {
        // Mirrors DockWindowController.syncRevealAnimated height selection:
        // start = height(...) [or live window height], target = destinationHeight(...).
        let collapsed: CGFloat = 28
        let expanded: CGFloat = 92

        var expanding = RevealState.collapsed
        expanding.beginExpand()
        let expandStart = expanding.height(collapsed: collapsed, expanded: expanded)
        let expandTarget = expanding.destinationHeight(collapsed: collapsed, expanded: expanded)
        #expect(expandStart == collapsed)
        #expect(expandTarget == expanded)
        #expect(expandTarget > expandStart) // positive motion delta

        var collapsing = RevealState.expanded
        collapsing.beginCollapse()
        let collapseStart = collapsing.height(collapsed: collapsed, expanded: expanded)
        let collapseTarget = collapsing.destinationHeight(collapsed: collapsed, expanded: expanded)
        #expect(collapseStart == expanded)
        #expect(collapseTarget == collapsed)
        #expect(collapseTarget < collapseStart) // positive motion delta the other way
    }

    @Test("mid-flight reverse: collapsing→expanding destination is still expanded")
    func midFlightReverseTargetsCorrectEnd() {
        let collapsed: CGFloat = 28
        let expanded: CGFloat = 92
        var state = RevealState.expanded
        state.beginCollapse()
        #expect(state.destinationHeight(collapsed: collapsed, expanded: expanded) == collapsed)
        // User re-hovers before finish — reverse direction.
        state.beginExpand()
        #expect(state.phase == .expanding)
        #expect(state.destinationHeight(collapsed: collapsed, expanded: expanded) == expanded)
    }
}
