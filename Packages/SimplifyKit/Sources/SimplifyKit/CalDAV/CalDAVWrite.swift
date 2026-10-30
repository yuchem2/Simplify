import Foundation

// Creating, changing and deleting events on a CalDAV server. A change reads the resource first,
// edits only the properties it is about (alarms, attendees and anything else unknown stay as
// they were), and writes it back over the version it read (If-Match), so a change made elsewhere
// in between is a conflict rather than lost.
extension CalDAVProvider {
    public func createEvent(_ draft: EventDraft, id: String, in remote: RemoteCalendar.Reference, calendar: Calendar) async throws {
        guard let collection = URL(string: remote.remoteID) else { throw CalendarSyncError.invalidResponse }
        let url = collection.appending(path: id + ".ics")
        var resource = ICSResource(calendar: ICSResource.newCalendar(), person: calendar, defaultZone: remote.timeZone)
        var event = ICalendar.Component(name: "VEVENT", properties: [ICalendar.Property(name: "UID", params: [:], value: id)])
        resource.apply(draft, start: draft.start, end: draft.end, to: &event)
        if let rule = draft.repeatRule.rrule { event.set("RRULE", ICSResource.rrule(rule)) }
        resource.calendar.children.append(event)
        resource.defineZone(of: draft)
        do {
            try await client.put(url, ics: resource.text, etag: nil, isNew: true)
        } catch CalendarSyncError.conflict {
            // A retry after a lost answer finds the event already there.
            guard try await client.resource(url).ics.contains("UID:" + id) else { throw CalendarSyncError.conflict }
        }
    }

    public func updateEvent(_ event: EventSnapshot, to draft: EventDraft, scope: EditScope, in remote: RemoteCalendar.Reference, calendar: Calendar) async throws {
        var (url, etag, resource) = try await load(event, in: remote, calendar: calendar)
        let uid = event.seriesRemoteID
        switch event.isSeriesMember ? scope : .allOccurrences {
        case .allOccurrences:
            try resource.editAll(uid, event: event, draft: draft)
        case .thisOccurrence(let originalStart):
            try resource.editOccurrence(uid, OccurrenceKey(event: event, originalStart: originalStart, calendar: calendar), draft: draft)
        case .thisAndFollowing(let originalStart):
            let key = OccurrenceKey(event: event, originalStart: originalStart, calendar: calendar)
            let newUID = EventDraft.splitID(series: uid, at: key)
            guard var tail = try resource.split(uid, at: key, newUID: newUID),
                  let collection = URL(string: remote.remoteID) else {
                try resource.editAll(uid, event: event, draft: draft)
                break
            }
            try tail.editAll(newUID, event: event, draft: draft)
            tail.defineZone(of: draft)
            // The new part first: should the second write fail, occurrences show twice rather than not at all.
            let tailURL = collection.appending(path: newUID + ".ics")
            do {
                try await client.put(tailURL, ics: tail.text, etag: nil, isNew: true)
            } catch CalendarSyncError.conflict {
                // Written by an earlier try of this same change.
                guard try await client.resource(tailURL).ics.contains("UID:" + newUID) else { throw CalendarSyncError.conflict }
            }
        }
        resource.defineZone(of: draft)
        try await client.put(url, ics: resource.text, etag: etag)
    }

    public func deleteEvent(_ event: EventSnapshot, scope: EditScope, in remote: RemoteCalendar.Reference, calendar: Calendar) async throws {
        let loaded: (url: URL, etag: String?, resource: ICSResource)
        do {
            loaded = try await load(event, in: remote, calendar: calendar)
        } catch CalendarSyncError.conflict {
            return  // Already gone.
        }
        var resource = loaded.resource
        let uid = event.seriesRemoteID
        switch event.isSeriesMember ? scope : .allOccurrences {
        case .allOccurrences:
            return try await client.delete(loaded.url, etag: loaded.etag)
        case .thisOccurrence(let originalStart):
            resource.removeOccurrence(uid, OccurrenceKey(event: event, originalStart: originalStart, calendar: calendar))
        case .thisAndFollowing(let originalStart):
            guard try resource.split(uid, at: OccurrenceKey(event: event, originalStart: originalStart, calendar: calendar), newUID: nil) != nil else {
                return try await client.delete(loaded.url, etag: loaded.etag)
            }
        }
        if !resource.calendar.children.contains(where: { $0.name == "VEVENT" }) {
            return try await client.delete(loaded.url, etag: loaded.etag)
        }
        try await client.put(loaded.url, ics: resource.text, etag: loaded.etag)
    }

