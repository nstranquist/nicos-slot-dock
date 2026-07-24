import Foundation
import OSLog

/// Local OSLog dogfood (no network). Prefer sparse **info** for state the human cares about;
/// **debug** for high-frequency paths; **warning/error** only for unexpected faults.
///
/// ## Keep (worth reading in Console / `log show`)
/// | Category | What stays at info+ |
/// |----------|---------------------|
/// | AppLifecycle | launch / terminate / handoff |
/// | Launch | open success / miss / invalid target |
/// | Menu | context actions (sparse, user-driven) |
/// | Preferences | real toggles, Open-at-Login outcomes, collision actions |
/// | SystemDock | compose counts, import, watcher fallback |
/// | Performance | ⏱ ops ≥ threshold; reveal.complete wall time |
/// | Dock | outside-click collapse; relayout when strip membership changes |
/// | Windowing | safe-area apply/restore; **one** trust-block notice |
/// | Hotkey | register problems / fire |
/// | Error | faults only |
///
/// ## Quiet on purpose
/// - Running snapshot **unchanged** → debug only
/// - Reveal expand/collapse phase chatter → debug
/// - Login-item Automation denied → **once** at info, then suppressed
/// - Safe-area trust block → **once** until Accessibility granted
/// - `Preferences updated` every mutate → debug
///
/// ## Console.app / CLI
/// ```
/// subsystem:com.nstranquist.nicos-slot-dock
/// /usr/bin/log show --predicate 'subsystem == "com.nstranquist.nicos-slot-dock"' --last 1h --info
/// ```
enum SlotDockTelemetry {
    static let subsystem =
        Bundle.main.bundleIdentifier ?? "com.nstranquist.nicos-slot-dock"

    static let appLifecycle = Logger(subsystem: subsystem, category: "AppLifecycle")
    static let dock = Logger(subsystem: subsystem, category: "Dock")
    static let launch = Logger(subsystem: subsystem, category: "Launch")
    static let preferences = Logger(subsystem: subsystem, category: "Preferences")
    static let systemDock = Logger(subsystem: subsystem, category: "SystemDock")
    static let running = Logger(subsystem: subsystem, category: "Running")
    static let performance = Logger(subsystem: subsystem, category: "Performance")
    static let windowing = Logger(subsystem: subsystem, category: "Windowing")
    static let menu = Logger(subsystem: subsystem, category: "Menu")
    static let hotkey = Logger(subsystem: subsystem, category: "Hotkey")
    static let iconCache = Logger(subsystem: subsystem, category: "IconCache")
    static let error = Logger(subsystem: subsystem, category: "Error")

    /// Signpost-style timed block; logs duration in ms when ≥ `thresholdMS`.
    @discardableResult
    static func measure<T>(
        _ name: String,
        thresholdMS: Double = 0.5,
        alwaysLog: Bool = false,
        _ body: () -> T
    ) -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = body()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if alwaysLog || ms >= thresholdMS {
            performance.info(
                "⏱ \(name, privacy: .public) \(ms, format: .fixed(precision: 2), privacy: .public)ms"
            )
        }
        return result
    }

    static func measure(
        _ name: String,
        thresholdMS: Double = 0.5,
        alwaysLog: Bool = false,
        _ body: () -> Void
    ) {
        _ = measure(name, thresholdMS: thresholdMS, alwaysLog: alwaysLog) { body(); return 0 }
    }

    static func event(_ logger: Logger, _ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func fault(_ message: String) {
        error.error("\(message, privacy: .public)")
    }

    /// Structured state transition (searchable prefix).
    static func transition(_ logger: Logger, _ name: String, details: String = "") {
        if details.isEmpty {
            logger.info("→ \(name, privacy: .public)")
        } else {
            logger.info("→ \(name, privacy: .public) \(details, privacy: .public)")
        }
    }
}
