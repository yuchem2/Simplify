import Foundation

/// The parts of Google Calendar API v3 the app reads and writes.
public struct GoogleCalendarAPI: Sendable {
    let http: HTTPTransport
    let session: GoogleSession

    public init(http: HTTPTransport = URLSessionTransport(), session: GoogleSession) {
        self.http = http
        self.session = session
    }

    private static let base = URL(string: "https://www.googleapis.com/calendar/v3/")!

    public func calendarList() async throws -> [GoogleCalendarEntry] {
        var entries: [GoogleCalendarEntry] = []
        var pageToken: String?
        repeat {
            var query = [URLQueryItem(name: "maxResults", value: "250")]
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: Page<GoogleCalendarEntry> = try await get("users/me/calendarList", query)
            entries += page.items ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil
        return entries
    }

    /// Everything that changed since `syncToken`, or every event when it is nil. Series come back
    /// as one master with its RRULE; changed or cancelled occurrences come back on their own.
    public func events(calendarID: String, syncToken: String?) async throws -> (events: [GoogleEvent], nextSyncToken: String?, timeZone: String?) {
        var events: [GoogleEvent] = []
        var pageToken: String?
        var nextSync: String?
        var zone: String?
        repeat {
            var query = [URLQueryItem(name: "maxResults", value: "2500"), URLQueryItem(name: "showDeleted", value: "true")]
            if let syncToken { query.append(URLQueryItem(name: "syncToken", value: syncToken)) }
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: EventPage = try await get("calendars/\(Self.escape(calendarID))/events", query)
            events += page.items ?? []
            pageToken = page.nextPageToken
            nextSync = page.nextSyncToken ?? nextSync
            zone = page.timeZone ?? zone
        } while pageToken != nil
        return (events, nextSync, zone)
    }

    /// The occurrences of one series in a window, for rules the local engine cannot expand.
    public func instances(calendarID: String, eventID: String, in range: DateInterval) async throws -> [GoogleEvent] {
        let format = ISO8601DateFormatter()
        var events: [GoogleEvent] = []
        var pageToken: String?
        repeat {
            var query = [URLQueryItem(name: "timeMin", value: format.string(from: range.start)),
                         URLQueryItem(name: "timeMax", value: format.string(from: range.end)),
                         URLQueryItem(name: "maxResults", value: "2500")]
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: EventPage = try await get("calendars/\(Self.escape(calendarID))/events/\(Self.escape(eventID))/instances", query)
            events += page.items ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil
        return events
    }

    // MARK: - Writes

    /// One event as Google holds it now, read before changing it.
    public func event(calendarID: String, eventID: String) async throws -> GoogleEvent {
        let (data, status) = try await send("GET", "calendars/\(Self.escape(calendarID))/events/\(Self.escape(eventID))")
        switch status {
        case 200: return try decode(data)
        case 404, 410: throw CalendarSyncError.conflict
        default: throw Self.writeFailure(status, data)
        }
    }

    /// `events.insert`. The body carries the id the app chose, so a retry after a lost answer
    /// finds the event already there (409) instead of making a second one.
    public func insertEvent(calendarID: String, _ body: [String: Any]) async throws {
        let (data, status) = try await send("POST", "calendars/\(Self.escape(calendarID))/events", body: body)
        guard status == 200 || status == 409 else { throw Self.writeFailure(status, data) }
    }

    /// `events.patch`: only the fields in `body` change; `NSNull` clears one.
    public func patchEvent(calendarID: String, eventID: String, _ body: [String: Any]) async throws {
        let (data, status) = try await send("PATCH", "calendars/\(Self.escape(calendarID))/events/\(Self.escape(eventID))", body: body)
        switch status {
        case 200: return
        case 404, 410: throw CalendarSyncError.conflict
        default: throw Self.writeFailure(status, data)
        }
    }

    /// `events.delete`; an event already gone counts as deleted.
    public func deleteEvent(calendarID: String, eventID: String) async throws {
        let (data, status) = try await send("DELETE", "calendars/\(Self.escape(calendarID))/events/\(Self.escape(eventID))")
        guard [200, 204, 404, 410].contains(status) else { throw Self.writeFailure(status, data) }
    }

    // MARK: - Requests

    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem]) async throws -> T {
        let (data, status) = try await send("GET", path, query)
        switch status {
        case 200: return try decode(data)
        case 410: throw CalendarSyncError.syncTokenExpired
        default: throw Self.failure(status, data)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw CalendarSyncError.invalidResponse }
    }

