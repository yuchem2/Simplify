import Foundation
import SwiftData

/// A day, week or month as the store names it, without a calendar.
public struct PeriodRef: Hashable, Sendable {
    public var scope: PeriodScope
    public var key: String

    public init(scope: PeriodScope, key: String) {
        self.scope = scope
        self.key = key
    }

    public init(_ period: Period) {
        self.init(scope: period.scope, key: period.key)
    }

    public func period(calendar: Calendar) -> Period? {
        Period(key: key, scope: scope, calendar: calendar)
    }
}

/// One row of a period's ToDo list: the ToDo itself, shown where it is filed or through a link.
public struct TodoEntry: Identifiable, Hashable, Sendable {
    public var todoID: UUID
    /// Nil for the ToDo's own period, the link's id where it shows through "잇기".
    public var linkID: UUID?
    public var title: String
    public var isDone: Bool
    public var label: Palette?
    public var order: Double
    /// Where the ToDo is filed; "넘기기" moves this.
    public var home: PeriodRef
    /// Every other period it shows in, its home included when this row is a link.
    public var elsewhere: [PeriodRef]
    public var sourceNoteID: UUID?

    public var id: UUID { linkID ?? todoID }
    public var isLink: Bool { linkID != nil }
}

/// Reading and changing ToDos and the links that show one ToDo in several periods.
///
/// A ToDo is filed under one period (its home) and may be linked into others. Ticking, renaming
/// or labelling changes the one ToDo, so every period shows the change. Rows within a period are
/// ordered by fractional `order` values shared between ToDos and links, so moving a row only
/// rewrites that row.
public enum Todos {
    // MARK: Reading

