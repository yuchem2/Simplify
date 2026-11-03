import AppKit
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
    /// The month sheet, the week grid or the year. Remembered across launches.
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
    /// White wall, graphite, or whatever the Mac is set to (설정 › 일반). Remembered across launches.
    var theme = Theme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }

    enum Theme: String, CaseIterable {
        case system, light, dark

        /// Sets the appearance every window and token colour follows.
        @MainActor func apply() {
            switch self {
            case .system: NSApplication.shared.appearance = nil
            case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
            case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
            }
        }

        var label: String {
            switch self {
            case .system: "시스템"
            case .light: "흰 벽"
            case .dark: "흑연"
            }
        }
    }

    /// Timed events in day cells start with their time (설정 › 일반). On unless turned off. Kept in
    /// the App Group's defaults since stage 7; the widgets' cells are too narrow and leave it aside.
    var showsCellTimes = SharedSettings.showsCellTimes(in: SharedSettings.defaults) {
        didSet { SyncedSettings.set(.bool(showsCellTimes), forKey: SharedSettings.showsCellTimes, in: SharedSettings.defaults) }
    }

    /// Calendar marks take their calendar's shape too (설정 › 일반). Off unless turned on; shared with the widgets.
    var showsPatterns = SharedSettings.showsPatterns(in: SharedSettings.defaults) {
        didSet {
            SyncedSettings.set(.bool(showsPatterns), forKey: SharedSettings.showsPatterns, in: SharedSettings.defaults)
            WidgetRefresh.request()
        }
    }

    /// Weeks start on Sunday or Monday (설정 › 일반), in the app and the widgets alike.
    var weekStart: WeekStart {
        get { calendar.firstWeekday == WeekStart.monday.rawValue ? .monday : .sunday }
        set {
            guard newValue != weekStart else { return }
            SyncedSettings.set(.int(newValue.rawValue), forKey: SharedSettings.firstWeekday, in: SharedSettings.defaults)
            rebuildCalendar()
            WidgetRefresh.request()
        }
    }

    enum WeekStart: Int, CaseIterable {
        case sunday = 1, monday = 2

        var label: String {
            switch self {
            case .sunday: "일요일"
            case .monday: "월요일"
            }
        }
    }

    enum CalendarView: String, Hashable, CaseIterable {
        case week, month, year

        var label: String {
            switch self {
            case .week: "주"
            case .month: "월"
            case .year: "년"
            }
        }

        /// One page of the view, for 이전/다음 labels.
        var unit: String {
            switch self {
            case .week: "주"
            case .month: "달"
            case .year: "해"
            }
        }
    }

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
            case .medium: TextStyle.cell.size
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

    /// The year of the chosen day, January to December.
    var shownYear: Int { calendar.component(.year, from: selectedDay) }

    /// Whole weeks from the week of 1 January to the week of 31 December.
    var yearDays: [Date] {
        let first = calendar.date(from: DateComponents(year: shownYear, month: 1, day: 1))!
        let last = calendar.date(from: DateComponents(year: shownYear, month: 12, day: 31))!
        let start = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7, to: first)!
        let end = calendar.date(byAdding: .day, value: (calendar.firstWeekday + 6 - calendar.component(.weekday, from: last)) % 7, to: last)!
        let count = calendar.dateComponents([.day], from: start, to: end).day! + 1
        return (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    /// What decides `shownDays`: the view, the first day of its month or year, and the weekday rows
    /// start on. Cheap to compare, so the window reloads events only when it changes.
    var shownRange: String {
        switch calendarView {
        case .year: "year-\(shownYear)-\(calendar.firstWeekday)"
        case .week, .month: "month-\(month.start.timeIntervalSinceReferenceDate)-\(calendar.firstWeekday)"
        }
    }

    /// The days whose events the calendar on screen needs: the month grid (which holds the week
    /// on screen too) or the whole year.
    var shownDays: [Date] {
        calendarView == .year ? yearDays : grid.weeks.flatMap { $0 }
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

    /// One step of the view on screen: a month, a week keeping the same weekday, or a year keeping the date.
    func turnPage(by steps: Int) {
        switch calendarView {
        case .month: turnMonth(by: steps)
        case .week: moveSelection(byDays: 7 * steps)
        case .year: turnMonth(by: 12 * steps)
        }
    }

    func goToToday() {
        select(today)
    }

    /// A widget was clicked (`simplify://day/…`): that day, in the panel's day page.
    func open(_ url: URL) {
        refreshToday()
        guard !isModalOpen, let day = DayLink.day(from: url, calendar: calendar) else { return }
        select(day)
        panelScope = .day
    }

    /// Called when the date changes while the app is open.
    func refreshToday(now: Date = .now) {
        today = calendar.startOfDay(for: now)
    }

    /// Another device's settings arrived (`DeviceSync`): show what is stored now.
    func takeSyncedSettings() {
        let defaults = SharedSettings.defaults
        let times = SharedSettings.showsCellTimes(in: defaults)
        if times != showsCellTimes { showsCellTimes = times }
        let patterns = SharedSettings.showsPatterns(in: defaults)
        if patterns != showsPatterns { showsPatterns = patterns }
        if SharedSettings.firstWeekday(in: defaults) != calendar.firstWeekday { rebuildCalendar() }
    }

    /// Called when the system time zone changes: keeps the same calendar dates (the 26th stays
    /// the 26th) under a calendar in the new zone.
    func timeZoneDidChange(now: Date = .now) {
        NSTimeZone.resetSystemTimeZone()
        rebuildCalendar(now: now)
    }

    /// A new `Calendar.simplify` (another zone or first weekday) that keeps the same calendar dates.
    private func rebuildCalendar(now: Date = .now) {
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
    /// Sundays are red, wherever the week starts; public holidays join them once calendars sync (stage 2).
    func isRedDay(_ day: Date) -> Bool { calendar.component(.weekday, from: day) == 1 }
}
