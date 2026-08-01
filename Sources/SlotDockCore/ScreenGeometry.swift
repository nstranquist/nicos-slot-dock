import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#else
public typealias CGFloat = Double
public struct CGPoint: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
}
public struct CGRect: Equatable, Sendable {
    public var origin: CGPoint
    public var size: CGSize
    public init(origin: CGPoint, size: CGSize) { self.origin = origin; self.size = size }
    public var minX: CGFloat { origin.x }
    public var midX: CGFloat { origin.x + size.width / 2 }
    public var maxX: CGFloat { origin.x + size.width }
    public var minY: CGFloat { origin.y }
    public var maxY: CGFloat { origin.y + size.height }
    public func contains(_ p: CGPoint) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }
}
public struct CGSize: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat
    public init(width: CGFloat, height: CGFloat) { self.width = width; self.height = height }
}
#endif

/// Pure multi-display geometry helpers (unit-tested without AppKit).
public enum ScreenGeometry {
    public struct ScreenBox: Equatable, Sendable {
        public var frame: CGRect
        public var visibleFrame: CGRect
        public init(frame: CGRect, visibleFrame: CGRect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    /// Pick the screen whose frame contains the point; fallback to first.
    public static func screenIndex(containing point: CGPoint, screens: [ScreenBox]) -> Int {
        guard !screens.isEmpty else { return 0 }
        if let i = screens.firstIndex(where: { $0.frame.contains(point) }) {
            return i
        }
        // Nearest center
        var best = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (i, s) in screens.enumerated() {
            let cx = s.frame.midX
            let cy = (s.frame.minY + s.frame.maxY) / 2
            let dx = point.x - cx
            let dy = point.y - cy
            let d = dx * dx + dy * dy
            if d < bestDist {
                bestDist = d
                best = i
            }
        }
        return best
    }

    public enum Alignment: String, Sendable {
        case leading, center, trailing
    }

    /// Bottom-edge strip frame on a visible rect.
    public static func stripFrame(
        visible: CGRect,
        height: CGFloat,
        width: CGFloat,
        alignment: Alignment,
        horizontalMargin: CGFloat,
        bottomInset: CGFloat
    ) -> CGRect {
        // Never let the minimum desktop strip width overflow a narrow display
        // (Sidecar, portrait, or a small virtual display). On normal displays
        // this preserves the historical 200 pt minimum.
        let margin = horizontalMargin.isFinite ? max(0, horizontalMargin) : 0
        let availableWidth = max(1, visible.size.width - margin * 2)
        let requestedWidth = width.isFinite ? width : 200
        let w = min(max(requestedWidth, 200), availableWidth)
        let effectiveMargin = min(margin, max(0, (visible.size.width - w) / 2))
        let x: CGFloat
        switch alignment {
        case .leading:
            x = visible.minX + effectiveMargin
        case .center:
            x = visible.midX - w / 2
        case .trailing:
            x = visible.maxX - w - effectiveMargin
        }
        let inset = bottomInset.isFinite ? bottomInset : 0
        let safeHeight = height.isFinite ? max(0, height) : 0
        let y = visible.minY + inset
        return CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: w, height: safeHeight))
    }

    /// Whether pointer is near the bottom edge of the given visible frame (reveal hit test).
    public static func isNearBottomEdge(
        point: CGPoint,
        visible: CGRect,
        threshold: CGFloat,
        stripMidX: CGFloat,
        stripHalfWidth: CGFloat
    ) -> Bool {
        guard point.y <= visible.minY + threshold else { return false }
        return abs(point.x - stripMidX) < stripHalfWidth
    }
}