    /// The resource `event` came in, as it is on the server now.
    private func load(_ event: EventSnapshot, in remote: RemoteCalendar.Reference, calendar: Calendar) async throws -> (url: URL, etag: String?, resource: ICSResource) {
        guard let collection = URL(string: remote.remoteID), let href = event.resourceHref,
              let url = CalDAVClient.url(ofResource: href, in: collection) else { throw CalendarSyncError.invalidResponse }
        let (ics, etag) = try await client.resource(url)
        guard let vcalendar = ICalendar.parse(ics).first(where: { $0.name == "VCALENDAR" }) else { throw CalendarSyncError.invalidResponse }
        return (url, etag, ICSResource(calendar: vcalendar, person: calendar, defaultZone: remote.timeZone))
    }
}

/// One CalDAV resource being edited: a VCALENDAR with a series (or single event) and its
/// changed occurrences.
struct ICSResource {
    typealias Property = ICalendar.Property
    typealias Component = ICalendar.Component

    var calendar: Component
    /// The person's calendar: all-day dates are its midnights.
    let person: Calendar
    let floating: ICalendar.Floating

    init(calendar: Component, person: Calendar, defaultZone: String?) {
        self.calendar = calendar
        self.person = person
        floating = ICalendar.floating(calendar: person, defaultZone: defaultZone)
    }

    static func newCalendar() -> Component {
        Component(name: "VCALENDAR", properties: [
            Property(name: "VERSION", params: [:], value: "2.0"),
            Property(name: "PRODID", params: [:], value: "-//Simplify//Simplify//KO"),
            Property(name: "CALSCALE", params: [:], value: "GREGORIAN"),
        ])
    }

    static func rrule(_ line: String) -> Property {
        Property(name: "RRULE", params: [:], value: line.hasPrefix("RRULE:") ? String(line.dropFirst(6)) : line)
    }

    var text: String { ICalendarWriter.text([calendar]) }

    // MARK: - Edits

    /// Changes the series (or single event) as a whole. Changed occurrences and EXDATEs move with
    /// it; a new rule drops them, as they belonged to the old one.
    mutating func editAll(_ uid: String, event: EventSnapshot, draft: EventDraft) throws {
        guard let index = masterIndex(uid), let oldStart = calendar.children[index].first("DTSTART").flatMap(moment) else {
            throw CalendarSyncError.invalidResponse
        }
        var master = calendar.children[index]
        let span = draft.seriesSpan(masterDay: day(of: oldStart, in: draft.zoned(person)), calendar: person)
        apply(draft, start: span.start, end: span.end, to: &master)
        let isSeries = !master.all("RRULE").isEmpty || !master.all("RDATE").isEmpty
        let changesRule = isSeries ? draft.changesRule(of: event) : draft.repeatRule != .none

        if changesRule {
            ["RRULE", "RDATE", "EXDATE"].forEach { master.remove($0) }
            if let rule = draft.repeatRule.rrule { master.set("RRULE", Self.rrule(rule)) }
            calendar.children[index] = master
            let reader = self
            calendar.children.removeAll { reader.isOverride($0, of: uid) }
            return
        }
        guard isSeries else {
            calendar.children[index] = master
            return
        }

        // Occurrence ids move as many days as the series start did, to its new time of day.
        func moved(_ name: String, _ old: ICalendar.Moment) -> Property {
            let days = dayCount(from: oldStart, to: old)
            let date: Date
            if draft.isAllDay {
                date = person.date(byAdding: .day, value: days, to: span.start)!
            } else {
                let zoned = draft.zoned(person)
                date = zoned.date(byAdding: .day, value: days, to: span.start)!
            }
            return ICalendarWriter.time(name, date, isAllDay: draft.isAllDay, zone: draft.zoneID(person), calendar: person)
        }
        let exdates = master.all("EXDATE").flatMap(values).map { moved("EXDATE", $0) }
        master.remove("EXDATE")
        master.properties += exdates
        if oldStart.isDay != draft.isAllDay {
            master.set("RRULE", master.first("RRULE").map { retyped(rule: $0, allDay: draft.isAllDay, zone: draft.zoned(person)) })
        }
        calendar.children[index] = master
        for i in calendar.children.indices where isOverride(calendar.children[i], of: uid) {
            guard let id = calendar.children[i].first("RECURRENCE-ID").flatMap(moment) else { continue }
            calendar.children[i].set("RECURRENCE-ID", moved("RECURRENCE-ID", id))
        }
    }

