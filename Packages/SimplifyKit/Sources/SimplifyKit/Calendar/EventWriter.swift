import Foundation

/// Where the app saves events. Online, a change goes straight to the provider; offline (or while
/// earlier changes of the same account still wait) it is kept in `PendingWrites.json` and sent
/// in order once the connection is back.
///
/// The queue lives in its own file next to the cache rather than in it: the cache is thrown
/// away and downloaded again when it cannot be opened, and these changes exist nowhere else.
public actor EventWriter {
    public enum Outcome: Sendable, Equatable {
        case saved
        /// Kept until the connection is back.
        case queued
    }

    private let fileURL: URL?
    public private(set) var pending: [PendingWrite]
    private var isFlushing = false
    /// Accounts with a write on its way to the provider, and who waits for each to finish:
    /// one write per account at a time keeps them in the order they were made.
    private var busy: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    /// `fileURL` nil keeps the queue in `<App Group>/Library/Application Support/PendingWrites.json`.
    public init(fileURL: URL? = nil) {
        let url = fileURL ?? (try? SimplifyStore.storeURL(named: "PendingWrites.json"))
        self.fileURL = url
        pending = []
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([PendingWrite].self, from: data) {
            pending = saved
        } else {
            // Unreadable (a newer format?): set aside rather than overwritten by the next save.
            let aside = url.appendingPathExtension("unreadable")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
        }
    }

    /// The queue as saved, for readers outside the app (widgets). Leaves an unreadable file alone.
    public static func storedWrites(fileURL: URL? = nil) -> [PendingWrite] {
        guard let url = fileURL ?? (try? SimplifyStore.storeURL(named: "PendingWrites.json")),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PendingWrite].self, from: data)) ?? []
    }

    public func create(_ draft: EventDraft, in source: RemoteCalendar.Reference, accountID: String,
                       provider: any CalendarProvider, calendar: Calendar) async throws -> Outcome {
        await acquire(accountID)
        defer { release(accountID) }
        return try await perform(PendingWrite(id: UUID(), accountID: accountID, calendar: source, kind: .create(id: EventDraft.newID()),
                                       event: nil, draft: draft, createdAt: .now), provider: provider, calendar: calendar)
    }

    public func update(_ event: EventSnapshot, to draft: EventDraft, scope: EditScope, in source: RemoteCalendar.Reference,
                       accountID: String, provider: any CalendarProvider, calendar: Calendar) async throws -> Outcome {
        await acquire(accountID)
        defer { release(accountID) }
        return try await perform(PendingWrite(id: UUID(), accountID: accountID, calendar: source, kind: .update(scope),
                                       event: event, draft: draft, createdAt: .now), provider: provider, calendar: calendar)
    }

    public func delete(_ event: EventSnapshot, scope: EditScope, in source: RemoteCalendar.Reference,
                       accountID: String, provider: any CalendarProvider, calendar: Calendar) async throws -> Outcome {
        let write = PendingWrite(id: UUID(), accountID: accountID, calendar: source, kind: .delete(scope),
                                 event: event, draft: nil, createdAt: .now)
        // Taken first, so a create being sent right now finishes and is deleted for real.
        await acquire(accountID)
        defer { release(accountID) }
        // Deleting a whole event that never reached the provider: forget it and what followed it.
        if !event.isSeriesMember || scope == .allOccurrences,
           pending.contains(where: { !$0.isSent && $0.eventKey == write.eventKey && $0.kind == .create(id: event.seriesRemoteID) }) {
            pending.removeAll { $0.eventKey == write.eventKey && !$0.isSent }
            save()
            return .saved
        }
        return try await perform(write, provider: provider, calendar: calendar)
    }

    /// Sends what waits, oldest first, and returns the accounts something reached; sync those.
    ///
    /// Being offline stops the round. A server hiccup or a lost sign-in holds that account's
    /// writes for the next round. A refusal (a conflict, a read-only calendar) marks that write
    /// failed and holds later writes to the same event behind it, while the rest go on.
    public func flush(calendar: Calendar, provider: @Sendable (String) async throws -> any CalendarProvider) async -> [String] {
        guard !isFlushing else { return [] }
        isFlushing = true
        defer { isFlushing = false }

        var reached: [String] = []
        var heldAccounts: Set<String> = []
        var heldEvents = Set(pending.filter { if case .failed = $0.status { true } else { false } }.map(\.eventKey))
        // Round after round: writes made while one was being sent queue behind it and go too.
        var progress = true
        rounds: while progress {
            progress = false
            for id in pending.filter(\.isWaiting).map(\.id) {
                guard let write = pending.first(where: { $0.id == id }), !heldAccounts.contains(write.accountID),
                      !heldEvents.contains(write.eventKey) else { continue }
                await acquire(write.accountID)
                defer { release(write.accountID) }
                // Looked up again after every await: the queue may have changed meanwhile.
                guard pending.first(where: { $0.id == id })?.isWaiting == true else { continue }
                do {
                    try await send(write, provider: try await provider(write.accountID), calendar: calendar)
                    mark(id, .sent(at: .now))
                    if !reached.contains(write.accountID) { reached.append(write.accountID) }
                    progress = true
                } catch CalendarSyncError.offline {
                    break rounds
                } catch is CancellationError {
                    break rounds
                } catch let error as CalendarSyncError where error.needsReconnect || Self.isTransient(error) {
                    heldAccounts.insert(write.accountID)
                } catch {
                    mark(id, .failed(error as? CalendarSyncError ?? .invalidResponse))
                    heldEvents.insert(write.eventKey)
                }
            }
        }
        return reached
    }

    /// Call when a sync of the account that started at `started` has finished: what was sent
    /// before then is in the cache now and no longer needs showing on top of it.
    public func didSync(_ accountID: String, startedAt started: Date) {
        let before = pending.count
        pending.removeAll { write in
            guard write.accountID == accountID, case .sent(let at) = write.status else { return false }
            return at <= started
        }
        if pending.count != before { save() }
    }

    /// `snapshots` from the cache with the changes that have not come back from the provider yet.
    public func overlay(_ snapshots: [EventSnapshot], calendar: Calendar) -> [EventSnapshot] {
        PendingOverlay.apply(pending.filter { $0.isWaiting || $0.isSent }, to: snapshots, calendar: calendar)
    }

    /// Gives up a failed (or waiting) write, and the later writes to the same event that depend on it.
    public func discard(_ id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let key = pending[index].eventKey
        let later = pending[index...].filter { $0.eventKey == key && !$0.isSent }.map(\.id)
        pending.removeAll { later.contains($0.id) }
        save()
    }

    /// Puts a failed write back in line for the next `flush`.
    public func retry(_ id: UUID) {
        mark(id, .waiting)
    }

    // MARK: -

    private func perform(_ write: PendingWrite, provider: any CalendarProvider, calendar: Calendar) async throws -> Outcome {
        // Behind earlier writes of the account (and a failed one to the same event), so they
        // reach the provider in the order made.
        if pending.contains(where: { $0.accountID == write.accountID && ($0.isWaiting || (!$0.isSent && $0.eventKey == write.eventKey)) }) {
            return enqueue(write)
        }
        do {
            try await send(write, provider: provider, calendar: calendar)
            return .saved
        } catch CalendarSyncError.offline {
            return enqueue(write)
        }
    }

    private func enqueue(_ write: PendingWrite) -> Outcome {
        pending.append(write)
        save()
        return .queued
    }

    private func send(_ write: PendingWrite, provider: any CalendarProvider, calendar: Calendar) async throws {
        switch write.kind {
        case .create(let id):
            try await provider.createEvent(write.draft!, id: id, in: write.calendar, calendar: calendar)
        case .update(let scope):
            try await provider.updateEvent(write.event!, to: write.draft!, scope: scope, in: write.calendar, calendar: calendar)
        case .delete(let scope):
            try await provider.deleteEvent(write.event!, scope: scope, in: write.calendar, calendar: calendar)
        }
    }

    /// Saved at once: a write sent and then sent again after a quit could move a series twice.
    private func mark(_ id: UUID, _ status: PendingWrite.Status) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index].status = status
        save()
    }

    private func acquire(_ account: String) async {
        guard busy.contains(account) else {
            busy.insert(account)
            return
        }
        await withCheckedContinuation { waiters[account, default: []].append($0) }
    }

    /// Hands the account to the next waiter, if any.
    private func release(_ account: String) {
        if var queue = waiters[account], !queue.isEmpty {
            queue.removeFirst().resume()
            waiters[account] = queue
        } else {
            busy.remove(account)
        }
    }

    /// Worth trying again later as it is: a timeout, a rate limit, a server hiccup.
    private static func isTransient(_ error: CalendarSyncError) -> Bool {
        guard case .http(let status, _) = error else { return false }
        return status == 408 || status == 429 || (500...599).contains(status)
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try JSONEncoder().encode(pending).write(to: fileURL, options: .atomic)
        } catch {
            // Kept in memory; the next save tries again.
        }
    }
}
