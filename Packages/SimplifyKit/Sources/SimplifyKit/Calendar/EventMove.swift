import Foundation

/// An event dragged from one day to another: it keeps its times and its length, and only its days change.
public enum EventMove {
    /// Whole days from the day the event was picked up on to the day it was dropped on.
    public static func days(from grabbed: Date, to dropped: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: grabbed), to: calendar.startOfDay(for: dropped)).day ?? 0
    }

    /// `start` and `end` moved by `days` on the calendar, so the clock times stay as they were
    /// across a daylight-saving change, and an all-day event still starts and ends at midnight.
    public static func shift(start: Date, end: Date, byDays days: Int, calendar: Calendar) -> (start: Date, end: Date) {
        guard days != 0 else { return (start, end) }
        let movedStart = calendar.date(byAdding: .day, value: days, to: start) ?? start
        let movedEnd = calendar.date(byAdding: .day, value: days, to: end) ?? end
        return (movedStart, max(movedStart, movedEnd))
    }
}

/// What an event row carries while it is dragged: the occurrence, and the day whose row was
/// picked up (a band shows on several).
public struct EventDragItem: Codable, Equatable, Sendable {
    public var occurrenceID: String
    public var day: Date

    public init(occurrenceID: String, day: Date) {
        self.occurrenceID = occurrenceID
        self.day = day
    }
}