    /// Sends one request, refreshing the token once on 401 and waiting out rate limits and server
    /// hiccups; any other answer comes back for the caller to read.
    private func send(_ method: String, _ path: String, _ query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> (Data, Int) {
        var components = URLComponents(url: Self.base.appending(path: path, directoryHint: .notDirectory), resolvingAgainstBaseURL: false)!
        // `appending(path:)` would re-escape the already escaped ids, so the path is set as-is.
        components.percentEncodedPath = Self.base.path() + path
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }

        var refreshed = false
        var refreshNow = false
        for attempt in 0..<4 {
            request.setValue("Bearer \(try await session.accessToken(forceRefresh: refreshNow))", forHTTPHeaderField: "Authorization")
            refreshNow = false
            let (data, response): (Data, HTTPURLResponse)
            do {
                (data, response) = try await http.send(request)
            } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
                throw CalendarSyncError.offline
            }
            switch response.statusCode {
            case 401 where !refreshed:
                // Refresh once, for the very next try only.
                refreshed = true
                refreshNow = true
            case 403 where Self.isRateLimit(data), 429, 500...599:
                // Rate limits and server hiccups: wait 1, 2, 4 seconds, then give up.
                guard attempt < 3 else { throw CalendarSyncError.http(status: response.statusCode, reason: Self.reason(data)) }
                try await Task.sleep(for: .seconds(1 << attempt))
            default:
                return (data, response.statusCode)
            }
        }
        throw CalendarSyncError.http(status: 401)
    }

    /// The error for an answer the caller did not expect.
    static func failure(_ status: Int, _ data: Data) -> CalendarSyncError {
        switch (status, reason(data)) {
        case (403, "insufficientPermissions"), (403, "ACCESS_TOKEN_SCOPE_INSUFFICIENT"): .missingCalendarPermission
        case (403, "accessNotConfigured"), (403, "SERVICE_DISABLED"): .apiDisabled
        default: .http(status: status, reason: reason(data))
        }
    }

    /// The error for an unexpected answer to a write: as for reads, plus a calendar that takes
    /// no changes and a change made elsewhere first.
    static func writeFailure(_ status: Int, _ data: Data) -> CalendarSyncError {
        switch (status, reason(data)) {
        case (403, "requiredAccessLevel"), (403, "forbiddenForNonOrganizer"): .readOnly
        case (412, _): .conflict
        default: failure(status, data)
        }
    }

    /// Google's error body: `{"error":{"errors":[{"reason":…}],"details":[{"reason":…}],"status":…}}`.
    static func reason(_ data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data) else { return nil }
        return body.error.details?.compactMap(\.reason).first
            ?? body.error.errors?.compactMap(\.reason).first
            ?? body.error.status
    }

    private static func isRateLimit(_ data: Data) -> Bool {
        ["rateLimitExceeded", "userRateLimitExceeded", "RATE_LIMIT_EXCEEDED"].contains(reason(data) ?? "")
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { var reason: String? }
        struct Inner: Decodable {
            var errors: [Detail]?
            var details: [Detail]?
            var status: String?
        }
        var error: Inner
    }

    static func escape(_ id: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/#?@")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }

    private struct Page<Item: Decodable>: Decodable {
        var items: [Item]?
        var nextPageToken: String?
    }

    private struct EventPage: Decodable {
        var items: [GoogleEvent]?
        var nextPageToken: String?
        var nextSyncToken: String?
        var timeZone: String?
    }
}

public struct GoogleCalendarEntry: Decodable, Sendable {
    public var id: String
    public var summary: String?
    public var summaryOverride: String?
    public var backgroundColor: String?
    public var accessRole: String?
    public var primary: Bool?
    public var timeZone: String?

    public var displayName: String { summaryOverride ?? summary ?? id }
    public var isReadOnly: Bool { !(accessRole == "owner" || accessRole == "writer") }
    /// Google's public-holiday calendars, e.g. `ko.south_korea#holiday@group.v.calendar.google.com`.
    public var isHoliday: Bool { id.contains("#holiday@group.v.calendar.google.com") }
}

public struct GoogleEvent: Decodable, Sendable {
    public var id: String
    public var status: String?
    public var summary: String?
    public var location: String?
    public var description: String?
    public var start: Time?
    public var end: Time?
    public var recurrence: [String]?
    public var recurringEventId: String?
    public var originalStartTime: Time?

    public struct Time: Decodable, Sendable {
        public var date: String?
        public var dateTime: String?
        public var timeZone: String?
    }
}
