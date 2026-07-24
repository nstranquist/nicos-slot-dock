import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import SlotDockCore

/// Applies / restores window frames per SafeAreaPlanner ledger. Fail-soft without Accessibility.
///
/// Window identity uses **CGWindowNumber** (`pid:windowNumber`), which is stable for a
/// window’s lifetime — not AX enumeration index (which shifts when windows close).
@MainActor
final class SafeAreaController {
    private(set) var ledger: [String: PadRecord] = [:]
    private(set) var lastError: String?
    /// Avoid log spam: emit blocked-trust once until process is trusted (or option off).
    private var didLogTrustBlocked = false
    private var ownBundleID: String {
        Bundle.main.bundleIdentifier ?? "com.nstranquist.nicos-slot-dock"
    }
    private var ownPID: pid_t { ProcessInfo.processInfo.processIdentifier }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt once for Accessibility (user must enable in System Settings).
    func requestTrustIfNeeded() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Sync padding to current need + strip height.
    func sync(
        need: SafeAreaNeed,
        padHeight: CGFloat,
        extraGap: CGFloat,
        screen: NSScreen?
    ) {
        lastError = nil
        guard need == .active || !ledger.isEmpty else { return }

        if need == .active && !isTrusted {
            lastError = "Accessibility permission required for window safe-area padding."
            if !didLogTrustBlocked {
                didLogTrustBlocked = true
                SlotDockTelemetry.windowing.info(
                    "Safe-area blocked: no Accessibility trust (further blocks quiet until granted)"
                )
            }
            return
        }
        if isTrusted {
            didLogTrustBlocked = false
        }

        let screen = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let band = ScreenBottomBand(
            visibleFrame: screen.visibleFrame,
            padHeight: padHeight,
            extraGap: extraGap
        )

        // Always enumerate when we have ledger entries to restore (need.none) or apply.
        let (windows, plan) = SlotDockTelemetry.measure("SafeArea.plan", thresholdMS: 2) {
            let windows = enumerateWindows(on: screen)
            let plan = SafeAreaPlanner.plan(
                need: need,
                windows: windows,
                band: band,
                ledger: ledger
            )
            return (windows, plan)
        }

        for item in plan.restore {
            setFrame(windowID: item.windowID, frame: item.to)
        }
        for item in plan.apply {
            setFrame(windowID: item.windowID, frame: item.to)
        }
        ledger = plan.nextLedger
        SlotDockTelemetry.windowing.info(
            "Safe-area need=\(need.rawValue, privacy: .public) windows=\(windows.count, privacy: .public) apply=\(plan.apply.count, privacy: .public) restore=\(plan.restore.count, privacy: .public) ledger=\(self.ledger.count, privacy: .public)"
        )
    }

    /// Force restore everything we ever padded (option off / quit).
    func restoreAllTracked() {
        let count = ledger.count
        guard count > 0 else { return }
        let plan = SafeAreaPlanner.restoreAll(ledger: ledger)
        for item in plan.restore {
            setFrame(windowID: item.windowID, frame: item.to)
        }
        ledger = [:]
        lastError = nil
        SlotDockTelemetry.windowing.info(
            "Safe-area restoreAll count=\(count, privacy: .public)"
        )
    }

    // MARK: - Enumeration (CGWindowNumber-stable IDs)

    private func enumerateWindows(on screen: NSScreen) -> [WindowFrameSnapshot] {
        let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let screenFrame = screen.frame
        var result: [WindowFrameSnapshot] = []

        for entry in info {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t else { continue }
            if pid == ownPID { continue }
            guard let windowNumber = entry[kCGWindowNumber as String] as? Int else { continue }
            guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat
            else { continue }
            if w < 80 || h < 80 { continue }

            // CG bounds are top-left global; convert to AppKit bottom-left for planner.
            let frame = cgBoundsToAppKit(x: x, y: y, width: w, height: h)
            if !framesOverlap(frame, screenFrame) { continue }

            let owner = entry[kCGWindowOwnerName as String] as? String
            // Skip system UI chrome loosely
            if owner == "Window Server" || owner == "Dock" { continue }

            let id = WindowIdentity.makeID(pid: pid, windowNumber: windowNumber)
            let bundle = bundleID(forPID: pid)
            result.append(WindowFrameSnapshot(id: id, frame: frame, bundleIdentifier: bundle))
        }
        return result
    }

