import Foundation
import Testing
@testable import SimplifyKit

/// When a repeating event stops: the editor's 안 함 / 날짜 / 횟수, written as UNTIL or COUNT.
struct RepeatEndTests {
    func timed(_ end: RepeatEnd, zone: String? = nil) -> EventDraft {
        EventDraft(title: "주간 회의", isAllDay: false, start: kst(11, 16, 10), end: kst(11, 16, 11), timeZone: zone, repeatRule: .weekly, repeatEnd: end)
    }

    // MARK: Writing the rule

    @Test func untilIsTheLastDay() {
        // All day: the date itself.
        let allDay = EventDraft(title: "당번", isAllDay: true, start: kst(11, 16), end: kst(11, 17), repeatRule: .weekly, repeatEnd: .until(kst(12, 16)))
        #expect(allDay.rrule(calendar: seoul) == "RRULE:FREQ=WEEKLY;UNTIL=20261216")
        // Timed: the last second of that day in the event's zone, in UTC.
        #expect(timed(.until(kst(12, 16))).rrule(calendar: seoul) == "RRULE:FREQ=WEEKLY;UNTIL=20261216T145959Z")
        #expect(timed(.until(kst(12, 16)), zone: "America/New_York").rrule(calendar: seoul) == "RRULE:FREQ=WEEKLY;UNTIL=20261217T045959Z")
    }

    @Test func countAndNever() {
        #expect(timed(.count(10)).rrule(calendar: seoul) == "RRULE:FREQ=WEEKLY;COUNT=10")
        #expect(timed(.never).rrule(calendar: seoul) == "RRULE:FREQ=WEEKLY")
        var none = timed(.count(10))
        none.repeatRule = .none
        #expect(none.rrule(calendar: seoul) == nil)
    }

    /// What is written reads back as the same end.
    @Test func storedEndsReadBack() {
        let draft = timed(.until(kst(12, 16)))
        let rule = draft.recurrence(calendar: seoul)
        #expect(rule?.until == kst(12, 16, 23, 59).addingTimeInterval(59))
        #expect(RepeatEnd(rule, isAllDay: false, calendar: seoul) == .until(kst(12, 16)))
        // An event in another zone reads back the day picked, not the day it is in Seoul then.
        let newYork = timed(.until(kst(12, 16)), zone: "America/New_York").recurrence(calendar: seoul)
        #expect(RepeatEnd(newYork, isAllDay: false, timeZone: "America/New_York", calendar: seoul) == .until(kst(12, 16)))

        let allDay = Recurrence(rrule: "RRULE:FREQ=WEEKLY;UNTIL=20261216", calendar: DayKey.utc)
        #expect(RepeatEnd(allDay, isAllDay: true, calendar: seoul) == .until(kst(12, 16)))
        #expect(RepeatEnd(Recurrence(rrule: "RRULE:FREQ=DAILY;COUNT=7", calendar: seoul), isAllDay: false, calendar: seoul) == .count(7))
        #expect(RepeatEnd(Recurrence(frequency: .daily), isAllDay: false, calendar: seoul) == .never)
        #expect(RepeatEnd(nil, isAllDay: false, calendar: seoul) == .never)
    }

    // MARK: What changes

    var master: EventSnapshot {
        var event = EventSnapshot(id: "s:S1", sourceID: "s", remoteID: "S1", title: "주간 회의", isAllDay: false)
        event.start = kst(10, 1, 9)
        event.end = kst(10, 1, 10)
        event.timeZone = "Asia/Seoul"
        event.recurrence = Recurrence(rrule: "RRULE:FREQ=WEEKLY;COUNT=10", calendar: seoul)
        return event
    }

    @Test func onlyAnotherEndChangesTheRule() {
        var draft = EventDraft(editing: master, occurrenceStart: kst(11, 5, 9), calendar: seoul)
        #expect(draft.repeatEnd == .count(10))
        #expect(!draft.changesRule(of: master, calendar: seoul))

        draft.repeatEnd = .count(12)
        #expect(draft.changesRule(of: master, calendar: seoul))
        #expect(draft.changesEnd(of: master, calendar: seoul))
        #expect(!draft.changesPreset(of: master))

        draft.repeatEnd = .never
        #expect(draft.changesEnd(of: master, calendar: seoul))

        // Another preset replaces the rule as a whole, end and all.
        draft.repeatRule = .daily
        #expect(draft.changesPreset(of: master))
        #expect(!draft.changesEnd(of: master, calendar: seoul))
    }

