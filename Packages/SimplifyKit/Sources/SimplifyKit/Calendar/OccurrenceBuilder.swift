import Foundation

/// Turns stored events into the occurrences that fall in a range, and lays them out by day.
public enum OccurrenceBuilder {
    /// Every occurrence overlapping `range`, sorted by start (all-day first on the same start).
    ///
    /// Series are expanded with their rule, minus EXDATEs and minus occurrences that were moved
    /// or cancelled; moved ones then appear at their new time.
    public static func occurrences(from events: [EventSnapshot], in range: DateInterval, calendar: Calendar) -> [EventOccurrence] {
        // Occurrences of a series that were changed or cancelled, keyed by series.
        var replaced: [String: Set<Date>] = [:]
        for event in events where event.recurringEventID != nil {
            guard let original = originalStart(of: event, calendar: calendar) else { continue }
            replaced[seriesKey(event.sourceID, event.recurringEventID!), default: []].insert(original)
        }

        var result: [EventOccurrence] = []
        for event in events where !event.isCancelled {
            guard let (start, end) = span(of: event, calendar: calendar) else { continue }
            let isSeries = (event.recurrence != nil || event.recurrenceUnsupported) && event.recurringEventID == nil
            // A series whose rule cannot be expanded shows only through its stored occurrences.
            if isSeries, event.recurrenceUnsupported { continue }
            if isSeries, var rule = event.recurrence {
                var zoned = calendar
                if !event.isAllDay, let id = event.timeZone, let zone = TimeZone(identifier: id) { zoned.timeZone = zone }
                let duration = end.timeIntervalSince(start)
                let replacedStarts = replaced[seriesKey(event.sourceID, event.remoteID)] ?? []
                var starts: [Date]
                if event.isAllDay {
                    // All-day rule dates were read in UTC; compare by calendar day so they hold in any zone.
                    if let until = rule.until, let lastDay = DayKey.date(DayKey.key(until, calendar: DayKey.utc), calendar: calendar) {
                        rule.until = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: lastDay)
                    }
                    let skipDays = Set(event.exceptionDates.map { DayKey.key($0, calendar: DayKey.utc) })
                        .union(replacedStarts.map { DayKey.key($0, calendar: calendar) })
                    starts = RecurrenceExpander.occurrences(of: rule, start: start, duration: duration, calendar: zoned, in: range)
                        .filter { !skipDays.contains(DayKey.key($0, calendar: calendar)) }
                } else {
                    let skip = Set(event.exceptionDates).union(replacedStarts)
                    starts = RecurrenceExpander.occurrences(of: rule, start: start, duration: duration, calendar: zoned, in: range, excluding: skip)
                }
                for occurrenceStart in starts {
                    let occurrenceEnd = event.isAllDay
                        ? calendar.date(byAdding: .day, value: dayCount(start, end, calendar), to: occurrenceStart)!
                        : occurrenceStart.addingTimeInterval(duration)
                    result.append(occurrence(event, start: occurrenceStart, end: occurrenceEnd))
                }
            } else if start < range.end, max(end, start.addingTimeInterval(1)) > range.start {
                result.append(occurrence(event, start: start, end: end))
            }
        }
        return result.sorted { ($0.start, $0.isAllDay ? 0 : 1, $0.title) < ($1.start, $1.isAllDay ? 0 : 1, $1.title) }
    }

    /// One entry of a day cell or day list.
    public struct Slot: Hashable, Sendable {
        public let occurrence: EventOccurrence
        /// The band started on an earlier day / goes on to a later day.
        public let continuesFromPrevious: Bool
        public let continuesToNext: Bool
    }

    /// Occurrences for each of `days`: bands (all-day or a day or longer) on every day they cover,
    /// then timed events on the day they start, then completed reminders.
    public static func byDay(_ occurrences: [EventOccurrence], days: [Date], calendar: Calendar) -> [Date: [Slot]] {
        var result: [Date: [Slot]] = [:]
        for day in days {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
            var bands: [Slot] = []
            var timed: [Slot] = []
            for occurrence in occurrences {
                if occurrence.isBand {
                    guard occurrence.start < dayEnd, occurrence.end > day else { continue }
                    bands.append(Slot(occurrence: occurrence,
                                      continuesFromPrevious: occurrence.start < day,
                                      continuesToNext: occurrence.end > dayEnd))
                } else if occurrence.start >= day, occurrence.start < dayEnd {
                    timed.append(Slot(occurrence: occurrence, continuesFromPrevious: false, continuesToNext: false))
                }
            }
            // Earlier, then longer bands first. Rows can still shift between days when bands overlap;
            // per-week lanes would fix that (left for when the week grid arrives).
            bands.sort { ($0.occurrence.start, -$0.occurrence.end.timeIntervalSince1970) < ($1.occurrence.start, -$1.occurrence.end.timeIntervalSince1970) }
            let slots = bands + timed
            result[day] = slots.filter { !$0.occurrence.isCompleted } + slots.filter(\.occurrence.isCompleted)
        }
        return result
    }

    // MARK: -

    private static func seriesKey(_ source: String, _ remote: String) -> String { source + "\u{1F}" + remote }

    private static func span(of event: EventSnapshot, calendar: Calendar) -> (Date, Date)? {
        if event.isAllDay {
            guard let startKey = event.startDay, let start = DayKey.date(startKey, calendar: calendar) else { return nil }
            let end = event.endDay.flatMap { DayKey.date($0, calendar: calendar) } ?? calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, max(end, calendar.date(byAdding: .day, value: 1, to: start)!))
        }
        guard let start = event.start else { return nil }
        return (start, max(event.end ?? start, start))
    }

    private static func originalStart(of event: EventSnapshot, calendar: Calendar) -> Date? {
        if let day = event.originalStartDay { return DayKey.date(day, calendar: calendar) }
        return event.originalStart
    }

    private static func dayCount(_ start: Date, _ end: Date, _ calendar: Calendar) -> Int {
        max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
    }

    private static func occurrence(_ event: EventSnapshot, start: Date, end: Date) -> EventOccurrence {
        EventOccurrence(id: event.id + "@" + String(Int(start.timeIntervalSince1970)), eventID: event.id, sourceID: event.sourceID,
                        title: event.title, location: event.location, isAllDay: event.isAllDay, start: start, end: end,
                        isCompleted: event.isCompleted)
    }
}
