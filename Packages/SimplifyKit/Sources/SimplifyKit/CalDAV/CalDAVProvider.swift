import Foundation

/// An iCloud (or any CalDAV) account as a `CalendarProvider`.
public struct CalDAVProvider: CalendarProvider {
    /// How far around today a series the local engine cannot expand is written out by the server.
    static let expandWindow: (past: Int, future: Int) = (1, 2)

    let client: CalDAVClient
    let home: URL

    public init(client: CalDAVClient, home: URL) {
        self.client = client
        self.home = home
    }

    public func calendars() async throws -> [RemoteCalendar] {
        // Apple's calendar-order, then the server's order for calendars without one.
        try await client.calendars(home: home).enumerated()
            .sorted { ($0.element.order ?? Int.max, $0.offset) < ($1.element.order ?? Int.max, $1.offset) }
            .map { _, calendar in
                var remote = RemoteCalendar(id: calendar.url.absoluteString, name: calendar.name)
                remote.colorHex = calendar.color
                remote.isReadOnly = calendar.isReadOnly
                remote.timeZone = calendar.timeZone
                return remote
            }
    }

    public func changes(in remote: RemoteCalendar.Reference, syncToken: String?, calendar: Calendar) async throws -> CalendarChanges {
        guard let collection = URL(string: remote.remoteID) else { throw CalendarSyncError.invalidResponse }
        var syncToken = syncToken
        let delta: (changed: [String], deleted: [String], token: String?)
        do {
            delta = try await client.syncCollection(collection, token: syncToken)
        } catch CalendarSyncError.syncTokenExpired where syncToken != nil {
            syncToken = nil
            delta = try await client.syncCollection(collection, token: nil)
        }

        var changes = delta.deleted.map { EventChange.replaceResource(href: CalDAVClient.normalize($0), []) }
        let now = Date.now
        let window = DateInterval(start: calendar.date(byAdding: .year, value: -Self.expandWindow.past, to: now)!,
                                  end: calendar.date(byAdding: .year, value: Self.expandWindow.future, to: now)!)
        for (href, ics) in try await client.multiget(collection, hrefs: delta.changed) {
            let key = CalDAVClient.normalize(href)
            var events = ICalendar.events(in: ics, sourceID: remote.sourceID, href: key, calendar: calendar, defaultZone: remote.timeZone)
            if let index = events.firstIndex(where: { $0.recurrenceUnsupported && $0.recurringEventID == nil }) {
                events = try await expanded(master: events[index], href: href, collection: collection, window: window, calendar: calendar, zone: remote.timeZone)
            }
            changes.append(.replaceResource(href: key, events))
        }
        return CalendarChanges(isFullFetch: syncToken == nil, changes: changes, nextSyncToken: delta.token)
    }

    /// A series the engine cannot expand: the server writes its occurrences out. Should the server
    /// refuse (a 4xx) or write nothing out, the series shows as its first occurrence only, rather than
    /// not at all; any other failure is thrown so the sync token stays put and the next round asks again.
    private func expanded(master: EventSnapshot, href: String, collection: URL, window: DateInterval, calendar: Calendar, zone: String?) async throws -> [EventSnapshot] {
        do {
            let resources = try await client.multiget(collection, hrefs: [href], expand: window)
            let occurrences = resources.flatMap { _, ics in
                ICalendar.events(in: ics, sourceID: master.sourceID, href: master.resourceHref ?? href, calendar: calendar, defaultZone: zone)
            }
            .map { occurrence -> EventSnapshot in
                var occurrence = occurrence
                // Every written-out occurrence carries a RECURRENCE-ID; one without is the series start.
                if occurrence.recurringEventID == nil {
                    occurrence.id += "@" + String(Int((occurrence.start ?? .distantPast).timeIntervalSince1970))
                    occurrence.recurringEventID = master.remoteID
                    occurrence.originalStart = occurrence.start
                    occurrence.originalStartDay = occurrence.startDay
                }
                occurrence.isExpandedInstance = true
                return occurrence
            }
            if !occurrences.isEmpty { return [master] + occurrences }
        } catch CalendarSyncError.http(let status, _) where (400..<500).contains(status) && ![408, 429].contains(status) {
            // Refused; a timeout or rate limit is thrown instead, to be asked again next round.
        }
        var single = master
        single.recurrenceUnsupported = false
        return [single]
    }
}
