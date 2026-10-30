import CryptoKit
import EventKit
import Foundation

/// The Mac's reminders (whatever the Reminders app syncs, iCloud included) as a `CalendarProvider`.
///
/// Each list is a calendar and each reminder with a due date an event on that day. EventKit
/// reads a local copy, so every sync reads every list in full; the sync token is a digest of what
/// was read, and an unchanged list writes nothing.
public actor RemindersProvider: CalendarProvider {
    private let store = EKEventStore()

    public init() {}

    public static var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    /// Shows the system's access prompt the first time; afterwards answers with the saved choice.
    public func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        // A store made before access was granted can keep answering with no lists.
        if granted { store.reset() }
        return granted
    }

    public func calendars() async throws -> [RemoteCalendar] {
        guard Self.isAuthorized else { throw CalendarSyncError.remindersAccessDenied }
        let main = store.defaultCalendarForNewReminders()?.calendarIdentifier
        return store.calendars(for: .reminder).map { list in
            var remote = RemoteCalendar(id: list.calendarIdentifier, name: list.title)
            remote.colorHex = Self.hex(list.cgColor)
            remote.isReadOnly = !list.allowsContentModifications
            remote.isPrimary = list.calendarIdentifier == main
            return remote
        }
    }

    public func changes(in remote: RemoteCalendar.Reference, syncToken: String?, calendar: Calendar) async throws -> CalendarChanges {
        guard Self.isAuthorized else { throw CalendarSyncError.remindersAccessDenied }
        guard let list = store.calendar(withIdentifier: remote.remoteID) else {
            return CalendarChanges(isFullFetch: true, changes: [], nextSyncToken: nil)
        }
        let open = await fetch(store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list]))
        // Ticked-off reminders from the past year, for "완료된 미리알림 보기".
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: .now)
        let done = await fetch(store.predicateForCompletedReminders(withCompletionDateStarting: yearAgo, ending: nil, calendars: [list]))
        let snapshots = (open + done).compactMap { $0.snapshot(sourceID: remote.sourceID, calendar: calendar) }
        return Self.changes(for: snapshots, syncToken: syncToken)
    }

    // Reminders stay read-only: the calendar only shows them.

    public func createEvent(_ draft: EventDraft, id: String, in remote: RemoteCalendar.Reference, calendar: Calendar) async throws {
        throw CalendarSyncError.readOnly
    }

    public func updateEvent(_ event: EventSnapshot, to draft: EventDraft, scope: EditScope, in remote: RemoteCalendar.Reference, calendar: Calendar) async throws {
        throw CalendarSyncError.readOnly
    }

    public func deleteEvent(_ event: EventSnapshot, scope: EditScope, in remote: RemoteCalendar.Reference, calendar: Calendar) async throws {
        throw CalendarSyncError.readOnly
    }

    /// Everything as a full fetch, or nothing when it matches what was stored last time.
    static func changes(for snapshots: [EventSnapshot], syncToken: String?) -> CalendarChanges {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(snapshots.sorted { $0.id < $1.id })) ?? Data()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if digest == syncToken { return CalendarChanges(isFullFetch: false, changes: [], nextSyncToken: syncToken) }
        return CalendarChanges(isFullFetch: true, changes: snapshots.map(EventChange.upsert), nextSyncToken: digest)
    }

    private func fetch(_ predicate: NSPredicate) async -> [ReminderItem] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                // Read into plain values here: the reminder objects stay on EventKit's queue.
                continuation.resume(returning: (reminders ?? []).map(ReminderItem.init))
            }
        }
    }

    private static func hex(_ color: CGColor?) -> String? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let parts = color?.converted(to: srgb, intent: .defaultIntent, options: nil)?.components, parts.count >= 3 else { return nil }
        return String(format: "#%02x%02x%02x", Int(parts[0] * 255), Int(parts[1] * 255), Int(parts[2] * 255))
    }
}

/// One reminder as plain values.
public struct ReminderItem: Sendable, Equatable {
    public var id: String
    public var title: String
    /// The due date, or the start date when there is no due date. No hour means a whole day.
    public var due: DateComponents?
    public var isCompleted: Bool

    public init(id: String, title: String, due: DateComponents?, isCompleted: Bool) {
        self.id = id
        self.title = title
        self.due = due
        self.isCompleted = isCompleted
    }

    init(_ reminder: EKReminder) {
        self.init(id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                  due: reminder.dueDateComponents ?? reminder.startDateComponents, isCompleted: reminder.isCompleted)
    }

    /// The reminder as an event on its due day: all day when it has no time, otherwise a moment at
    /// that time. Reminders without a date have no place on the calendar and give nil.
    ///
    /// A repeating reminder shows once, on its current due date; the Reminders app moves that date
    /// on when it is ticked off.
    public func snapshot(sourceID: String, calendar: Calendar) -> EventSnapshot? {
        guard let due, let year = due.year, let month = due.month, let day = due.day else { return nil }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAllDay = due.hour == nil
        var event = EventSnapshot(id: sourceID + ":" + id, sourceID: sourceID, remoteID: id,
                                  title: title.isEmpty ? "(제목 없음)" : title, isAllDay: isAllDay)
        event.isCompleted = isCompleted
        if isAllDay {
            event.startDay = String(format: "%04d-%02d-%02d", year, month, day)
        } else {
            var zoned = calendar
            if let zone = due.timeZone { zoned.timeZone = zone }
            guard let start = zoned.date(from: DateComponents(year: year, month: month, day: day, hour: due.hour, minute: due.minute ?? 0)) else { return nil }
            event.start = start
            event.end = start
        }
        return event
    }
}
