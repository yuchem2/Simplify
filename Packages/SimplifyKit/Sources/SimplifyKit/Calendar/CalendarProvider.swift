import Foundation

/// One calendar service account as the sync engine sees it: a list of calendars, and the
/// changes in each since the last sync. Google, iCloud (CalDAV) and the Mac's reminders each
/// have an adapter; the engine does the bookkeeping (cache, sync tokens, errors) for all of them.
public protocol CalendarProvider: Sendable {
    /// The account's calendars, in the provider's order.
    func calendars() async throws -> [RemoteCalendar]

    /// What changed in one calendar since `syncToken`, or everything when it is nil.
    /// `calendar` is the person's calendar, for reading dates that carry no zone.
    func changes(in remote: RemoteCalendar.Reference, syncToken: String?, calendar: Calendar) async throws -> CalendarChanges
}

public struct RemoteCalendar: Sendable, Hashable {
    /// The provider's calendar id: a Google calendar id, a CalDAV collection URL, a reminders list id.
    public var id: String
    public var name: String
    /// `#4986e7`, or `#4986e7ff` from CalDAV.
    public var colorHex: String?
    public var isReadOnly = false
    public var isHoliday = false
    /// The calendar's own zone, for timed events that do not name one.
    public var timeZone: String?
    /// The account's main calendar, listed first.
    public var isPrimary = false

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// What `changes(in:)` needs to know about a stored calendar.
    public struct Reference: Sendable {
        public var sourceID: String
        public var remoteID: String
        public var timeZone: String?
    }
}

public struct CalendarChanges: Sendable {
    /// The provider sent everything, not a delta: whatever is stored and not sent is gone.
    public var isFullFetch: Bool
    public var changes: [EventChange]
    /// Where the next fetch starts.
    public var nextSyncToken: String?

    public init(isFullFetch: Bool, changes: [EventChange], nextSyncToken: String?) {
        self.isFullFetch = isFullFetch
        self.changes = changes
        self.nextSyncToken = nextSyncToken
    }
}

/// One change to the stored events of a calendar, applied in order.
public enum EventChange: Sendable {
    /// A new or changed event, series, or changed occurrence of a series.
    case upsert(EventSnapshot)
    /// A deleted event or series, with every changed occurrence of it.
    case remove(remoteID: String)
    /// The occurrences of a series the engine cannot expand, fetched one by one; they replace
    /// the ones stored before.
    case replaceOccurrences(seriesID: String, [EventSnapshot])
    /// Everything one CalDAV resource holds (a series and its changed occurrences); an empty
    /// list means the resource was deleted.
    case replaceResource(href: String, [EventSnapshot])
}
