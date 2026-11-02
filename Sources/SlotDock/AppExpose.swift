import Foundation

/// Fail-soft App Exposé for the frontmost application.
///
/// Uses `CoreDockSendNotification` when the symbol is present. If the symbol
/// is missing, callers still have activate-and-raise as a public fallback.
enum AppExpose {
    private typealias Send = @convention(c) (CFString, UnsafeRawPointer?) -> Void

    private static let send: Send? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") else {
            return nil
        }
        return unsafeBitCast(symbol, to: Send.self)
    }()

    @discardableResult
    static func showFrontApplicationWindows() -> Bool {
        guard let send else {
            SlotDockTelemetry.menu.debug("App Exposé symbol unavailable")
            return false
        }
        send("com.apple.expose.front.awake" as CFString, nil)
        return true
    }
}
