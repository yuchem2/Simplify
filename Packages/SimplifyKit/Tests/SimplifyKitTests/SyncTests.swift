import Foundation
import SwiftData
import Testing
@testable import SimplifyKit

/// A tiny stand-in for Google Calendar: calendars and per-calendar responses by sync token.
final class FakeGoogle: @unchecked Sendable {
    let lock = NSLock()
    var calendars: String
    /// Calendar id → (sync token or "" for a full fetch) → response.
    var events: [String: [String: (Int, String)]] = [:]
    var instances: [String: String] = [:]

    init(calendars: String) { self.calendars = calendars }

    lazy var http: FakeHTTP = FakeHTTP { [unowned self] request in
        self.lock.withLock {
            let url = request.url!
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
            let path = url.path(percentEncoded: false)
            if path.hasSuffix("/users/me/calendarList") { return (200, self.calendars) }
            if path.contains("/instances") { return (200, self.instances[path] ?? #"{"items":[]}"#) }
            let id = path.components(separatedBy: "/calendars/")[1].components(separatedBy: "/events")[0]
            let token = query.first { $0.name == "syncToken" }?.value ?? ""
            return self.events[id]?[token] ?? (404, "{}")
        }
    }
}

@MainActor
struct SyncTests {
    let cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    let account = "google:1"

    func setup(_ google: FakeGoogle) throws -> (ModelContainer, CalendarSyncEngine, GoogleCalendarAPI) {
        let container = try SimplifyStore.makeCacheContainer(inMemory: true)
        let store = MemoryTokenStore()
        try store.save(GoogleTokens(accessToken: "t", refreshToken: "r", expiresAt: .distantFuture), for: account)
        let session = GoogleSession(accountID: account, oauth: GoogleOAuth(clientID: GoogleTests.clientID, http: google.http), store: store)
        return (container, CalendarSyncEngine(modelContainer: container), GoogleCalendarAPI(http: google.http, session: session))
    }

    var october: DateInterval {
        DateInterval(start: cal.date(from: DateComponents(year: 2026, month: 9, day: 28))!,
                     end: cal.date(from: DateComponents(year: 2026, month: 11, day: 2))!)
    }

    static let twoCalendars = ##"""
    {"items":[{"id":"me@example.com","summary":"me@example.com","summaryOverride":"업무","accessRole":"owner","backgroundColor":"#4986e7","primary":true},
              {"id":"ko.south_korea#holiday@group.v.calendar.google.com","summary":"대한민국의 휴일","accessRole":"reader","backgroundColor":"#f83a22"}]}
    """##

    @Test func fullThenIncremental() async throws {
        let google = FakeGoogle(calendars: Self.twoCalendars)
        google.events["me@example.com"] = [
            "": (200, #"""
            {"items":[{"id":"a","summary":"디자인 리뷰","start":{"dateTime":"2026-10-26T14:00:00+09:00"},"end":{"dateTime":"2026-10-26T15:00:00+09:00"}},
                      {"id":"b","summary":"치과","start":{"dateTime":"2026-10-27T18:00:00+09:00"},"end":{"dateTime":"2026-10-27T19:00:00+09:00"}}],
             "nextSyncToken":"s1","timeZone":"Asia/Seoul"}
            """#),
            "s1": (200, #"""
            {"items":[{"id":"a","summary":"디자인 리뷰(변경)","start":{"dateTime":"2026-10-26T16:00:00+09:00"},"end":{"dateTime":"2026-10-26T17:00:00+09:00"}},
                      {"id":"b","status":"cancelled"}],"nextSyncToken":"s2"}
            """#),
        ]
        google.events["ko.south_korea#holiday@group.v.calendar.google.com"] = [
            "": (200, #"{"items":[{"id":"h","summary":"한글날","start":{"date":"2026-10-09"},"end":{"date":"2026-10-10"}}],"nextSyncToken":"h1"}"#),
            "h1": (200, #"{"items":[],"nextSyncToken":"h1"}"#),
        ]
        let (container, engine, api) = try setup(google)
        try await engine.upsertAccount(id: account, provider: .google, email: "me@example.com")

        try await engine.sync(account, provider: api, calendar: cal)
        var titles = CalendarCache.occurrences(in: october, context: container.mainContext, calendar: cal).map(\.title)
        #expect(titles == ["한글날", "디자인 리뷰", "치과"])

        let sources = try container.mainContext.fetch(FetchDescriptor<CalendarSource>(sortBy: [SortDescriptor(\.order)]))
        #expect(sources.map(\.name) == ["업무", "대한민국의 휴일"])
        #expect(sources.map(\.palette) == [.blue, .red])
        #expect(sources[1].isHoliday && sources[1].isReadOnly)

        try await engine.sync(account, provider: api, calendar: cal)
        titles = CalendarCache.occurrences(in: october, context: container.mainContext, calendar: cal).map(\.title)
        #expect(titles == ["한글날", "디자인 리뷰(변경)"])
        #expect(sources[0].syncToken == "s2")
    }

    @Test func expiredSyncTokenStartsOver() async throws {
        let google = FakeGoogle(calendars: #"{"items":[{"id":"c","summary":"개인","accessRole":"owner"}]}"#)
        google.events["c"] = [
            "": (200, #"{"items":[{"id":"x","summary":"새로 받은 일정","start":{"date":"2026-10-15"},"end":{"date":"2026-10-16"}}],"nextSyncToken":"fresh"}"#),
            "stale": (410, "{}"),
        ]
        let (container, engine, api) = try setup(google)
        try await engine.upsertAccount(id: account, provider: .google, email: "me@example.com")
        try await engine.sync(account, provider: api, calendar: cal)
        let source = try container.mainContext.fetch(FetchDescriptor<CalendarSource>()).first!
        source.syncToken = "stale"
        container.mainContext.insert(EventRecord(EventSnapshot(id: source.id + ":old", sourceID: source.id, remoteID: "old", title: "오래된 일정", isAllDay: false)))
        try container.mainContext.save()

        try await engine.sync(account, provider: api, calendar: cal)
        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<EventRecord>()).map(\.title) == ["새로 받은 일정"])
        #expect(try fresh.fetch(FetchDescriptor<CalendarSource>()).first?.syncToken == "fresh")
    }

    @Test func hiddenCalendarsAreLeftOut() async throws {
        let google = FakeGoogle(calendars: Self.twoCalendars)
        google.events["me@example.com"] = ["": (200, #"{"items":[{"id":"a","summary":"리뷰","start":{"date":"2026-10-20"},"end":{"date":"2026-10-21"}}],"nextSyncToken":"s"}"#)]
        google.events["ko.south_korea#holiday@group.v.calendar.google.com"] = ["": (200, #"{"items":[{"id":"h","summary":"한글날","start":{"date":"2026-10-09"},"end":{"date":"2026-10-10"}}],"nextSyncToken":"h"}"#)]
        let (container, engine, api) = try setup(google)
        try await engine.upsertAccount(id: account, provider: .google, email: "me@example.com")
        try await engine.sync(account, provider: api, calendar: cal)
        try container.mainContext.fetch(FetchDescriptor<CalendarSource>()).first { $0.isHoliday }!.isVisible = false
        #expect(CalendarCache.occurrences(in: october, context: container.mainContext, calendar: cal).map(\.title) == ["리뷰"])
    }

    @Test func removedAccountLeavesNothing() async throws {
        let google = FakeGoogle(calendars: #"{"items":[{"id":"c","summary":"개인","accessRole":"owner"}]}"#)
        google.events["c"] = ["": (200, #"{"items":[{"id":"x","summary":"일정","start":{"date":"2026-10-15"},"end":{"date":"2026-10-16"}}],"nextSyncToken":"t"}"#)]
        let (container, engine, api) = try setup(google)
        try await engine.upsertAccount(id: account, provider: .google, email: "me@example.com")
        try await engine.sync(account, provider: api, calendar: cal)
        try await engine.removeAccount(id: account)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<EventRecord>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<CalendarSource>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<CalendarAccount>()) == 0)
    }

    @Test func revokedTokenMarksTheAccount() async throws {
        let google = FakeGoogle(calendars: "{}")
        let container = try SimplifyStore.makeCacheContainer(inMemory: true)
        let store = MemoryTokenStore()
        try store.save(GoogleTokens(accessToken: "t", refreshToken: "r", expiresAt: .distantPast), for: account)
        let refuse = FakeHTTP { _ in (400, #"{"error":"invalid_grant"}"#) }
        let api = GoogleCalendarAPI(http: google.http, session: GoogleSession(accountID: account, oauth: GoogleOAuth(clientID: GoogleTests.clientID, http: refuse), store: store))
        let engine = CalendarSyncEngine(modelContainer: container)
        try await engine.upsertAccount(id: account, provider: .google, email: "me@example.com")
        await #expect(throws: CalendarSyncError.needsReauth) {
            try await engine.sync(account, provider: api, calendar: cal)
        }
        #expect(try container.mainContext.fetch(FetchDescriptor<CalendarAccount>()).first?.status == .needsReauth)
    }

    @Test func paletteMatching() {
        // Google's event colours by name.
        let expected: [(String, Palette)] = [
            ("#7986cb", .blue),   // Lavender
            ("#33b679", .green),  // Sage
            ("#8e24aa", .purple), // Grape
            ("#e67c73", .red),    // Flamingo
            ("#f6bf26", .yellow), // Banana
            ("#f4511e", .orange), // Tangerine
            ("#039be5", .blue),   // Peacock
            ("#616161", .grey),   // Graphite
            ("#3f51b5", .blue),   // Blueberry
            ("#0b8043", .green),  // Basil
            ("#d50000", .red),    // Tomato
            ("#4986e7", .blue), ("#16a765", .green), ("#f83a22", .red), ("#cabdbf", .grey),
        ]
        for (hex, palette) in expected {
            #expect(Palette.nearest(toHex: hex) == palette, "\(hex)")
        }
        #expect(Palette.nearest(toHex: nil) == .blue)
    }

    /// One calendar failing does not stop the others, and the account is not marked synced.
    @Test func oneFailingCalendarDoesNotStopTheRest() async throws {
        let google = FakeGoogle(calendars: #"{"items":[{"id":"broken","summary":"깨진 캘린더","accessRole":"reader"},{"id":"fine","summary":"개인","accessRole":"owner"}]}"#)
        google.events["broken"] = ["": (404, #"{"error":{"code":404,"errors":[{"reason":"notFound"}]}}"#)]
        google.events["fine"] = ["": (200, #"{"items":[{"id":"x","summary":"살아남은 일정","start":{"date":"2026-10-15"},"end":{"date":"2026-10-16"}}],"nextSyncToken":"t"}"#)]
        let (container, engine, api) = try setup(google)
        try await engine.upsertAccount(id: account, provider: .google, email: "me@example.com")
        await #expect(throws: CalendarSyncError.http(status: 404, reason: "notFound")) {
            try await engine.sync(account, provider: api, calendar: cal)
        }
        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<EventRecord>()).map(\.title) == ["살아남은 일정"])
        #expect(try fresh.fetch(FetchDescriptor<CalendarAccount>()).first?.lastSyncedAt == nil)
    }

    /// When an unsupported rule becomes expandable, the calendar is fetched again in full, so the
    /// one-by-one occurrences go and only Google's real exceptions come back.
    @Test func expandedInstancesAreDroppedWhenTheSeriesBecomesSupported() async throws {
        let google = FakeGoogle(calendars: #"{"items":[{"id":"c","summary":"개인","accessRole":"owner"}]}"#)
        google.events["c"] = [
            "": (200, #"""
            {"items":[{"id":"odd","summary":"특이 반복","start":{"dateTime":"2026-10-01T09:00:00+09:00"},"end":{"dateTime":"2026-10-01T10:00:00+09:00"},
                       "recurrence":["RRULE:FREQ=YEARLY;BYWEEKNO=40"]}],"nextSyncToken":"t1"}
            """#),
            "t1": (200, #"""
            {"items":[{"id":"odd","summary":"특이 반복","start":{"dateTime":"2026-10-01T09:00:00+09:00"},"end":{"dateTime":"2026-10-01T10:00:00+09:00"},
                       "recurrence":["RRULE:FREQ=WEEKLY"]}],"nextSyncToken":"t2"}
            """#),
        ]
        google.instances["/calendar/v3/calendars/c/events/odd/instances"] = #"""
        {"items":[{"id":"odd_1","summary":"특이 반복","recurringEventId":"odd","originalStartTime":{"dateTime":"2026-10-01T09:00:00+09:00"},
                   "start":{"dateTime":"2026-10-01T09:00:00+09:00"},"end":{"dateTime":"2026-10-01T10:00:00+09:00"}}]}
        """#
        let (container, engine, api) = try setup(google)
        try await engine.upsertAccount(id: account, provider: .google, email: "me@example.com")
        try await engine.sync(account, provider: api, calendar: cal)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<EventRecord>(predicate: #Predicate { $0.isExpandedInstance })) == 1)

        // The series is edited into a weekly rule: this round notices, the next refetches everything.
        let edited = google.events["c"]?["t1"]
        google.events["c"]?[""] = edited
        try await engine.sync(account, provider: api, calendar: cal)
        #expect(try ModelContext(container).fetch(FetchDescriptor<CalendarSource>()).first?.syncToken == nil)
        try await engine.sync(account, provider: api, calendar: cal)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<EventRecord>(predicate: #Predicate { $0.isExpandedInstance })) == 0)
        // The full refetch settles: it does not keep asking for another one.
        #expect(try ModelContext(container).fetch(FetchDescriptor<CalendarSource>()).first?.syncToken != nil)
        let weekly = CalendarCache.occurrences(in: october, context: ModelContext(container), calendar: cal)
        #expect(weekly.count == 5) // Oct 1, 8, 15, 22, 29
    }
}
