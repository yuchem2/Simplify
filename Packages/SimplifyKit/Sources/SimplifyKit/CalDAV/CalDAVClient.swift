import Foundation

/// An Apple ID and app-specific password, plus where discovery found the account's calendars.
public struct CalDAVCredentials: Codable, Sendable, Equatable {
    public var username: String
    public var password: String
    /// The calendar home (`https://p12-caldav.icloud.com/123456/calendars/`), once discovered.
    public var home: URL?

    public init(username: String, password: String, home: URL? = nil) {
        self.username = username
        self.password = password
        self.home = home
    }
}

/// One calendar collection under the home.
public struct DAVCalendar: Sendable, Equatable {
    public var url: URL
    public var name: String
    public var color: String?
    public var order: Int?
    public var isReadOnly: Bool
    public var timeZone: String?
}

/// The parts of CalDAV (RFC 4791, sync from RFC 6578) the app reads and writes.
public struct CalDAVClient: Sendable {
    public static let iCloud = URL(string: "https://caldav.icloud.com/")!

    let http: HTTPTransport
    let credentials: CalDAVCredentials

    public init(http: HTTPTransport = URLSessionTransport(), credentials: CalDAVCredentials) {
        self.http = http
        self.credentials = credentials
    }

    /// Finds the signed-in principal and its calendar home. A wrong password fails here with
    /// `needsReauth`.
    public func discover(server: URL = iCloud) async throws -> (principal: String, home: URL) {
        let root = try await send("PROPFIND", server, depth: "0", body: """
            <d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>
            """)
        guard let href = try DAVResponse.multistatus(root).responses.first?
            .property(DAVNode.dav, "current-user-principal")?.child(DAVNode.dav, "href")?.trimmedText,
            let principal = URL(string: href, relativeTo: server)?.absoluteURL else { throw CalendarSyncError.invalidResponse }

        let homeBody = try await send("PROPFIND", principal, depth: "0", body: """
            <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><c:calendar-home-set/></d:prop></d:propfind>
            """)
        guard let homeHref = try DAVResponse.multistatus(homeBody).responses.first?
            .property(DAVNode.caldav, "calendar-home-set")?.child(DAVNode.dav, "href")?.trimmedText,
            let home = URL(string: homeHref, relativeTo: principal)?.absoluteURL else { throw CalendarSyncError.invalidResponse }
        return (principal.path(percentEncoded: false), home)
    }

    /// The event calendars under `home`. Reminders lists (VTODO-only collections), the scheduling
    /// inbox and outbox are left out.
    public func calendars(home: URL) async throws -> [DAVCalendar] {
        let data = try await send("PROPFIND", home, depth: "1", body: """
            <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:a="http://apple.com/ns/ical/">
            <d:prop><d:resourcetype/><d:displayname/><a:calendar-color/><a:calendar-order/>
            <c:supported-calendar-component-set/><d:current-user-privilege-set/><c:calendar-timezone/></d:prop>
            </d:propfind>
            """)
        return try DAVResponse.multistatus(data).responses.compactMap { response in
            guard response.property(DAVNode.dav, "resourcetype")?.child(DAVNode.caldav, "calendar") != nil,
                  let url = URL(string: response.href, relativeTo: home)?.absoluteURL else { return nil }
            if let components = response.property(DAVNode.caldav, "supported-calendar-component-set") {
                let names = components.children(DAVNode.caldav, "comp").compactMap { $0.attributes["name"]?.uppercased() }
                guard names.contains("VEVENT") else { return nil }
            }
            let privileges = response.property(DAVNode.dav, "current-user-privilege-set")?
                .children(DAVNode.dav, "privilege").flatMap { $0.children.map(\.name) }
            let name = response.property(DAVNode.dav, "displayname")?.trimmedText ?? ""
            return DAVCalendar(
                url: url,
                name: name.isEmpty ? url.lastPathComponent : name,
                color: response.property(DAVNode.apple, "calendar-color")?.trimmedText,
                order: response.property(DAVNode.apple, "calendar-order").flatMap { Int($0.trimmedText) },
                isReadOnly: privileges.map { Set($0).isDisjoint(with: ["write", "write-content", "all"]) } ?? false,
                timeZone: response.property(DAVNode.caldav, "calendar-timezone").flatMap { Self.zoneID(inVTimeZone: $0.text) })
        }
    }

    /// The members that changed or went away since `token` (all members when nil), and the next
    /// token. A token the server no longer accepts throws `syncTokenExpired`.
    public func syncCollection(_ collection: URL, token: String?) async throws -> (changed: [String], deleted: [String], token: String?) {
        var changed: [String] = []
        var deleted: [String] = []
        var token = token
        // A server may cut a long answer short (507 on the collection itself); ask again from there.
        for _ in 0..<50 {
            let data = try await send("REPORT", collection, depth: nil, body: """
                <d:sync-collection xmlns:d="DAV:"><d:sync-token>\((token ?? "").xmlEscaped)</d:sync-token>\
                <d:sync-level>1</d:sync-level><d:prop><d:getetag/></d:prop></d:sync-collection>
                """)
            let (responses, next) = try DAVResponse.multistatus(data)
            var truncated = false
            for response in responses {
                if Self.isSameResource(response.href, collection) {
                    truncated = response.status == 507
                } else if response.status == 404 {
                    deleted.append(response.href)
                } else if !response.href.hasSuffix("/") {
                    changed.append(response.href)
                }
            }
            token = next
            if !truncated { break }
        }
        return (changed, deleted, token)
    }