    public static func entries(for period: Period, in context: ModelContext) throws -> [TodoEntry] {
        let ref = PeriodRef(period)
        let key = period.key
        let homes = try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.periodKey == key }))
            .filter { $0.scope == period.scope }
        let links = try context.fetch(FetchDescriptor<TodoLink>(predicate: #Predicate { $0.periodKey == key }))
            .filter { $0.scope == period.scope }
        let homeIDs = Set(homes.map(\.id))
        let linked = try items(ids: Set(links.map(\.todoID)).subtracting(homeIDs), in: context)
        let allIDs = homeIDs.union(linked.keys)
        let linksByTodo = Dictionary(grouping: try allLinks(for: allIDs, in: context), by: \.todoID)

        func others(_ item: TodoItem) -> [PeriodRef] {
            var refs = [PeriodRef(scope: item.scope, key: item.periodKey)]
            refs += (linksByTodo[item.id] ?? []).map { PeriodRef(scope: $0.scope, key: $0.periodKey) }
            var seen: Set<PeriodRef> = [ref]
            return refs.filter { seen.insert($0).inserted }
        }

        var rows = homes.map { entry($0, link: nil, order: $0.order, elsewhere: others($0)) }
        var shown = homeIDs
        for link in links.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard let item = linked[link.todoID], shown.insert(item.id).inserted else { continue }
            rows.append(entry(item, link: link.id, order: link.order, elsewhere: others(item)))
        }
        return rows.sorted { ($0.order, $0.title) < ($1.order, $1.title) }
    }

    public static func item(_ id: UUID, in context: ModelContext) throws -> TodoItem? {
        try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })).first
    }

    /// Unfinished ToDos left in each period, by period key, for the counts on the month and week.
    /// Day, week and month keys never collide, so one dictionary holds all three.
    public static func remaining(in context: ModelContext) throws -> [String: Int] {
        let open = try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { !$0.isDone }))
        let openIDs = Set(open.map(\.id))
        var places: [UUID: Set<String>] = [:]
        for item in open { places[item.id, default: []].insert(item.periodKey) }
        for link in try context.fetch(FetchDescriptor<TodoLink>()) where openIDs.contains(link.todoID) {
            places[link.todoID, default: []].insert(link.periodKey)
        }
        var counts: [String: Int] = [:]
        for keys in places.values {
            for key in keys { counts[key, default: 0] += 1 }
        }
        return counts
    }

    /// Finished and total ToDos anywhere in a month: its own list, its days, and the weeks named
    /// after it (a week belongs to the month of its first day). Each ToDo counts once.
    public static func tally(for month: Period, in context: ModelContext) throws -> (done: Int, total: Int) {
        var keys: Set<String> = [month.key]
        for day in month.days {
            keys.insert(Period(containing: day, scope: .day, calendar: month.calendar).key)
            let week = Period(containing: day, scope: .week, calendar: month.calendar)
            if month.contains(week.start) { keys.insert(week.key) }
        }
        var ids = Set(try context.fetch(FetchDescriptor<TodoItem>()).filter { keys.contains($0.periodKey) }.map(\.id))
        ids.formUnion(try context.fetch(FetchDescriptor<TodoLink>()).filter { keys.contains($0.periodKey) }.map(\.todoID))
        let items = try items(ids: ids, in: context).values
        return (items.count { $0.isDone }, items.count)
    }

    /// Unfinished ToDos that do not show in `period` yet, newest first, for 가져오기.
    public static func open(notIn period: Period, in context: ModelContext) throws -> [TodoItem] {
        let here = Set(try entries(for: period, in: context).map(\.todoID))
        return try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { !$0.isDone }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            .filter { !here.contains($0.id) }
    }

    /// ToDos whose title holds `query` (all of them for an empty query), unfinished first, then
    /// newest first, for the memo's `[[` search.
    public static func search(_ query: String, limit: Int = 30, in context: ModelContext) throws -> [TodoItem] {
        let query = query.trimmingCharacters(in: .whitespaces)
        let all = try context.fetch(FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        let found = query.isEmpty ? all : all.filter { $0.title.localizedStandardContains(query) }
        return Array((found.filter { !$0.isDone } + found.filter(\.isDone)).prefix(limit))
    }

    // MARK: Changing

    /// A new ToDo at the end of `period`'s list. Blank titles make nothing.
    @discardableResult
    public static func add(_ title: String, to period: Period, sourceNoteID: UUID? = nil, in context: ModelContext) throws -> TodoItem? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let item = TodoItem(title: title, period: period, order: try endOrder(of: period, in: context))
        item.sourceNoteID = sourceNoteID
        context.insert(item)
        try context.save()
        return item
    }

    public static func setDone(_ id: UUID, _ isDone: Bool, in context: ModelContext) throws {
        guard let item = try item(id, in: context), item.isDone != isDone else { return }
        item.isDone = isDone
        item.updatedAt = SyncStamp.after(item.updatedAt)
        try context.save()
    }

    /// A blank title leaves the ToDo as it was.
    public static func rename(_ id: UUID, to title: String, in context: ModelContext) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let item = try item(id, in: context), item.title != title else { return }
        item.title = title
        item.updatedAt = SyncStamp.after(item.updatedAt)
        try context.save()
    }

    public static func setLabel(_ id: UUID, _ label: Palette?, in context: ModelContext) throws {
        guard let item = try item(id, in: context), item.colorLabel != label?.rawValue else { return }
        item.colorLabel = label?.rawValue
        item.updatedAt = SyncStamp.after(item.updatedAt)
        try context.save()
    }

    /// ⌫ on a row: a link only leaves that period; the ToDo's own row deletes it everywhere.
    public static func remove(_ entry: TodoEntry, in context: ModelContext) throws {
        if let linkID = entry.linkID {
            try context.fetch(FetchDescriptor<TodoLink>(predicate: #Predicate { $0.id == linkID })).forEach { deleteLink($0, in: context) }
        } else {
            try delete(entry.todoID, in: context)
        }
        try context.save()
    }

    public static func delete(_ id: UUID, in context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })) {
            context.delete(item)
            SyncStamp.bury(.todo, item.id.uuidString, at: SyncStamp.after(item.updatedAt), in: context)
        }
        try context.fetch(FetchDescriptor<TodoLink>(predicate: #Predicate { $0.todoID == id })).forEach { deleteLink($0, in: context) }
        try context.save()
    }

    /// "잇기": shows the ToDo in `period` too, at the end of its list. False when it already shows there.
    @discardableResult
    public static func link(_ id: UUID, to period: Period, in context: ModelContext) throws -> Bool {
        guard try item(id, in: context) != nil,
              !(try entries(for: period, in: context).contains { $0.todoID == id }) else { return false }
        context.insert(TodoLink(todoID: id, period: period, order: try endOrder(of: period, in: context)))
        try context.save()
        return true
    }

    /// "넘기기": the row leaves `period` and shows in `target` instead, at the end of its list.
    /// Passing the ToDo's own row moves its home; passing a link moves the link. Where the ToDo
    /// already shows in `target`, the row only leaves.
    public static func pass(_ entry: TodoEntry, to target: Period, in context: ModelContext) throws {
        let targetRef = PeriodRef(target)
        guard entry.home != targetRef || entry.isLink else { return }
        let alreadyThere = try entries(for: target, in: context).first { $0.todoID == entry.todoID }
        // A link passed to the period it is already in stays put.
        if entry.isLink, alreadyThere?.linkID == entry.linkID { return }
        let order = try endOrder(of: target, in: context)
        if let linkID = entry.linkID {
            let link = try context.fetch(FetchDescriptor<TodoLink>(predicate: #Predicate { $0.id == linkID })).first
            if let link, alreadyThere != nil {
                deleteLink(link, in: context)
            } else if let link {
                link.scopeRaw = target.scope.rawValue
                link.periodKey = target.key
                link.order = order
                link.updatedAt = SyncStamp.after(link.updatedAt)
            }
        } else if let item = try item(entry.todoID, in: context) {
            // A link into the target becomes the home itself.
            if let existing = alreadyThere, let linkID = existing.linkID {
                try context.fetch(FetchDescriptor<TodoLink>(predicate: #Predicate { $0.id == linkID })).forEach { deleteLink($0, in: context) }
                item.order = existing.order
            } else {
                item.order = order
            }
            item.scopeRaw = target.scope.rawValue
            item.periodKey = target.key
            item.updatedAt = SyncStamp.after(item.updatedAt)
        }
        try context.save()
    }

    /// Drags a row to `index` among `period`'s rows (counted before the move). Only that row's
    /// order changes: it takes a value between its new neighbours.
    public static func move(_ entry: TodoEntry, to index: Int, in period: Period, in context: ModelContext) throws {
        var rows = try entries(for: period, in: context)
        guard let from = rows.firstIndex(where: { $0.id == entry.id }) else { return }
        rows.remove(at: from)
        let at = min(max(0, index > from ? index - 1 : index), rows.count)
        let value = order(between: at > 0 ? rows[at - 1].order : nil, and: at < rows.count ? rows[at].order : nil)
        try setOrder(of: entry, to: value, in: context)
        try context.save()
    }

    /// A value between two neighbours' orders; nil means no neighbour on that side.
    public static func order(between before: Double?, and after: Double?) -> Double {
        switch (before, after) {
        case (nil, nil): 1
        case (let b?, nil): b + 1
        case (nil, let a?): a - 1
        case (let b?, let a?): (b + a) / 2
        }
    }

    /// The ToDo's row in its own period, for passing a ToDo picked from a list.
    public static func homeEntry(_ item: TodoItem) -> TodoEntry {
        entry(item, link: nil, order: item.order, elsewhere: [])
    }

    // MARK: Helpers

    static func endOrder(of period: Period, in context: ModelContext) throws -> Double {
        order(between: try entries(for: period, in: context).last?.order, and: nil)
    }

    private static func setOrder(of entry: TodoEntry, to value: Double, in context: ModelContext) throws {
        if let linkID = entry.linkID, let link = try context.fetch(FetchDescriptor<TodoLink>(predicate: #Predicate { $0.id == linkID })).first {
            link.order = value
            link.updatedAt = SyncStamp.after(link.updatedAt)
        } else if entry.linkID == nil, let item = try item(entry.todoID, in: context) {
            item.order = value
            item.updatedAt = SyncStamp.after(item.updatedAt)
        }
    }

    /// Deletes a link and leaves its tombstone.
    private static func deleteLink(_ link: TodoLink, in context: ModelContext) {
        context.delete(link)
        SyncStamp.bury(.link, link.id.uuidString, at: SyncStamp.after(link.updatedAt), in: context)
    }

    private static func items(ids: Set<UUID>, in context: ModelContext) throws -> [UUID: TodoItem] {
        guard !ids.isEmpty else { return [:] }
        let list = Array(ids)
        let items = try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { list.contains($0.id) }))
        // A period may hold two copies after a sync; the first one wins.
        return Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func allLinks(for ids: Set<UUID>, in context: ModelContext) throws -> [TodoLink] {
        guard !ids.isEmpty else { return [] }
        let list = Array(ids)
        return try context.fetch(FetchDescriptor<TodoLink>(predicate: #Predicate { list.contains($0.todoID) }))
    }

    private static func entry(_ item: TodoItem, link: UUID?, order: Double, elsewhere: [PeriodRef]) -> TodoEntry {
        TodoEntry(todoID: item.id, linkID: link, title: item.title, isDone: item.isDone,
                  label: item.colorLabel.flatMap(Palette.init(rawValue:)), order: order,
                  home: PeriodRef(scope: item.scope, key: item.periodKey), elsewhere: elsewhere,
                  sourceNoteID: item.sourceNoteID)
    }
}
