import AppKit
import Foundation
import SlotDockCore

struct ResolvedSlotIcon {
    let image: NSImage
    /// Custom raster photos need a rounded clip. IconServices / icns / sidecar
    /// artwork already includes the macOS mask — clipping again mismatches Dock.
    let appliesMask: Bool
}

/// Process-wide icon cache so strip redraws (hover, flash, running dots) do not
/// re-hit `NSWorkspace` / disk for every frame.
enum SlotIconCache {
    /// NSCache is thread-safe; wrap for Swift 6 static Sendable checks.
    private final class Box: @unchecked Sendable {
        let cache: NSCache<NSString, BoxValue>
        let misses: NSCache<NSString, NSNumber>
        let lock = NSLock()

        init() {
            let cache = NSCache<NSString, BoxValue>()
            cache.countLimit = 512
            cache.totalCostLimit = 64 * 1024 * 1024
            self.cache = cache
            let misses = NSCache<NSString, NSNumber>()
            misses.countLimit = 512
            self.misses = misses
        }
    }

    private final class BoxValue: NSObject {
        let resolved: ResolvedSlotIcon
        init(_ resolved: ResolvedSlotIcon) { self.resolved = resolved }
    }

    private static let box = Box()

    static func image(for slot: Slot, pointSize: CGFloat, liveToken: String = "") -> NSImage? {
        resolved(for: slot, pointSize: pointSize, liveToken: liveToken)?.image
    }

    static func resolved(for slot: Slot, pointSize: CGFloat, liveToken: String = "") -> ResolvedSlotIcon? {
        let key = cacheKey(slot: slot, pointSize: pointSize, liveToken: liveToken) as NSString
        box.lock.lock()
        if let hit = box.cache.object(forKey: key) {
            box.lock.unlock()
            return hit.resolved
        }
        if box.misses.object(forKey: key) != nil {
            box.lock.unlock()
            return nil
        }
        box.lock.unlock()

        let resolved = SlotDockTelemetry.measure("icon.resolve", thresholdMS: 12) {
            resolveUncached(slot: slot, liveToken: liveToken).map { hintSize($0, pointSize: pointSize) }
        }
        guard let resolved else {
            box.lock.lock()
            box.misses.setObject(1, forKey: key)
            box.lock.unlock()
            SlotDockTelemetry.iconCache.debug("icon miss empty id=\(slot.id, privacy: .private)")
            return nil
        }
        box.lock.lock()
        box.misses.removeObject(forKey: key)
        let pixels = max(Int(resolved.image.size.width * resolved.image.size.height * 4), 1)
        box.cache.setObject(BoxValue(resolved), forKey: key, cost: pixels)
        box.lock.unlock()
        return resolved
    }

    static func invalidateAll() {
        box.lock.lock()
        box.cache.removeAllObjects()
        box.misses.removeAllObjects()
        box.lock.unlock()
        SlotDockTelemetry.iconCache.info("icon cache invalidated")
    }

