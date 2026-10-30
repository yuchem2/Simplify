import Foundation
import Testing
@testable import SimplifyKit

/// Answers requests from a script and records them.
final class FakeHTTP: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (URLRequest) throws -> (Int, String, [String: String])
    private(set) var requests: [URLRequest] = []

    init(_ handler: @escaping (URLRequest) throws -> (Int, String)) {
        self.handler = { request in
            let (status, body) = try handler(request)
            return (status, body, [:])
        }
    }

    /// Answers with response headers too (an ETag).
    init(headers handler: @escaping (URLRequest) throws -> (Int, String, [String: String])) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body, headers) = try lock.withLock {
            requests.append(request)
            return try handler(request)
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: GoogleTokens] = [:]
    func load(_ id: String) -> GoogleTokens? { lock.withLock { items[id] } }
    func save(_ tokens: GoogleTokens, for id: String) throws { lock.withLock { items[id] = tokens } }
    func delete(_ id: String) { lock.withLock { items[id] = nil } }
}

struct GoogleTests {
    let cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    static let clientID = "123-abc.apps.googleusercontent.com"

    @Test func redirectUsesTheReversedClientID() {
        let oauth = GoogleOAuth(clientID: Self.clientID, http: FakeHTTP { _ in (200, "{}") })
        #expect(oauth.callbackScheme == "com.googleusercontent.apps.123-abc")
        #expect(oauth.redirectURI == "com.googleusercontent.apps.123-abc:/oauthredirect")
        let url = oauth.authorizationURL(pkce: .init(), state: "s1")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.first { $0.name == "code_challenge_method" }?.value == "S256")
        #expect(oauth.code(fromCallback: URL(string: "com.googleusercontent.apps.123-abc:/oauthredirect?code=xyz&state=s1")!, state: "s1") == "xyz")
        #expect(oauth.code(fromCallback: URL(string: "com.googleusercontent.apps.123-abc:/oauthredirect?code=xyz&state=evil")!, state: "s1") == nil)
    }

    @Test func pkceChallengeIsTheVerifierHash() {
        let pkce = GoogleOAuth.PKCE()
        #expect(pkce.verifier.count == 43)
        #expect(pkce.challenge.count == 43)
        #expect(pkce.verifier != pkce.challenge)
    }

    @Test func identityComesFromTheIDToken() {
        let payload = Data(#"{"sub":"10987","email":"me@example.com"}"#.utf8).base64URL
        let tokens = GoogleTokens(accessToken: "a", refreshToken: "r", expiresAt: .now, idToken: "h.\(payload).s")
        #expect(tokens.identity?.id == "10987")
        #expect(tokens.identity?.email == "me@example.com")
    }

    @Test func revokedRefreshTokenAsksToSignInAgain() async {
        let oauth = GoogleOAuth(clientID: Self.clientID, http: FakeHTTP { _ in (400, #"{"error":"invalid_grant"}"#) })
        await #expect(throws: CalendarSyncError.needsReauth) {
            _ = try await oauth.refresh(GoogleTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantPast))
        }
    }

    @Test func signInWithoutCalendarPermissionIsRefused() async {
        let http = FakeHTTP { _ in (200, #"{"access_token":"a","refresh_token":"r","expires_in":3600,"scope":"openid https://www.googleapis.com/auth/userinfo.email"}"#) }
        let oauth = GoogleOAuth(clientID: Self.clientID, http: http)
        await #expect(throws: CalendarSyncError.missingCalendarPermission) {
            _ = try await oauth.exchange(code: "c", pkce: .init())
        }
    }

    /// A 401 refreshes the token once and retries with the new one.
    @Test func expiredAccessTokenIsRefreshed() async throws {
        let store = MemoryTokenStore()
        try store.save(GoogleTokens(accessToken: "old", refreshToken: "r", expiresAt: .distantFuture), for: "acct")
        let http = FakeHTTP { request in
            if request.url!.host() == "oauth2.googleapis.com" { return (200, #"{"access_token":"new","expires_in":3600}"#) }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer new"
                ? (200, ##"{"items":[{"id":"primary@example.com","summary":"내 캘린더","accessRole":"owner","backgroundColor":"#4986e7"}]}"##)
                : (401, "{}")
        }
        let api = GoogleCalendarAPI(http: http, session: GoogleSession(accountID: "acct", oauth: GoogleOAuth(clientID: Self.clientID, http: http), store: store))
        let list = try await api.calendarList()
        #expect(list.map(\.displayName) == ["내 캘린더"])
        #expect(store.load("acct")?.accessToken == "new")
        #expect(store.load("acct")?.refreshToken == "r")
    }

    @Test func eventPagesAndSyncToken() async throws {
        let store = MemoryTokenStore()
        try store.save(GoogleTokens(accessToken: "t", refreshToken: "r", expiresAt: .distantFuture), for: "acct")
        let http = FakeHTTP { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
            #expect(request.url!.path().contains("ko.south_korea%23holiday%40group.v.calendar.google.com"))
            if query.contains(where: { $0.name == "pageToken" }) {
                return (200, #"{"items":[{"id":"b","summary":"B"}],"nextSyncToken":"sync-2"}"#)
            }
            return (200, #"{"items":[{"id":"a","summary":"A"}],"nextPageToken":"p2","timeZone":"Asia/Seoul"}"#)
        }
        let api = GoogleCalendarAPI(http: http, session: GoogleSession(accountID: "acct", oauth: GoogleOAuth(clientID: Self.clientID, http: http), store: store))
        let result = try await api.events(calendarID: "ko.south_korea#holiday@group.v.calendar.google.com", syncToken: nil)
        #expect(result.events.map(\.id) == ["a", "b"])
        #expect(result.nextSyncToken == "sync-2")
        #expect(result.timeZone == "Asia/Seoul")
    }

    @Test func goneSyncTokenIsReported() async throws {
        let store = MemoryTokenStore()
        try store.save(GoogleTokens(accessToken: "t", refreshToken: "r", expiresAt: .distantFuture), for: "acct")
        let http = FakeHTTP { _ in (410, "{}") }
        let api = GoogleCalendarAPI(http: http, session: GoogleSession(accountID: "acct", oauth: GoogleOAuth(clientID: Self.clientID, http: http), store: store))
        await #expect(throws: CalendarSyncError.syncTokenExpired) {
            _ = try await api.events(calendarID: "c", syncToken: "old")
        }
    }

    /// Google's 403s mean different things: a missing scope, a disabled API, or a rate limit.
    @Test func forbiddenReasonsAreTold() async throws {
        let store = MemoryTokenStore()
        try store.save(GoogleTokens(accessToken: "t", refreshToken: "r", expiresAt: .distantFuture), for: "acct")
        for (body, expected) in [
            (#"{"error":{"code":403,"errors":[{"reason":"insufficientPermissions"}],"status":"PERMISSION_DENIED","details":[{"reason":"ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}}"#, CalendarSyncError.missingCalendarPermission),
            (#"{"error":{"code":403,"errors":[{"reason":"accessNotConfigured"}],"status":"PERMISSION_DENIED","details":[{"reason":"SERVICE_DISABLED"}]}}"#, .apiDisabled),
            (#"{"error":{"code":403,"errors":[{"reason":"forbidden"}]}}"#, .http(status: 403, reason: "forbidden")),
        ] {
            let http = FakeHTTP { _ in (403, body) }
            let api = GoogleCalendarAPI(http: http, session: GoogleSession(accountID: "acct", oauth: GoogleOAuth(clientID: Self.clientID, http: http), store: store))
            await #expect(throws: expected) { _ = try await api.calendarList() }
            #expect(http.requests.count == 1, "a 403 that is not a rate limit is not retried")
        }
    }

    // MARK: Mapping

    func decode(_ json: String) throws -> GoogleEvent {
        try JSONDecoder().decode(GoogleEvent.self, from: Data(json.utf8))
    }

    @Test func timedSeriesWithExceptions() throws {
        let event = try decode(#"""
        {"id":"standup","summary":"주간 스탠드업","start":{"dateTime":"2026-10-05T09:30:00+09:00","timeZone":"Asia/Seoul"},
         "end":{"dateTime":"2026-10-05T10:00:00+09:00","timeZone":"Asia/Seoul"},
         "recurrence":["EXDATE;TZID=Asia/Seoul:20261012T093000","RRULE:FREQ=WEEKLY;BYDAY=MO"]}
        """#).snapshot(sourceID: "g:me:primary", calendar: cal, defaultZone: nil)
        #expect(event.id == "g:me:primary:standup")
        #expect(event.recurrence?.frequency == .weekly)
        #expect(event.exceptionDates == [cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9, minute: 30))!])
        #expect(event.end!.timeIntervalSince(event.start!) == 1800)
    }

    @Test func allDayAndChangedOccurrence() throws {
        let allDay = try decode(#"{"id":"w","summary":"제주 워크숍","start":{"date":"2026-10-29"},"end":{"date":"2026-10-31"}}"#)
            .snapshot(sourceID: "s", calendar: cal, defaultZone: "Asia/Seoul")
        #expect(allDay.isAllDay)
        #expect(allDay.startDay == "2026-10-29")
        #expect(allDay.endDay == "2026-10-31")

        let moved = try decode(#"""
        {"id":"standup_20261019T003000Z","status":"confirmed","recurringEventId":"standup",
         "originalStartTime":{"dateTime":"2026-10-19T09:30:00+09:00"},
         "start":{"dateTime":"2026-10-20T10:00:00+09:00"},"end":{"dateTime":"2026-10-20T10:30:00+09:00"}}
        """#).snapshot(sourceID: "s", calendar: cal, defaultZone: "Asia/Seoul")
        #expect(moved.recurringEventID == "standup")
        #expect(moved.originalStart == cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9, minute: 30)))
        #expect(moved.title == "(제목 없음)")
    }

    @Test func unsupportedRuleIsMarked() throws {
        let event = try decode(#"""
        {"id":"x","summary":"x","start":{"dateTime":"2026-10-01T09:00:00Z"},"end":{"dateTime":"2026-10-01T10:00:00Z"},
         "recurrence":["RRULE:FREQ=YEARLY;BYWEEKNO=20"]}
        """#).snapshot(sourceID: "s", calendar: cal, defaultZone: nil)
        #expect(event.recurrenceUnsupported)
        #expect(event.recurrence == nil)
    }

    @Test func cancelledEventsAreMarked() throws {
        let event = try decode(#"{"id":"gone","status":"cancelled"}"#).snapshot(sourceID: "s", calendar: cal, defaultZone: nil)
        #expect(event.isCancelled)
    }

    @Test func calendarEntryFlags() throws {
        let entries = try JSONDecoder().decode([GoogleCalendarEntry].self, from: Data(#"""
        [{"id":"ko.south_korea#holiday@group.v.calendar.google.com","summary":"대한민국의 휴일","accessRole":"reader"},
         {"id":"me@example.com","summary":"me@example.com","summaryOverride":"업무","accessRole":"owner"}]
        """#.utf8))
        #expect(entries[0].isHoliday && entries[0].isReadOnly)
        #expect(!entries[1].isHoliday && !entries[1].isReadOnly)
        #expect(entries[1].displayName == "업무")
    }

    /// After a 401 the token is refreshed once; a later 5xx retry reuses it.
    @Test func tokenIsRefreshedOnlyOnce() async throws {
        let store = MemoryTokenStore()
        try store.save(GoogleTokens(accessToken: "old", refreshToken: "r", expiresAt: .distantFuture), for: "acct")
        var calendarCalls = 0
        let http = FakeHTTP { request in
            if request.url!.host() == "oauth2.googleapis.com" { return (200, #"{"access_token":"new","expires_in":3600}"#) }
            calendarCalls += 1
            switch calendarCalls {
            case 1: return (401, "{}")
            case 2: return (503, "{}")
            default: return (200, #"{"items":[]}"#)
            }
        }
        let api = GoogleCalendarAPI(http: http, session: GoogleSession(accountID: "acct", oauth: GoogleOAuth(clientID: Self.clientID, http: http), store: store))
        _ = try await api.calendarList()
        #expect(http.requests.filter { $0.url!.host() == "oauth2.googleapis.com" }.count == 1)
    }
}
