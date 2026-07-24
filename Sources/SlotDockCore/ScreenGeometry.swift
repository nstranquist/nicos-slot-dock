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
        let w = min(max(width, 200), max(200, visible.size.width - horizontalMargin * 2))
        let x: CGFloat
        switch alignment {
        case .leading:
            x = visible.minX + horizontalMargin
        case .center:
            x = visible.midX - w / 2
        case .trailing:
            x = visible.maxX - w - horizontalMargin
        }
        let y = visible.minY + bottomInset
        return CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: w, height: height))
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
