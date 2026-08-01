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

        var nextLedger = plan.nextLedger
        var failures = 0
        for item in plan.restore {
            if !setFrame(windowID: item.windowID, frame: item.to) {
                // Keep failed restores retryable. The window may have moved
                // displays or temporarily declined an AX mutation.
                if let record = ledger[item.windowID] {
                    nextLedger[item.windowID] = record
                }
                failures += 1
            }
        }
        for item in plan.apply {
            if !setFrame(windowID: item.windowID, frame: item.to) {
                failures += 1
            }
        }
        ledger = nextLedger
        if failures > 0 {
            lastError = "Accessibility could not update \(failures) window frame\(failures == 1 ? "" : "s"); will retry."
        }
        SlotDockTelemetry.windowing.info(
            "Safe-area need=\(need.rawValue, privacy: .public) windows=\(windows.count, privacy: .public) apply=\(plan.apply.count, privacy: .public) restore=\(plan.restore.count, privacy: .public) ledger=\(self.ledger.count, privacy: .public)"
        )
    }

    /// Force restore everything we ever padded (option off / quit).
    func restoreAllTracked() {
        lastError = nil
        let count = ledger.count
        guard count > 0 else { return }
        let plan = SafeAreaPlanner.restoreAll(ledger: ledger)
        var remaining = ledger
        var failures = 0
        for item in plan.restore {
            if setFrame(windowID: item.windowID, frame: item.to) {
                remaining.removeValue(forKey: item.windowID)
            } else {
                failures += 1
            }
        }
        ledger = remaining
        lastError = failures == 0
            ? nil
            : "Accessibility could not restore \(failures) window frame\(failures == 1 ? "" : "s"); will retry."
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
                  let x = cgFloat(bounds["X"]),
                  let y = cgFloat(bounds["Y"]),
                  let w = cgFloat(bounds["Width"]),
                  let h = cgFloat(bounds["Height"])
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
        guard let primary = primaryScreen else {
            return CGRect(x: x, y: y, width: width, height: height)
        }
        return CGRect(
            x: primary.frame.minX + x,
            y: primary.frame.maxY - y - height,
            width: width,
            height: height
        )
    }

    // MARK: - Apply via AX, match by CGWindowNumber identity

    private func setFrame(windowID: String, frame: CGRect) -> Bool {
        guard isTrusted else {
            lastError = "Accessibility permission is not granted."
            return false
        }
        guard let identity = WindowIdentity.parse(windowID) else {
            lastError = "Invalid window identity \(windowID)."
            return false
        }
        guard let axWindow = findAXWindow(pid: identity.pid, windowNumber: identity.windowNumber)
                ?? findAXWindowByFrame(pid: identity.pid, approximate: frame)
        else {
            lastError = "The target window is not currently accessible."
            return false
        }

        // AX position is top-left global. Keep the pre-mutation frame so a
        // rejected size update does not leave a half-applied position change.
        guard let primary = primaryScreen else {
            lastError = "Could not determine the primary display coordinate space."
            return false
        }
        let previousFrame = axFrameAppKit(axWindow)
        var axPos = CGPoint(x: frame.minX - primary.frame.minX, y: primary.frame.maxY - frame.maxY)
        var axSize = CGSize(width: frame.width, height: frame.height)
        guard let posVal = AXValueCreate(.cgPoint, &axPos),
              let sizeVal = AXValueCreate(.cgSize, &axSize)
        else {
            lastError = "Could not construct an Accessibility frame value."
            return false
        }
        let positionResult = AXUIElementSetAttributeValue(
            axWindow,
            kAXPositionAttribute as CFString,
            posVal
        )
        guard positionResult == .success else {
            lastError = "The target application rejected the requested window position."
            return false
        }
        let sizeResult = AXUIElementSetAttributeValue(
            axWindow,
            kAXSizeAttribute as CFString,
            sizeVal
        )
        guard sizeResult == .success else {
            if let previousFrame {
                var previousPos = CGPoint(
                    x: previousFrame.minX - primary.frame.minX,
                    y: primary.frame.maxY - previousFrame.maxY
                )
                if let previousPositionValue = AXValueCreate(.cgPoint, &previousPos) {
                    _ = AXUIElementSetAttributeValue(
                        axWindow,
                        kAXPositionAttribute as CFString,
                        previousPositionValue
                    )
                }
            }
            lastError = "The target application rejected the requested window frame."
            return false
        }
        return true
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
        return bestDist < 80 ? best : nil
    }

    private func axFrameAppKit(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef,
              let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        let posVal = unsafeDowncast(posRef, to: AXValue.self)
        let sizeVal = unsafeDowncast(sizeRef, to: AXValue.self)
        var pos = CGPoint(x: 0, y: 0)
        var size = CGSize(width: 0, height: 0)
        guard AXValueGetValue(posVal, .cgPoint, &pos),
              AXValueGetValue(sizeVal, .cgSize, &size)
        else { return nil }
        let primary = primaryScreen
        guard let primary else {
            return CGRect(x: pos.x, y: pos.y, width: size.width, height: size.height)
        }
        let y = primary.frame.maxY - pos.y - size.height
        return CGRect(x: primary.frame.minX + pos.x, y: y, width: size.width, height: size.height)
    }

    private var primaryScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func framesOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
        a.maxX > b.minX && a.minX < b.maxX && a.maxY > b.minY && a.minY < b.maxY
    }

    private func cgFloat(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat { return value }
        if let value = value as? NSNumber { return CGFloat(truncating: value) }
        return nil
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
