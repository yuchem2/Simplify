import Foundation
import Observation
import SimplifyKit

/// What the window is looking at: the month on screen, the chosen day, and the panel's scope.
@MainActor
@Observable
final class AppModel {
    private(set) var calendar: Calendar
    private(set) var today: Date
    private(set) var selectedDay: Date
    private(set) var month: Period
    var panelScope: PeriodScope = .day

    init(calendar: Calendar = .simplify, now: Date = .now) {
        let day = calendar.startOfDay(for: now)
        self.calendar = calendar
        today = day
        selectedDay = day
        month = Period(containing: now, scope: .month, calendar: calendar)
    }

    /// The day, week or month shown in the panel.
    var panelPeriod: Period {
        Period(containing: selectedDay, scope: panelScope, calendar: calendar)
    }

    var grid: MonthGrid {
        MonthGrid(month: month.start, calendar: calendar)
    }

    /// Choosing a day outside the shown month turns to that month.
    func select(_ day: Date) {
        selectedDay = calendar.startOfDay(for: day)
        if !month.contains(selectedDay) {
            month = Period(containing: selectedDay, scope: .month, calendar: calendar)
        }
    }

    func moveSelection(byDays days: Int) {
        select(calendar.date(byAdding: .day, value: days, to: selectedDay)!)
    }

    /// Turns the month and keeps the same day number, clamped to the new month's length.
    func turnMonth(by months: Int) {
        select(calendar.date(byAdding: .month, value: months, to: selectedDay)!)
    }

    func goToToday() {
        select(today)
    }

    /// Called when the date changes while the app is open.
    func refreshToday(now: Date = .now) {
        today = calendar.startOfDay(for: now)
    }

    /// Called when the system time zone changes: keeps the same calendar dates (the 26th stays
    /// the 26th) under a calendar in the new zone.
    func timeZoneDidChange(now: Date = .now) {
        NSTimeZone.resetSystemTimeZone()
        let old = calendar
        let new = Calendar.simplify
        func carry(_ date: Date) -> Date {
            new.date(from: old.dateComponents([.year, .month, .day], from: date))!
        }
        calendar = new
        selectedDay = carry(selectedDay)
        month = Period(containing: carry(month.start), scope: .month, calendar: new)
        today = new.startOfDay(for: now)
    }

    func isToday(_ day: Date) -> Bool { day == today }
    func isSelected(_ day: Date) -> Bool { day == selectedDay }
    /// Sundays are red; public holidays join them once calendars sync (stage 2).
    func isRedDay(_ day: Date) -> Bool { calendar.component(.weekday, from: day) == 1 }
}
