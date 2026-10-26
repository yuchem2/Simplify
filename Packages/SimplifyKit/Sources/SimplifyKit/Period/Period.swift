import Foundation

/// How long a diary page lasts: one day, one Sunday–Saturday week, or one month.
public enum PeriodScope: String, Codable, CaseIterable, Sendable {
    case day, week, month
}

/// A day, week or month that memos and ToDos belong to.
///
/// `key` is the stable storage id: `2026-10-26`, `2026-W44` (the week's number in its year), `2026-10`.
public struct Period: Hashable, Sendable {
    public let scope: PeriodScope
    /// The first instant of the period: start of day, Sunday 00:00, or the 1st 00:00.
    public let start: Date
    public let calendar: Calendar

    public init(containing date: Date, scope: PeriodScope, calendar: Calendar = .simplify) {
        self.scope = scope
        self.calendar = calendar
        switch scope {
        case .day:
            start = calendar.startOfDay(for: date)
        case .week:
            start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        case .month:
            start = calendar.dateInterval(of: .month, for: date)!.start
        }
    }

    /// The first instant after the period.
    public var end: Date {
        calendar.dateInterval(of: component, for: start)!.end
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// The period `offset` steps away of the same scope; negative goes back.
    public func advanced(by offset: Int) -> Period {
        Period(containing: calendar.date(byAdding: component, value: offset, to: start)!, scope: scope, calendar: calendar)
    }

    /// Every day in the period, each at its start of day. Where daylight saving starts at
    /// midnight that day begins at 01:00, so each step re-anchors to the next day's start.
    public var days: [Date] {
        var result: [Date] = []
        var day = start
        let end = end
        while day < end {
            result.append(day)
            day = calendar.dateInterval(of: .day, for: day)!.end
        }
        return result
    }

    public var key: String {
        switch scope {
        case .day:
            let c = calendar.dateComponents([.year, .month, .day], from: start)
            return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        case .week:
            let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)
            return String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
        case .month:
            let c = calendar.dateComponents([.year, .month], from: start)
            return String(format: "%04d-%02d", c.year!, c.month!)
        }
    }

    private var component: Calendar.Component {
        switch scope {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    public static func == (lhs: Period, rhs: Period) -> Bool {
        lhs.scope == rhs.scope && lhs.start == rhs.start
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(scope)
        hasher.combine(start)
    }
}

public extension Calendar {
    /// The Gregorian calendar with weeks from Sunday to Saturday, as Korean wall calendars print
    /// them; week 1 is the week holding 1 January. In the user's current time zone, with Korean
    /// names. The zone is fixed at creation so stored dates and keys stay consistent; when the
    /// system zone changes, build a new calendar and carry dates across by year, month and day.
    static var simplify: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.timeZone = .current
        return calendar
    }
}
