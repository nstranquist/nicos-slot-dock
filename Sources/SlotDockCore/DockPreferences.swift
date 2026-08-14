import Foundation

/// User-tunable dock behavior. Pure, headless, persisted with slots.
public struct DockPreferences: Codable, Equatable, Sendable {
    public enum IconSize: String, Codable, CaseIterable, Sendable {
        case small
        case medium
        case large

        public var pointSize: CGFloat {
            switch self {
            case .small: return 36
            case .medium: return 44
            case .large: return 52
            }
        }

        public var displayName: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }
    }

    public enum Alignment: String, Codable, CaseIterable, Sendable {
        case leading
        case center
        case trailing

        public var displayName: String {
            switch self {
            case .leading: return "Left"
            case .center: return "Center"
            case .trailing: return "Right"
            }
        }
    }

    /// Icon size on the strip.
    public var iconSize: IconSize
    /// Collapse after cursor leaves (when not pinned).
    public var autoHide: Bool
    /// Seconds before auto-hide fires after pointer leaves (0.1…3).
    public var autoHideDelay: Double
    /// Extra points outside the strip frame that still count as “hovering”
    /// (above/around the dock). Leave margin only; when the pointer exits this
    /// expanded rect the auto-hide delay timer arms. Prior hard-coded 8 pt.
    public var autoHideLeaveMargin: Double
    /// Keep strip expanded until user collapses.
    public var pinOpen: Bool
    /// Reveal when cursor nears the bottom edge.
    public var edgeHover: Bool
    /// Vertical hit-zone height (points) for edge-hover reveal when collapsed/auto-hidden.
    /// Also drives the collapsed tab chrome height so the visual bar matches the hit zone.
    public var edgeTriggerHeight: Double
    /// Extra lateral margin (points) beyond half strip width for bottom-edge hover hit.
    /// Live path is `stripWidth/2 + edgeHorizontalOvershoot` (prior hard-coded +48).
    public var edgeHorizontalOvershoot: Double
    /// Full expand/collapse travel base duration in seconds (prior hard-coded 0.22).
    /// Remaining distance still scales duration down from this base.
    public var revealBaseDuration: Double
    /// Inter-icon spacing on the strip when labels are off (prior hard-coded 8).
    /// With labels, effective spacing is this value + `iconSpacingLabelsExtra` (prior 10).
    public var iconSpacing: Double
    /// Show label under each icon on the strip.
    public var showLabels: Bool
    /// Show native hover tooltips on strip icons (performant NSView.toolTip).
    public var showIconTooltips: Bool
    /// Horizontal placement along the bottom edge.
    public var alignment: Alignment
    /// Soft scale/press feedback when launching.
    public var launchFeedback: Bool
    /// Remappable shortcuts (menu + optional global).
    public var hotkeys: DockHotkeys
    /// Show the menu-bar status item (right side of the bar). Off = strip only.
    public var showStatusItem: Bool
    /// Keep the strip visible in macOS full-screen Spaces.
    public var showInFullScreen: Bool
    /// Honor system macOS Dock apps: off / merge (default) / mirror.
    public var systemDockIntegration: SystemDockIntegration
    /// In merge mode, draw a divider between custom slots and system Dock apps.
    public var showSystemDockDivider: Bool
    /// Show a minimal running-app dot under open apps.
    public var showRunningDots: Bool
    /// Overlay Mac Dock notification badges (counts / unread marks) on strip icons.
    public var showNotificationBadges: Bool
    /// Opt-in: append running GUI apps not already on the strip (event-driven, ephemeral).
    public var showTransientRunningApps: Bool
    /// Opt-in: inset overlapping windows so content clears the Nicos Slot Dock strip.
    public var safeAreaPadding: Bool
    /// Extra points above the strip when safe-area padding is active.
    public var safeAreaExtraGap: Double
    /// User dismissed the one-shot collision compatibility prompt.
    public var collisionGuideDismissed: Bool
    /// Desired login-item state (default off — never autostart without opt-in).
    /// Applied via SMAppService when running as a real app bundle.
    public var launchAtLogin: Bool

    public init(
        iconSize: IconSize = .medium,
        autoHide: Bool = true,
        autoHideDelay: Double = 0.85,
        autoHideLeaveMargin: Double = Self.defaultAutoHideLeaveMargin,
        pinOpen: Bool = false,
        edgeHover: Bool = true,
        edgeTriggerHeight: Double = Self.defaultEdgeTriggerHeight,
        edgeHorizontalOvershoot: Double = Self.defaultEdgeHorizontalOvershoot,
        revealBaseDuration: Double = Self.defaultRevealBaseDuration,
        iconSpacing: Double = Self.defaultIconSpacing,
        showLabels: Bool = false,
        showIconTooltips: Bool = true,
        alignment: Alignment = .center,
        launchFeedback: Bool = true,
        hotkeys: DockHotkeys = .default,
        showStatusItem: Bool = true,
        showInFullScreen: Bool = true,
        systemDockIntegration: SystemDockIntegration = .merge,
        showSystemDockDivider: Bool = true,
        showRunningDots: Bool = true,
        showNotificationBadges: Bool = true,
        showTransientRunningApps: Bool = false,
        safeAreaPadding: Bool = false,
        safeAreaExtraGap: Double = 8,
        collisionGuideDismissed: Bool = false,
        launchAtLogin: Bool = false
    ) {
        self.iconSize = iconSize
        self.autoHide = autoHide
        self.autoHideDelay = Self.clampDelay(autoHideDelay)
        self.autoHideLeaveMargin = Self.clampAutoHideLeaveMargin(autoHideLeaveMargin)
        self.pinOpen = pinOpen
        self.edgeHover = edgeHover
        self.edgeTriggerHeight = Self.clampEdgeTriggerHeight(edgeTriggerHeight)
        self.edgeHorizontalOvershoot = Self.clampEdgeHorizontalOvershoot(edgeHorizontalOvershoot)
        self.revealBaseDuration = Self.clampRevealBaseDuration(revealBaseDuration)
        self.iconSpacing = Self.clampIconSpacing(iconSpacing)
        self.showLabels = showLabels
        self.showIconTooltips = showIconTooltips
        self.alignment = alignment
        self.launchFeedback = launchFeedback
        self.hotkeys = hotkeys
        self.showStatusItem = showStatusItem
        self.showInFullScreen = showInFullScreen
        self.systemDockIntegration = systemDockIntegration
        self.showSystemDockDivider = showSystemDockDivider
        self.showRunningDots = showRunningDots
        self.showNotificationBadges = showNotificationBadges
        self.showTransientRunningApps = showTransientRunningApps
        self.safeAreaPadding = safeAreaPadding
        self.safeAreaExtraGap = Self.clampSafeAreaExtraGap(safeAreaExtraGap)
        self.collisionGuideDismissed = collisionGuideDismissed
        self.launchAtLogin = launchAtLogin
    }

    public static let `default` = DockPreferences()

    /// Minimum hide delay (snappy). Below this is clamped; 0 is not allowed (would thrash with every mouse sample).
    public static let minAutoHideDelay: Double = 0.1
    public static let maxAutoHideDelay: Double = 3.0

    /// Prior hard-coded leave grace zone around the strip (`insetBy(dx: -8, dy: -8)`).
    public static let defaultAutoHideLeaveMargin: Double = 8
    /// Logical minimum: leave as soon as the pointer exits the exact strip frame.
    public static let minAutoHideLeaveMargin: Double = 0
    /// Soft max: large grace zone without owning most of the display.
    public static let maxAutoHideLeaveMargin: Double = 64

    /// Prior hard-coded bottom-edge hit height (and collapsed tab chrome).
    public static let defaultEdgeTriggerHeight: Double = 28
    /// Logical minimum: 1 pt still forms a hit band; 0 would only match the exact edge.
    public static let minEdgeTriggerHeight: Double = 1
    /// Soft max ≈ quarter of a short laptop height — tall hit zone without owning the display.
    public static let maxEdgeTriggerHeight: Double = 200

    /// Prior hard-coded lateral hit overshoot (`stripHalf + 48`).
    public static let defaultEdgeHorizontalOvershoot: Double = 48
    /// Logical minimum: no extra lateral margin beyond half strip width.
    public static let minEdgeHorizontalOvershoot: Double = 0
    /// Soft max ≈ half of a wide strip (~480 pt) so overshoot cannot exceed a full strip width alone.
    public static let maxEdgeHorizontalOvershoot: Double = 240

    /// Prior hard-coded reveal travel base duration.
    public static let defaultRevealBaseDuration: Double = 0.22
    /// Logical minimum: 0 = snap (no animation). Live path treats `base <= 0` as instant.
    public static let minRevealBaseDuration: Double = 0
    /// Soft max: multi-second full travel is still intentional; beyond is accidental.
    public static let maxRevealBaseDuration: Double = 2.0
    /// Below this resolved duration the window snaps (animator is useless / janky).
    public static let revealSnapDurationThreshold: Double = 0.02

    /// Prior hard-coded unlabeled icon spacing; labels use base + `iconSpacingLabelsExtra`.
    public static let defaultIconSpacing: Double = 8
    /// Logical minimum: icons may touch (0 pt gap).
    public static let minIconSpacing: Double = 0
    /// Soft max: extreme density for oversized icons / labeled strips.
    public static let maxIconSpacing: Double = 48
    /// Fixed delta so default labeled spacing stays 10 when base is 8.
    public static let iconSpacingLabelsExtra: Double = 2

    /// Outer vertical chrome pad around the icon row when labels are off (prior hard-coded 10).
    public static let chromePadWithoutLabels: Double = 10
    /// Outer vertical chrome pad when labels are on (prior hard-coded 8).
    public static let chromePadWithLabels: Double = 8
    /// Label row height contribution to expanded strip (prior hard-coded 14).
    public static let labelRowHeight: Double = 14
    /// Running-dot row height contribution (prior hard-coded 6).
    public static let runningDotRowHeight: Double = 6
    /// Extra chrome under the icon stack in the window height (prior hard-coded 28).
    public static let expandedChromeExtra: Double = 28

    public static func clampDelay(_ value: Double) -> Double {
        clamp(value, fallback: 0.85, lower: minAutoHideDelay, upper: maxAutoHideDelay)
    }

    public static func clampAutoHideLeaveMargin(_ value: Double) -> Double {
        clamp(value, fallback: defaultAutoHideLeaveMargin, lower: minAutoHideLeaveMargin, upper: maxAutoHideLeaveMargin)
    }

    public static func clampEdgeTriggerHeight(_ value: Double) -> Double {
        clamp(value, fallback: defaultEdgeTriggerHeight, lower: minEdgeTriggerHeight, upper: maxEdgeTriggerHeight)
    }

    public static func clampEdgeHorizontalOvershoot(_ value: Double) -> Double {
        clamp(value, fallback: defaultEdgeHorizontalOvershoot, lower: minEdgeHorizontalOvershoot, upper: maxEdgeHorizontalOvershoot)
    }

    public static func clampRevealBaseDuration(_ value: Double) -> Double {
        clamp(value, fallback: defaultRevealBaseDuration, lower: minRevealBaseDuration, upper: maxRevealBaseDuration)
    }

    public static func clampIconSpacing(_ value: Double) -> Double {
        clamp(value, fallback: defaultIconSpacing, lower: minIconSpacing, upper: maxIconSpacing)
    }

    public static func clampSafeAreaExtraGap(_ value: Double) -> Double {
        clamp(value, fallback: 8, lower: 0, upper: 40)
    }

    private static func clamp(_ value: Double, fallback: Double, lower: Double, upper: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(upper, max(lower, value))
    }

    /// Lateral half-width for `isNearBottomEdge` — strip half plus overshoot.
    public static func edgeHitHalfWidth(stripWidth: CGFloat, overshoot: Double) -> CGFloat {
        stripWidth / 2 + CGFloat(clampEdgeHorizontalOvershoot(overshoot))
    }

    /// Bottom-aligned content rect inside the dock window (AppKit bottom-left origin).
    /// Matches DockChrome's bottom-aligned strip; ignores the top Spacer dead zone.
    public static func bottomAlignedContentFrame(
        windowFrame: CGRect,
        contentHeight: CGFloat
    ) -> CGRect {
        let h = max(0, min(contentHeight, windowFrame.height))
        return CGRect(
            x: windowFrame.minX,
            y: windowFrame.minY,
            width: windowFrame.width,
            height: h
        )
    }

    /// Expanded hover frame around a base rect. Pointer inside still counts as
    /// “over the dock”; leaving arms the auto-hide delay timer.
    public static func pointerOverStripFrame(windowFrame: CGRect, leaveMargin: Double) -> CGRect {
        let m = CGFloat(clampAutoHideLeaveMargin(leaveMargin))
        return windowFrame.insetBy(dx: -m, dy: -m)
    }

    /// Whether `point` is still within the leave-margin hover zone.
    ///
    /// Pass `contentHeight` (visible bar height) so leave margin is measured from the
    /// **icons/chrome**, not the full window that includes a top Spacer (~28 pt).
    /// Without that, leave margin 2 vs 8 is almost indistinguishable.
    public static func isPointerOverStrip(
        point: CGPoint,
        windowFrame: CGRect,
        leaveMargin: Double,
        contentHeight: CGFloat? = nil
    ) -> Bool {
        let base: CGRect
        if let contentHeight {
            base = bottomAlignedContentFrame(windowFrame: windowFrame, contentHeight: contentHeight)
        } else {
            base = windowFrame
        }
        return pointerOverStripFrame(windowFrame: base, leaveMargin: leaveMargin).contains(point)
    }

    /// Distance-scaled expand/collapse duration.
    ///
    /// - `base <= 0` → 0 (snap; caller skips the animator).
    /// - Full travel (`heightFraction` 1) → `base`.
    /// - Short reverse mid-flight → down to `0.4 * base` (no hard 0.07 floor that
    ///   used to make low base values feel stuck at the old minimum).
    public static func scaledRevealDuration(base: Double, heightFraction: Double) -> Double {
        let b = clampRevealBaseDuration(base)
        if b <= 0 { return 0 }
        let f = min(1.0, max(0.0, heightFraction))
        return b * (0.4 + 0.6 * f)
    }

    /// Whether a resolved duration should snap instead of animating.
    public static func shouldSnapReveal(duration: Double) -> Bool {
        duration < revealSnapDurationThreshold
    }

    /// Effective inter-icon spacing (labels get a fixed extra for the prior 8/10 pair).
    public func effectiveIconSpacing() -> CGFloat {
        CGFloat(iconSpacing) + (showLabels ? Self.iconSpacingLabelsExtra : 0)
    }

    /// Outer vertical pad around icons (not inter-icon spacing). Shared by strip chrome + window height.
    public func chromeVerticalPad() -> CGFloat {
        CGFloat(showLabels ? Self.chromePadWithLabels : Self.chromePadWithoutLabels)
    }

    /// Visible icon-bar height only (no window animation spacer). Pure for leave hit-tests.
    public func contentBarHeight() -> CGFloat {
        let icon = iconSize.pointSize
        let pad = chromeVerticalPad()
        let labels: CGFloat = showLabels ? CGFloat(Self.labelRowHeight) : 0
        let dots: CGFloat = showRunningDots ? CGFloat(Self.runningDotRowHeight) : 0
        return icon + pad * 2 + labels + dots
    }

    /// Expanded strip window height (content bar + animation chrome extra). Pure for layout.
    public func expandedStripHeight() -> CGFloat {
        contentBarHeight() + CGFloat(Self.expandedChromeExtra)
    }

    /// Icon-row contribution to strip width (count × (icon + spacing)). Pure for tests.
    public static func stripIconsWidth(count: Int, iconSize: CGFloat, spacing: CGFloat) -> CGFloat {
        CGFloat(max(count, 1)) * (iconSize + spacing)
    }

    /// Normalize after decode (clamp delay, fix bad values).
    public mutating func sanitize() {
        autoHideDelay = Self.clampDelay(autoHideDelay)
        autoHideLeaveMargin = Self.clampAutoHideLeaveMargin(autoHideLeaveMargin)
        edgeTriggerHeight = Self.clampEdgeTriggerHeight(edgeTriggerHeight)
        edgeHorizontalOvershoot = Self.clampEdgeHorizontalOvershoot(edgeHorizontalOvershoot)
        revealBaseDuration = Self.clampRevealBaseDuration(revealBaseDuration)
        iconSpacing = Self.clampIconSpacing(iconSpacing)
        safeAreaExtraGap = Self.clampSafeAreaExtraGap(safeAreaExtraGap)
        hotkeys.sanitize()
        // Never let a user strand an auto-hidden strip with every recovery
        // affordance disabled. The status item is the durable fallback when
        // edge hover and all shortcuts are off.
        if autoHide && !pinOpen && !edgeHover && !showStatusItem && !hotkeys.hasEnabledBinding {
            showStatusItem = true
        }
    }

    // Backward-compatible decode for fields added after v1.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        iconSize = try c.decodeIfPresent(IconSize.self, forKey: .iconSize) ?? .medium
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? true
        autoHideDelay = Self.clampDelay(try c.decodeIfPresent(Double.self, forKey: .autoHideDelay) ?? 0.85)
        autoHideLeaveMargin = Self.clampAutoHideLeaveMargin(
            try c.decodeIfPresent(Double.self, forKey: .autoHideLeaveMargin) ?? Self.defaultAutoHideLeaveMargin
        )
        pinOpen = try c.decodeIfPresent(Bool.self, forKey: .pinOpen) ?? false
        edgeHover = try c.decodeIfPresent(Bool.self, forKey: .edgeHover) ?? true
        edgeTriggerHeight = Self.clampEdgeTriggerHeight(
            try c.decodeIfPresent(Double.self, forKey: .edgeTriggerHeight) ?? Self.defaultEdgeTriggerHeight
        )
        edgeHorizontalOvershoot = Self.clampEdgeHorizontalOvershoot(
            try c.decodeIfPresent(Double.self, forKey: .edgeHorizontalOvershoot) ?? Self.defaultEdgeHorizontalOvershoot
        )
        revealBaseDuration = Self.clampRevealBaseDuration(
            try c.decodeIfPresent(Double.self, forKey: .revealBaseDuration) ?? Self.defaultRevealBaseDuration
        )
        iconSpacing = Self.clampIconSpacing(
            try c.decodeIfPresent(Double.self, forKey: .iconSpacing) ?? Self.defaultIconSpacing
        )
        showLabels = try c.decodeIfPresent(Bool.self, forKey: .showLabels) ?? false
        showIconTooltips = try c.decodeIfPresent(Bool.self, forKey: .showIconTooltips) ?? true
        alignment = try c.decodeIfPresent(Alignment.self, forKey: .alignment) ?? .center
        launchFeedback = try c.decodeIfPresent(Bool.self, forKey: .launchFeedback) ?? true
        hotkeys = try c.decodeIfPresent(DockHotkeys.self, forKey: .hotkeys) ?? .default
        showStatusItem = try c.decodeIfPresent(Bool.self, forKey: .showStatusItem) ?? true
        showInFullScreen = try c.decodeIfPresent(Bool.self, forKey: .showInFullScreen) ?? true
        systemDockIntegration = try c.decodeIfPresent(SystemDockIntegration.self, forKey: .systemDockIntegration) ?? .merge
        showSystemDockDivider = try c.decodeIfPresent(Bool.self, forKey: .showSystemDockDivider) ?? true
        showRunningDots = try c.decodeIfPresent(Bool.self, forKey: .showRunningDots) ?? true
        showNotificationBadges = try c.decodeIfPresent(Bool.self, forKey: .showNotificationBadges) ?? true
        showTransientRunningApps = try c.decodeIfPresent(Bool.self, forKey: .showTransientRunningApps) ?? false
        safeAreaPadding = try c.decodeIfPresent(Bool.self, forKey: .safeAreaPadding) ?? false
        safeAreaExtraGap = try c.decodeIfPresent(Double.self, forKey: .safeAreaExtraGap) ?? 8
        collisionGuideDismissed = try c.decodeIfPresent(Bool.self, forKey: .collisionGuideDismissed) ?? false
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        sanitize()
    }

    private enum CodingKeys: String, CodingKey {
        case iconSize, autoHide, autoHideDelay, autoHideLeaveMargin, pinOpen, edgeHover, edgeTriggerHeight
        case edgeHorizontalOvershoot, revealBaseDuration, iconSpacing
        case showLabels, showIconTooltips, alignment, launchFeedback, hotkeys, showStatusItem, showInFullScreen
        case systemDockIntegration, showSystemDockDivider
        case showRunningDots, showNotificationBadges, showTransientRunningApps
        case safeAreaPadding, safeAreaExtraGap, collisionGuideDismissed
        case launchAtLogin
    }
}

#if canImport(CoreGraphics)
import CoreGraphics
#else
public typealias CGFloat = Double
#endif