    /// Unsent writes saved before the end existed still read, and repeat forever.
    @Test func oldDraftsReadWithoutAnEnd() throws {
        let draft = timed(.until(kst(12, 16)))
        let data = try JSONEncoder().encode(draft)
        #expect(try JSONDecoder().decode(EventDraft.self, from: data) == draft)

        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["repeatEnd"] = nil
        let old = try JSONDecoder().decode(EventDraft.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.repeatEnd == .never)
        #expect(old.repeatRule == .weekly)
        #expect(old.title == "주간 회의")
    }

    // MARK: Reading presets

    @Test func presetShapedRulesWithAnEndArePresets() {
        let thursday = kst(10, 1, 9)
        func preset(_ line: String) -> RepeatPreset? {
            RepeatPreset.matching(Recurrence(rrule: line, calendar: seoul)!, start: thursday, calendar: seoul)
        }
        #expect(preset("RRULE:FREQ=WEEKLY;COUNT=10") == .weekly)
        #expect(preset("RRULE:FREQ=WEEKLY;BYDAY=TH;UNTIL=20261216T145959Z") == .weekly)
        #expect(preset("RRULE:FREQ=MONTHLY;BYMONTHDAY=1;COUNT=5") == .monthly)
        #expect(preset("RRULE:FREQ=DAILY;UNTIL=20261216") == .daily)
        #expect(preset("RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=10") == nil)
        #expect(preset("RRULE:FREQ=WEEKLY;BYDAY=MO,WE") == nil)
        #expect(preset("RRULE:FREQ=MONTHLY;BYDAY=1TH") == nil)
    }
}

struct RepeatEndWriteTests {
    let reference = RemoteCalendar.Reference(sourceID: "s", remoteID: "c", timeZone: "Asia/Seoul")
    let google = GoogleWriteTests()

    /// The ten-week Google series, with one week skipped.
    static let master = """
        {"id":"s1","summary":"주간 회의","start":{"dateTime":"2026-10-01T09:00:00+09:00","timeZone":"Asia/Seoul"},\
        "end":{"dateTime":"2026-10-01T10:00:00+09:00","timeZone":"Asia/Seoul"},\
        "recurrence":["RRULE:FREQ=WEEKLY;COUNT=10","EXDATE;TZID=Asia/Seoul:20261015T090000"]}
        """

    func server() throws -> (GoogleCalendarAPI, FakeHTTP) {
        try google.api { request in request.httpMethod == "GET" ? (200, Self.master) : (request.httpMethod == "DELETE" ? 204 : 200, "{}") }
    }

    var series: EventSnapshot {
        try! JSONDecoder().decode(GoogleEvent.self, from: Data(Self.master.utf8)).snapshot(sourceID: "s", calendar: seoul, defaultZone: nil)
    }

    @Test func googleCreateSendsTheEnd() async throws {
        let (api, http) = try server()
        let draft = EventDraft(title: "점심", isAllDay: false, start: kst(11, 5, 12), end: kst(11, 5, 13), repeatRule: .weekly, repeatEnd: .count(4))
        try await api.createEvent(draft, id: "abc123", in: reference, calendar: seoul)
        #expect(google.body(http.requests[0])["recurrence"] as? [String] == ["RRULE:FREQ=WEEKLY;COUNT=4"])
    }

