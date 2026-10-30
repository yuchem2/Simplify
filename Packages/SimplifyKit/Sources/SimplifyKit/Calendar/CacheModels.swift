import Foundation
import SwiftData

// The calendar cache: a local copy of what the providers hold. It never syncs to iCloud
// (the providers are the source of truth), so it may use unique ids freely.

public enum CalendarProviderKind: String, Codable, Sendable {
    case google, icloud
    /// The Mac's own reminders (EventKit); one account per Mac.
    case reminders
}

@Model
public final class CalendarAccount {
    public enum Status: String, Sendable { case ok, needsReauth }

    /// `google:<sub>`, `icloud:<principal path>` or `reminders:local`, stable across email changes.
    @Attribute(.unique) public var id: String
    public var providerRaw: String
    public var email: String
    public var statusRaw: String = Status.ok.rawValue
    public var lastSyncedAt: Date?
    public var createdAt: Date = Date.now

    public init(id: String, provider: CalendarProviderKind, email: String) {
        self.id = id
        providerRaw = provider.rawValue
        self.email = email
    }

    public var provider: CalendarProviderKind { CalendarProviderKind(rawValue: providerRaw) ?? .google }
    public var status: Status {
        get { Status(rawValue: statusRaw) ?? .ok }
        set { statusRaw = newValue.rawValue }
    }
}

/// One calendar of an account ("업무", "대한민국의 휴일").
@Model
public final class CalendarSource {
    /// `<account id>|<provider calendar id>`.
    @Attribute(.unique) public var id: String
    public var accountID: String
    public var remoteID: String
    public var name: String
    public var colorHex: String?
    public var paletteRaw: String = Palette.blue.rawValue
    public var isVisible: Bool = true
    public var isReadOnly: Bool = false
    public var isHoliday: Bool = false
    public var timeZone: String?
    /// Where the next incremental fetch starts; nil means fetch everything.
    public var syncToken: String?
    public var order: Int = 0

    public init(accountID: String, remoteID: String, name: String) {
        id = accountID + "|" + remoteID
        self.accountID = accountID
        self.remoteID = remoteID
        self.name = name
    }

    public var palette: Palette { Palette(rawValue: paletteRaw) ?? .blue }
}

@Model
public final class EventRecord {
    @Attribute(.unique) public var id: String
    public var sourceID: String
    public var remoteID: String
    public var title: String
    public var location: String?
    public var notes: String?
    public var isAllDay: Bool
    public var start: Date?
    public var end: Date?
    public var startDay: String?
    public var endDay: String?
    public var timeZone: String?
    public var recurrenceData: Data?
    public var recurrenceUnsupported: Bool = false
    public var exceptionDatesData: Data?
    public var recurringEventID: String?
    public var originalStart: Date?
    public var originalStartDay: String?
    public var isCancelled: Bool = false
    public var isExpandedInstance: Bool = false
    public var resourceHref: String?
    public var isCompleted: Bool = false

    public init(_ snapshot: EventSnapshot) {
        id = snapshot.id
        sourceID = snapshot.sourceID
        remoteID = snapshot.remoteID
        title = snapshot.title
        isAllDay = snapshot.isAllDay
        update(from: snapshot)
    }

    public func update(from s: EventSnapshot) {
        title = s.title
        location = s.location
        notes = s.notes
        isAllDay = s.isAllDay
        start = s.start
        end = s.end
        startDay = s.startDay
        endDay = s.endDay
        timeZone = s.timeZone
        recurrenceData = s.recurrence.flatMap { try? JSONEncoder().encode($0) }
        recurrenceUnsupported = s.recurrenceUnsupported
        exceptionDatesData = s.exceptionDates.isEmpty ? nil : try? JSONEncoder().encode(s.exceptionDates)
        recurringEventID = s.recurringEventID
        originalStart = s.originalStart
        originalStartDay = s.originalStartDay
        isCancelled = s.isCancelled
        isExpandedInstance = s.isExpandedInstance
        resourceHref = s.resourceHref
        isCompleted = s.isCompleted
    }

    public var snapshot: EventSnapshot {
        var s = EventSnapshot(id: id, sourceID: sourceID, remoteID: remoteID, title: title, isAllDay: isAllDay)
        s.location = location
        s.notes = notes
        s.start = start
        s.end = end
        s.startDay = startDay
        s.endDay = endDay
        s.timeZone = timeZone
        s.recurrence = recurrenceData.flatMap { try? JSONDecoder().decode(Recurrence.self, from: $0) }
        s.recurrenceUnsupported = recurrenceUnsupported
        s.exceptionDates = exceptionDatesData.flatMap { try? JSONDecoder().decode([Date].self, from: $0) } ?? []
        s.recurringEventID = recurringEventID
        s.originalStart = originalStart
        s.originalStartDay = originalStartDay
        s.isCancelled = isCancelled
        s.isExpandedInstance = isExpandedInstance
        s.resourceHref = resourceHref
        s.isCompleted = isCompleted
        return s
    }
}

public enum CacheSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { [CalendarAccount.self, CalendarSource.self, EventRecord.self] }
}
