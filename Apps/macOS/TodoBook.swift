import Foundation
import Observation
import OSLog
import SwiftData
import SimplifyKit

/// The diary store's ToDos for the window: each period's rows, the counts on the month and week,
/// and the small drawn pop over the panel (가져오기, `[[` search, ⌘⇧T, a date to pass to).
@MainActor
@Observable
final class TodoBook {
    /// Unfinished ToDos per period key, for ✓N on the month and week.
    private(set) var remaining: [String: Int] = [:]
    /// Bumped on every change, so views reading rows draw again.
    private(set) var revision = 0
    var pop: PanelPop?
    /// The row picked with a click (a `TodoEntry.id`); ⌫, Return and Space act on it.
    var selectedRow: UUID?
    /// The memo line a memo pop belongs to, in window coordinates (top-left origin), read while the
    /// memo still had focus. Nil puts the pop at the top of the panel.
    @ObservationIgnored var popAnchor: CGRect?
    @ObservationIgnored private var context: ModelContext
    /// Called after every change, for `DeviceSync`.
    @ObservationIgnored var onChange: (() -> Void)?
    private static let log = Logger(subsystem: "dev.yoom.simplify", category: "todos")

    init(context: ModelContext) {
        self.context = context
        remaining = (try? Todos.remaining(in: context)) ?? [:]
    }

    /// The store was changed by another process (a widget): read it through `fresh` from now on,
    /// since a context keeps the values it already loaded.
    func use(_ fresh: ModelContext) {
        context = fresh
        // Pops hold ToDos read through the old context.
        pop = nil
        selectedRow = nil
        revision += 1
        let counts = (try? Todos.remaining(in: context)) ?? remaining
        if counts != remaining { remaining = counts }
    }

    // MARK: Reading

    func entries(for period: Period) -> [TodoEntry] {
        _ = revision
        return (try? Todos.entries(for: period, in: context)) ?? []
    }

    func remaining(on day: Date, calendar: Calendar) -> Int {
        remaining[Period(containing: day, scope: .day, calendar: calendar).key] ?? 0
    }

    func tally(for month: Period) -> (done: Int, total: Int) {
        _ = revision
        return (try? Todos.tally(for: month, in: context)) ?? (0, 0)
    }

    func open(notIn period: Period) -> [TodoItem] {
        (try? Todos.open(notIn: period, in: context)) ?? []
    }

    func search(_ query: String) -> [TodoItem] {
        (try? Todos.search(query, in: context)) ?? []
    }

    func item(_ id: UUID) -> TodoItem? {
        try? Todos.item(id, in: context)
    }

    // MARK: Changing

    @discardableResult
    func add(_ title: String, to period: Period, sourceNoteID: UUID? = nil) -> TodoItem? {
        var made: TodoItem?
        change { made = try Todos.add(title, to: period, sourceNoteID: sourceNoteID, in: context) }
        return made
    }

    func setDone(_ id: UUID, _ isDone: Bool) {
        change { try Todos.setDone(id, isDone, in: context) }
    }

    func rename(_ id: UUID, to title: String) {
        change { try Todos.rename(id, to: title, in: context) }
    }

    func setLabel(_ id: UUID, _ label: Palette?) {
        change { try Todos.setLabel(id, label, in: context) }
    }

    func remove(_ entry: TodoEntry) {
        change { try Todos.remove(entry, in: context) }
        if selectedRow == entry.id { selectedRow = nil }
    }

    func pass(_ entry: TodoEntry, to target: Period) {
        change { try Todos.pass(entry, to: target, in: context) }
    }

    func link(_ id: UUID, to period: Period) {
        change { try Todos.link(id, to: period, in: context) }
    }

    func move(_ entry: TodoEntry, to index: Int, in period: Period) {
        change { try Todos.move(entry, to: index, in: period, in: context) }
    }

    /// Runs a store change; a failed one is rolled back so the screen keeps showing what is stored.
    private func change(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            context.rollback()
            Self.log.error("ToDo change failed: \(String(describing: error), privacy: .private)")
        }
        revision += 1
        let counts = (try? Todos.remaining(in: context)) ?? remaining
        if counts != remaining { remaining = counts }
        WidgetRefresh.request()
        onChange?()
    }
}

/// The drawn pop over the panel and what it is for.
enum PanelPop: Equatable {
    /// 할 일 › 가져오기 for this period.
    case importer(Period)
    /// `[[` in the memo, or 할 일 가져오기…: pick a ToDo to put at this offset of the memo's
    /// letters. `typed` when the brackets were typed, so closing puts them back.
    case search(at: Int, typed: Bool)
    /// ⌘⇧T: which period the picked memo lines become ToDos in.
    case makeTodos(lines: [Int])
    /// 다른 날짜…: a day to pass a row to, or to file the picked memo lines under.
    case pickDay(DayPurpose)
    /// ⌘K: a link's address for the memo's letters at `location` (UTF-16; none picked when
    /// `length` is 0), `address` the link's own when they are in one.
    case link(location: Int, length: Int, address: String?)

    enum DayPurpose: Equatable {
        case pass(TodoEntry, from: Period)
        case makeTodos(lines: [Int])
    }
}