    private static func cacheKey(slot: Slot, pointSize: CGFloat, liveToken: String) -> String {
        let icon = slot.iconPath ?? ""
        return "\(slot.id)|\(slot.target)|\(icon)|\(liveToken)|\(fileSignature(for: icon))|\(fileSignature(for: slot.target))|\(Int(pointSize * 2))"
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

    private static func resolveUncached(slot: Slot, liveToken: String) -> ResolvedSlotIcon? {
        if let custom = slot.iconPath, !custom.isEmpty {
            let path = (custom as NSString).expandingTildeInPath
            if let img = NSImage(contentsOfFile: path) {
                let ext = (path as NSString).pathExtension.lowercased()
                let isComposed = ext == "icns" || Self.hasTransparentCorners(img)
                return ResolvedSlotIcon(image: img, appliesMask: !isComposed)
            }
        }
        let request = LaunchResolver.resolve(slot: slot)
        if request.kind == .application, !request.resolvedTarget.isEmpty {
            if !liveToken.isEmpty,
               let sidecar = AppBundleIconResolver.image(at: request.resolvedTarget, token: liveToken)
            {
                return ResolvedSlotIcon(image: sidecar, appliesMask: false)
            }
            if let idle = AppBundleIconResolver.idleSidecarImage(at: request.resolvedTarget) {
                return ResolvedSlotIcon(image: idle, appliesMask: false)
            }
            // Electron packs a composed squircle as electron.icns. IconServices remasks it.
            if AppBundleIconResolver.prefersRawBundleIcon(at: request.resolvedTarget),
               let bundleIcon = AppBundleIconResolver.bundleIconFileImage(at: request.resolvedTarget)
            {
                return ResolvedSlotIcon(image: bundleIcon, appliesMask: false)
            }
            if let running = Self.runningIcon(forAppAt: request.resolvedTarget) {
                return ResolvedSlotIcon(image: running, appliesMask: false)
            }
            return ResolvedSlotIcon(
                image: NSWorkspace.shared.icon(forFile: request.resolvedTarget),
                appliesMask: false
            )
        }
        if request.kind == .file, !request.resolvedTarget.isEmpty {
            return ResolvedSlotIcon(
                image: NSWorkspace.shared.icon(forFile: request.resolvedTarget),
                appliesMask: false
            )
        }
        if request.kind == .url {
            let image = NSImage(systemSymbolName: "link", accessibilityDescription: slot.label)
            return image.map { ResolvedSlotIcon(image: $0, appliesMask: false) }
        }
        let fallback = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: slot.label)
        return fallback.map { ResolvedSlotIcon(image: $0, appliesMask: false) }
    }

    private static func runningIcon(forAppAt path: String) -> NSImage? {
        let canonical = SystemDockEntry.canonicalIdentityPath(path).lowercased()
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, !app.isTerminated else { continue }
            guard let appPath = app.bundleURL.map({ SystemDockEntry.canonicalIdentityPath($0.path) }) else {
                continue
            }
            if appPath.lowercased() == canonical {
                return app.icon
            }
        }
        return nil
    }

    /// Hint the drawing size without baking a 1× bitmap.
    private static func hintSize(_ resolved: ResolvedSlotIcon, pointSize: CGFloat) -> ResolvedSlotIcon {
        guard pointSize > 0 else { return resolved }
        let copy = resolved.image.copy() as? NSImage ?? resolved.image
        copy.size = NSSize(width: pointSize, height: pointSize)
        return ResolvedSlotIcon(image: copy, appliesMask: resolved.appliesMask)
    }

    private static func hasTransparentCorners(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            return false
        }
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 4, height > 4 else { return false }
        func alpha(_ x: Int, _ y: Int) -> CGFloat {
            rep.colorAt(x: x, y: y)?.alphaComponent ?? 1
        }
        return alpha(0, 0) < 0.05
            && alpha(width - 1, 0) < 0.05
            && alpha(0, height - 1) < 0.05
            && alpha(width - 1, height - 1) < 0.05
    }
}