    /// Changes one occurrence: its changed copy when there is one, otherwise a new one made from
    /// the series (alarms included).
    mutating func editOccurrence(_ uid: String, _ key: OccurrenceKey, draft: EventDraft) throws {
        if let index = overrideIndex(uid, key) {
            var changed = calendar.children[index]
            apply(draft, start: draft.start, end: draft.end, to: &changed)
            calendar.children[index] = changed
            return
        }
        guard let index = masterIndex(uid), let start = calendar.children[index].first("DTSTART") else { throw CalendarSyncError.invalidResponse }
        var copy = calendar.children[index]
        ["RRULE", "RDATE", "EXDATE"].forEach { copy.remove($0) }
        copy.set("RECURRENCE-ID", like(start, "RECURRENCE-ID", key))
        apply(draft, start: draft.start, end: draft.end, to: &copy)
        calendar.children.insert(copy, at: index + 1)
    }

    /// Leaves one occurrence out: an EXDATE on the series, and its changed copy gone.
    mutating func removeOccurrence(_ uid: String, _ key: OccurrenceKey) {
        if let index = overrideIndex(uid, key) { calendar.children.remove(at: index) }
        guard let index = masterIndex(uid), let start = calendar.children[index].first("DTSTART") else { return }
        var master = calendar.children[index]
        master.properties.append(like(start, "EXDATE", key))
        Self.stamp(&master)
        calendar.children[index] = master
    }

    /// Ends the series before `key`. With `newUID`, returns the part from `key` on as a resource
    /// of its own (its changed occurrences and EXDATEs with it, a COUNT cut down to what is left).
    /// Nil when `key` is the series' first occurrence, which leaves nothing to split.
    mutating func split(_ uid: String, at key: OccurrenceKey, newUID: String?) throws -> ICSResource? {
        guard let index = masterIndex(uid), let startProperty = calendar.children[index].first("DTSTART"),
              let start = moment(startProperty) else { throw CalendarSyncError.invalidResponse }
        guard isBefore(start, key) else { return nil }
        var tail = self
        let master = calendar.children[index]

        // Up to the split.
        var head = master
        let until = RuleText.until(before: start.isDay ? dayKeyed(key) : key, calendar: person)
        head.set("RRULE", head.first("RRULE").map { Self.rrule(RuleText.rrule($0.value, until: until)) })
        keepExdates(&head) { isBefore($0, key) }
        Self.stamp(&head)
        calendar.children[index] = head
        let reader = self
        calendar.children.removeAll { reader.isOverride($0, of: uid) && !($0.first("RECURRENCE-ID").flatMap(reader.moment).map { reader.isBefore($0, key) } ?? false) }

        guard let newUID else { return tail }
        // From the split on.
        var first = master
        let end = master.first("DTEND")
        let length: (days: Int, seconds: TimeInterval) = {
            guard let end, let endMoment = moment(end) else { return (start.isDay ? 1 : 0, 0) }
            switch (start, endMoment) {
            case (.day, .day): return (dayCount(from: start, to: endMoment), 0)
            case (.instant(let a, _), .instant(let b, _)): return (0, b.timeIntervalSince(a))
            default: return (0, 0)
            }
        }()
        first.set("DTSTART", like(startProperty, "DTSTART", key))
        if let end {
            let endKey = start.isDay
                ? OccurrenceKey(date: person.date(byAdding: .day, value: length.days, to: dayKeyed(key).date)!, day: nil)
                : OccurrenceKey(date: key.date.addingTimeInterval(length.seconds), day: nil)
            first.set("DTEND", like(start.isDay ? startProperty : end, "DTEND", start.isDay ? dayKeyed(endKey) : endKey))
        }
        if let rule = first.first("RRULE"), let count = RuleText.count(in: rule.value) {
            var zoned = start.isDay ? DayKey.utc : floating.calendar
            if case .instant(let date, let zone) = start {
                if let zone, let tz = TimeZone(identifier: zone) { zoned.timeZone = tz }
                let before = RuleText.occurrences(of: rule.value, start: date, before: key.date, calendar: zoned) ?? 0
                first.set("RRULE", Self.rrule(RuleText.rrule(rule.value, count: max(1, count - before))))
            } else if case .day(_, let date) = start, let splitDay = DayKey.date(dayKeyed(key).day!, calendar: DayKey.utc) {
                let before = RuleText.occurrences(of: rule.value, start: date, before: splitDay, calendar: zoned) ?? 0
                first.set("RRULE", Self.rrule(RuleText.rrule(rule.value, count: max(1, count - before))))
            }
        }
        keepExdates(&first) { !reader.isBefore($0, key) }
        tail.calendar.children[index] = first
        tail.calendar.children.removeAll { reader.isOverride($0, of: uid) && ($0.first("RECURRENCE-ID").flatMap(reader.moment).map { reader.isBefore($0, key) } ?? true) }
        for i in tail.calendar.children.indices where tail.calendar.children[i].name == "VEVENT" && tail.calendar.children[i].first("UID")?.value == uid {
            tail.calendar.children[i].set("UID", Property(name: "UID", params: [:], value: newUID))
        }
        // Other events the resource may hold stay with the original.
        tail.calendar.children.removeAll { $0.name == "VEVENT" && $0.first("UID")?.value != newUID }
        return tail
    }

