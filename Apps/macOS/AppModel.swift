import Foundation
import Observation
import SimplifyKit

/// What the window is looking at: the month or week on screen, the chosen day, and the panel's scope.
@MainActor
@Observable
final class AppModel {
    private(set) var calendar: Calendar
    private(set) var today: Date
    private(set) var selectedDay: Date
    private(set) var month: Period
    var panelScope: PeriodScope = .day
    /// The month sheet or the week grid. Remembered across launches.
    var calendarView = CalendarView(rawValue: UserDefaults.standard.string(forKey: "calendarView") ?? "") ?? .month {
        didSet { UserDefaults.standard.set(calendarView.rawValue, forKey: "calendarView") }
    }
    /// The settings modal is up; the month underneath ignores keys and clicks.
    var isSettingsOpen = false
    /// The event popover (an event's details, or the editor) and what it points at.
    var popover: EventPopoverState?
    /// The event picked with a click or Tab, by occurrence id; Return opens it, ⌫ deletes it.
    var selectedEventID: String?
    /// Settings or the event popover is up; the month's menus and arrow keys wait.
    var isModalOpen: Bool { isSettingsOpen || popover != nil }
    /// The day panel is folded away so the month gets the whole window. Remembered across launches.
    var isPanelHidden = UserDefaults.standard.bool(forKey: "isPanelHidden") {
        didSet { UserDefaults.standard.set(isPanelHidden, forKey: "isPanelHidden") }
    }
    /// How large event titles are inside day cells (설정 › 일반). Remembered across launches.
    var cellTextSize = CellTextSize(rawValue: UserDefaults.standard.string(forKey: "cellTextSize") ?? "") ?? .medium {
        didSet { UserDefaults.standard.set(cellTextSize.rawValue, forKey: "cellTextSize") }
    }

    enum CalendarView: String, Hashable { case month, week }

    enum CellTextSize: String, CaseIterable {
        case small, medium, large

        var label: String {
            switch self {
            case .small: "작게"
            case .medium: "보통"
            case .large: "크게"
            }
        }

        var points: CGFloat {
            switch self {
            case .small: 10
            case .medium: 11
            case .large: 13
            }
        }

        /// One event row: the text plus a 2 pt gap.
        var rowHeight: CGFloat { (points * 1.4).rounded() + 2 }
        /// Never below 8 pt, so the calendar colour stays readable as a colour.
        var markSize: CGFloat {
            switch self {
            case .small: 8
            case .medium: 9
            case .large: 10
            }
        }
    }

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

    /// The week grid always shows the chosen day's week.
    var shownWeek: Period {
        Period(containing: selectedDay, scope: .week, calendar: calendar)
    }

    var grid: MonthGrid {
        MonthGrid(month: month.start, calendar: calendar)
    }

    /// Choosing a day outside the shown month turns to that month.
    func select(_ day: Date) {
        let day = calendar.startOfDay(for: day)
        if day != selectedDay { selectedEventID = nil }
        selectedDay = day
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

    /// One step of the view on screen: a month, or a week keeping the same weekday.
    func turnPage(by steps: Int) {
        switch calendarView {
        case .month: turnMonth(by: steps)
        case .week: moveSelection(byDays: 7 * steps)
        }
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
