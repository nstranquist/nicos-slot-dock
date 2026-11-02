import Foundation
import Testing
@testable import SlotDockCore

@Suite("CalendarDockIcon")
struct CalendarDockIconTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private var sampleDate: Date {
        DateComponents(
            calendar: utc,
            timeZone: utc.timeZone,
            year: 2026,
            month: 8,
            day: 26,
            hour: 15
        ).date!
    }

    @Test("matches Calendar by path and bundle, not by label")
    func matchesCalendar() {
        #expect(CalendarDockIcon.matches(path: "/System/Applications/Calendar.app"))
        #expect(CalendarDockIcon.matches(path: "/Applications/Calendar.app/", bundleIdentifier: nil))
        #expect(
            CalendarDockIcon.matches(
                path: "/System/Applications/Notes.app",
                bundleIdentifier: "com.apple.iCal"
            )
        )
        #expect(!CalendarDockIcon.matches(path: "/System/Applications/Notes.app"))
        #expect(
            !CalendarDockIcon.matches(
                path: "/System/Applications/Messages.app",
                bundleIdentifier: "com.apple.MobileSMS"
            )
        )

        let sys = Slot(
            id: "sysdock:com.apple.iCal:/System/Applications/Calendar.app",
            label: "Calendar",
            target: "/System/Applications/Calendar.app"
        )
        #expect(CalendarDockIcon.matches(slot: sys))

        let custom = Slot(
            id: "custom-cal",
            label: "Cal",
            target: "/System/Applications/Calendar.app"
        )
        #expect(CalendarDockIcon.matches(slot: custom))

        let notes = Slot(
            id: "notes",
            label: "Calendar",
            target: "/System/Applications/Notes.app"
        )
        #expect(!CalendarDockIcon.matches(slot: notes))
    }

    @Test("English month is Dock-style uppercase without a trailing dot")
    func englishCaption() {
        let caption = CalendarDockIcon.caption(
            date: sampleDate,
            calendar: utc,
            locale: Locale(identifier: "en_US")
        )
        #expect(caption.month == "AUG")
        #expect(caption.day == "26")
        #expect(caption.cacheKey.contains("1-2026-8-26"))
        #expect(CalendarDockIcon.dayKey(date: sampleDate, calendar: utc) == "1-2026-8-26")
    }

    @Test("digit months keep their locale glyphs")
    func digitMonth() {
        #expect(CalendarDockIcon.displayMonth("8月", locale: Locale(identifier: "ja_JP")) == "8月")
        #expect(CalendarDockIcon.displayMonth("Aug.", locale: Locale(identifier: "en_US")) == "AUG")
        #expect(CalendarDockIcon.displayMonth("sept.", locale: Locale(identifier: "fr_FR")) == "SEPT")
    }

    @Test("day key changes at local midnight")
    func dayKeyRolls() {
        let before = DateComponents(
            calendar: utc,
            timeZone: utc.timeZone,
            year: 2026,
            month: 8,
            day: 26,
            hour: 23,
            minute: 59
        ).date!
        let after = DateComponents(
            calendar: utc,
            timeZone: utc.timeZone,
            year: 2026,
            month: 8,
            day: 27,
            hour: 0,
            minute: 1
        ).date!
        #expect(CalendarDockIcon.dayKey(date: before, calendar: utc) == "1-2026-8-26")
        #expect(CalendarDockIcon.dayKey(date: after, calendar: utc) == "1-2026-8-27")
        #expect(
            CalendarDockIcon.iconCacheKey(date: before, calendar: utc, locale: Locale(identifier: "en_US"))
                != CalendarDockIcon.iconCacheKey(date: after, calendar: utc, locale: Locale(identifier: "en_US"))
        )
    }
}
