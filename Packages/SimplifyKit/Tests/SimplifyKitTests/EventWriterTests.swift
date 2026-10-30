import Foundation
import Testing
@testable import SimplifyKit

/// Records the writes it gets; `refuse` decides which fail and how.
actor RecordingProvider: CalendarProvider {
    private(set) var calls: [String] = []
    var refuse: @Sendable (String) -> CalendarSyncError? = { _ in nil }

    /// Creates take this long to answer.
    var createDelay: Duration = .zero

    func refuse(_ rule: @escaping @Sendable (String) -> CalendarSyncError?) { refuse = rule }
    func slowCreates(_ delay: Duration) { createDelay = delay }

    func calendars() async throws -> [RemoteCalendar] { [] }
    func changes(in remote: RemoteCalendar.Reference, syncToken: String?, calendar: Calendar) async throws -> CalendarChanges {
        CalendarChanges(isFullFetch: false, changes: [], nextSyncToken: syncToken)
    }

    private func record(_ call: String) throws {
        if let error = refuse(call) { throw error }
        calls.append(call)
    }

    func createEvent(_ draft: EventDraft, id: String, in remote: RemoteCalendar.Reference, calendar: Calendar) async throws {
        if createDelay > .zero { try await Task.sleep(for: createDelay) }
        try record("create \(id) \(draft.title)")
    }

    func updateEvent(_ event: EventSnapshot, to draft: EventDraft, scope: EditScope, in remote: RemoteCalendar.Reference, calendar: Calendar) async throws {
        try record("update \(event.remoteID) \(draft.title)")
    }

    func deleteEvent(_ event: EventSnapshot, scope: EditScope, in remote: RemoteCalendar.Reference, calendar: Calendar) async throws {
        try record("delete \(event.remoteID)")
    }
}

