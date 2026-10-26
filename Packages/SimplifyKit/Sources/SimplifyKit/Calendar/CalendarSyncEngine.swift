import Foundation
import SwiftData

/// Writes one Google account's calendars and events into the cache.
///
/// Runs on its own actor and context; the app reads the results through a fresh context once a
/// save lands. The actor is reentrant across network awaits, so after every await the account and
/// calendar are looked up again by id: an account disconnected mid-sync is left alone.
@ModelActor
public actor CalendarSyncEngine {
    /// How far around today a series the local engine cannot expand is fetched occurrence by occurrence.
    static let instanceWindow: (past: Int, future: Int) = (1, 2)

    /// Records a newly signed-in account, or updates the email of one already known.
    public func upsertAccount(id: String, provider: CalendarProviderKind, email: String) throws {
        if let account = try account(id) {
            account.email = email
            account.status = .ok
        } else {
            modelContext.insert(CalendarAccount(id: id, provider: provider, email: email))
        }
        try modelContext.save()
    }

    /// Removes an account and everything cached for it.
    public func removeAccount(id: String) throws {
        for source in try sources(of: id) {
            try deleteEvents(of: source.id)
            modelContext.delete(source)
        }
        if let account = try account(id) { modelContext.delete(account) }
        try modelContext.save()
    }

    /// Fetches the calendar list and every calendar's changes.
    ///
    /// A revoked token or a missing calendar permission marks the account for signing in again and
    /// stops. Any other error in one calendar is remembered while the rest still sync; the first
    /// such error is thrown at the end, and `lastSyncedAt` only moves when every calendar synced.
    public func syncGoogleAccount(_ accountID: String, api: GoogleCalendarAPI, calendar: Calendar) async throws {
        do {
            let entries = try await api.calendarList()
            guard try account(accountID) != nil else { return }
            try updateSources(of: accountID, from: entries)

            var firstError: Error?
            for sourceID in try sources(of: accountID).map(\.id) {
                do {
                    try await syncSource(sourceID, api: api, calendar: calendar)
                } catch let error as CalendarSyncError where error == .needsReauth || error == .missingCalendarPermission || error == .offline {
                    throw error
                } catch {
                    firstError = firstError ?? error
                }
            }
            guard let account = try account(accountID) else { return }
            account.status = .ok
            if firstError == nil { account.lastSyncedAt = .now }
            try modelContext.save()
            if let firstError { throw firstError }
        } catch let error as CalendarSyncError where error == .needsReauth || error == .missingCalendarPermission {
            // Both are fixed by signing in again (and ticking the calendar box on Google's screen).
            try account(accountID)?.status = .needsReauth
            try modelContext.save()
            throw error
        }
    }

    // MARK: - Calendars

    private func updateSources(of accountID: String, from entries: [GoogleCalendarEntry]) throws {
        var existing = Dictionary(uniqueKeysWithValues: try sources(of: accountID).map { ($0.remoteID, $0) })
        for (index, entry) in entries.enumerated() {
            let source = existing.removeValue(forKey: entry.id) ?? {
                let new = CalendarSource(accountID: accountID, remoteID: entry.id, name: entry.displayName)
                modelContext.insert(new)
                return new
            }()
            // Assign only what changed, so an unchanged list writes nothing every minute.
            set(source, \.name, entry.displayName)
            if source.colorHex != entry.backgroundColor {
                source.colorHex = entry.backgroundColor
                source.paletteRaw = Palette.nearest(toHex: entry.backgroundColor).rawValue
            }
            set(source, \.isReadOnly, entry.isReadOnly)
            set(source, \.isHoliday, entry.isHoliday)
            set(source, \.timeZone, entry.timeZone)
            set(source, \.order, entry.primary == true ? -1 : index)
        }
        // Calendars the person unsubscribed from.
        for gone in existing.values {
            try deleteEvents(of: gone.id)
            modelContext.delete(gone)
        }
        if modelContext.hasChanges { try modelContext.save() }
    }

    private func set<Value: Equatable>(_ source: CalendarSource, _ path: ReferenceWritableKeyPath<CalendarSource, Value>, _ value: Value) {
        if source[keyPath: path] != value { source[keyPath: path] = value }
    }

    // MARK: - Events

    private func syncSource(_ sourceID: String, api: GoogleCalendarAPI, calendar: Calendar) async throws {
        guard let before = try source(sourceID) else { return }
        let remoteID = before.remoteID
        var syncToken = before.syncToken
        let fetched: (events: [GoogleEvent], nextSyncToken: String?, timeZone: String?)
        do {
            fetched = try await api.events(calendarID: remoteID, syncToken: syncToken)
        } catch CalendarSyncError.syncTokenExpired {
            syncToken = nil
            fetched = try await api.events(calendarID: remoteID, syncToken: nil)
        }
        // The calendar may have been removed while the request was out.
        guard let source = try self.source(sourceID) else { return }
        if syncToken == nil { try deleteEvents(of: sourceID) }
        let zone = fetched.timeZone ?? source.timeZone

        var unsupported: [String] = []
        var refetchEverything = false
        for event in fetched.events {
            let snapshot = event.snapshot(sourceID: sourceID, calendar: calendar, defaultZone: zone)
            if snapshot.isCancelled, snapshot.recurringEventID == nil {
                // A deleted single event or a whole deleted series (with its changed occurrences).
                try delete(id: snapshot.id)
                try deleteOccurrences(ofSeries: snapshot.remoteID, in: sourceID)
                continue
            }
            // A series the engine can expand now, after being fetched occurrence by occurrence:
            // those stored occurrences cannot be told apart from real exceptions, so the whole
            // calendar is fetched again next round and Google's true exceptions come back with it.
            if !snapshot.recurrenceUnsupported, snapshot.recurringEventID == nil, try record(snapshot.id)?.recurrenceUnsupported == true {
                refetchEverything = true
            }
            try upsert(snapshot)
            if snapshot.recurrenceUnsupported { unsupported.append(snapshot.remoteID) }
        }
        try modelContext.save()

        let now = Date.now
        let window = DateInterval(start: calendar.date(byAdding: .year, value: -Self.instanceWindow.past, to: now)!,
                                  end: calendar.date(byAdding: .year, value: Self.instanceWindow.future, to: now)!)
        for seriesID in unsupported {
            let instances = try await api.instances(calendarID: remoteID, eventID: seriesID, in: window)
            guard try self.source(sourceID) != nil else { return }
            try deleteOccurrences(ofSeries: seriesID, in: sourceID)
            for instance in instances {
                var snapshot = instance.snapshot(sourceID: sourceID, calendar: calendar, defaultZone: zone)
                snapshot.isExpandedInstance = true
                try upsert(snapshot)
            }
            try modelContext.save()
        }

        // The token moves on only once everything above landed; a failure part-way repeats this
        // fetch next round instead of skipping what was missed.
        guard let done = try self.source(sourceID) else { return }
        done.syncToken = refetchEverything ? nil : fetched.nextSyncToken
        try modelContext.save()
    }

    private func upsert(_ snapshot: EventSnapshot) throws {
        let id = snapshot.id
        if let record = try modelContext.fetch(FetchDescriptor<EventRecord>(predicate: #Predicate { $0.id == id })).first {
            record.update(from: snapshot)
        } else {
            modelContext.insert(EventRecord(snapshot))
        }
    }

    private func record(_ id: String) throws -> EventRecord? {
        try modelContext.fetch(FetchDescriptor<EventRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func delete(id: String) throws {
        try modelContext.delete(model: EventRecord.self, where: #Predicate { $0.id == id })
    }

    private func deleteOccurrences(ofSeries seriesID: String, in sourceID: String) throws {
        try modelContext.delete(model: EventRecord.self, where: #Predicate { $0.sourceID == sourceID && $0.recurringEventID == seriesID })
    }

    private func deleteEvents(of sourceID: String) throws {
        try modelContext.delete(model: EventRecord.self, where: #Predicate { $0.sourceID == sourceID })
    }

    // MARK: - Lookups

    private func account(_ id: String) throws -> CalendarAccount? {
        try modelContext.fetch(FetchDescriptor<CalendarAccount>(predicate: #Predicate { $0.id == id })).first
    }

    private func source(_ id: String) throws -> CalendarSource? {
        try modelContext.fetch(FetchDescriptor<CalendarSource>(predicate: #Predicate { $0.id == id })).first
    }

    private func sources(of accountID: String) throws -> [CalendarSource] {
        try modelContext.fetch(FetchDescriptor<CalendarSource>(predicate: #Predicate { $0.accountID == accountID }, sortBy: [SortDescriptor(\.order)]))
    }
}

/// Reads the cache for the views.
public enum CalendarCache {
    /// Every stored event of the visible calendars, decoded once so a month change does not
    /// touch the store again.
    public static func visibleSnapshots(context: ModelContext) -> [EventSnapshot] {
        let visible = ((try? context.fetch(FetchDescriptor<CalendarSource>(predicate: #Predicate { $0.isVisible }))) ?? []).map(\.id)
        guard !visible.isEmpty else { return [] }
        let records = (try? context.fetch(FetchDescriptor<EventRecord>(predicate: #Predicate { visible.contains($0.sourceID) }))) ?? []
        return records.map(\.snapshot)
    }

    /// Occurrences from visible calendars that overlap `range`.
    public static func occurrences(in range: DateInterval, context: ModelContext, calendar: Calendar) -> [EventOccurrence] {
        OccurrenceBuilder.occurrences(from: visibleSnapshots(context: context), in: range, calendar: calendar)
    }
}
