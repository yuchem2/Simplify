import Foundation
import SwiftData
import Testing
@testable import SimplifyKit

/// A tiny stand-in for iCloud's CalDAV server: one home with a calendar and a reminders list.
final class FakeCalDAV: @unchecked Sendable {
    let lock = NSLock()
    /// href → ICS of the resources the "work" calendar holds now.
    var resources: [String: String] = [:]
    /// Sync token → (changed hrefs, deleted hrefs, next token). Unknown tokens are rejected.
    var deltas: [String: ([String], [String], String)] = [:]
    var currentToken = "t1"
    var password = "abcd-efgh-ijkl-mnop"
    /// What a multiget with `<c:expand>` answers: the written-out occurrences, or nil to refuse (403).
    var expanded: String?

    static let home = "https://p01-caldav.icloud.com/123/calendars/"
    static let work = "/123/calendars/work/"

    lazy var http: FakeHTTP = FakeHTTP { [unowned self] request in
        try self.lock.withLock { try self.answer(request) }
    }

    private func answer(_ request: URLRequest) throws -> (Int, String) {
        let login = Data("me@icloud.com:\(password)".utf8).base64EncodedString()
        guard request.value(forHTTPHeaderField: "Authorization") == "Basic \(login)" else { return (401, "") }
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        let url = request.url!.absoluteString
        if url == "https://caldav.icloud.com/" {
            return (207, Self.multistatus("<d:response><d:href>/</d:href>\(Self.ok("<d:current-user-principal><d:href>/123/principal/</d:href></d:current-user-principal>"))</d:response>"))
        }
        if url == "https://caldav.icloud.com/123/principal/" {
            return (207, Self.multistatus("<d:response><d:href>/123/principal/</d:href>\(Self.ok("<c:calendar-home-set><d:href>\(Self.home)</d:href></c:calendar-home-set>"))</d:response>"))
        }
        if url == Self.home {
            return (207, Self.multistatus("""
            <d:response><d:href>/123/calendars/</d:href>\(Self.ok("<d:resourcetype><d:collection/></d:resourcetype>"))</d:response>
            <d:response><d:href>/123/calendars/inbox/</d:href>\(Self.ok("<d:resourcetype><d:collection/><c:schedule-inbox/></d:resourcetype>"))</d:response>
            <d:response><d:href>/123/calendars/work/</d:href>\(Self.ok("""
                <d:resourcetype><d:collection/><c:calendar/></d:resourcetype><d:displayname>업무</d:displayname>
                <a:calendar-color>#FF2968FF</a:calendar-color><a:calendar-order>2</a:calendar-order>
                <c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>
                <d:current-user-privilege-set><d:privilege><d:read/></d:privilege><d:privilege><d:write/></d:privilege></d:current-user-privilege-set>
                """))</d:response>
            <d:response><d:href>/123/calendars/shared/</d:href>\(Self.ok("""
                <d:resourcetype><d:collection/><c:calendar/></d:resourcetype><d:displayname>가족</d:displayname>
                <a:calendar-color>#1BADF8</a:calendar-color><a:calendar-order>1</a:calendar-order>
                <d:current-user-privilege-set><d:privilege><d:read/></d:privilege></d:current-user-privilege-set>
                """))</d:response>
            <d:response><d:href>/123/calendars/tasks/</d:href>\(Self.ok("""
                <d:resourcetype><d:collection/><c:calendar/></d:resourcetype><d:displayname>미리알림</d:displayname>
                <c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>
                """))</d:response>
            """))
        }
        if url.hasSuffix("/shared/") {
            return (207, Self.multistatus("<d:sync-token>s1</d:sync-token>"))
        }
        guard url.hasSuffix(Self.work) else { return (404, "") }
        if body.contains("sync-collection") {
            let token = body.components(separatedBy: "<d:sync-token>")[1].components(separatedBy: "</d:sync-token>")[0]
            let delta: ([String], [String], String)
            if token.isEmpty {
                delta = (resources.keys.sorted(), [], currentToken)
            } else if let known = deltas[token] {
                delta = known
            } else {
                return (403, #"<d:error xmlns:d="DAV:"><d:valid-sync-token/></d:error>"#)
            }
            let rows = delta.0.map { "<d:response><d:href>\($0)</d:href>\(Self.ok("<d:getetag>\"1\"</d:getetag>"))</d:response>" }
                + delta.1.map { "<d:response><d:href>\($0)</d:href><d:status>HTTP/1.1 404 Not Found</d:status></d:response>" }
            return (207, Self.multistatus(rows.joined() + "<d:sync-token>\(delta.2)</d:sync-token>"))
        }
        if body.contains("calendar-multiget"), body.contains("<c:expand") {
            guard let expanded else { return (403, "") }
            let href = body.components(separatedBy: "<d:href>")[1].components(separatedBy: "</d:href>")[0]
            return (207, Self.multistatus("<d:response><d:href>\(href)</d:href>\(Self.ok("<c:calendar-data><![CDATA[\(expanded)]]></c:calendar-data>"))</d:response>"))
        }
        if body.contains("calendar-multiget") {
            let hrefs = body.components(separatedBy: "<d:href>").dropFirst().map { $0.components(separatedBy: "</d:href>")[0] }
            let rows = hrefs.compactMap { href in
                resources[href].map { "<d:response><d:href>\(href)</d:href>\(Self.ok("<c:calendar-data><![CDATA[\($0)]]></c:calendar-data>"))</d:response>" }
            }
            return (207, Self.multistatus(rows.joined()))
        }
        return (400, "")
    }

