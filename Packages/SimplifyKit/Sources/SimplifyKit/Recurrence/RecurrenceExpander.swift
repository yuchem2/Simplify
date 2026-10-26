import Foundation

/// Turns a `Recurrence` into concrete start times.
public enum RecurrenceExpander {
    /// Start times of the occurrences that overlap `range`, in order.
    ///
    /// - Parameters:
    ///   - start: The first occurrence (the event's DTSTART). It always counts as an occurrence.
    ///   - duration: How long each occurrence lasts, so one that began before `range` still shows.
    ///   - calendar: In the event's own time zone, so wall-clock times hold across DST.
    ///   - excluding: Starts removed by EXDATE or replaced by a moved occurrence.
    public static func occurrences(
        of rule: Recurrence,
        start: Date,
        duration: TimeInterval = 0,
        calendar: Calendar,
        in range: DateInterval,
        excluding: Set<Date> = []
    ) -> [Date] {
        var cal = calendar
        cal.firstWeekday = rule.weekStart
        let time = cal.dateComponents([.hour, .minute, .second], from: start)
        let first = Self.periodStart(of: start, frequency: rule.frequency, calendar: cal)

        var results: [Date] = []
        var produced = 0
        var startedDTSTART = false

        func accept(_ date: Date) -> Bool {
            if let until = rule.until, date > until { return false }
            if let count = rule.count, produced >= count { return false }
            produced += 1
            if !excluding.contains(date), date < range.end, date.addingTimeInterval(max(duration, 1)) > range.start {
                results.append(date)
            }
            return true
        }

        // 10,000 periods covers a daily rule for 27 years; anything longer is cut off.
        for k in 0..<10_000 {
            guard let period = Self.advance(first, by: k * rule.interval, frequency: rule.frequency, calendar: cal) else { break }
            if period >= range.end, rule.count == nil { break }
            let candidates = Self.candidates(in: period, rule: rule, start: start, time: time, calendar: cal)
            for date in candidates where date >= start {
                if !startedDTSTART {
                    startedDTSTART = true
                    // DTSTART is the first occurrence even when it does not match the rule.
                    if date != start, !accept(start) { return results }
                }
                if date >= range.end, rule.count == nil { return results }
                if !accept(date) { return results }
            }
            if let until = rule.until, period > until { break }
            if let count = rule.count, produced >= count { break }
        }
        return results
    }

    // MARK: - Periods

    private static func periodStart(of date: Date, frequency: Recurrence.Frequency, calendar: Calendar) -> Date {
        switch frequency {
        case .daily: calendar.startOfDay(for: date)
        case .weekly: calendar.dateInterval(of: .weekOfYear, for: date)!.start
        case .monthly: calendar.dateInterval(of: .month, for: date)!.start
        case .yearly: calendar.dateInterval(of: .year, for: date)!.start
        }
    }

    private static func advance(_ date: Date, by n: Int, frequency: Recurrence.Frequency, calendar: Calendar) -> Date? {
        switch frequency {
        case .daily: calendar.date(byAdding: .day, value: n, to: date)
        case .weekly: calendar.date(byAdding: .weekOfYear, value: n, to: date)
        case .monthly: calendar.date(byAdding: .month, value: n, to: date)
        case .yearly: calendar.date(byAdding: .year, value: n, to: date)
        }
    }

    // MARK: - Candidates within one period

    private static func candidates(in period: Date, rule: Recurrence, start: Date, time: DateComponents, calendar: Calendar) -> [Date] {
        let startParts = calendar.dateComponents([.month, .day, .weekday], from: start)
        var days: [DateComponents] = []

        switch rule.frequency {
        case .daily:
            days = [calendar.dateComponents([.year, .month, .day], from: period)]
        case .weekly:
            let weekdays = rule.byWeekday.isEmpty ? [startParts.weekday!] : rule.byWeekday.map(\.weekday)
            for offset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: offset, to: period)!
                if weekdays.contains(calendar.component(.weekday, from: day)) {
                    days.append(calendar.dateComponents([.year, .month, .day], from: day))
                }
            }
        case .monthly:
            days = Self.days(inMonthOf: period, rule: rule, defaultDay: startParts.day!, calendar: calendar)
        case .yearly:
            let year = calendar.component(.year, from: period)
            for month in rule.byMonth.isEmpty ? [startParts.month!] : rule.byMonth.sorted() {
                let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
                days += Self.days(inMonthOf: monthStart, rule: rule, defaultDay: startParts.day!, calendar: calendar)
            }
        }

        // Filters that narrow a coarser frequency (e.g. a daily rule only in June, or only on weekdays).
        if !rule.byMonth.isEmpty, rule.frequency != .yearly {
            days = days.filter { rule.byMonth.contains($0.month!) }
        }
        if rule.frequency == .daily {
            if !rule.byWeekday.isEmpty {
                let weekdays = rule.byWeekday.map(\.weekday)
                days = days.filter { weekdays.contains(calendar.component(.weekday, from: calendar.date(from: $0)!)) }
            }
            if !rule.byMonthDay.isEmpty {
                days = days.filter { comps in
                    let length = calendar.range(of: .day, in: .month, for: calendar.date(from: comps)!)!.count
                    return rule.byMonthDay.contains { ($0 > 0 ? $0 : length + 1 + $0) == comps.day! }
                }
            }
        }

        var dates = days.compactMap { day -> Date? in
            var parts = day
            parts.hour = time.hour
            parts.minute = time.minute
            parts.second = time.second
            return calendar.date(from: parts)
        }.sorted()

        if !rule.bySetPosition.isEmpty {
            dates = rule.bySetPosition.compactMap { pos in
                let index = pos > 0 ? pos - 1 : dates.count + pos
                return dates.indices.contains(index) ? dates[index] : nil
            }.sorted()
        }
        return dates
    }

    /// The days of one month a monthly (or yearly-by-month) rule lands on.
    private static func days(inMonthOf monthStart: Date, rule: Recurrence, defaultDay: Int, calendar: Calendar) -> [DateComponents] {
        let ym = calendar.dateComponents([.year, .month], from: monthStart)
        let length = calendar.range(of: .day, in: .month, for: monthStart)!.count
        func day(_ d: Int) -> DateComponents { DateComponents(year: ym.year, month: ym.month, day: d) }

        if !rule.byMonthDay.isEmpty {
            // A day the month lacks (the 31st in April) is skipped, as RFC 5545 says.
            return Set(rule.byMonthDay.map { $0 > 0 ? $0 : length + 1 + $0 })
                .filter { (1...length).contains($0) }
                .sorted()
                .map(day)
        }
        if !rule.byWeekday.isEmpty {
            var result: Set<Int> = []
            for weekdayRule in rule.byWeekday {
                let matches = (1...length).filter {
                    calendar.component(.weekday, from: calendar.date(from: day($0))!) == weekdayRule.weekday
                }
                if let ordinal = weekdayRule.ordinal {
                    let index = ordinal > 0 ? ordinal - 1 : matches.count + ordinal
                    if matches.indices.contains(index) { result.insert(matches[index]) }
                } else {
                    result.formUnion(matches)
                }
            }
            return result.sorted().map(day)
        }
        return defaultDay <= length ? [day(defaultDay)] : []
    }
}