    /// Writes the draft's title, place, notes and times into one VEVENT.
    func apply(_ draft: EventDraft, start: Date, end: Date, to event: inout Component) {
        event.set("SUMMARY", ICalendarWriter.textProperty("SUMMARY", draft.title))
        event.set("LOCATION", draft.location.flatMap { $0.isEmpty ? nil : ICalendarWriter.textProperty("LOCATION", $0) })
        event.set("DESCRIPTION", draft.notes.flatMap { $0.isEmpty ? nil : ICalendarWriter.textProperty("DESCRIPTION", $0) })
        let zone = draft.zoneID(person)
        event.set("DTSTART", ICalendarWriter.time("DTSTART", start, isAllDay: draft.isAllDay, zone: zone, calendar: person))
        event.set("DTEND", ICalendarWriter.time("DTEND", end, isAllDay: draft.isAllDay, zone: zone, calendar: person))
        event.remove("DURATION")
        Self.stamp(&event)
    }

    /// Adds a VTIMEZONE for the draft's zone when the resource does not define it yet.
    mutating func defineZone(of draft: EventDraft) {
        guard !draft.isAllDay else { return }
        let id = draft.zoneID(person)
        // By the literal TZID: an alias (`Korea Standard Time`) does not define `Asia/Seoul`.
        let defined = calendar.children.contains { $0.name == "VTIMEZONE" && $0.first("TZID")?.value == id }
        if !defined, let zone = ICalendarWriter.timeZone(id) { calendar.children.insert(zone, at: 0) }
    }

    // MARK: - Finding things

    private func masterIndex(_ uid: String) -> Int? {
        calendar.children.firstIndex { $0.name == "VEVENT" && $0.first("UID")?.value == uid && $0.first("RECURRENCE-ID") == nil }
    }

    private func overrideIndex(_ uid: String, _ key: OccurrenceKey) -> Int? {
        calendar.children.firstIndex { component in
            isOverride(component, of: uid) && component.first("RECURRENCE-ID").flatMap(moment).map { matches($0, key) } == true
        }
    }

    private func isOverride(_ component: Component, of uid: String) -> Bool {
        component.name == "VEVENT" && component.first("UID")?.value == uid && component.first("RECURRENCE-ID") != nil
    }

    private func moment(_ property: Property) -> ICalendar.Moment? {
        ICalendar.moment(property, floating: floating)
    }

    /// Each value of a property that may hold several (`EXDATE:20261105T090000,20261112T090000`).
    private func values(_ property: Property) -> [ICalendar.Moment] {
        property.value.split(separator: ",").compactMap {
            moment(Property(name: property.name, params: property.params, value: String($0)))
        }
    }

    private func keepExdates(_ event: inout Component, where keep: (ICalendar.Moment) -> Bool) {
        let kept: [Property] = event.all("EXDATE").compactMap { property in
            let parts = property.value.split(separator: ",").map(String.init)
            let keptParts = parts.filter { part in
                moment(Property(name: "EXDATE", params: property.params, value: part)).map(keep) ?? true
            }
            if keptParts.count == parts.count { return property }
            return keptParts.isEmpty ? nil : Property(name: "EXDATE", params: property.params, value: keptParts.joined(separator: ","))
        }
        event.remove("EXDATE")
        event.properties += kept
    }

    private func matches(_ moment: ICalendar.Moment, _ key: OccurrenceKey) -> Bool {
        switch moment {
        case .day(let day, _): day == dayKeyed(key).day
        case .instant(let date, _): key.day == nil && abs(date.timeIntervalSince(key.date)) < 1
        }
    }

