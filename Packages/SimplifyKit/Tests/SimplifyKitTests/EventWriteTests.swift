import Foundation
import SwiftData
import Testing
@testable import SimplifyKit

/// A CalDAV server that only stores resources, with ETags that go up on every write.
final class FakeDAVStore: @unchecked Sendable {
    var files: [String: (ics: String, etag: Int)] = [:]
    /// Someone else writes the resource right after it was read.
    var changedElsewhere = false
    /// A server that sends no ETags.
    var sendsETags = true

    lazy var http = FakeHTTP(headers: { [unowned self] request in self.answer(request) })

    static let collection = "https://p01-caldav.icloud.com/123/calendars/work/"
    static let path = "/123/calendars/work/S1.ics"

    private func answer(_ request: URLRequest) -> (Int, String, [String: String]) {
        let path = request.url!.path(percentEncoded: false)
        let current = files[path]
        let ifMatch = request.value(forHTTPHeaderField: "If-Match")
        if let ifMatch, ifMatch != current.map({ "\"\($0.etag)\"" }) { return (412, "", [:]) }
        switch request.httpMethod {
        case "GET":
            guard let current else { return (404, "", [:]) }
            if changedElsewhere { files[path]!.etag += 1 }
            return (200, current.ics, sendsETags ? ["ETag": "\"\(current.etag)\""] : [:])
        case "PUT":
            if request.value(forHTTPHeaderField: "If-None-Match") == "*", current != nil { return (412, "", [:]) }
            files[path] = (String(decoding: request.httpBody!, as: UTF8.self), (current?.etag ?? 0) + 1)
            return (current == nil ? 201 : 204, "", [:])
        case "DELETE":
            guard current != nil else { return (404, "", [:]) }
            files[path] = nil
            return (204, "", [:])
        default:
            return (400, "", [:])
        }
    }

