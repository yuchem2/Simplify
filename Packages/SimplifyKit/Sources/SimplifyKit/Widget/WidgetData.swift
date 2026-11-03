import Foundation
import SwiftData

/// What the widgets read from the shared stores, once per timeline: events of this month's grid
/// and tomorrow, and the ToDos of today and tomorrow. No network; the app keeps the stores fresh.
public struct WidgetData: Sendable {
    public enum State: Sendable, Equatable {
        case ready
        /// No calendar account is connected yet.
        case noAccounts
        /// The calendar cache would not open.
        case unavailable
    }

    public var state: State
    public var events: [WidgetEvent]
    /// ToDos by day key (`yyyy-MM-dd`); nil when the diary store would not open.
    public var todos: [String: [TodoEntry]]?

    public init(state: State, events: [WidgetEvent] = [], todos: [String: [TodoEntry]]? = [:]) {
        self.state = state
        self.events = events
        self.todos = todos
    }

    public func todos(on day: Date, calendar: Calendar) -> [TodoEntry]? {
        todos.map { $0[DayKey.key(day, calendar: calendar)] ?? [] }
    }
}

/// Reads the shared stores for the widgets, and makes the one change a widget may make.
public enum WidgetStore {
    /// Opens the stores in the App Group and reads them. The cache is never set aside here when it
    /// fails to open (that is the app's call); the widget says it could not read it instead.
    public static func load(now: Date = .now, calendar: Calendar = .simplify) -> WidgetData {
        let cache = try? SimplifyStore.makeCacheContainer()
        // Opened with the migration plan like the app does; the app, opened first after an update,
        // normally migrates the file before a widget gets to it.
        let diary = try? SimplifyStore.makeContainer()
        return load(now: now, calendar: calendar, cache: cache, diary: diary,
                    pending: EventWriter.storedWrites(), defaults: SharedSettings.defaults)
    }

    /// The days the widgets can show from `now` until tomorrow ends: the month grids of today and
    /// tomorrow (they differ on the last day of a month, when the midnight entry shows the next one),
    /// and the week of coming days the lists run on into, counted from tomorrow.
    public static func range(now: Date, calendar: Calendar) -> DateInterval {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let first = MonthGrid(month: now, calendar: calendar).weeks.first!.first!
        let last = MonthGrid(month: tomorrow, calendar: calendar).weeks.last!.last!
        let gridEnd = calendar.date(byAdding: .day, value: 1, to: last)!
        let weekAhead = calendar.date(byAdding: .day, value: 1 + comingDays, to: tomorrow)!
        return DateInterval(start: first, end: max(gridEnd, weekAhead))
    }

    /// How far ahead the lists look for the next days with events.
    public static let comingDays = 7

    static func load(now: Date, calendar: Calendar, cache: ModelContainer?, diary: ModelContainer?,
                     pending: [PendingWrite], defaults: UserDefaults) -> WidgetData {
        let todos = diary.map { container -> [String: [TodoEntry]] in
            let context = ModelContext(container)
            var result: [String: [TodoEntry]] = [:]
            for offset in 0...1 {
                let day = calendar.date(byAdding: .day, value: offset, to: now)!
                let period = Period(containing: day, scope: .day, calendar: calendar)
                result[period.key] = (try? Todos.entries(for: period, in: context)) ?? []
            }
            return result
        }
        guard let cache else { return WidgetData(state: .unavailable, todos: todos) }

        let context = ModelContext(cache)
        let accounts = (try? context.fetch(FetchDescriptor<CalendarAccount>())) ?? []
        guard !accounts.isEmpty else { return WidgetData(state: .noAccounts, todos: todos) }
        let reminderAccounts = Set(accounts.filter { $0.provider == .reminders }.map(\.id))
        let sources = (try? context.fetch(FetchDescriptor<CalendarSource>())) ?? []
        let visible = Set(sources.filter(\.isVisible).map(\.id))
        let calendars = Dictionary(sources.map {
            ($0.id, WidgetCalendar(palette: $0.palette, isReminderList: reminderAccounts.contains($0.accountID), isHoliday: $0.isHoliday))
        }) { first, _ in first }

        // As the app shows them: the cache with unsent changes on top, visible calendars only.
        let waiting = pending.filter { $0.isWaiting || $0.isSent }
        var snapshots = PendingOverlay.apply(waiting, to: CalendarCache.visibleSnapshots(context: context), calendar: calendar)
            .filter { visible.contains($0.sourceID) }
        if !(defaults.bool(forKey: SharedSettings.showsCompletedReminders)) { snapshots.removeAll(where: \.isCompleted) }
        let occurrences = OccurrenceBuilder.occurrences(from: snapshots, in: range(now: now, calendar: calendar), calendar: calendar)
        return WidgetData(state: .ready, events: WidgetContent.events(occurrences, calendars: calendars), todos: todos)
    }

    /// A widget's checkbox: ticks or unticks the ToDo, and leaves a note for the app to read the store again.
    public static func setTodo(_ id: UUID, done: Bool, in container: ModelContainer, defaults: UserDefaults) throws {
        try Todos.setDone(id, done, in: ModelContext(container))
        SharedSettings.markDiaryChanged(in: defaults)
    }
}
