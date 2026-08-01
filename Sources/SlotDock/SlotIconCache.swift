import AppKit
import Foundation
import SlotDockCore

/// Process-wide icon cache so strip redraws (hover, flash, running dots) do not
/// re-hit `NSWorkspace` / disk for every frame.
enum SlotIconCache {
    /// NSCache is thread-safe; wrap for Swift 6 static Sendable checks.
    private final class Box: @unchecked Sendable {
        let cache: NSCache<NSString, NSImage>
        let misses: NSCache<NSString, NSNumber>
        let lock = NSLock()

        init() {
            let cache = NSCache<NSString, NSImage>()
            cache.countLimit = 512
            cache.totalCostLimit = 64 * 1024 * 1024
            self.cache = cache
            let misses = NSCache<NSString, NSNumber>()
            misses.countLimit = 512
            self.misses = misses
        }
    }

    private static let box = Box()

    static func image(for slot: Slot, pointSize: CGFloat) -> NSImage? {
        let key = cacheKey(slot: slot, pointSize: pointSize) as NSString
        box.lock.lock()
        if let hit = box.cache.object(forKey: key) {
            box.lock.unlock()
            return hit
        }
        if box.misses.object(forKey: key) != nil {
            box.lock.unlock()
            return nil
        }
        box.lock.unlock()

        // Miss path only — measure slow icon resolves for perf dogfood.
        // IconServices cold path is often 5–15ms; only flag real slowness.
        let image = SlotDockTelemetry.measure("icon.resolve", thresholdMS: 12) {
            resolveUncached(slot: slot)
        }
        guard let image else {
            box.lock.lock()
            box.misses.setObject(1, forKey: key)
            box.lock.unlock()
            SlotDockTelemetry.iconCache.debug("icon miss empty id=\(slot.id, privacy: .private)")
            return nil
        }
        let sized = sizedImage(image, pointSize: pointSize)
        box.lock.lock()
        box.misses.removeObject(forKey: key)
        let pixels = max(Int(sized.size.width * sized.size.height * 4), 1)
        box.cache.setObject(sized, forKey: key, cost: pixels)
        box.lock.unlock()
        return sized
    }

    static func invalidateAll() {
        box.lock.lock()
        box.cache.removeAllObjects()
        box.misses.removeAllObjects()
        box.lock.unlock()
        SlotDockTelemetry.iconCache.info("icon cache invalidated")
    }

    private static func cacheKey(slot: Slot, pointSize: CGFloat) -> String {
        let icon = slot.iconPath ?? ""
        return "\(slot.id)|\(slot.target)|\(icon)|\(fileSignature(for: icon))|\(fileSignature(for: slot.target))|\(Int(pointSize * 2))"
    }

    /// Include enough file identity to invalidate an icon when an app or
    /// custom image is replaced at the same path. Missing paths get a stable
    /// negative-cache key and are retried automatically when they appear.
    private static func fileSignature(for rawPath: String) -> String {
        let path = (rawPath as NSString).expandingTildeInPath
        guard path.hasPrefix("/"),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        else { return "missing" }
        let size = attributes[.size] as? NSNumber
        let modified = attributes[.modificationDate] as? Date
        let inode = attributes[.systemFileNumber] as? NSNumber
        return "\(inode?.int64Value ?? -1):\(size?.int64Value ?? -1):\(modified?.timeIntervalSince1970 ?? -1)"
    }

    private static func resolveUncached(slot: Slot) -> NSImage? {
        if let custom = slot.iconPath, !custom.isEmpty {
            let path = (custom as NSString).expandingTildeInPath
            if let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        let request = LaunchResolver.resolve(slot: slot)
        if request.kind == .application || request.kind == .file, !request.resolvedTarget.isEmpty {
            return NSWorkspace.shared.icon(forFile: request.resolvedTarget)
        }
        if request.kind == .url {
            return NSImage(systemSymbolName: "link", accessibilityDescription: slot.label)
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: slot.label)
    }

    private static func sizedImage(_ image: NSImage, pointSize: CGFloat) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        if image.size.width == size.width && image.size.height == size.height {
            return image
        }
        let copy = NSImage(size: size)
        copy.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        copy.unlockFocus()
        return copy
    }
}
