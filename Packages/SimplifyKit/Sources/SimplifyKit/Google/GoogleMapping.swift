import Foundation

extension GoogleEvent {
    /// The stored form of this event. `calendar` reads all-day EXDATEs on the user's own days;
    /// `defaultZone` is the calendar's zone for timed events that do not name one.
    public func snapshot(sourceID: String, calendar: Calendar, defaultZone: String?) -> EventSnapshot {
        let isAllDay = start?.date != nil
        var event = EventSnapshot(id: sourceID + ":" + id, sourceID: sourceID, remoteID: id,
                                  title: summary?.isEmpty == false ? summary! : "(제목 없음)", isAllDay: isAllDay)
        event.location = location
        event.notes = description.flatMap { $0.isEmpty ? nil : $0 }
        event.isCancelled = status == "cancelled"
        event.timeZone = start?.timeZone ?? defaultZone

        if isAllDay {
            event.startDay = start?.date
            event.endDay = end?.date
        } else {
            event.start = start?.dateTime.flatMap(Self.parseDateTime)
            event.end = end?.dateTime.flatMap(Self.parseDateTime)
        }

        if let lines = recurrence, recurringEventId == nil {
            // Timed series repeat in their own zone; all-day ones by calendar day, read in UTC.
            var zoned = isAllDay ? DayKey.utc : calendar
            if !isAllDay, let id = event.timeZone, let zone = TimeZone(identifier: id) { zoned.timeZone = zone }
            let rules = lines.filter { $0.uppercased().hasPrefix("RRULE") }
            // Several RRULEs, RDATEs, or a rule the engine does not cover: Google expands it instead.
            if rules.count == 1, !lines.contains(where: { $0.uppercased().hasPrefix("RDATE") }),
               let rule = Recurrence(rrule: rules[0], calendar: zoned) {
                event.recurrence = rule
            } else {
                event.recurrenceUnsupported = true
            }
            event.exceptionDates = Recurrence.exceptionDates(from: lines, calendar: zoned)
        }

        if let recurringEventId {
            event.recurringEventID = recurringEventId
            event.originalStartDay = originalStartTime?.date
            event.originalStart = originalStartTime?.dateTime.flatMap(Self.parseDateTime)
        }
        return event
    }

    /// RFC 3339, with or without fractional seconds.
    static func parseDateTime(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
