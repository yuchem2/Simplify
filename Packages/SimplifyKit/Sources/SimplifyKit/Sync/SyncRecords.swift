import Foundation
import SwiftData

/// Moves records between the diary store (and the shared settings) and a `SyncSnapshot`.
public enum SyncRecords {
    /// What taking a merged snapshot in changed on this device.
    public struct Applied: Equatable, Sendable {
        /// `SyncKey.note` of every memo whose text arrived, changed or went.
        public var notes: Set<String> = []
        /// Any ToDo or link changed.
        public var todosChanged = false
        /// `SyncedSettings` keys whose value changed.
        public var settings: Set<String> = []

        public init() {}

        public var isEmpty: Bool { notes.isEmpty && !todosChanged && settings.isEmpty }
    }

    /// Everything this device shares, as stored now.
    public static func read(from context: ModelContext, defaults: UserDefaults) throws -> SyncSnapshot {
        // A period may hold two memos after an older sync; the newest is the one shown.
        var notes: [String: SyncNote] = [:]
        for note in try context.fetch(FetchDescriptor<DiaryNote>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])) {
            guard let body = note.body else { continue }
            let record = SyncNote(id: note.id, scope: note.scopeRaw, periodKey: note.periodKey, body: body, updatedAt: note.updatedAt)
            if notes[record.key] == nil { notes[record.key] = record }
        }
        var todos: [UUID: SyncTodo] = [:]
        for item in try context.fetch(FetchDescriptor<TodoItem>()) where todos[item.id] == nil {
            todos[item.id] = SyncTodo(id: item.id, title: item.title, isDone: item.isDone, scope: item.scopeRaw, periodKey: item.periodKey,
                                      order: item.order, colorLabel: item.colorLabel, sourceNoteID: item.sourceNoteID,
                                      createdAt: item.createdAt, updatedAt: item.updatedAt)
        }
        var links: [UUID: SyncLink] = [:]
        for link in try context.fetch(FetchDescriptor<TodoLink>()) where links[link.id] == nil {
            links[link.id] = SyncLink(id: link.id, todoID: link.todoID, scope: link.scopeRaw, periodKey: link.periodKey,
                                      order: link.order, createdAt: link.createdAt, updatedAt: link.updatedAt)
        }
        var deletions: [String: SyncDeletion] = [:]
        for tombstone in try context.fetch(FetchDescriptor<SyncTombstone>()) {
            guard let kind = tombstone.kind else { continue }
            let deletion = SyncDeletion(kind: kind, key: tombstone.key, deletedAt: tombstone.deletedAt)
            if (deletions[deletion.id]?.deletedAt ?? .distantPast) < deletion.deletedAt { deletions[deletion.id] = deletion }
        }
        return SyncSnapshot(notes: Array(notes.values), todos: Array(todos.values), links: Array(links.values),
                            deletions: Array(deletions.values), settings: SyncedSettings.snapshot(in: defaults)).sorted
    }

    /// Makes the store and settings hold `snapshot`, touching only what differs.
    @discardableResult
    public static func apply(_ snapshot: SyncSnapshot, to context: ModelContext, defaults: UserDefaults) throws -> Applied {
        var applied = Applied()

        // Memos, by period.
        let wanted = Dictionary(snapshot.notes.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let stored = Dictionary(grouping: try context.fetch(FetchDescriptor<DiaryNote>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])),
                                by: { "\($0.scopeRaw)|\($0.periodKey)" })
        for (key, notes) in stored where wanted[key] == nil {
            notes.forEach(context.delete)
            applied.notes.insert(key)
        }
        for (key, record) in wanted {
            var notes = stored[key] ?? []
            let note = notes.isEmpty ? nil : notes.removeFirst()
            notes.forEach(context.delete)
            if let note {
                if note.body != record.body { applied.notes.insert(key) }
                if note.id != record.id { note.id = record.id }
                if note.body != record.body { note.body = record.body }
                if note.updatedAt != record.updatedAt { note.updatedAt = record.updatedAt }
            } else {
                let note = DiaryNote(id: record.id, scopeRaw: record.scope, periodKey: record.periodKey)
                note.body = record.body
                note.updatedAt = record.updatedAt
                context.insert(note)
                applied.notes.insert(key)
            }
        }

        // ToDos and links, by id.
        var items = Dictionary(grouping: try context.fetch(FetchDescriptor<TodoItem>()), by: \.id)
        for record in snapshot.todos {
            var copies = items.removeValue(forKey: record.id) ?? []
            let item = copies.isEmpty ? nil : copies.removeFirst()
            copies.forEach(context.delete)
            if item == nil || !same(item!, record) {
                let item = item ?? { let new = TodoItem(id: record.id); context.insert(new); return new }()
                fill(item, from: record)
                applied.todosChanged = true
            }
        }
        for item in items.values.joined() {
            context.delete(item)
            applied.todosChanged = true
        }
        var links = Dictionary(grouping: try context.fetch(FetchDescriptor<TodoLink>()), by: \.id)
        for record in snapshot.links {
            var copies = links.removeValue(forKey: record.id) ?? []
            let link = copies.isEmpty ? nil : copies.removeFirst()
            copies.forEach(context.delete)
            if link == nil || !same(link!, record) {
                let link = link ?? { let new = TodoLink(id: record.id); context.insert(new); return new }()
                fill(link, from: record)
                applied.todosChanged = true
            }
        }
        for link in links.values.joined() {
            context.delete(link)
            applied.todosChanged = true
        }

        // Tombstones: one per record, the latest.
        var tombstones = Dictionary(grouping: try context.fetch(FetchDescriptor<SyncTombstone>()), by: { "\($0.kindRaw)|\($0.key)" })
        for deletion in snapshot.deletions {
            var copies = tombstones.removeValue(forKey: deletion.id) ?? []
            if copies.isEmpty {
                context.insert(SyncTombstone(kind: deletion.kind, key: deletion.key, deletedAt: deletion.deletedAt))
                continue
            }
            let kept = copies.removeFirst()
            copies.forEach(context.delete)
            if kept.deletedAt != deletion.deletedAt { kept.deletedAt = deletion.deletedAt }
        }
        // Any left are of kinds this version does not know; they stay.

        if context.hasChanges { try context.save() }
        applied.settings = SyncedSettings.apply(snapshot.settings, in: defaults)
        return applied
    }

    private static func same(_ item: TodoItem, _ record: SyncTodo) -> Bool {
        item.title == record.title && item.isDone == record.isDone && item.scopeRaw == record.scope && item.periodKey == record.periodKey
            && item.order == record.order && item.colorLabel == record.colorLabel && item.sourceNoteID == record.sourceNoteID
            && item.createdAt == record.createdAt && item.updatedAt == record.updatedAt
    }

    private static func fill(_ item: TodoItem, from record: SyncTodo) {
        item.title = record.title
        item.isDone = record.isDone
        item.scopeRaw = record.scope
        item.periodKey = record.periodKey
        item.order = record.order
        item.colorLabel = record.colorLabel
        item.sourceNoteID = record.sourceNoteID
        item.createdAt = record.createdAt
        item.updatedAt = record.updatedAt
    }

    private static func same(_ link: TodoLink, _ record: SyncLink) -> Bool {
        link.todoID == record.todoID && link.scopeRaw == record.scope && link.periodKey == record.periodKey
            && link.order == record.order && link.createdAt == record.createdAt && link.updatedAt == record.updatedAt
    }

    private static func fill(_ link: TodoLink, from record: SyncLink) {
        link.todoID = record.todoID
        link.scopeRaw = record.scope
        link.periodKey = record.periodKey
        link.order = record.order
        link.createdAt = record.createdAt
        link.updatedAt = record.updatedAt
    }
}