    /// Whether `moment` comes before the occurrence `key`.
    func isBefore(_ moment: ICalendar.Moment, _ key: OccurrenceKey) -> Bool {
        switch moment {
        case .day(let day, _): day < dayKeyed(key).day!
        case .instant(let date, _): date < key.date && abs(date.timeIntervalSince(key.date)) >= 1
        }
    }

    /// `key` with its day filled in (from the person's calendar for a timed one).
    private func dayKeyed(_ key: OccurrenceKey) -> OccurrenceKey {
        key.day != nil ? key : OccurrenceKey(date: key.date, day: DayKey.key(key.date, calendar: person))
    }

    /// A property naming `key` the way `start` (the series' DTSTART) names its times: a date,
    /// a UTC time, a time in the same TZID, or a floating time.
    private func like(_ start: Property, _ name: String, _ key: OccurrenceKey) -> Property {
        switch moment(start) {
        case .day?:
            return Property(name: name, params: ["VALUE": "DATE"], value: dayKeyed(key).day!.replacingOccurrences(of: "-", with: ""))
        case .instant(_, let zone)?:
            if start.value.hasSuffix("Z") { return Property(name: name, params: [:], value: ICalendarWriter.utcStamp(key.date)) }
            if let tzid = start.params["TZID"], let id = ICalendar.timeZoneID(tzid), let tz = TimeZone(identifier: id) {
                return Property(name: name, params: ["TZID": tzid], value: ICalendarWriter.stamp(key.date, zone: tz))
            }
            let tz = zone.flatMap(TimeZone.init(identifier:)) ?? floating.calendar.timeZone
            return Property(name: name, params: [:], value: ICalendarWriter.stamp(key.date, zone: tz))
        case nil:
            return Property(name: name, params: [:], value: ICalendarWriter.utcStamp(key.date))
        }
    }

    /// The day a moment falls on, as year-month-day: an all-day one as written, a timed one in `zoned`.
    private func day(of moment: ICalendar.Moment, in zoned: Calendar) -> DateComponents {
        switch moment {
        case .day(_, let date): DayKey.utc.dateComponents([.year, .month, .day], from: date)
        case .instant(let date, _): zoned.dateComponents([.year, .month, .day], from: date)
        }
    }

    /// Calendar days from one moment's day to another's, each read where it was written.
    private func dayCount(from a: ICalendar.Moment, to b: ICalendar.Moment) -> Int {
        func utcDay(_ moment: ICalendar.Moment) -> Date {
            switch moment {
            case .day(_, let date): return date
            case .instant(let date, let zone):
                var zoned = floating.calendar
                if let zone, let tz = TimeZone(identifier: zone) { zoned.timeZone = tz }
                return DayKey.utc.date(from: zoned.dateComponents([.year, .month, .day], from: date))!
            }
        }
        return DayKey.utc.dateComponents([.day], from: utcDay(a), to: utcDay(b)).day ?? 0
    }

    /// The rule with its UNTIL written as a date (all-day series) or a UTC time (timed ones).
    private func retyped(rule: Property, allDay: Bool, zone: Calendar) -> Property {
        let parts = rule.value.split(separator: ";").map(String.init)
        guard let until = parts.first(where: { $0.uppercased().hasPrefix("UNTIL=") }).map({ String($0.dropFirst(6)) }) else { return rule }
        let value: String
        if allDay {
            guard let date = Recurrence.parseDateTime(until, calendar: zone) else { return rule }
            value = ICalendarWriter.dayStamp(date, calendar: zone)
        } else {
            guard let date = Recurrence.parseDateTime(until, calendar: zone, dateOnlyMeansEndOfDay: true) else { return rule }
            value = ICalendarWriter.utcStamp(date)
        }
        return Self.rrule(RuleText.rrule(rule.value, until: value, count: RuleText.count(in: rule.value)))
    }

    /// DTSTAMP and LAST-MODIFIED now, SEQUENCE one up, as RFC 5546 asks of a changed event.
    private static func stamp(_ event: inout Component) {
        let now = ICalendarWriter.utcStamp(.now)
        event.set("DTSTAMP", Property(name: "DTSTAMP", params: [:], value: now))
        event.set("LAST-MODIFIED", Property(name: "LAST-MODIFIED", params: [:], value: now))
        let sequence = event.first("SEQUENCE").flatMap { Int($0.value) } ?? 0
        event.set("SEQUENCE", Property(name: "SEQUENCE", params: [:], value: String(sequence + 1)))
    }
}