    /// A new end on every occurrence keeps the skipped week.
    @Test func googleEndOnlyKeepsTheRest() async throws {
        let (api, http) = try server()
        var draft = EventDraft(editing: series, occurrenceStart: kst(11, 5, 9), calendar: seoul)
        #expect(draft.repeatEnd == .count(10))
        draft.repeatEnd = .until(kst(12, 16))
        try await api.updateEvent(series, to: draft, scope: .allOccurrences, in: reference, calendar: seoul)
        let sent = google.body(http.requests[1])
        #expect(sent["recurrence"] as? [String] == ["RRULE:FREQ=WEEKLY;UNTIL=20261216T145959Z", "EXDATE;TZID=Asia/Seoul:20261015T090000"])
        // The series does not move.
        #expect((sent["start"] as? [String: Any])?["dateTime"] as? String == "2026-10-01T09:00:00+09:00")

        // The same end sends no rule.
        let same = EventDraft(editing: series, occurrenceStart: kst(11, 5, 9), calendar: seoul)
        try await api.updateEvent(series, to: same, scope: .allOccurrences, in: reference, calendar: seoul)
        #expect(google.body(http.requests[3])["recurrence"] == nil)
    }

    /// The count picked is the whole series': after a split at the sixth week, the new part makes the rest.
    @Test func googleSplitCountsFromTheFirst() async throws {
        let (api, http) = try server()
        var draft = EventDraft(editing: series, occurrenceStart: kst(11, 5, 9), calendar: seoul)
        draft.title = "새 주간 회의"
        draft.repeatEnd = .count(12)
        try await api.updateEvent(series, to: draft, scope: .thisAndFollowing(originalStart: kst(11, 5, 9)), in: reference, calendar: seoul)
        // Five occurrences came before 11/5 (10/15 skipped still counts, as COUNT does).
        #expect(google.body(http.requests[1])["recurrence"] as? [String] == ["RRULE:FREQ=WEEKLY;COUNT=7", "EXDATE;TZID=Asia/Seoul:20261015T090000"])
        #expect(google.body(http.requests[2]) as NSDictionary == ["recurrence": ["RRULE:FREQ=WEEKLY;UNTIL=20261104T235959Z", "EXDATE;TZID=Asia/Seoul:20261015T090000"]])

        // Another preset with a count: the new rule alone, its count less what came before.
        draft.repeatRule = .daily
        try await api.updateEvent(series, to: draft, scope: .thisAndFollowing(originalStart: kst(11, 5, 9)), in: reference, calendar: seoul)
        #expect(google.body(http.requests[4])["recurrence"] as? [String] == ["RRULE:FREQ=DAILY;COUNT=7"])

        // A date end is the same date in both.
        draft.repeatRule = .weekly
        draft.repeatEnd = .until(kst(12, 16))
        try await api.updateEvent(series, to: draft, scope: .thisAndFollowing(originalStart: kst(11, 5, 9)), in: reference, calendar: seoul)
        #expect(google.body(http.requests[7])["recurrence"] as? [String] == ["RRULE:FREQ=WEEKLY;UNTIL=20261216T145959Z", "EXDATE;TZID=Asia/Seoul:20261015T090000"])
    }

    // MARK: CalDAV

    let dav = CalDAVWriteTests()

    @Test func calDAVEndOnlyKeepsSkippedAndChangedOccurrences() async throws {
        let (provider, store) = dav.setup()
        let series = dav.master(store)
        var draft = EventDraft(editing: series, occurrenceStart: kst(11, 5, 9), calendar: seoul)
        #expect(draft.repeatEnd == .count(10))
        draft.repeatEnd = .until(kst(12, 16))
        try await provider.updateEvent(series, to: draft, scope: .allOccurrences, in: dav.reference, calendar: seoul)
        let ics = store.files[FakeDAVStore.path]!.ics
        #expect(ics.contains("RRULE:FREQ=WEEKLY;UNTIL=20261216T145959Z\r\n"))
        #expect(ics.contains("EXDATE;TZID=Asia/Seoul:20261015T090000"))
        #expect(ics.contains("RECURRENCE-ID;TZID=Asia/Seoul:20261008T090000"))
        #expect(ics.contains("RECURRENCE-ID;TZID=Asia/Seoul:20261112T090000"))
        #expect(dav.master(store).recurrence?.until == kst(12, 16, 23, 59).addingTimeInterval(59))

        draft = EventDraft(editing: dav.master(store), occurrenceStart: kst(11, 5, 9), calendar: seoul)
        #expect(draft.repeatEnd == .until(kst(12, 16)))
        draft.repeatEnd = .never
        try await provider.updateEvent(dav.master(store), to: draft, scope: .allOccurrences, in: dav.reference, calendar: seoul)
        #expect(store.files[FakeDAVStore.path]!.ics.contains("RRULE:FREQ=WEEKLY\r\n"))
    }

