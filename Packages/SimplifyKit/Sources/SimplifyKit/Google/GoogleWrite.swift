import Foundation

// Creating, changing and deleting events through `events.insert`, `patch` and `delete`.
// One occurrence of a series is its own instance (`<series id>_<original start>`); "this and
// following" ends the series before the occurrence and starts a new one there.
extension GoogleCalendarAPI {
    public func createEvent(_ draft: EventDraft, id: String, in remote: RemoteCalendar.Reference, calendar: Calendar) async throws {
        var body = Self.body(draft, start: draft.start, end: draft.end, calendar: calendar, clearing: false)
        body["id"] = id
        if let rule = draft.repeatRule.rrule { body["recurrence"] = [rule] }
        try await insertEvent(calendarID: remote.remoteID, body)
    }

    public func updateEvent(_ event: EventSnapshot, to draft: EventDraft, scope: EditScope, in remote: RemoteCalendar.Reference, calendar: Calendar) async throws {
        let calendarID = remote.remoteID
        guard event.isSeriesMember else {
            var body = Self.body(draft, start: draft.start, end: draft.end, calendar: calendar, clearing: true)
            if let rule = draft.repeatRule.rrule { body["recurrence"] = [rule] }
            return try await patchEvent(calendarID: calendarID, eventID: event.remoteID, body)
        }
        switch scope {
        case .thisOccurrence(let originalStart):
            let body = Self.body(draft, start: draft.start, end: draft.end, calendar: calendar, clearing: true)
            try await patchEvent(calendarID: calendarID, eventID: Self.instanceID(of: event, originalStart: originalStart, calendar: calendar), body)
        case .allOccurrences:
            let master = try await self.event(calendarID: calendarID, eventID: event.seriesRemoteID)
            try await patchEvent(calendarID: calendarID, eventID: master.id, Self.seriesBody(master, event: event, draft: draft, calendar: calendar, zone: remote.timeZone))
        case .thisAndFollowing(let originalStart):
            let master = try await self.event(calendarID: calendarID, eventID: event.seriesRemoteID)
            let split = OccurrenceKey(event: event, originalStart: originalStart, calendar: calendar)
            guard let ended = Self.ending(master, before: split, calendar: calendar, zone: remote.timeZone) else {
                // The first occurrence: the whole series changes.
                return try await patchEvent(calendarID: calendarID, eventID: master.id, Self.seriesBody(master, event: event, draft: draft, calendar: calendar, zone: remote.timeZone))
            }
            // The new part first: should the second request fail, occurrences show twice rather than not at all.
            var body = Self.body(draft, start: draft.start, end: draft.end, calendar: calendar, clearing: false)
            body["id"] = EventDraft.splitID(series: master.id, at: split)
            if draft.changesRule(of: event) {
                if let rule = draft.repeatRule.rrule { body["recurrence"] = [rule] }
            } else {
                body["recurrence"] = Self.following(master, from: split, calendar: calendar, zone: remote.timeZone)
            }
            try await insertEvent(calendarID: calendarID, body)
            try await patchEvent(calendarID: calendarID, eventID: master.id, ["recurrence": ended])
        }
    }

    public func deleteEvent(_ event: EventSnapshot, scope: EditScope, in remote: RemoteCalendar.Reference, calendar: Calendar) async throws {
        let calendarID = remote.remoteID
        guard event.isSeriesMember else { return try await deleteEvent(calendarID: calendarID, eventID: event.remoteID) }
        switch scope {
        case .thisOccurrence(let originalStart):
            try await deleteEvent(calendarID: calendarID, eventID: Self.instanceID(of: event, originalStart: originalStart, calendar: calendar))
        case .allOccurrences:
            try await deleteEvent(calendarID: calendarID, eventID: event.seriesRemoteID)
        case .thisAndFollowing(let originalStart):
            let master = try await self.event(calendarID: calendarID, eventID: event.seriesRemoteID)
            let split = OccurrenceKey(event: event, originalStart: originalStart, calendar: calendar)
            if let ended = Self.ending(master, before: split, calendar: calendar, zone: remote.timeZone) {
                try await patchEvent(calendarID: calendarID, eventID: master.id, ["recurrence": ended])
            } else {
                try await deleteEvent(calendarID: calendarID, eventID: master.id)
            }
        }
    }

    // MARK: - Bodies

