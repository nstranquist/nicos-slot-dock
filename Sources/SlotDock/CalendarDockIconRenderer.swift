import AppKit
import SlotDockCore

/// Draws a Calendar-style dock tile with today's month and day.
///
/// Apple's Dock loads `Calendar.docktileplugin` into the Dock process. There is no
/// supported way to reuse that plugin for another app's tile, and Icon Services
/// still returns the static JUL 17 marketing icon.
enum CalendarDockIconRenderer {
    static func image(caption: CalendarDockIcon.Caption, pointSize: CGFloat) -> NSImage {
        let size = max(pointSize, 16)
        let canvas = NSSize(width: size, height: size)
        return NSImage(size: canvas, flipped: true) { rect in
            draw(caption: caption, in: rect)
            return true
        }
    }

    static func draw(caption: CalendarDockIcon.Caption, in rect: NSRect) {
        let radius = min(rect.width, rect.height) * 0.2237
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.addClip()

        NSColor.white.setFill()
        rect.fill()

        let headerHeight = rect.height * (rect.height < 72 ? 0.32 : 0.29)
        let header = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerHeight)
        let headerTop = NSColor(srgbRed: 1.0, green: 0.353, blue: 0.306, alpha: 1)
        let headerBottom = NSColor(srgbRed: 0.937, green: 0.267, blue: 0.224, alpha: 1)
        NSGradient(starting: headerTop, ending: headerBottom)?.draw(in: header, angle: 90)

        NSColor.black.withAlphaComponent(0.08).setFill()
        NSRect(x: rect.minX, y: header.maxY, width: rect.width, height: 1).fill()

        let monthStyle = NSMutableParagraphStyle()
        monthStyle.alignment = .center
        monthStyle.lineBreakMode = .byClipping
        let monthSize = max(6.5, headerHeight * 0.42)
        let monthAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: monthSize, weight: .semibold),
            .foregroundColor: NSColor.white,
            .kern: max(0.35, monthSize * 0.08),
            .paragraphStyle: monthStyle,
        ]
        let monthRect = header.insetBy(dx: rect.width * 0.06, dy: headerHeight * 0.16)
        (caption.month as NSString).draw(in: monthRect, withAttributes: monthAttrs)

        let body = NSRect(
            x: rect.minX,
            y: header.maxY,
            width: rect.width,
            height: rect.height - headerHeight
        )
        let dayStyle = NSMutableParagraphStyle()
        dayStyle.alignment = .center
        dayStyle.lineBreakMode = .byClipping
        let daySize = max(11, body.height * 0.64)
        let dayWeight: NSFont.Weight = rect.height < 48 ? .regular : .light
        let dayAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: daySize, weight: dayWeight),
            .foregroundColor: NSColor(srgbRed: 0.165, green: 0.165, blue: 0.173, alpha: 1),
            .kern: caption.day.count > 1 ? -daySize * 0.04 : 0,
            .paragraphStyle: dayStyle,
        ]
        var dayRect = body.insetBy(dx: rect.width * 0.08, dy: body.height * 0.06)
        dayRect.origin.y -= body.height * 0.03
        (caption.day as NSString).draw(in: dayRect, withAttributes: dayAttrs)
    }
}