    @Test func calDAVSplitCountsFromTheFirst() async throws {
        let (provider, store) = dav.setup()
        let series = dav.master(store)
        var draft = EventDraft(editing: series, occurrenceStart: kst(11, 5, 9), calendar: seoul)
        draft.start = kst(11, 5, 10)
        draft.end = kst(11, 5, 11)
        draft.repeatEnd = .count(12)
        try await provider.updateEvent(series, to: draft, scope: .thisAndFollowing(originalStart: kst(11, 5, 9)), in: dav.reference, calendar: seoul)
        let newPath = store.files.keys.first { $0 != FakeDAVStore.path }!
        #expect(store.files[FakeDAVStore.path]!.ics.contains("RRULE:FREQ=WEEKLY;UNTIL=20261104T235959Z"))
        let new = store.files[newPath]!.ics
        #expect(new.contains("RRULE:FREQ=WEEKLY;COUNT=7"))
        // The changed occurrence after the split goes with the new part.
        #expect(new.contains("RECURRENCE-ID;TZID=Asia/Seoul:20261112T100000"))
    }

    @Test func calDAVCreateWritesTheEnd() async throws {
        let (provider, store) = dav.setup()
        let draft = EventDraft(title: "당번", isAllDay: true, start: kst(11, 16), end: kst(11, 17), repeatRule: .weekly, repeatEnd: .until(kst(12, 14)))
        try await provider.createEvent(draft, id: "new1", in: dav.reference, calendar: seoul)
        let ics = store.files["/123/calendars/work/new1.ics"]!.ics
        #expect(ics.contains("RRULE:FREQ=WEEKLY;UNTIL=20261214\r\n"))
        let read = dav.events(store, "/123/calendars/work/new1.ics")[0]
        #expect(RepeatEnd(read.recurrence, isAllDay: true, calendar: seoul) == .until(kst(12, 14)))
    }

    // MARK: Shown before the provider answers

    let writer = EventWriterTests()

    func shown(_ draft: EventDraft, scope: EditScope, series: EventSnapshot) -> [Date] {
        let write = PendingWrite(id: UUID(), accountID: writer.account, calendar: writer.google, kind: .update(scope), event: series, draft: draft, createdAt: .now)
        let range = DateInterval(start: kst(10, 1), end: kst(12, 31))
        return OccurrenceBuilder.occurrences(from: PendingOverlay.apply([write], to: [series], calendar: seoul), in: range, calendar: seoul).map(\.start)
    }

    @Test func overlayEndsWhereTheDraftSays() {
        var series = writer.weekly
        series.exceptionDates = [kst(10, 8, 9)]
        var draft = EventDraft(editing: series, occurrenceStart: kst(10, 22, 9), calendar: seoul)
        draft.repeatEnd = .count(4)
        // Four from the first, the skipped week still skipped.
        #expect(shown(draft, scope: .allOccurrences, series: series) == [kst(10, 1, 9), kst(10, 15, 9), kst(10, 22, 9)])

        draft.repeatEnd = .until(kst(10, 29))
        #expect(shown(draft, scope: .allOccurrences, series: series) == [kst(10, 1, 9), kst(10, 15, 9), kst(10, 22, 9), kst(10, 29, 9)])

        // Split at 10/22 with a count of 5: three before (10/8 skipped but counted), two after.
        draft.title = "새 주간 회의"
        draft.repeatEnd = .count(5)
        #expect(shown(draft, scope: .thisAndFollowing(originalStart: kst(10, 22, 9)), series: series) == [kst(10, 1, 9), kst(10, 15, 9), kst(10, 22, 9), kst(10, 29, 9)])

        // A new event with an end.
        let made = PendingOverlay.snapshot(of: timedNew(.count(3)), remoteID: "n1", in: writer.google, calendar: seoul)
        #expect(made.recurrence?.count == 3)
    }

    func timedNew(_ end: RepeatEnd) -> EventDraft {
        EventDraft(title: "점심", isAllDay: false, start: kst(11, 5, 12), end: kst(11, 5, 13), repeatRule: .weekly, repeatEnd: end)
    }
}