    static func ok(_ props: String) -> String {
        "<d:propstat><d:prop>\(props)</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>"
    }

    static func multistatus(_ inner: String) -> String {
        #"<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:a="http://apple.com/ns/ical/">"#
            + inner + "</d:multistatus>"
    }

    static func event(_ uid: String, _ title: String, day: String) -> String {
        "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:\(uid)\r\nDTSTART;VALUE=DATE:\(day)\r\nSUMMARY:\(title)\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    }
}

@MainActor
struct CalDAVTests {
    let cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    let account = "icloud:/123/principal/"
    let credentials = CalDAVCredentials(username: "me@icloud.com", password: "abcd-efgh-ijkl-mnop")

    var october: DateInterval {
        DateInterval(start: cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!,
                     end: cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!)
    }

    @Test func discoversHomeAndEventCalendars() async throws {
        let server = FakeCalDAV()
        let client = CalDAVClient(http: server.http, credentials: credentials)
        let (principal, home) = try await client.discover()
        #expect(principal == "/123/principal/")
        #expect(home.absoluteString == FakeCalDAV.home)

        let calendars = try await CalDAVProvider(client: client, home: home).calendars()
        // The inbox and the VTODO-only reminders list are left out; calendar-order sorts the rest.
        #expect(calendars.map(\.name) == ["가족", "업무"])
        #expect(calendars.map(\.isReadOnly) == [true, false])
        #expect(calendars.map { Palette.nearest(toHex: $0.colorHex) } == [.blue, .pink])
        #expect(calendars[1].id == "https://p01-caldav.icloud.com/123/calendars/work/")
    }

    @Test func wrongPasswordNeedsReauth() async throws {
        let server = FakeCalDAV()
        let client = CalDAVClient(http: server.http, credentials: CalDAVCredentials(username: "me@icloud.com", password: "wrong"))
        await #expect(throws: CalendarSyncError.needsReauth) { try await client.discover() }
    }

    @Test func fullThenIncrementalSync() async throws {
        let server = FakeCalDAV()
        server.resources = [
            "/123/calendars/work/a.ics": FakeCalDAV.event("a", "디자인 리뷰", day: "20261020"),
            "/123/calendars/work/b%20c.ics": FakeCalDAV.event("b", "치과", day: "20261022"),
        ]
        let container = try SimplifyStore.makeCacheContainer(inMemory: true)
        let engine = CalendarSyncEngine(modelContainer: container)
        let provider = CalDAVProvider(client: CalDAVClient(http: server.http, credentials: credentials), home: URL(string: FakeCalDAV.home)!)
        try await engine.upsertAccount(id: account, provider: .icloud, email: "me@icloud.com")

        try await engine.sync(account, provider: provider, calendar: cal)
        var titles = CalendarCache.occurrences(in: october, context: ModelContext(container), calendar: cal).map(\.title)
        #expect(titles == ["디자인 리뷰", "치과"])
        let hrefs = try ModelContext(container).fetch(FetchDescriptor<EventRecord>()).compactMap(\.resourceHref).sorted()
        #expect(hrefs == ["/123/calendars/work/a.ics", "/123/calendars/work/b c.ics"])

        // a.ics changed, b c.ics was deleted.
        server.resources["/123/calendars/work/a.ics"] = FakeCalDAV.event("a", "디자인 리뷰(변경)", day: "20261021")
        server.deltas["t1"] = (["/123/calendars/work/a.ics"], ["/123/calendars/work/b%20c.ics"], "t2")
        try await engine.sync(account, provider: provider, calendar: cal)
        titles = CalendarCache.occurrences(in: october, context: ModelContext(container), calendar: cal).map(\.title)
        #expect(titles == ["디자인 리뷰(변경)"])
        let work = try ModelContext(container).fetch(FetchDescriptor<CalendarSource>()).first { $0.name == "업무" }
        #expect(work?.syncToken == "t2")
    }

