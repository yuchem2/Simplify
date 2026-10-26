import Foundation

/// One stored event as plain values: a single event, a repeating series (its master), or one
/// changed or cancelled occurrence of a series. Providers fill it in; the views never see it.
public struct EventSnapshot: Hashable, Sendable {
    public var id: String
    public var sourceID: String
    /// The provider's event id; a series and its changed occurrences share a master id.
    public var remoteID: String
    public var title: String
    public var location: String?
    public var isAllDay: Bool
    /// Timed events: the instants. All-day events: unused.
    public var start: Date?
    public var end: Date?
    /// All-day events: `2026-10-29` and the day after the last day (exclusive), as the
    /// provider sends them, so they stay on the same calendar days in every time zone.
    public var startDay: String?
    public var endDay: String?
    /// The zone a timed series repeats in, so 9:00 stays 9:00 across DST.
    public var timeZone: String?
    public var recurrence: Recurrence?
    /// The series repeats by a rule the engine cannot expand; its occurrences are stored one by one.
    public var recurrenceUnsupported = false
    public var exceptionDates: [Date] = []
    /// For a changed or cancelled occurrence: the series it belongs to, and where it was meant to start.
    public var recurringEventID: String?
    public var originalStart: Date?
    public var originalStartDay: String?
    public var isCancelled = false
    /// One occurrence of a series fetched from the provider because the engine cannot expand its
    /// rule (as opposed to an exception the person made).
    public var isExpandedInstance = false

    public init(id: String, sourceID: String, remoteID: String, title: String, isAllDay: Bool) {
        self.id = id
        self.sourceID = sourceID
        self.remoteID = remoteID
        self.title = title
        self.isAllDay = isAllDay
    }
}

/// An event as it appears on a given day: one occurrence of a series, or a single event.
public struct EventOccurrence: Identifiable, Hashable, Sendable {
    public let id: String
    public let eventID: String
    public let sourceID: String
    public let title: String
    public let location: String?
    public let isAllDay: Bool
    public let start: Date
    /// Exclusive.
    public let end: Date

    /// All-day events and anything lasting a day or more run across cells as a band.
    public var isBand: Bool { isAllDay || end.timeIntervalSince(start) >= 24 * 3600 }
}

public enum DayKey {
    /// `yyyy-MM-dd` → the start of that day in `calendar`.
    public static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The `yyyy-MM-dd` of `date` in `calendar`.
    public static func key(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// All-day rule dates (EXDATE, a date-only UNTIL) are read in UTC so they stay on the same
    /// calendar day whatever zone the person is in; compare them by `key(_:calendar: utc)`.
    public static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