    private func bundleID(forPID pid: pid_t) -> String? {
        NSWorkspace.shared.runningApplications.first { $0.processIdentifier == pid }?.bundleIdentifier
    }

    /// CG window list Y is top-left of primary; AppKit uses bottom-left.
    private func cgBoundsToAppKit(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let primary else {
            return CGRect(x: x, y: y, width: width, height: height)
        }
        // Main display: AppKit y = primaryHeight - cgY - height (for primary-origin screens).
        // For multi-monitor, CG global coords: use primary.frame.maxY as reference when origin is zero.
        let appKitY = primary.frame.maxY - y - height
        return CGRect(x: x, y: appKitY, width: width, height: height)
    }

    // MARK: - Apply via AX, match by CGWindowNumber identity

    private func setFrame(windowID: String, frame: CGRect) {
        guard isTrusted else { return }
        guard let identity = WindowIdentity.parse(windowID) else { return }
        guard let axWindow = findAXWindow(pid: identity.pid, windowNumber: identity.windowNumber)
                ?? findAXWindowByFrame(pid: identity.pid, approximate: frame)
        else { return }

        // AX position is top-left global
        let primary = NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let primary else { return }
        var axPos = CGPoint(x: frame.minX, y: primary.frame.maxY - frame.maxY)
        var axSize = CGSize(width: frame.width, height: frame.height)
        if let posVal = AXValueCreate(.cgPoint, &axPos) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &axSize) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeVal)
        }
    }

    /// Prefer matching AX window that reports the same CG window number when available.
    private func findAXWindow(pid: pid_t, windowNumber: Int) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return nil }

        // Try kAXWindowNumberAttribute if present (private but widely works).
        // Prefer NSNumber bridging over CFNumber cast (avoids unsafeBitCast warnings).
        let numberKey = "AXWindowNumber" as CFString
        for win in windows {
            var numRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(win, numberKey, &numRef) == .success,
                  let numRef
            else { continue }
            if let n = numRef as? Int, n == windowNumber {
                return win
            }
            if let n = numRef as? NSNumber, n.intValue == windowNumber {
                return win
            }
        }
        return nil
    }

    /// Fallback: match by AppKit frame proximity (for restores after pad).
    private func findAXWindowByFrame(pid: pid_t, approximate: CGRect) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return nil }

        var best: AXUIElement?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for win in windows {
            guard let f = axFrameAppKit(win) else { continue }
            let dist = abs(f.midX - approximate.midX) + abs(f.midY - approximate.midY)
                + abs(f.width - approximate.width) * 0.1
            if dist < bestDist {
                bestDist = dist
                best = win
            }
        }
        // Require reasonably close match
        return bestDist < 400 ? best : nil
    }

    private func axFrameAppKit(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef,
              let sizeVal = sizeRef
        else { return nil }
        var pos = CGPoint(x: 0, y: 0)
        var size = CGSize(width: 0, height: 0)
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        else { return nil }
        let primary = NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let primary else {
            return CGRect(x: pos.x, y: pos.y, width: size.width, height: size.height)
        }
        let y = primary.frame.maxY - pos.y - size.height
        return CGRect(x: pos.x, y: y, width: size.width, height: size.height)
    }

    private func framesOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
        a.maxX > b.minX && a.minX < b.maxX && a.maxY > b.minY && a.minY < b.maxY
    }
}

/// Stable window key: process id + CoreGraphics window number.
public enum WindowIdentity {
    public static func makeID(pid: pid_t, windowNumber: Int) -> String {
        "\(pid):\(windowNumber)"
    }

    public static func parse(_ id: String) -> (pid: pid_t, windowNumber: Int)? {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let pid = Int32(parts[0]),
              let num = Int(parts[1])
        else { return nil }
        return (pid, num)
    }
}

// CGRect mid helpers
private extension CGRect {
    var midX: CGFloat { minX + width / 2 }
    var midY: CGFloat { minY + height / 2 }
}
