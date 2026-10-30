import Foundation

/// A change saved while offline (or behind other such changes), waiting to reach the provider.
public struct PendingWrite: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: Codable, Sendable, Equatable {
        /// A new event, under the id chosen when it was saved.
        case create(id: String)
        case update(EditScope)
        case delete(EditScope)
    }

    public enum Status: Codable, Sendable, Equatable {
        case waiting
        /// The provider refused it (a conflict, a read-only calendar); it waits for the person to
        /// retry or discard it, and later changes to the same event wait behind it.
        case failed(CalendarSyncError)
        /// Written; still shown on top of the cache until the account's next sync brings it in.
        case sent(at: Date)
    }

    public let id: UUID
    public let accountID: String
    public let calendar: RemoteCalendar.Reference
    public let kind: Kind
    /// The event as it was shown when it was changed or deleted; nil for a new one.
    public let event: EventSnapshot?
    /// The new values; nil for a deletion.
    public let draft: EventDraft?
    public let createdAt: Date
    public var status: Status = .waiting

    /// The series (or single event) this write is about, so later writes to it keep their order.
    var eventKey: String {
        if case .create(let id) = kind { return calendar.sourceID + ":" + id }
        return calendar.sourceID + ":" + (event?.seriesRemoteID ?? "")
    }

    var isWaiting: Bool { status == .waiting }
    var isSent: Bool { if case .sent = status { true } else { false } }
}

// MARK: - Showing pending writes

/// What the cache would hold once the pending writes reach the provider, so a change saved
/// offline shows at once. It follows the providers' rules closely enough to look right until
/// the next sync replaces it with what the provider made of it.
enum PendingOverlay {
    static func apply(_ writes: [PendingWrite], to snapshots: [EventSnapshot], calendar: Calendar) -> [EventSnapshot] {
        writes.reduce(snapshots) { snapshots, write in apply(write, to: snapshots, calendar: calendar) }
    }

    static func apply(_ write: PendingWrite, to snapshots: [EventSnapshot], calendar: Calendar) -> [EventSnapshot] {
        var snapshots = snapshots
        let source = write.calendar.sourceID
        switch write.kind {
        case .create(let id):
            guard let draft = write.draft, !snapshots.contains(where: { $0.id == source + ":" + id }) else { return snapshots }
            snapshots.append(snapshot(of: draft, remoteID: id, in: write.calendar, calendar: calendar))

        case .update(let scope):
            guard let event = write.event, let draft = write.draft else { return snapshots }
            let series = event.seriesRemoteID
            switch event.isSeriesMember ? scope : .allOccurrences {
            case .allOccurrences:
                updateAll(&snapshots, source: source, series: series, event: event, draft: draft, calendar: calendar)
            case .thisOccurrence(let originalStart):
                let key = OccurrenceKey(event: event, originalStart: originalStart, calendar: calendar)
                var changed = snapshots.first { isException($0, source, series, at: key, calendar) }
                    ?? exception(of: series, at: key, in: write.calendar, pending: write.id)
                fill(&changed, with: draft, start: draft.start, end: draft.end, calendar: calendar)
                snapshots.removeAll { $0.id == changed.id }
                snapshots.append(changed)
            case .thisAndFollowing(let originalStart):
                let key = OccurrenceKey(event: event, originalStart: originalStart, calendar: calendar)
                guard let index = masterIndex(snapshots, source, series), isAfterFirst(key, of: snapshots[index], calendar) else {
                    updateAll(&snapshots, source: source, series: series, event: event, draft: draft, calendar: calendar)
                    return snapshots
                }
                let master = snapshots[index]
                end(&snapshots[index], before: key, calendar: calendar)
                // The id the provider gives the new part, so it can be changed again before a sync.
                var following = snapshot(of: draft, remoteID: EventDraft.splitID(series: series, at: key), in: write.calendar, calendar: calendar)
                if !draft.changesRule(of: event) { following.recurrence = master.recurrence.map { remaining($0, of: master, from: key, calendar: calendar) } }
                following.exceptionDates = master.exceptionDates.filter { !isBefore($0, key, allDay: master.isAllDay) }
                // Changed occurrences from the split on now belong to the new part.
                for i in snapshots.indices where isException(snapshots[i], source, series) && !isBefore(snapshots[i], key) {
                    snapshots[i].recurringEventID = following.remoteID
                }
                // A sync may already have brought the new part in.
                if !snapshots.contains(where: { $0.id == following.id }) { snapshots.append(following) }
            }

        case .delete(let scope):
            guard let event = write.event else { return snapshots }
            let series = event.seriesRemoteID
            switch event.isSeriesMember ? scope : .allOccurrences {
            case .allOccurrences:
                snapshots.removeAll { $0.sourceID == source && ($0.remoteID == series || $0.recurringEventID == series) }
            case .thisOccurrence(let originalStart):
                let key = OccurrenceKey(event: event, originalStart: originalStart, calendar: calendar)
                snapshots.removeAll { isException($0, source, series, at: key, calendar) }
                if let index = masterIndex(snapshots, source, series) {
                    snapshots[index].exceptionDates.append(key.day.flatMap { DayKey.date($0, calendar: DayKey.utc) } ?? key.date)
                }
            case .thisAndFollowing(let originalStart):
                let key = OccurrenceKey(event: event, originalStart: originalStart, calendar: calendar)
                guard let index = masterIndex(snapshots, source, series), isAfterFirst(key, of: snapshots[index], calendar) else {
                    snapshots.removeAll { $0.sourceID == source && ($0.remoteID == series || $0.recurringEventID == series) }
                    return snapshots
                }
                end(&snapshots[index], before: key, calendar: calendar)
                snapshots.removeAll { isException($0, source, series) && !isBefore($0, key) }
            }
        }
        return snapshots
    }

