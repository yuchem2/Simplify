import Foundation

/// The weeks that cover a month, from the calendar's first weekday, as shown in the month view (4 to 6 rows).
public struct MonthGrid: Sendable {
    public let month: Period
    /// Each row holds seven days from the first weekday, at their start of day.
    public let weeks: [[Date]]

    public init(month date: Date, calendar: Calendar = .simplify) {
        month = Period(containing: date, scope: .month, calendar: calendar)
        var rows: [[Date]] = []
        var week = Period(containing: month.start, scope: .week, calendar: calendar)
        while week.start < month.end {
            rows.append(week.days)
            week = week.advanced(by: 1)
        }
        weeks = rows
    }

    public func isInMonth(_ day: Date) -> Bool {
        month.contains(day)
    }
}
