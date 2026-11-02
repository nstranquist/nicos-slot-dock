import Foundation

/// Live Calendar tile captions. The system Dock draws these through
/// `Calendar.docktileplugin`; Icon Services still returns a static marketing icon.
public enum CalendarDockIcon {
    public static let bundleIdentifiers: Set<String> = [
        "com.apple.ical",
        "com.apple.calendar",
    ]

    public struct Caption: Equatable, Sendable {
        public var month: String
        public var day: String
        public var cacheKey: String

        public init(month: String, day: String, cacheKey: String) {
            self.month = month
            self.day = day
            self.cacheKey = cacheKey
        }
    }

    public static func matches(path: String, bundleIdentifier: String? = nil) -> Bool {
        if let bundleIdentifier, bundleIdentifiers.contains(bundleIdentifier.lowercased()) {
            return true
        }
        let canonical = SystemDockEntry.canonicalIdentityPath(path)
        return canonical.lowercased().hasSuffix("/calendar.app")
    }

    public static func matches(slot: Slot) -> Bool {
        let fromID = AppIdentity.bundleIdentifier(fromSlotID: slot.id)
        if matches(path: slot.target, bundleIdentifier: fromID) {
            return true
        }
        if let fromDisk = AppIdentity.bundleIdentifier(forAppPath: slot.target),
           matches(path: slot.target, bundleIdentifier: fromDisk)
        {
            return true
        }
        return matches(path: slot.target, bundleIdentifier: nil)
    }

    /// Era-year-month-day in the given calendar. Independent of locale glyphs.
    public static func dayKey(date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(parts.era ?? 1)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    public static func iconCacheKey(
        date: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        "\(dayKey(date: date, calendar: calendar))|\(locale.identifier)"
    }

    public static func caption(
        date: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> Caption {
        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.locale = locale
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.setLocalizedDateFormatFromTemplate("MMM")
        let month = displayMonth(monthFormatter.string(from: date), locale: locale)

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = locale
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.setLocalizedDateFormatFromTemplate("d")
        let day = dayFormatter.string(from: date)

        return Caption(
            month: month,
            day: day,
            cacheKey: iconCacheKey(date: date, calendar: calendar, locale: locale)
        )
    }

    /// Dock tiles use JUL / AUG for Latin months. Digit months (8月) stay as-is.
    public static func displayMonth(_ raw: String, locale: Locale) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) {
            return trimmed
        }
        let stripped = trimmed.replacingOccurrences(of: ".", with: "")
        return stripped.uppercased(with: locale)
    }
}