    // MARK: -

    /// A new event as the provider would store it.
    static func snapshot(of draft: EventDraft, remoteID: String, in reference: RemoteCalendar.Reference, calendar: Calendar) -> EventSnapshot {
        var event = EventSnapshot(id: reference.sourceID + ":" + remoteID, sourceID: reference.sourceID, remoteID: remoteID, title: "", isAllDay: draft.isAllDay)
        fill(&event, with: draft, start: draft.start, end: draft.end, calendar: calendar)
        event.recurrence = recurrence(draft.repeatRule)
        // CalDAV events live in `<collection>/<uid>.ics`.
        if let url = URL(string: reference.remoteID), url.scheme?.hasPrefix("http") == true {
            event.resourceHref = CalDAVClient.normalize(url.appending(path: remoteID + ".ics").path(percentEncoded: false))
        }
        return event
    }

    private static func updateAll(_ snapshots: inout [EventSnapshot], source: String, series: String, event: EventSnapshot, draft: EventDraft, calendar: Calendar) {
        guard let index = masterIndex(snapshots, source, series) else { return }
        var master = snapshots[index]
        let wasAllDay = master.isAllDay
        let oldFirst = first(of: master, calendar: calendar)
        let span = draft.seriesSpan(masterDay: draft.zoned(calendar).dateComponents([.year, .month, .day], from: oldFirst), calendar: calendar)
        fill(&master, with: draft, start: span.start, end: span.end, calendar: calendar)
        let isSeries = master.recurrence != nil || master.recurrenceUnsupported
        if isSeries ? draft.changesRule(of: event) : draft.repeatRule != .none {
            master.recurrence = recurrence(draft.repeatRule)
            master.recurrenceUnsupported = false
            master.exceptionDates = []
            snapshots.removeAll { isException($0, source, series) }
        } else if isSeries {
            // Skipped and changed occurrences move with the series.
            let zoned = draft.zoned(calendar)
            func moved(_ date: Date) -> Date {
                let days = zoned.dateComponents([.day], from: zoned.startOfDay(for: oldFirst), to: zoned.startOfDay(for: date)).day ?? 0
                return zoned.date(byAdding: .day, value: days, to: span.start)!
            }
            // All-day EXDATEs are kept as UTC midnights, the rest as instants.
            func local(_ date: Date) -> Date {
                wasAllDay ? DayKey.date(DayKey.key(date, calendar: DayKey.utc), calendar: calendar)! : date
            }
            func stored(_ date: Date) -> Date {
                draft.isAllDay ? DayKey.date(DayKey.key(date, calendar: calendar), calendar: DayKey.utc)! : date
            }
            master.exceptionDates = master.exceptionDates.map { stored(moved(local($0))) }
            for i in snapshots.indices where isException(snapshots[i], source, series) {
                if snapshots[i].originalStartDay != nil, draft.isAllDay {
                    snapshots[i].originalStartDay = DayKey.key(moved(original(snapshots[i], calendar)), calendar: calendar)
                } else {
                    snapshots[i].originalStart = moved(original(snapshots[i], calendar))
                    snapshots[i].originalStartDay = nil
                }
            }
        }
        snapshots[snapshots.firstIndex { $0.id == master.id }!] = master
    }

    private static func fill(_ event: inout EventSnapshot, with draft: EventDraft, start: Date, end: Date, calendar: Calendar) {
        event.title = draft.title.isEmpty ? "(제목 없음)" : draft.title
        event.location = draft.location.flatMap { $0.isEmpty ? nil : $0 }
        event.notes = draft.notes.flatMap { $0.isEmpty ? nil : $0 }
        event.isAllDay = draft.isAllDay
        if draft.isAllDay {
            event.startDay = DayKey.key(start, calendar: calendar)
            event.endDay = DayKey.key(end, calendar: calendar)
            event.start = nil
            event.end = nil
        } else {
            event.start = start
            event.end = end
            event.timeZone = draft.zoneID(calendar)
            event.startDay = nil
            event.endDay = nil
        }
    }