    /// Title, place, notes and times. `clearing` sends the unused time keys and empty fields as
    /// null, so a patch turns a timed event into an all-day one (and back) and clears a place.
    static func body(_ draft: EventDraft, start: Date, end: Date, calendar: Calendar, clearing: Bool) -> [String: Any] {
        func time(_ date: Date) -> [String: Any] {
            var time: [String: Any] = [:]
            if draft.isAllDay {
                time["date"] = DayKey.key(date, calendar: calendar)
                if clearing { time["dateTime"] = NSNull(); time["timeZone"] = NSNull() }
            } else {
                let zone = draft.zoneID(calendar)
                let format = ISO8601DateFormatter()
                format.timeZone = TimeZone(identifier: zone) ?? calendar.timeZone
                time["dateTime"] = format.string(from: date)
                time["timeZone"] = zone
                if clearing { time["date"] = NSNull() }
            }
            return time
        }
        var body: [String: Any] = ["summary": draft.title, "start": time(start), "end": time(end)]
        for (key, value) in [("location", draft.location), ("description", draft.notes)] {
            if let value, !value.isEmpty { body[key] = value } else if clearing { body[key] = NSNull() }
        }
        return body
    }

    /// The patch for a whole series: moved as the draft moved its occurrence, with a new rule
    /// only when the person picked another preset.
    static func seriesBody(_ master: GoogleEvent, event: EventSnapshot, draft: EventDraft, calendar: Calendar, zone: String?) -> [String: Any] {
        let span = draft.seriesSpan(masterDay: firstDay(of: master, draft: draft, calendar: calendar, zone: zone), calendar: calendar)
        var body = body(draft, start: span.start, end: span.end, calendar: calendar, clearing: true)
        if draft.changesRule(of: event) {
            body["recurrence"] = draft.repeatRule.rrule.map { [$0] } ?? []
        }
        return body
    }

    /// The day the series starts on, in the zone the draft reads days in.
    private static func firstDay(of master: GoogleEvent, draft: EventDraft, calendar: Calendar, zone: String?) -> DateComponents {
        let snapshot = master.snapshot(sourceID: "", calendar: calendar, defaultZone: zone)
        if let key = snapshot.startDay, let day = DayKey.date(key, calendar: calendar) {
            return calendar.dateComponents([.year, .month, .day], from: day)
        }
        return draft.zoned(calendar).dateComponents([.year, .month, .day], from: snapshot.start ?? draft.start)
    }

    /// The series' recurrence lines ending before `split`, or nil when `split` is its first occurrence.
    static func ending(_ master: GoogleEvent, before split: OccurrenceKey, calendar: Calendar, zone: String?) -> [String]? {
        let snapshot = master.snapshot(sourceID: "", calendar: calendar, defaultZone: zone)
        if let day = split.day {
            guard let first = snapshot.startDay, day > first else { return nil }
        } else {
            guard let first = snapshot.start, split.date > first else { return nil }
        }
        let until = RuleText.until(before: split, calendar: calendar)
        return (master.recurrence ?? []).map { $0.uppercased().hasPrefix("RRULE") ? RuleText.rrule($0, until: until) : $0 }
    }

    /// The series' recurrence lines for a new series starting at `split`, with a COUNT cut down
    /// to the occurrences left.
    static func following(_ master: GoogleEvent, from split: OccurrenceKey, calendar: Calendar, zone: String?) -> [String] {
        let snapshot = master.snapshot(sourceID: "", calendar: calendar, defaultZone: zone)
        var zoned = snapshot.isAllDay ? DayKey.utc : calendar
        if !snapshot.isAllDay, let id = snapshot.timeZone, let tz = TimeZone(identifier: id) { zoned.timeZone = tz }
        let first = snapshot.startDay.flatMap { DayKey.date($0, calendar: DayKey.utc) } ?? snapshot.start
        let splitDate = split.day.flatMap { DayKey.date($0, calendar: DayKey.utc) } ?? split.date
        return (master.recurrence ?? []).map { line in
            guard line.uppercased().hasPrefix("RRULE"), let count = RuleText.count(in: line), let first,
                  let before = RuleText.occurrences(of: line, start: first, before: splitDate, calendar: zoned) else { return line }
            return RuleText.rrule(line, count: max(1, count - before))
        }
    }

    /// The instance id Google gives one occurrence: `<series>_20261105T010000Z`, or
    /// `<series>_20261105` all day. A changed occurrence already carries its own.
    static func instanceID(of event: EventSnapshot, originalStart: Date, calendar: Calendar) -> String {
        if event.recurringEventID != nil { return event.remoteID }
        let key = OccurrenceKey(event: event, originalStart: originalStart, calendar: calendar)
        if let day = key.day { return event.remoteID + "_" + day.replacingOccurrences(of: "-", with: "") }
        return event.remoteID + "_" + ICalendarWriter.utcStamp(key.date)
    }
}
