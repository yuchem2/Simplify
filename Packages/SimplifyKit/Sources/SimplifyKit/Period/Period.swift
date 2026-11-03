import Foundation

/// How long a diary page lasts: one day, one week (Sunday–Saturday, or Monday–Sunday when 설정 says
/// so), or one month.
public enum PeriodScope: String, Codable, CaseIterable, Sendable {
    case day, week, month
}

/// A day, week or month that memos and ToDos belong to.
///
/// `key` is the stable storage id: `2026-10-26`, `2026-W44` (the week's number in its year), `2026-10`.
/// Week numbers are always counted in Sunday weeks, whatever day the calendar starts weeks on, so a
/// week memo stays with the week it shares six days with when the start day changes.
public struct Period: Hashable, Sendable {
    public let scope: PeriodScope
    /// The first instant of the period: start of day, the week's first day 00:00, or the 1st 00:00.
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

    /// The period a stored `key` names, or nil for a key that does not parse.
    public init?(key: String, scope: PeriodScope, calendar: Calendar = .simplify) {
        let parts = key.split(separator: "-").map(String.init)
        var components = DateComponents()
        switch scope {
        case .day:
            guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
            components = DateComponents(year: y, month: m, day: d)
        case .week:
            guard parts.count == 2, let y = Int(parts[0]), parts[1].first == "W", let w = Int(parts[1].dropFirst()),
                  let sunday = calendar.sundayWeeks.date(from: DateComponents(weekday: 1, weekOfYear: w, yearForWeekOfYear: y)) else { return nil }
            // The week that starts within that Sunday week.
            components = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: calendar.firstWeekday - 1, to: sunday)!)
        case .month:
            guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            components = DateComponents(year: y, month: m, day: 1)
        }
        guard let date = calendar.date(from: components) else { return nil }
        self.init(containing: date, scope: scope, calendar: calendar)
        guard self.key == key else { return nil }
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
            // The Sunday week this week starts in; the same week for Sunday-first calendars.
            let c = calendar.sundayWeeks.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)
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
    /// them, or from Monday when 설정 › 일반 says so (`SharedSettings.firstWeekday`, read by the app
    /// and the widgets alike); week 1 is the week holding 1 January. In the user's current time
    /// zone, with Korean names. The zone is fixed at creation so stored dates and keys stay
    /// consistent; when the system zone or the start day changes, build a new calendar and carry
    /// dates across by year, month and day.
    static var simplify: Calendar {
        simplify(firstWeekday: SharedSettings.firstWeekday(in: SharedSettings.defaults))
    }

    static func simplify(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 1
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.timeZone = .current
        return calendar
    }

    /// The weekdays of a row from its first day, as `Calendar.Component.weekday` numbers (1 = Sunday).
    var weekdaysInOrder: [Int] {
        (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// `일` for 1 (Sunday) to `토` for 7.
    static func weekdayName(_ weekday: Int) -> String {
        ["일", "월", "화", "수", "목", "금", "토"][weekday - 1]
    }

    /// The same calendar counting Sunday weeks, which week keys are numbered in.
    internal var sundayWeeks: Calendar {
        var calendar = self
        calendar.firstWeekday = 1
        return calendar
    }
}
