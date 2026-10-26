import Foundation

extension GoogleCalendarAPI: CalendarProvider {
    /// How far around today a series the local engine cannot expand is fetched occurrence by occurrence.
    static let instanceWindow: (past: Int, future: Int) = (1, 2)

    public func calendars() async throws -> [RemoteCalendar] {
        try await calendarList().map { entry in
            var remote = RemoteCalendar(id: entry.id, name: entry.displayName)
            remote.colorHex = entry.backgroundColor
            remote.isReadOnly = entry.isReadOnly
            remote.isHoliday = entry.isHoliday
            remote.timeZone = entry.timeZone
            remote.isPrimary = entry.primary == true
            return remote
        }
    }

    public func changes(in remote: RemoteCalendar.Reference, syncToken: String?, calendar: Calendar) async throws -> CalendarChanges {
        var syncToken = syncToken
        let fetched: (events: [GoogleEvent], nextSyncToken: String?, timeZone: String?)
        do {
            fetched = try await events(calendarID: remote.remoteID, syncToken: syncToken)
        } catch CalendarSyncError.syncTokenExpired {
            syncToken = nil
            fetched = try await events(calendarID: remote.remoteID, syncToken: nil)
        }
        let zone = fetched.timeZone ?? remote.timeZone

        var changes: [EventChange] = []
        var unsupported: [String] = []
        for event in fetched.events {
            let snapshot = event.snapshot(sourceID: remote.sourceID, calendar: calendar, defaultZone: zone)
            if snapshot.isCancelled, snapshot.recurringEventID == nil {
                // A deleted single event or a whole deleted series (with its changed occurrences).
                changes.append(.remove(remoteID: snapshot.remoteID))
                continue
            }
            changes.append(.upsert(snapshot))
            if snapshot.recurrenceUnsupported { unsupported.append(snapshot.remoteID) }
        }

        let now = Date.now
        let window = DateInterval(start: calendar.date(byAdding: .year, value: -Self.instanceWindow.past, to: now)!,
                                  end: calendar.date(byAdding: .year, value: Self.instanceWindow.future, to: now)!)
        for seriesID in unsupported {
            let occurrences = try await instances(calendarID: remote.remoteID, eventID: seriesID, in: window).map { instance in
                var snapshot = instance.snapshot(sourceID: remote.sourceID, calendar: calendar, defaultZone: zone)
                snapshot.isExpandedInstance = true
                return snapshot
            }
            changes.append(.replaceOccurrences(seriesID: seriesID, occurrences))
        }
        return CalendarChanges(isFullFetch: syncToken == nil, changes: changes, nextSyncToken: fetched.nextSyncToken)
    }
}