    private static func recurrence(_ preset: RepeatPreset) -> Recurrence? {
        switch preset {
        case .none: nil
        case .daily: Recurrence(frequency: .daily)
        case .weekly: Recurrence(frequency: .weekly)
        case .monthly: Recurrence(frequency: .monthly)
        case .yearly: Recurrence(frequency: .yearly)
        }
    }

    private static func exception(of series: String, at key: OccurrenceKey, in reference: RemoteCalendar.Reference, pending: UUID) -> EventSnapshot {
        var event = EventSnapshot(id: reference.sourceID + ":" + series + "@pending-" + pending.uuidString, sourceID: reference.sourceID, remoteID: series, title: "", isAllDay: false)
        event.recurringEventID = series
        if let day = key.day { event.originalStartDay = day } else { event.originalStart = key.date }
        return event
    }

    /// Ends a series' rule before `key`.
    private static func end(_ master: inout EventSnapshot, before key: OccurrenceKey, calendar: Calendar) {
        if master.isAllDay {
            // All-day rule dates are read in UTC (see `DayKey.utc`).
            let day = key.day ?? DayKey.key(key.date, calendar: calendar)
            master.recurrence?.until = DayKey.date(day, calendar: DayKey.utc)?.addingTimeInterval(-1)
        } else {
            master.recurrence?.until = key.date.addingTimeInterval(-1)
        }
        master.recurrence?.count = nil
    }

    /// The rule for the part of a series from `key` on: a COUNT cut down to what is left.
    private static func remaining(_ rule: Recurrence, of master: EventSnapshot, from key: OccurrenceKey, calendar: Calendar) -> Recurrence {
        guard let count = rule.count else { return rule }
        var zoned = calendar
        if let id = master.timeZone, let tz = TimeZone(identifier: id), !master.isAllDay { zoned.timeZone = tz }
        let start = first(of: master, calendar: calendar)
        let before = key.date > start
            ? RecurrenceExpander.occurrences(of: rule, start: start, calendar: zoned, in: DateInterval(start: start, end: key.date)).filter { $0 < key.date }.count
            : 0
        var rule = rule
        rule.count = max(1, count - before)
        return rule
    }

    private static func masterIndex(_ snapshots: [EventSnapshot], _ source: String, _ series: String) -> Int? {
        snapshots.firstIndex { $0.sourceID == source && $0.remoteID == series && $0.recurringEventID == nil }
    }

    private static func isException(_ event: EventSnapshot, _ source: String, _ series: String) -> Bool {
        event.sourceID == source && event.recurringEventID == series
    }

    private static func isException(_ event: EventSnapshot, _ source: String, _ series: String, at key: OccurrenceKey, _ calendar: Calendar) -> Bool {
        guard isException(event, source, series) else { return false }
        if let day = key.day { return event.originalStartDay == day }
        return event.originalStart.map { abs($0.timeIntervalSince(key.date)) < 1 } ?? false
    }

    /// Where a series starts: its first day's midnight, or its first start.
    private static func first(of event: EventSnapshot, calendar: Calendar) -> Date {
        event.startDay.flatMap { DayKey.date($0, calendar: calendar) } ?? event.start ?? .distantPast
    }

    private static func original(_ event: EventSnapshot, _ calendar: Calendar) -> Date {
        event.originalStartDay.flatMap { DayKey.date($0, calendar: calendar) } ?? event.originalStart ?? .distantPast
    }

    private static func isAfterFirst(_ key: OccurrenceKey, of master: EventSnapshot, _ calendar: Calendar) -> Bool {
        key.date > first(of: master, calendar: calendar)
    }

    /// Whether a changed occurrence was meant to start before the occurrence `key`.
    private static func isBefore(_ exception: EventSnapshot, _ key: OccurrenceKey) -> Bool {
        if let day = exception.originalStartDay { return day < (key.day ?? "") }
        return (exception.originalStart ?? .distantPast) < key.date
    }

    /// Whether `date` comes before the occurrence `key`; all-day EXDATEs are UTC midnights.
    private static func isBefore(_ date: Date, _ key: OccurrenceKey, allDay: Bool) -> Bool {
        if allDay, let day = key.day, let split = DayKey.date(day, calendar: DayKey.utc) {
            return DayKey.key(date, calendar: DayKey.utc) < DayKey.key(split, calendar: DayKey.utc)
        }
        return date < key.date
    }
}