struct EventWriterTests {
    let google = RemoteCalendar.Reference(sourceID: "g|c", remoteID: "c", timeZone: nil)
    let account = "google:1"

    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "pending-\(UUID().uuidString).json")
    }

    func event(_ id: String, _ title: String) -> EventSnapshot {
        var event = EventSnapshot(id: google.sourceID + ":" + id, sourceID: google.sourceID, remoteID: id, title: title, isAllDay: false)
        event.start = kst(10, 1, 9)
        event.end = kst(10, 1, 10)
        return event
    }

    var weekly: EventSnapshot {
        var series = event("S1", "주간 회의")
        series.timeZone = "Asia/Seoul"
        series.recurrence = Recurrence(frequency: .weekly)
        return series
    }

    func draft(_ title: String, _ event: EventSnapshot? = nil) -> EventDraft {
        var draft = event.map { EventDraft(editing: $0, occurrenceStart: $0.start!, calendar: seoul) }
            ?? EventDraft(title: "", isAllDay: false, start: kst(11, 5, 12), end: kst(11, 5, 13))
        draft.title = title
        return draft
    }

    @Test func onlineChangesGoStraightThrough() async throws {
        let provider = RecordingProvider()
        let writer = EventWriter(fileURL: tempFile())
        #expect(try await writer.create(draft("점심"), in: google, accountID: account, provider: provider, calendar: seoul) == .saved)
        #expect(await provider.calls.count == 1)
        #expect(await writer.pending.isEmpty)
    }

    @Test func offlineChangesWaitAndSurviveARestart() async throws {
        let file = tempFile()
        let provider = RecordingProvider()
        await provider.refuse { _ in .offline }
        let writer = EventWriter(fileURL: file)
        #expect(try await writer.create(draft("점심"), in: google, accountID: account, provider: provider, calendar: seoul) == .queued)

        let restarted = EventWriter(fileURL: file)
        #expect(await restarted.pending.count == 1)
        let shown = await restarted.overlay([], calendar: seoul)
        #expect(shown.map(\.title) == ["점심"])
        #expect(shown[0].start == kst(11, 5, 12))
        #expect(shown[0].resourceHref == nil)

        await provider.refuse { _ in nil }
        let started = Date.now
        #expect(await restarted.flush(calendar: seoul) { _ in provider } == [account])
        #expect(await provider.calls == ["create \(shown[0].remoteID) 점심"])
        // Still shown until the account's sync brings it in.
        #expect(await restarted.overlay([], calendar: seoul).count == 1)
        await restarted.didSync(account, startedAt: started.addingTimeInterval(-60))
        #expect(await restarted.pending.count == 1, "sent after that sync started")
        await restarted.didSync(account, startedAt: .now)
        #expect(await restarted.pending.isEmpty)
        #expect(await EventWriter(fileURL: file).pending.isEmpty)
    }

    /// While something waits, later changes of the account wait behind it, even online.
    @Test func laterChangesKeepTheirOrder() async throws {
        let provider = RecordingProvider()
        await provider.refuse { _ in .offline }
        let writer = EventWriter(fileURL: tempFile())
        _ = try await writer.update(event("A", "a"), to: draft("A1", event("A", "a")), scope: .allOccurrences, in: google, accountID: account, provider: provider, calendar: seoul)
        await provider.refuse { _ in nil }
        #expect(try await writer.update(event("B", "b"), to: draft("B1", event("B", "b")), scope: .allOccurrences, in: google, accountID: account, provider: provider, calendar: seoul) == .queued)
        #expect(try await writer.create(draft("다른 계정"), in: google, accountID: "google:2", provider: provider, calendar: seoul) == .saved)

        _ = await writer.flush(calendar: seoul) { _ in provider }
        #expect(await provider.calls.suffix(2) == ["update A A1", "update B B1"])
    }

    @Test func anEventMadeAndDeletedOfflineIsForgotten() async throws {
        let provider = RecordingProvider()
        await provider.refuse { _ in .offline }
        let writer = EventWriter(fileURL: tempFile())
        _ = try await writer.create(draft("점심"), in: google, accountID: account, provider: provider, calendar: seoul)
        let made = await writer.overlay([], calendar: seoul)[0]
        _ = try await writer.update(made, to: draft("점심 (변경)", made), scope: .allOccurrences, in: google, accountID: account, provider: provider, calendar: seoul)
        #expect(await writer.overlay([], calendar: seoul).map(\.title) == ["점심 (변경)"])

        #expect(try await writer.delete(made, scope: .allOccurrences, in: google, accountID: account, provider: provider, calendar: seoul) == .saved)
        #expect(await writer.pending.isEmpty)
        #expect(await provider.calls.isEmpty)
    }

    /// An event made offline can be changed again before it reaches the provider: it already has its id.
    @Test func anEventMadeOfflineCanBeChangedOffline() async throws {
        let provider = RecordingProvider()
        await provider.refuse { _ in .offline }
        let writer = EventWriter(fileURL: tempFile())
        _ = try await writer.create(draft("점심"), in: google, accountID: account, provider: provider, calendar: seoul)
        let made = await writer.overlay([], calendar: seoul)[0]
        _ = try await writer.update(made, to: draft("저녁", made), scope: .allOccurrences, in: google, accountID: account, provider: provider, calendar: seoul)
        await provider.refuse { _ in nil }
        _ = await writer.flush(calendar: seoul) { _ in provider }
        #expect(await provider.calls == ["create \(made.remoteID) 점심", "update \(made.remoteID) 저녁"])
    }

    /// Deleting an event while its offline create is on its way waits for it, then deletes it for real.
    @Test func aDeleteDuringTheSendIsNotLost() async throws {
        let provider = RecordingProvider()
        await provider.refuse { _ in .offline }
        let writer = EventWriter(fileURL: tempFile())
        _ = try await writer.create(draft("점심"), in: google, accountID: account, provider: provider, calendar: seoul)
        let made = await writer.overlay([], calendar: seoul)[0]
        await provider.refuse { _ in nil }
        await provider.slowCreates(.milliseconds(300))

        let flushing = Task { await writer.flush(calendar: seoul) { _ in provider } }
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await writer.delete(made, scope: .allOccurrences, in: google, accountID: account, provider: provider, calendar: seoul) == .saved)
        _ = await flushing.value
        #expect(await provider.calls == ["create \(made.remoteID) 점심", "delete \(made.remoteID)"])
    }

    @Test func anUnreadableQueueIsSetAside() async throws {
        let file = tempFile()
        try Data("not json".utf8).write(to: file)
        let writer = EventWriter(fileURL: file)
        #expect(await writer.pending.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path + ".unreadable"))
    }

    @Test func aRefusalHoldsOnlyItsOwnEvent() async throws {
        let provider = RecordingProvider()
        await provider.refuse { _ in .offline }
        let writer = EventWriter(fileURL: tempFile())
        for (id, title) in [("A", "A1"), ("A", "A2"), ("B", "B1")] {
            _ = try await writer.update(event(id, id), to: draft(title, event(id, id)), scope: .allOccurrences, in: google, accountID: account, provider: provider, calendar: seoul)
        }
        await provider.refuse { $0.hasPrefix("update A") ? .conflict : nil }
        #expect(await writer.flush(calendar: seoul) { _ in provider } == [account])
        #expect(await provider.calls == ["update B B1"])
        let statuses = await writer.pending.map(\.status)
        #expect(statuses[0] == .failed(.conflict))
        #expect(statuses[1] == .waiting)
        #expect(await writer.overlay([event("A", "A")], calendar: seoul).map(\.title) == ["A2"], "the failed change is not shown")

        // Giving up the failed change gives up the one that built on it.
        await writer.discard(await writer.pending[0].id)
        let left = await writer.pending
        #expect(left.count == 1)
        #expect(left.allSatisfy { $0.isSent })
    }

    @Test func serverHiccupsWaitForTheNextRound() async throws {
        let provider = RecordingProvider()
        await provider.refuse { _ in .offline }
        let writer = EventWriter(fileURL: tempFile())
        _ = try await writer.create(draft("점심"), in: google, accountID: account, provider: provider, calendar: seoul)
        await provider.refuse { _ in .http(status: 503) }
        #expect(await writer.flush(calendar: seoul) { _ in provider }.isEmpty)
        #expect(await writer.pending.map(\.status) == [.waiting])
    }

    // MARK: Overlay

    var october: DateInterval { DateInterval(start: kst(10, 1), end: kst(11, 1)) }

    func shown(_ writes: [(EditScope, Bool)], calendar: Calendar = seoul) -> [Date] {
        let series = weekly
        let pending = writes.map { scope, isDelete in
            var draft = EventDraft(editing: series, occurrenceStart: kst(10, 22, 9), calendar: seoul)
            draft.start = kst(10, 22, 14)
            draft.end = kst(10, 22, 15)
            return PendingWrite(id: UUID(), accountID: account, calendar: google, kind: isDelete ? .delete(scope) : .update(scope),
                                event: series, draft: isDelete ? nil : draft, createdAt: .now)
        }
        return OccurrenceBuilder.occurrences(from: PendingOverlay.apply(pending, to: [series], calendar: seoul), in: october, calendar: seoul).map(\.start)
    }

    @Test func overlayShowsScopedChanges() {
        #expect(shown([]) == [kst(10, 1, 9), kst(10, 8, 9), kst(10, 15, 9), kst(10, 22, 9), kst(10, 29, 9)])
        #expect(shown([(.thisOccurrence(originalStart: kst(10, 22, 9)), false)]) == [kst(10, 1, 9), kst(10, 8, 9), kst(10, 15, 9), kst(10, 22, 14), kst(10, 29, 9)])
        #expect(shown([(.thisOccurrence(originalStart: kst(10, 22, 9)), true)]) == [kst(10, 1, 9), kst(10, 8, 9), kst(10, 15, 9), kst(10, 29, 9)])
        #expect(shown([(.allOccurrences, false)]) == [kst(10, 1, 14), kst(10, 8, 14), kst(10, 15, 14), kst(10, 22, 14), kst(10, 29, 14)])
        #expect(shown([(.thisAndFollowing(originalStart: kst(10, 22, 9)), false)]) == [kst(10, 1, 9), kst(10, 8, 9), kst(10, 15, 9), kst(10, 22, 14), kst(10, 29, 14)])
        #expect(shown([(.thisAndFollowing(originalStart: kst(10, 22, 9)), true)]) == [kst(10, 1, 9), kst(10, 8, 9), kst(10, 15, 9)])
        #expect(shown([(.allOccurrences, true)]).isEmpty)
    }

    @Test func overlaidCalDAVEventsKnowTheirResource() {
        let icloud = RemoteCalendar.Reference(sourceID: "i|w", remoteID: FakeDAVStore.collection, timeZone: nil)
        let made = PendingOverlay.snapshot(of: draft("치과"), remoteID: "u1", in: icloud, calendar: seoul)
        #expect(made.resourceHref == "/123/calendars/work/u1.ics")
        #expect(made.id == "i|w:u1")
    }
}
