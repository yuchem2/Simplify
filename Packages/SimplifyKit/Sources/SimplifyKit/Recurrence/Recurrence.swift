import Foundation

/// A repeat rule, independent of any calendar service.
///
/// Covers what people actually create in Google Calendar and Apple Calendar: every N days,
/// weeks, months or years, on chosen weekdays or month days, "the 2nd Tuesday" or "the last
/// Friday", ending after a count or on a date. Rules outside this subset fail to parse, and
/// their occurrences come from the service instead.
public struct Recurrence: Codable, Hashable, Sendable {
    public enum Frequency: String, Codable, Sendable {
        case daily, weekly, monthly, yearly
    }

    /// A weekday, optionally numbered within the month: `ordinal` 2 is "the 2nd", -1 "the last".
    public struct WeekdayRule: Codable, Hashable, Sendable {
        /// `Calendar.Component.weekday` numbering: 1 = Sunday … 7 = Saturday.
        public var weekday: Int
        public var ordinal: Int?

        public init(weekday: Int, ordinal: Int? = nil) {
            self.weekday = weekday
            self.ordinal = ordinal
        }
    }

    public var frequency: Frequency
    public var interval = 1
    public var count: Int?
    /// The last moment an occurrence may start (inclusive).
    public var until: Date?
    public var byWeekday: [WeekdayRule] = []
    /// 1…31, or -1 for the last day of the month.
    public var byMonthDay: [Int] = []
    public var byMonth: [Int] = []
    /// Picks from each period's candidates in order: 1 = first, -1 = last.
    public var bySetPosition: [Int] = []
    /// The weekday a week starts on, for weekly rules with an interval (1 = Sunday, 2 = Monday).
    public var weekStart = 2

    public init(frequency: Frequency) {
        self.frequency = frequency
    }
}

// MARK: - RFC 5545 text

extension Recurrence {
    private static let weekdayCodes = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

    /// Parses an `RRULE` line (`RRULE:FREQ=WEEKLY;BYDAY=MO,WE`), or returns nil when the rule uses
    /// parts this engine does not expand. A floating or date-only `UNTIL` is read in `calendar`'s zone.
    public init?(rrule line: String, calendar: Calendar) {
        let body = line.hasPrefix("RRULE:") ? String(line.dropFirst(6)) : line
        var parts: [String: String] = [:]
        for pair in body.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { return nil }
            parts[kv[0].uppercased()] = kv[1]
        }
        guard let freq = parts.removeValue(forKey: "FREQ"),
              let frequency = Frequency(rawValue: freq.lowercased()) else { return nil }
        self.init(frequency: frequency)

        if let value = parts.removeValue(forKey: "INTERVAL") {
            guard let n = Int(value), n > 0 else { return nil }
            interval = n
        }
        if let value = parts.removeValue(forKey: "COUNT") {
            guard let n = Int(value), n > 0 else { return nil }
            count = n
        }
        if let value = parts.removeValue(forKey: "UNTIL") {
            guard let date = Self.parseDateTime(value, calendar: calendar, dateOnlyMeansEndOfDay: true) else { return nil }
            until = date
        }
        if let value = parts.removeValue(forKey: "BYDAY") {
            for code in value.split(separator: ",") {
                guard let rule = Self.parseWeekday(String(code)) else { return nil }
                byWeekday.append(rule)
            }
        }
        if let value = parts.removeValue(forKey: "BYMONTHDAY") {
            for n in value.split(separator: ",") {
                guard let day = Int(n), day != 0, (-31...31).contains(day) else { return nil }
                byMonthDay.append(day)
            }
        }
        if let value = parts.removeValue(forKey: "BYMONTH") {
            for n in value.split(separator: ",") {
                guard let month = Int(n), (1...12).contains(month) else { return nil }
                byMonth.append(month)
            }
        }
        if let value = parts.removeValue(forKey: "BYSETPOS") {
            for n in value.split(separator: ",") {
                guard let pos = Int(n), pos != 0 else { return nil }
                bySetPosition.append(pos)
            }
        }
        if let value = parts.removeValue(forKey: "WKST") {
            guard let day = Self.weekdayCodes[value.uppercased()] else { return nil }
            weekStart = day
        }
        // BYHOUR, BYWEEKNO, BYYEARDAY and friends are left to the service.
        guard parts.isEmpty else { return nil }
        // Combinations the expander would get wrong go to the service instead.
        if byWeekday.contains(where: { $0.ordinal != nil }) {
            // Numbered weekdays only inside a month.
            guard frequency == .monthly || (frequency == .yearly && !byMonth.isEmpty) else { return nil }
        }
        // "Friday the 13th" style rules intersect weekday and month day; not expanded here.
        if !byWeekday.isEmpty, !byMonthDay.isEmpty, frequency != .daily { return nil }
        // Yearly weekday or month-day rules without months mean "across the whole year".
        if frequency == .yearly, byMonth.isEmpty, !byWeekday.isEmpty || !byMonthDay.isEmpty { return nil }
        if frequency == .weekly, !byMonthDay.isEmpty { return nil }
    }

    private static func parseWeekday(_ code: String) -> WeekdayRule? {
        let upper = code.uppercased()
        guard upper.count >= 2, let weekday = weekdayCodes[String(upper.suffix(2))] else { return nil }
        let prefix = upper.dropLast(2)
        if prefix.isEmpty { return WeekdayRule(weekday: weekday) }
        guard let ordinal = Int(prefix), ordinal != 0, (-5...5).contains(ordinal) else { return nil }
        return WeekdayRule(weekday: weekday, ordinal: ordinal)
    }

    /// `20261026T093000Z` (UTC), `20261026T093000` (in `calendar`'s zone) or `20261026` (a date).
    static func parseDateTime(_ value: String, calendar: Calendar, dateOnlyMeansEndOfDay: Bool = false) -> Date? {
        let digits = value.filter(\.isNumber)
        guard digits.count == 8 || digits.count == 14 else { return nil }
        func int(_ from: Int, _ length: Int) -> Int {
            let start = digits.index(digits.startIndex, offsetBy: from)
            return Int(digits[start..<digits.index(start, offsetBy: length)])!
        }
        var parts = DateComponents(year: int(0, 4), month: int(4, 2), day: int(6, 2))
        var cal = calendar
        if digits.count == 14 {
            parts.hour = int(8, 2)
            parts.minute = int(10, 2)
            parts.second = int(12, 2)
            if value.hasSuffix("Z") { cal.timeZone = TimeZone(identifier: "UTC")! }
        } else if dateOnlyMeansEndOfDay {
            parts.hour = 23
            parts.minute = 59
            parts.second = 59
        }
        return cal.date(from: parts)
    }

    /// Reads `EXDATE` lines into instants. Date-only values become the start of that day in `calendar`.
    public static func exceptionDates(from lines: [String], calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        for line in lines where line.uppercased().hasPrefix("EXDATE") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            var cal = calendar
            let params = line[..<colon].split(separator: ";").dropFirst()
            for param in params where param.uppercased().hasPrefix("TZID=") {
                if let zone = TimeZone(identifier: String(param.dropFirst(5))) { cal.timeZone = zone }
            }
            for value in line[line.index(after: colon)...].split(separator: ",") {
                if let date = parseDateTime(String(value), calendar: cal) { dates.append(date) }
            }
        }
        return dates
    }
}