    static let series = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Apple Inc.//macOS 26//EN
        BEGIN:VTIMEZONE
        TZID:Asia/Seoul
        BEGIN:STANDARD
        DTSTART:19700101T000000
        TZOFFSETFROM:+0900
        TZOFFSETTO:+0900
        END:STANDARD
        END:VTIMEZONE
        BEGIN:VEVENT
        UID:S1
        DTSTART;TZID=Asia/Seoul:20261001T090000
        DTEND;TZID=Asia/Seoul:20261001T100000
        SUMMARY:주간 회의
        RRULE:FREQ=WEEKLY;COUNT=10
        EXDATE;TZID=Asia/Seoul:20261015T090000
        ATTENDEE;CN=Kim:mailto:kim@example.com
        X-APPLE-TRAVEL-ADVISORY-BEHAVIOR:AUTOMATIC
        SEQUENCE:2
        BEGIN:VALARM
        ACTION:DISPLAY
        TRIGGER:-PT10M
        END:VALARM
        END:VEVENT
        BEGIN:VEVENT
        UID:S1
        RECURRENCE-ID;TZID=Asia/Seoul:20261008T090000
        DTSTART;TZID=Asia/Seoul:20261008T110000
        DTEND;TZID=Asia/Seoul:20261008T120000
        SUMMARY:주간 회의 (늦게)
        END:VEVENT
        BEGIN:VEVENT
        UID:S1
        RECURRENCE-ID;TZID=Asia/Seoul:20261112T090000
        DTSTART;TZID=Asia/Seoul:20261112T090000
        DTEND;TZID=Asia/Seoul:20261112T100000
        SUMMARY:주간 회의 (외부)
        END:VEVENT
        END:VCALENDAR
        """.replacingOccurrences(of: "\n", with: "\r\n")
}

let seoul: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
}()

/// A moment in 2026 on Seoul's wall clock.
func kst(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    seoul.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

struct EventDraftTests {
    let master: EventSnapshot = {
        var event = EventSnapshot(id: "s:S1", sourceID: "s", remoteID: "S1", title: "주간 회의", isAllDay: false)
        event.start = kst(10, 1, 9)
        event.end = kst(10, 1, 10)
        event.timeZone = "Asia/Seoul"
        event.recurrence = Recurrence(rrule: "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TH", calendar: seoul)
        event.notes = "안건 정리"
        return event
    }()

    @Test func editingATimedOccurrence() {
        let draft = EventDraft(editing: master, occurrenceStart: kst(11, 12, 9), calendar: seoul)
        #expect(draft.title == "주간 회의")
        #expect(draft.start == kst(11, 12, 9))
        #expect(draft.end == kst(11, 12, 10))
        #expect(draft.timeZone == "Asia/Seoul")
        #expect(draft.notes == "안건 정리")
        // Every other Thursday shows as weekly, and is kept unless another preset is picked.
        #expect(draft.repeatRule == .weekly)
        #expect(!draft.changesRule(of: master))
        var daily = draft
        daily.repeatRule = .daily
        #expect(daily.changesRule(of: master))
        #expect(draft.occurrenceStart == kst(11, 12, 9))
    }

    @Test func editingAnAllDayOccurrence() {
        var event = EventSnapshot(id: "s:A", sourceID: "s", remoteID: "A", title: "(제목 없음)", isAllDay: true)
        event.startDay = "2026-11-02"
        event.endDay = "2026-11-05"
        let draft = EventDraft(editing: event, occurrenceStart: kst(11, 9, 0), calendar: seoul)
        #expect(draft.title == "")
        #expect(draft.start == kst(11, 9))
        #expect(draft.end == kst(11, 12))
        #expect(draft.timeZone == nil)
        #expect(draft.repeatRule == .none)
    }

    @Test func aChangedOccurrenceHasNoRuleOfItsOwn() {
        var event = master
        event.recurringEventID = "S1"
        event.originalStart = kst(10, 15, 9)
        let draft = EventDraft(editing: event, occurrenceStart: kst(10, 15, 9), calendar: seoul)
        #expect(draft.repeatRule == .none)
        #expect(!draft.changesRule(of: event))
    }

    /// Changing every occurrence moves the series' first day by as many days as the occurrence moved.
    @Test func seriesMoveByTheDaysTheOccurrenceMoved() {
        var draft = EventDraft(editing: master, occurrenceStart: kst(11, 12, 9), calendar: seoul)
        draft.start = kst(11, 13, 10, 30)
        draft.end = kst(11, 13, 12)
        let span = draft.seriesSpan(masterDay: DateComponents(year: 2026, month: 10, day: 1), calendar: seoul)
        #expect(span.start == kst(10, 2, 10, 30))
        #expect(span.end == kst(10, 2, 12))

        var allDay = draft
        allDay.isAllDay = true
        allDay.start = kst(11, 14)
        allDay.end = kst(11, 16)
        let days = allDay.seriesSpan(masterDay: DateComponents(year: 2026, month: 10, day: 1), calendar: seoul)
        #expect(days.start == kst(10, 3))
        #expect(days.end == kst(10, 5))
    }

    @Test func notesAreCached() {
        var event = master
        event.notes = "회의실 B"
        #expect(EventRecord(event).snapshot.notes == "회의실 B")
    }

    @Test func remindersAreReadOnly() async {
        let draft = EventDraft(title: "x", isAllDay: true, start: kst(11, 1), end: kst(11, 2))
        let reference = RemoteCalendar.Reference(sourceID: "r", remoteID: "list", timeZone: nil)
        await #expect(throws: CalendarSyncError.readOnly) {
            try await RemindersProvider().createEvent(draft, id: "1", in: reference, calendar: seoul)
        }
        await #expect(throws: CalendarSyncError.readOnly) {
            try await RemindersProvider().deleteEvent(master, scope: .allOccurrences, in: reference, calendar: seoul)
        }
    }
}

struct ICalendarWriterTests {
    @Test func longTextIsFoldedAndEscapedAndReadsBack() {
        let title = String(repeating: "가나다, 라;마\\바\n", count: 8)
        let draft = EventDraft(title: title, isAllDay: false, start: kst(11, 5, 9), end: kst(11, 5, 10), notes: "첫 줄\n둘째 줄")
        var resource = ICSResource(calendar: ICSResource.newCalendar(), person: seoul, defaultZone: nil)
        var event = ICalendar.Component(name: "VEVENT", properties: [.init(name: "UID", params: [:], value: "U1")])
        resource.apply(draft, start: draft.start, end: draft.end, to: &event)
        resource.calendar.children.append(event)
        resource.defineZone(of: draft)
        let text = resource.text

        #expect(text.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        #expect(text.contains("DTSTART;TZID=Asia/Seoul:20261105T090000"))
        #expect(text.contains("BEGIN:VTIMEZONE\r\nTZID:Asia/Seoul"))
        let read = ICalendar.events(in: text, sourceID: "s", href: "/x.ics", calendar: seoul)
        #expect(read.count == 1)
        #expect(read[0].title == title)
        #expect(read[0].notes == "첫 줄\n둘째 줄")
        #expect(read[0].start == kst(11, 5, 9))
        #expect(read[0].end == kst(11, 5, 10))
        #expect(read[0].timeZone == "Asia/Seoul")
    }

    @Test func allDayAndUTCTimes() {
        #expect(ICalendarWriter.line(ICalendarWriter.time("DTSTART", kst(11, 5), isAllDay: true, zone: "Asia/Seoul", calendar: seoul)) == "DTSTART;VALUE=DATE:20261105")
        #expect(ICalendarWriter.line(ICalendarWriter.time("DTSTART", kst(11, 5, 9), isAllDay: false, zone: "UTC", calendar: seoul)) == "DTSTART:20261105T000000Z")
    }

    @Test func daylightZonesGetYearlyRules() {
        let zone = ICalendarWriter.timeZone("America/New_York", around: kst(6, 1))!
        let text = ICalendarWriter.text([zone])
        // Rules from this year, starting on the day they pick in 1970.
        #expect(text.contains("BEGIN:DAYLIGHT\r\nDTSTART:19700308T020000\r\nTZOFFSETFROM:-0500\r\nTZOFFSETTO:-0400\r\nRRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU"))
        #expect(text.contains("BEGIN:STANDARD\r\nDTSTART:19701101T020000\r\nTZOFFSETFROM:-0400\r\nTZOFFSETTO:-0500\r\nRRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU"))
        let london = ICalendarWriter.text([ICalendarWriter.timeZone("Europe/London", around: kst(6, 1))!])
        #expect(london.contains("DTSTART:19700329T010000\r\nTZOFFSETFROM:+0000\r\nTZOFFSETTO:+0100\r\nRRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU"))
        let fixed = ICalendarWriter.text([ICalendarWriter.timeZone("Asia/Seoul")!])
        #expect(fixed.contains("DTSTART:19700101T000000\r\nTZOFFSETFROM:+0900\r\nTZOFFSETTO:+0900"))
    }

    @Test func untouchedLinesAreWrittenBackAsTheyCame() {
        let parsed = ICalendar.parse(FakeDAVStore.series)
        #expect(ICalendarWriter.text(parsed) == FakeDAVStore.series + "\r\n")
    }
}

struct GoogleWriteTests {
    let reference = RemoteCalendar.Reference(sourceID: "s", remoteID: "c", timeZone: "Asia/Seoul")

    static let master = """
        {"id":"s1","summary":"주간 회의","start":{"dateTime":"2026-10-01T09:00:00+09:00","timeZone":"Asia/Seoul"},\
        "end":{"dateTime":"2026-10-01T10:00:00+09:00","timeZone":"Asia/Seoul"},"recurrence":["RRULE:FREQ=WEEKLY;COUNT=10"]}
        """

    func api(_ handler: @escaping (URLRequest) -> (Int, String)) throws -> (GoogleCalendarAPI, FakeHTTP) {
        let store = MemoryTokenStore()
        try store.save(GoogleTokens(accessToken: "t", refreshToken: "r", expiresAt: .distantFuture), for: "acct")
        let http = FakeHTTP(handler)
        return (GoogleCalendarAPI(http: http, session: GoogleSession(accountID: "acct", oauth: GoogleOAuth(clientID: GoogleTests.clientID, http: http), store: store)), http)
    }

    /// Answers the master on GET and succeeds at everything else.
    func server() throws -> (GoogleCalendarAPI, FakeHTTP) {
        try api { request in request.httpMethod == "GET" ? (200, Self.master) : (request.httpMethod == "DELETE" ? 204 : 200, "{}") }
    }

    var series: EventSnapshot {
        try! JSONDecoder().decode(GoogleEvent.self, from: Data(Self.master.utf8)).snapshot(sourceID: "s", calendar: seoul, defaultZone: nil)
    }

    func body(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    func line(_ request: URLRequest) -> String {
        request.httpMethod! + " " + request.url!.path(percentEncoded: true)
    }

    @Test func createSendsTheChosenIDAndRule() async throws {
        let (api, http) = try server()
        let draft = EventDraft(title: "점심", isAllDay: false, start: kst(11, 5, 12), end: kst(11, 5, 13), location: "을지로", repeatRule: .weekly)
        try await api.createEvent(draft, id: "abc123", in: reference, calendar: seoul)
        #expect(http.requests.map(line) == ["POST /calendar/v3/calendars/c/events"])
        let sent = body(http.requests[0])
        #expect(sent["id"] as? String == "abc123")
        #expect(sent["summary"] as? String == "점심")
        #expect(sent["location"] as? String == "을지로")
        #expect(sent["description"] == nil)
        #expect(sent["recurrence"] as? [String] == ["RRULE:FREQ=WEEKLY"])
        #expect(sent["start"] as? [String: String] == ["dateTime": "2026-11-05T12:00:00+09:00", "timeZone": "Asia/Seoul"])
    }

    /// A retry after an answer that never came back finds the event made (409).
    @Test func createdTwiceIsCreatedOnce() async throws {
        let (api, http) = try api { _ in (409, #"{"error":{"errors":[{"reason":"duplicate"}]}}"#) }
        let draft = EventDraft(title: "점심", isAllDay: true, start: kst(11, 5), end: kst(11, 6))
        try await api.createEvent(draft, id: "abc123", in: reference, calendar: seoul)
        #expect(http.requests.count == 1, "a 409 is not retried")
    }

    @Test func oneOccurrenceIsPatchedByItsInstanceID() async throws {
        let (api, http) = try server()
        var draft = EventDraft(editing: series, occurrenceStart: kst(11, 5, 9), calendar: seoul)
        draft.start = kst(11, 5, 14)
        draft.end = kst(11, 5, 15)
        try await api.updateEvent(series, to: draft, scope: .thisOccurrence(originalStart: kst(11, 5, 9)), in: reference, calendar: seoul)
        #expect(http.requests.map(line) == ["PATCH /calendar/v3/calendars/c/events/s1_20261105T000000Z"])
        let sent = body(http.requests[0])
        #expect(sent["recurrence"] == nil)
        #expect((sent["start"] as? [String: Any])?["date"] is NSNull)

        try await api.deleteEvent(series, scope: .thisOccurrence(originalStart: kst(11, 5, 9)), in: reference, calendar: seoul)
        #expect(line(http.requests[1]) == "DELETE /calendar/v3/calendars/c/events/s1_20261105T000000Z")

        var allDay = series
        allDay.isAllDay = true
        allDay.startDay = "2026-10-01"
        #expect(GoogleCalendarAPI.instanceID(of: allDay, originalStart: kst(11, 5), calendar: seoul) == "s1_20261105")
    }

    @Test func everyOccurrenceMovesTheSeries() async throws {
        let (api, http) = try server()
        var draft = EventDraft(editing: series, occurrenceStart: kst(11, 5, 9), calendar: seoul)
        draft.start = kst(11, 6, 10)
        draft.end = kst(11, 6, 11)
        try await api.updateEvent(series, to: draft, scope: .allOccurrences, in: reference, calendar: seoul)
        #expect(http.requests.map(line) == ["GET /calendar/v3/calendars/c/events/s1", "PATCH /calendar/v3/calendars/c/events/s1"])
        let sent = body(http.requests[1])
        #expect((sent["start"] as? [String: Any])?["dateTime"] as? String == "2026-10-02T10:00:00+09:00")
        #expect((sent["end"] as? [String: Any])?["dateTime"] as? String == "2026-10-02T11:00:00+09:00")
        #expect(sent["recurrence"] == nil, "the rule stays as it was")

        draft.repeatRule = .none
        try await api.updateEvent(series, to: draft, scope: .allOccurrences, in: reference, calendar: seoul)
        #expect(body(http.requests[3])["recurrence"] as? [String] == [])
    }

    @Test func thisAndFollowingSplitsTheSeries() async throws {
        let (api, http) = try server()
        var draft = EventDraft(editing: series, occurrenceStart: kst(11, 5, 9), calendar: seoul)
        draft.title = "새 주간 회의"
        try await api.updateEvent(series, to: draft, scope: .thisAndFollowing(originalStart: kst(11, 5, 9)), in: reference, calendar: seoul)
        #expect(http.requests.map(line) == ["GET /calendar/v3/calendars/c/events/s1", "POST /calendar/v3/calendars/c/events", "PATCH /calendar/v3/calendars/c/events/s1"])
        let new = body(http.requests[1])
        #expect(new["summary"] as? String == "새 주간 회의")
        // Five of the ten occurrences came before 11/5.
        #expect(new["recurrence"] as? [String] == ["RRULE:FREQ=WEEKLY;COUNT=5"])
        #expect((new["start"] as? [String: Any])?["dateTime"] as? String == "2026-11-05T09:00:00+09:00")
        #expect(body(http.requests[2]) as NSDictionary == ["recurrence": ["RRULE:FREQ=WEEKLY;UNTIL=20261104T235959Z"]])

        // Sent again (the patch never got its answer): the new part keeps its id, so Google
        // answers 409 rather than making a second one.
        try await api.updateEvent(series, to: draft, scope: .thisAndFollowing(originalStart: kst(11, 5, 9)), in: reference, calendar: seoul)
        #expect(body(http.requests[4])["id"] as? String == new["id"] as? String)

        try await api.deleteEvent(series, scope: .thisAndFollowing(originalStart: kst(11, 5, 9)), in: reference, calendar: seoul)
        #expect(body(http.requests[7]) as NSDictionary == ["recurrence": ["RRULE:FREQ=WEEKLY;UNTIL=20261104T235959Z"]])

        // From the first occurrence on is the whole series.
        try await api.deleteEvent(series, scope: .thisAndFollowing(originalStart: kst(10, 1, 9)), in: reference, calendar: seoul)
        #expect(line(http.requests.last!) == "DELETE /calendar/v3/calendars/c/events/s1")
    }

    @Test func singleEventsTurnAllDay() async throws {
        let (api, http) = try server()
        var event = EventSnapshot(id: "s:e1", sourceID: "s", remoteID: "e1", title: "출장", isAllDay: false)
        event.start = kst(11, 5, 9)
        event.end = kst(11, 5, 18)
        event.location = "부산"
        var draft = EventDraft(editing: event, occurrenceStart: kst(11, 5, 9), calendar: seoul)
        draft.isAllDay = true
        draft.start = kst(11, 5)
        draft.end = kst(11, 7)
        draft.location = nil
        try await api.updateEvent(event, to: draft, scope: .allOccurrences, in: reference, calendar: seoul)
        #expect(http.requests.map(line) == ["PATCH /calendar/v3/calendars/c/events/e1"])
        let sent = body(http.requests[0])
        let start = sent["start"] as? [String: Any]
        #expect(start?["date"] as? String == "2026-11-05")
        #expect(start?["dateTime"] is NSNull)
        #expect((sent["end"] as? [String: Any])?["date"] as? String == "2026-11-07")
        #expect(sent["location"] is NSNull)
    }

    @Test func writeErrors() async throws {
        let event = EventSnapshot(id: "s:e1", sourceID: "s", remoteID: "e1", title: "x", isAllDay: true)
        let draft = EventDraft(title: "x", isAllDay: true, start: kst(11, 5), end: kst(11, 6))
        let (gone, _) = try api { _ in (404, "") }
        await #expect(throws: CalendarSyncError.conflict) {
            try await gone.updateEvent(event, to: draft, scope: .allOccurrences, in: reference, calendar: seoul)
        }
        try await gone.deleteEvent(event, scope: .allOccurrences, in: reference, calendar: seoul)

        let (refused, _) = try api { _ in (403, #"{"error":{"errors":[{"reason":"requiredAccessLevel"}]}}"#) }
        await #expect(throws: CalendarSyncError.readOnly) {
            try await refused.deleteEvent(event, scope: .allOccurrences, in: reference, calendar: seoul)
        }
    }

    /// Writes refresh an expired token once, as reads do.
    @Test func writesRefreshTheTokenOnce() async throws {
        var calls = 0
        let (api, http) = try api { request in
            if request.url!.host() == "oauth2.googleapis.com" { return (200, #"{"access_token":"t2","expires_in":3600}"#) }
            calls += 1
            return calls == 1 ? (401, "") : (204, "")
        }
        let event = EventSnapshot(id: "s:e1", sourceID: "s", remoteID: "e1", title: "x", isAllDay: true)
        try await api.deleteEvent(event, scope: .allOccurrences, in: reference, calendar: seoul)
        #expect(http.requests.count == 3)
        #expect(http.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer t2")
    }

    /// Refusals that mean "read-only" or "conflict" are about writes; a sync keeps reading them as before.
    @Test func readsKeepTheirErrors() async throws {
        let (api, _) = try api { _ in (403, #"{"error":{"errors":[{"reason":"requiredAccessLevel"}]}}"#) }
        await #expect(throws: CalendarSyncError.http(status: 403, reason: "requiredAccessLevel")) { _ = try await api.calendarList() }
    }
}

struct CalDAVWriteTests {
    let reference = RemoteCalendar.Reference(sourceID: "s", remoteID: FakeDAVStore.collection, timeZone: nil)

    func setup() -> (CalDAVProvider, FakeDAVStore) {
        let store = FakeDAVStore()
        store.files[FakeDAVStore.path] = (FakeDAVStore.series, 1)
        let client = CalDAVClient(http: store.http, credentials: CalDAVCredentials(username: "me@icloud.com", password: "pw"))
        return (CalDAVProvider(client: client, home: URL(string: "https://p01-caldav.icloud.com/123/calendars/")!), store)
    }

    func events(_ store: FakeDAVStore, _ path: String = FakeDAVStore.path) -> [EventSnapshot] {
        ICalendar.events(in: store.files[path]?.ics ?? "", sourceID: "s", href: path, calendar: seoul)
    }

    func master(_ store: FakeDAVStore) -> EventSnapshot { events(store).first { $0.recurringEventID == nil }! }

    func headers(_ request: URLRequest) -> String {
        request.httpMethod! + " " + (request.value(forHTTPHeaderField: "If-Match") ?? "") + (request.value(forHTTPHeaderField: "If-None-Match") ?? "")
    }

    @Test func everyOccurrenceKeepsWhatTheAppDoesNotKnow() async throws {
        let (provider, store) = setup()
        let series = master(store)
        var draft = EventDraft(editing: series, occurrenceStart: kst(11, 5, 9), calendar: seoul)
        draft.start = kst(11, 5, 10)
        draft.end = kst(11, 5, 11)
        draft.title = "주간 회의 (10시)"
        try await provider.updateEvent(series, to: draft, scope: .allOccurrences, in: reference, calendar: seoul)

        #expect(store.http.requests.map(headers) == ["GET ", "PUT \"1\""])
        let ics = store.files[FakeDAVStore.path]!.ics
        #expect(ics.contains("ATTENDEE;CN=Kim:mailto:kim@example.com"))
        #expect(ics.contains("X-APPLE-TRAVEL-ADVISORY-BEHAVIOR:AUTOMATIC"))
        #expect(ics.contains("BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT10M\r\nEND:VALARM"))
        #expect(ics.contains("SEQUENCE:3"))
        #expect(ics.contains("RRULE:FREQ=WEEKLY;COUNT=10"))
        // The skipped and changed occurrences move to 10:00 with the series.
        #expect(ics.contains("EXDATE;TZID=Asia/Seoul:20261015T100000"))
        #expect(ics.contains("RECURRENCE-ID;TZID=Asia/Seoul:20261008T100000"))
        #expect(ics.contains("RECURRENCE-ID;TZID=Asia/Seoul:20261112T100000"))

        let read = master(store)
        #expect(read.title == "주간 회의 (10시)")
        #expect(read.start == kst(10, 1, 10))
        #expect(read.end == kst(10, 1, 11))
        // The changed occurrence keeps its own time.
        #expect(events(store).first { $0.originalStart == kst(10, 8, 10) }?.start == kst(10, 8, 11))
    }

    @Test func oneOccurrenceGetsAChangedCopy() async throws {
        let (provider, store) = setup()
        let series = master(store)
        var draft = EventDraft(editing: series, occurrenceStart: kst(10, 22, 9), calendar: seoul)
        draft.title = "특별 회의"
        draft.start = kst(10, 22, 14)
        draft.end = kst(10, 22, 15)
        try await provider.updateEvent(series, to: draft, scope: .thisOccurrence(originalStart: kst(10, 22, 9)), in: reference, calendar: seoul)

        let ics = store.files[FakeDAVStore.path]!.ics
        #expect(ics.contains("RECURRENCE-ID;TZID=Asia/Seoul:20261022T090000"))
        var copy = events(store).first { $0.originalStart == kst(10, 22, 9) }!
        #expect(copy.title == "특별 회의")
        #expect(copy.start == kst(10, 22, 14))
        #expect(copy.recurrence == nil)
        #expect(ics.components(separatedBy: "BEGIN:VALARM").count == 3, "the copy keeps the series' alarm")

        // Changing it again changes the copy, not adds another.
        draft = EventDraft(editing: copy, occurrenceStart: copy.start!, calendar: seoul)
        draft.title = "특별 회의 (변경)"
        try await provider.updateEvent(copy, to: draft, scope: .thisOccurrence(originalStart: copy.start!), in: reference, calendar: seoul)
        #expect(events(store).count == 4)
        copy = events(store).first { $0.originalStart == kst(10, 22, 9) }!
        #expect(copy.title == "특별 회의 (변경)")
    }

    @Test func oneOccurrenceIsLeftOut() async throws {
        let (provider, store) = setup()
        try await provider.deleteEvent(master(store), scope: .thisOccurrence(originalStart: kst(10, 29, 9)), in: reference, calendar: seoul)
        let changed = events(store).first { $0.originalStart == kst(11, 12, 9) }!
        try await provider.deleteEvent(changed, scope: .thisOccurrence(originalStart: changed.start!), in: reference, calendar: seoul)

        let read = master(store)
        #expect(Set(read.exceptionDates) == [kst(10, 15, 9), kst(10, 29, 9), kst(11, 12, 9)])
        #expect(events(store).count == 2)
    }

    @Test func thisAndFollowingSplitsTheResource() async throws {
        let (provider, store) = setup()
        let series = master(store)
        var draft = EventDraft(editing: series, occurrenceStart: kst(11, 5, 9), calendar: seoul)
        draft.start = kst(11, 5, 10)
        draft.end = kst(11, 5, 11)
        try await provider.updateEvent(series, to: draft, scope: .thisAndFollowing(originalStart: kst(11, 5, 9)), in: reference, calendar: seoul)

        #expect(store.http.requests.map(headers) == ["GET ", "PUT *", "PUT \"1\""])
        let newPath = store.files.keys.first { $0 != FakeDAVStore.path }!
        let old = store.files[FakeDAVStore.path]!.ics
        #expect(old.contains("RRULE:FREQ=WEEKLY;UNTIL=20261104T235959Z"))
        #expect(old.contains("RECURRENCE-ID;TZID=Asia/Seoul:20261008T090000"))
        #expect(!old.contains("20261112"))
        #expect(old.contains("EXDATE;TZID=Asia/Seoul:20261015T090000"))

        let new = store.files[newPath]!.ics
        #expect(new.contains("RRULE:FREQ=WEEKLY;COUNT=5"))
        #expect(new.contains("DTSTART;TZID=Asia/Seoul:20261105T100000"))
        #expect(new.contains("RECURRENCE-ID;TZID=Asia/Seoul:20261112T100000"))
        #expect(new.contains("ATTENDEE;CN=Kim"))
        #expect(new.contains("BEGIN:VTIMEZONE\r\nTZID:Asia/Seoul"))
        #expect(!new.contains("20261015") && !new.contains("20261008"))
        let newEvents = events(store, newPath)
        #expect(Set(newEvents.map(\.remoteID)).count == 1)
        #expect(newEvents[0].remoteID != "S1")
        #expect(newPath == "/123/calendars/work/\(newEvents[0].remoteID).ics")

        // Sent again after the second write's answer was lost: the new part is found, not made twice.
        try await provider.updateEvent(series, to: draft, scope: .thisAndFollowing(originalStart: kst(11, 5, 9)), in: reference, calendar: seoul)
        #expect(store.files.count == 2)
    }

    @Test func serversWithoutETagsStillTakeChanges() async throws {
        let (provider, store) = setup()
        store.sendsETags = false
        let draft = EventDraft(editing: series(), occurrenceStart: kst(10, 1, 9), calendar: seoul)
        try await provider.updateEvent(series(), to: draft, scope: .allOccurrences, in: reference, calendar: seoul)
        #expect(store.http.requests.map(headers) == ["GET ", "PUT "])
    }

    @Test func deletingFromTheFirstOccurrenceDeletesTheResource() async throws {
        let (provider, store) = setup()
        try await provider.deleteEvent(master(store), scope: .thisAndFollowing(originalStart: kst(10, 1, 9)), in: reference, calendar: seoul)
        #expect(store.http.requests.map(headers) == ["GET ", "DELETE \"1\""])
        #expect(store.files.isEmpty)
        // Gone already: nothing left to do.
        try await provider.deleteEvent(series(), scope: .allOccurrences, in: reference, calendar: seoul)
    }

    func series() -> EventSnapshot {
        ICalendar.events(in: FakeDAVStore.series, sourceID: "s", href: FakeDAVStore.path, calendar: seoul).first { $0.recurringEventID == nil }!
    }

    @Test func aChangeMadeElsewhereIsAConflict() async throws {
        let (provider, store) = setup()
        store.changedElsewhere = true
        let draft = EventDraft(editing: series(), occurrenceStart: kst(10, 1, 9), calendar: seoul)
        await #expect(throws: CalendarSyncError.conflict) {
            try await provider.updateEvent(series(), to: draft, scope: .allOccurrences, in: reference, calendar: seoul)
        }
        store.files = [:]
        await #expect(throws: CalendarSyncError.conflict) {
            try await provider.updateEvent(series(), to: draft, scope: .allOccurrences, in: reference, calendar: seoul)
        }
    }

    @Test func createWritesANewResource() async throws {
        let (provider, store) = setup()
        let draft = EventDraft(title: "치과", isAllDay: false, start: kst(11, 20, 15), end: kst(11, 20, 16), location: "강남, 2층", notes: "예약 확인", repeatRule: .monthly)
        try await provider.createEvent(draft, id: "new1", in: reference, calendar: seoul)
        #expect(store.http.requests.map(headers) == ["PUT *"])
        let path = "/123/calendars/work/new1.ics"
        let read = events(store, path)
        #expect(read.count == 1)
        #expect(read[0].title == "치과")
        #expect(read[0].location == "강남, 2층")
        #expect(read[0].notes == "예약 확인")
        #expect(read[0].start == kst(11, 20, 15))
        #expect(read[0].recurrence?.frequency == .monthly)
        #expect(store.files[path]!.ics.contains("BEGIN:VTIMEZONE"))

        // Sent again after an answer that never came: already there, so done.
        try await provider.createEvent(draft, id: "new1", in: reference, calendar: seoul)
        #expect(store.files.count == 2)
    }
}
