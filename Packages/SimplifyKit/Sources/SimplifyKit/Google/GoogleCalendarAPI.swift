import Foundation

/// The parts of Google Calendar API v3 the app reads.
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

    // MARK: - Requests

    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: Self.base.appending(path: path, directoryHint: .notDirectory), resolvingAgainstBaseURL: false)!
        // `appending(path:)` would re-escape the already escaped ids, so the path is set as-is.
        components.percentEncodedPath = Self.base.path() + path
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30

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
            case 200:
                do { return try JSONDecoder().decode(T.self, from: data) } catch { throw CalendarSyncError.invalidResponse }
            case 401 where !refreshed:
                // Refresh once, for the very next try only.
                refreshed = true
                refreshNow = true
            case 410:
                throw CalendarSyncError.syncTokenExpired
            case 403 where Self.isRateLimit(data), 429, 500...599:
                // Rate limits and server hiccups: wait 1, 2, 4 seconds, then give up.
                guard attempt < 3 else { throw CalendarSyncError.http(status: response.statusCode, reason: Self.reason(data)) }
                try await Task.sleep(for: .seconds(1 << attempt))
            case 403 where ["insufficientPermissions", "ACCESS_TOKEN_SCOPE_INSUFFICIENT"].contains(Self.reason(data)):
                throw CalendarSyncError.missingCalendarPermission
            case 403 where ["accessNotConfigured", "SERVICE_DISABLED"].contains(Self.reason(data)):
                throw CalendarSyncError.apiDisabled
            default:
                throw CalendarSyncError.http(status: response.statusCode, reason: Self.reason(data))
            }
        }
        throw CalendarSyncError.http(status: 401)
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