/// Electron / multi-mode apps (ChatGPT ↔ Codex) ship a composed icns plus
/// `icon-<mode>.png` sidecars. The system Dock shows the live tile; IconServices
/// remasks `electron.icns` and looks slightly inset. Prefer the sidecar / raw
/// bundle icns when present.
enum AppBundleIconResolver {
    @MainActor
    static func liveTokensForRunningApps() -> [String: String] {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var tokens: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, !app.isTerminated else { continue }
            guard let path = app.bundleURL.map({ SystemDockEntry.canonicalIdentityPath($0.path) }),
                  path.lowercased().hasSuffix(".app"),
                  hasSidecarIcons(at: path)
            else { continue }
            let sidecars = sidecarURLs(at: path)
            let available = Set(sidecars.keys)
            if let bundle = app.bundleIdentifier,
               let defaultsToken = defaultsToken(bundleID: bundle, available: available, dark: dark),
               !defaultsToken.isEmpty
            {
                tokens[path.lowercased()] = defaultsToken
                continue
            }
            var titles = DockAXWindowTitles.titles(for: app)
            if let name = app.localizedName, !name.isEmpty { titles.append(name) }
            let token = DockIconSidecar.preferredToken(titles: titles, available: available, dark: dark)
            if !token.isEmpty {
                tokens[path.lowercased()] = token
            }
        }
        return tokens
    }

    static func hasSidecarIcons(at appPath: String) -> Bool {
        !sidecarURLs(at: appPath).isEmpty
    }

    static func prefersRawBundleIcon(at appPath: String) -> Bool {
        if hasSidecarIcons(at: appPath) { return true }
        let file = (Bundle(url: URL(fileURLWithPath: appPath))?.infoDictionary?["CFBundleIconFile"] as? String)?
            .lowercased() ?? ""
        let base = (file as NSString).deletingPathExtension
        return base == "electron" || base == "app"
    }

    static func idleSidecarImage(at appPath: String) -> NSImage? {
        let sidecars = sidecarURLs(at: appPath)
        guard !sidecars.isEmpty else { return nil }
        let name = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let token = DockIconSidecar.preferredToken(
            titles: [name],
            available: Set(sidecars.keys),
            dark: dark
        )
        guard !token.isEmpty, let url = sidecars[token] else { return nil }
        return NSImage(contentsOf: url)
    }

    static func defaultsToken(bundleID: String, available: Set<String>, dark: Bool) -> String? {
        guard let defaults = UserDefaults(suiteName: bundleID) else { return nil }
        if let resource = defaults.string(forKey: "DockIconResourceName"), !resource.isEmpty {
            let token = DockIconSidecar.token(fromResourceName: resource)
            if available.contains(token) { return token }
        }
        if let preference = defaults.string(forKey: "DockIconPreference"), !preference.isEmpty {
            let token = DockIconSidecar.preferredToken(
                titles: [preference],
                available: available,
                dark: dark
            )
            if !token.isEmpty { return token }
        }
        return nil
    }

    static func liveToken(at appPath: String, titles: [String], dark: Bool) -> String {
        let sidecars = sidecarURLs(at: appPath)
        guard !sidecars.isEmpty else { return "" }
        return DockIconSidecar.preferredToken(
            titles: titles,
            available: Set(sidecars.keys),
            dark: dark
        )
    }

    static func image(at appPath: String, token: String) -> NSImage? {
        guard !token.isEmpty, let url = sidecarURLs(at: appPath)[token.lowercased()] else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    static func bundleIconFileImage(at appPath: String) -> NSImage? {
        let resources = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Resources")
        guard let info = Bundle(url: URL(fileURLWithPath: appPath))?.infoDictionary else {
            return nil
        }
        if let file = info["CFBundleIconFile"] as? String, !file.isEmpty {
            let name = (file as NSString).pathExtension.isEmpty ? file + ".icns" : file
            let url = resources.appendingPathComponent(name)
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    private struct SidecarListing: Sendable {
        var urls: [String: URL]
        var mtime: TimeInterval
    }

    private static let sidecarLock = NSLock()
    private nonisolated(unsafe) static var sidecarCache: [String: SidecarListing] = [:]

    private static func sidecarURLs(at appPath: String) -> [String: URL] {
        let resources = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Resources")
        let mtime = (try? FileManager.default.attributesOfItem(atPath: resources.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        sidecarLock.lock()
        if let hit = sidecarCache[appPath], hit.mtime == mtime {
            let urls = hit.urls
            sidecarLock.unlock()
            return urls
        }
        sidecarLock.unlock()

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: resources,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [:] }
        var out: [String: URL] = [:]
        for url in files {
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            let ext = url.pathExtension.lowercased()
            guard ext == "png" || ext == "icns" else { continue }
            guard name.hasPrefix("icon-") else { continue }
            let token = String(name.dropFirst("icon-".count))
            guard !token.isEmpty else { continue }
            // Prefer icns over png when both exist.
            if let existing = out[token], existing.pathExtension.lowercased() == "icns" {
                continue
            }
            out[token] = url
        }
        sidecarLock.lock()
        sidecarCache[appPath] = SidecarListing(urls: out, mtime: mtime)
        sidecarLock.unlock()
        return out
    }
}