    /// The iCalendar text of each resource, by href as the server wrote it. With `expand`, the
    /// server writes each occurrence in that window out as its own VEVENT.
    public func multiget(_ collection: URL, hrefs: [String], expand: DateInterval? = nil) async throws -> [(href: String, ics: String)] {
        var results: [(String, String)] = []
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let data = expand.map { #"<c:calendar-data><c:expand start="\#(format.string(from: $0.start))" end="\#(format.string(from: $0.end))"/></c:calendar-data>"# }
            ?? "<c:calendar-data/>"
        for start in stride(from: 0, to: hrefs.count, by: 100) {
            let batch = hrefs[start..<min(start + 100, hrefs.count)]
            let body = try await send("REPORT", collection, depth: "1", body: """
                <c:calendar-multiget xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">\
                <d:prop><d:getetag/>\(data)</d:prop>\
                \(batch.map { "<d:href>\($0.xmlEscaped)</d:href>" }.joined())</c:calendar-multiget>
                """)
            for response in try DAVResponse.multistatus(body).responses {
                if let ics = response.property(DAVNode.caldav, "calendar-data")?.text, !ics.isEmpty {
                    results.append((response.href, ics))
                }
            }
        }
        return results
    }

    /// One resource's iCalendar text and ETag. A resource gone since it was read is a conflict.
    public func resource(_ url: URL) async throws -> (ics: String, etag: String?) {
        let (data, response) = try await request("GET", url)
        switch response.statusCode {
        case 200: return (String(decoding: data, as: UTF8.self), response.value(forHTTPHeaderField: "ETag"))
        case 404, 410: throw CalendarSyncError.conflict
        default: throw Self.writeFailure(response.statusCode)
        }
    }

    /// Writes a resource: a new one (`isNew`), or over the version with `etag`. Either way a
    /// resource made or changed by someone else in between is a conflict. A server that gave
    /// no ETag gets the write without a precondition.
    public func put(_ url: URL, ics: String, etag: String?, isNew: Bool = false) async throws {
        var headers = ["Content-Type": "text/calendar; charset=utf-8"]
        if isNew { headers["If-None-Match"] = "*" } else if let etag { headers["If-Match"] = etag }
        let (_, response) = try await request("PUT", url, headers: headers, body: Data(ics.utf8))
        guard [200, 201, 204].contains(response.statusCode) else { throw Self.writeFailure(response.statusCode) }
    }

    /// Deletes a resource; one already gone counts as deleted.
    public func delete(_ url: URL, etag: String?) async throws {
        let (_, response) = try await request("DELETE", url, headers: etag.map { ["If-Match": $0] } ?? [:])
        guard [200, 204, 404, 410].contains(response.statusCode) else { throw Self.writeFailure(response.statusCode) }
    }

    /// `/123/calendars/work/A B.ics` on the collection's server.
    public static func url(ofResource href: String, in collection: URL) -> URL? {
        var components = URLComponents(url: collection, resolvingAgainstBaseURL: false)
        components?.path = href
        components?.query = nil
        return components?.url
    }

    // MARK: - Requests

    private func send(_ method: String, _ url: URL, depth: String?, body: String) async throws -> Data {
        var headers = ["Content-Type": "application/xml; charset=utf-8"]
        if let depth { headers["Depth"] = depth }
        let (data, response) = try await request(method, url, headers: headers, body: Data(("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" + body).utf8))
        switch response.statusCode {
        case 207, 200:
            return data
        case let status where [400, 403, 409].contains(status) && String(decoding: data, as: UTF8.self).contains("valid-sync-token"):
            throw CalendarSyncError.syncTokenExpired
        default:
            throw CalendarSyncError.http(status: response.statusCode)
        }
    }

    /// Sends one request, waiting out busy servers; any other answer comes back for the caller.
    private func request(_ method: String, _ url: URL, headers: [String: String] = [:], body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let login = Data("\(credentials.username):\(credentials.password)".utf8).base64EncodedString()
        request.setValue("Basic \(login)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        for attempt in 0..<4 {
            let (data, response): (Data, HTTPURLResponse)
            do {
                (data, response) = try await http.send(request)
            } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(error.code) {
                throw CalendarSyncError.offline
            }
            switch response.statusCode {
            case 401:
                throw CalendarSyncError.needsReauth
            case 429, 500...599:
                // Busy or a hiccup: wait 1, 2, 4 seconds, then give up.
                guard attempt < 3 else { throw CalendarSyncError.http(status: response.statusCode) }
                try await Task.sleep(for: .seconds(1 << attempt))
            default:
                return (data, response)
            }
        }
        throw CalendarSyncError.http(status: 503)
    }

    private static func writeFailure(_ status: Int) -> CalendarSyncError {
        switch status {
        case 412: .conflict
        case 403: .readOnly
        default: .http(status: status)
        }
    }

    /// The collection's own entry in a sync report, written as a path or a full URL.
    static func isSameResource(_ href: String, _ url: URL) -> Bool {
        normalize(href).trimmingCharacters(in: CharacterSet(charactersIn: "/")) == url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// One spelling per resource (`/1/calendars/home/A%20B.ics` and a full URL both become
    /// `/1/calendars/home/A B.ics`), so hrefs from different reports match.
    public static func normalize(_ href: String) -> String {
        URL(string: href)?.path(percentEncoded: false) ?? href.removingPercentEncoding ?? href
    }

    /// The TZID of a `calendar-timezone` VTIMEZONE.
    static func zoneID(inVTimeZone text: String) -> String? {
        ICalendar.parse(text).flatMap { $0.name == "VCALENDAR" ? $0.children : [$0] }
            .first { $0.name == "VTIMEZONE" }?.first("TZID").flatMap { ICalendar.timeZoneID($0.value) }
    }
}