    @Test func rejectedTokenStartsOver() async throws {
        let server = FakeCalDAV()
        server.resources = ["/123/calendars/work/a.ics": FakeCalDAV.event("a", "새 일정", day: "20261020")]
        server.currentToken = "fresh"
        let container = try SimplifyStore.makeCacheContainer(inMemory: true)
        let engine = CalendarSyncEngine(modelContainer: container)
        let provider = CalDAVProvider(client: CalDAVClient(http: server.http, credentials: credentials), home: URL(string: FakeCalDAV.home)!)
        try await engine.upsertAccount(id: account, provider: .icloud, email: "me@icloud.com")
        try await engine.sync(account, provider: provider, calendar: cal)

        let context = ModelContext(container)
        let work = try context.fetch(FetchDescriptor<CalendarSource>()).first { $0.name == "업무" }!
        work.syncToken = "stale"
        context.insert(EventRecord(EventSnapshot(id: work.id + ":old", sourceID: work.id, remoteID: "old", title: "오래된 일정", isAllDay: false)))
        try context.save()

        try await engine.sync(account, provider: provider, calendar: cal)
        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<EventRecord>()).map(\.title) == ["새 일정"])
        #expect(try fresh.fetch(FetchDescriptor<CalendarSource>()).first { $0.name == "업무" }?.syncToken == "fresh")
    }

    @Test func revokedPasswordMarksTheAccount() async throws {
        let server = FakeCalDAV()
        let container = try SimplifyStore.makeCacheContainer(inMemory: true)
        let engine = CalendarSyncEngine(modelContainer: container)
        let provider = CalDAVProvider(client: CalDAVClient(http: server.http, credentials: credentials), home: URL(string: FakeCalDAV.home)!)
        try await engine.upsertAccount(id: account, provider: .icloud, email: "me@icloud.com")
        server.password = "revoked"
        await #expect(throws: CalendarSyncError.needsReauth) { try await engine.sync(account, provider: provider, calendar: cal) }
        #expect(try ModelContext(container).fetch(FetchDescriptor<CalendarAccount>()).first?.status == .needsReauth)
    }

    static let rdateSeries = """
    BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:club\r\nDTSTART:20261005T100000Z\r\nDTEND:20261005T110000Z\r\n\
    RRULE:FREQ=MONTHLY;COUNT=2\r\nRDATE:20261020T100000Z\r\nSUMMARY:독서 모임\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n
    """

    func syncSeries(expanded: String?) async throws -> [EventOccurrence] {
        let server = FakeCalDAV()
        server.resources = ["/123/calendars/work/club.ics": Self.rdateSeries]
        server.expanded = expanded
        let container = try SimplifyStore.makeCacheContainer(inMemory: true)
        let engine = CalendarSyncEngine(modelContainer: container)
        let provider = CalDAVProvider(client: CalDAVClient(http: server.http, credentials: credentials), home: URL(string: FakeCalDAV.home)!)
        try await engine.upsertAccount(id: account, provider: .icloud, email: "me@icloud.com")
        try await engine.sync(account, provider: provider, calendar: cal)
        return CalendarCache.occurrences(in: october, context: ModelContext(container), calendar: cal)
    }

    @Test func unsupportedSeriesIsExpandedByTheServer() async throws {
        let expanded = """
        BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:club\r\nRECURRENCE-ID:20261005T100000Z\r\nDTSTART:20261005T100000Z\r\n\
        DTEND:20261005T110000Z\r\nSUMMARY:독서 모임\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:club\r\nRECURRENCE-ID:20261020T100000Z\r\n\
        DTSTART:20261020T100000Z\r\nDTEND:20261020T110000Z\r\nSUMMARY:독서 모임\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n
        """
        let days = try await syncSeries(expanded: expanded).map { cal.component(.day, from: $0.start) }
        #expect(days == [5, 20])
    }

    @Test func refusedExpansionShowsTheFirstOccurrence() async throws {
        let days = try await syncSeries(expanded: nil).map { cal.component(.day, from: $0.start) }
        #expect(days == [5])
    }

    @Test func multistatusParsing() throws {
        let body = FakeCalDAV.multistatus("""
        <d:response><d:href>/x/</d:href><d:status>HTTP/1.1 507 Insufficient Storage</d:status></d:response>
        <d:response><d:href>/x/a.ics</d:href>
          <d:propstat><d:prop><d:getetag>"1"</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
          <d:propstat><d:prop><d:displayname/></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>
        </d:response>
        <d:sync-token>http://example.com/sync/9</d:sync-token>
        """)
        let (responses, token) = try DAVResponse.multistatus(Data(body.utf8))
        #expect(responses.map(\.href) == ["/x/", "/x/a.ics"])
        #expect(responses[0].status == 507)
        #expect(responses[1].properties.map(\.name) == ["getetag"])
        #expect(token == "http://example.com/sync/9")
        #expect(CalDAVClient.isSameResource("/x/", URL(string: "https://h/x/")!))
        #expect(CalDAVClient.normalize("https://h/x/a%20b.ics") == "/x/a b.ics")
    }
}
