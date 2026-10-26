import Foundation
import SwiftData

/// Writes one account's calendars and events into the cache, whatever the provider.
///
/// Runs on its own actor and context; the app reads the results through a fresh context once a
/// save lands. The actor is reentrant across network awaits, so after every await the account and
/// calendar are looked up again by id: an account disconnected mid-sync is left alone.
@ModelActor
public actor CalendarSyncEngine {
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

    /// Marks an account for connecting again when its sign-in is gone before any request is made
    /// (an iCloud password missing from the keychain).
    public func markNeedsReauth(_ accountID: String) throws {
        try account(accountID)?.status = .needsReauth
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
    /// Errors that only signing in again fixes (a revoked token, a missing permission) mark the
    /// account and stop, as does being offline. Any other error in one calendar is remembered while
    /// the rest still sync; the first such error is thrown at the end, and `lastSyncedAt` only moves
    /// when every calendar synced.
    public func sync(_ accountID: String, provider: some CalendarProvider, calendar: Calendar) async throws {
        do {
            let remotes = try await provider.calendars()
            guard try account(accountID) != nil else { return }
            try updateSources(of: accountID, from: remotes)

            var firstError: Error?
            for sourceID in try sources(of: accountID).map(\.id) {
                do {
                    try await syncSource(sourceID, provider: provider, calendar: calendar)
                } catch let error as CalendarSyncError where error.needsReconnect || error == .offline {
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
        } catch let error as CalendarSyncError where error.needsReconnect {
            try account(accountID)?.status = .needsReauth
            try modelContext.save()
            throw error
        }
    }

    // MARK: - Calendars

    private func updateSources(of accountID: String, from remotes: [RemoteCalendar]) throws {
        var existing = Dictionary(uniqueKeysWithValues: try sources(of: accountID).map { ($0.remoteID, $0) })
        for (index, remote) in remotes.enumerated() {
            let source = existing.removeValue(forKey: remote.id) ?? {
                let new = CalendarSource(accountID: accountID, remoteID: remote.id, name: remote.name)
                modelContext.insert(new)
                return new
            }()
            // Assign only what changed, so an unchanged list writes nothing every minute.
            set(source, \.name, remote.name)
            if source.colorHex != remote.colorHex {
                source.colorHex = remote.colorHex
                source.paletteRaw = Palette.nearest(toHex: remote.colorHex).rawValue
            }
            set(source, \.isReadOnly, remote.isReadOnly)
            set(source, \.isHoliday, remote.isHoliday)
            set(source, \.timeZone, remote.timeZone)
            set(source, \.order, remote.isPrimary ? -1 : index)
        }
        // Calendars the person unsubscribed from or deleted.
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

    private func syncSource(_ sourceID: String, provider: some CalendarProvider, calendar: Calendar) async throws {
        guard let before = try source(sourceID) else { return }
        let reference = RemoteCalendar.Reference(sourceID: sourceID, remoteID: before.remoteID, timeZone: before.timeZone)
        let fetched = try await provider.changes(in: reference, syncToken: before.syncToken, calendar: calendar)
        // The calendar may have been removed while the request was out.
        guard try self.source(sourceID) != nil else { return }
        if fetched.isFullFetch { try deleteEvents(of: sourceID) }

        var refetchEverything = false
        for change in fetched.changes {
            switch change {
            case .upsert(let snapshot):
                // A series the engine can expand now, after being fetched occurrence by occurrence:
                // those stored occurrences cannot be told apart from real exceptions, so the whole
                // calendar is fetched again next round and the true exceptions come back with it.
                if !snapshot.recurrenceUnsupported, snapshot.recurringEventID == nil, try record(snapshot.id)?.recurrenceUnsupported == true {
                    refetchEverything = true
                }
                try upsert(snapshot)
            case .remove(let remoteID):
                try modelContext.delete(model: EventRecord.self, where: #Predicate {
                    $0.sourceID == sourceID && ($0.remoteID == remoteID || $0.recurringEventID == remoteID)
                })
            case .replaceOccurrences(let seriesID, let occurrences):
                try deleteOccurrences(ofSeries: seriesID, in: sourceID)
                for occurrence in occurrences { try upsert(occurrence) }
            case .replaceResource(let href, let events):
                let keep = Set(events.map(\.id))
                let stored = try modelContext.fetch(FetchDescriptor<EventRecord>(predicate: #Predicate { $0.sourceID == sourceID && $0.resourceHref == href }))
                for record in stored where !keep.contains(record.id) { modelContext.delete(record) }
                for event in events { try upsert(event) }
            }
        }
        try modelContext.save()

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
