import Foundation
import SwiftData

/// Moves records between the diary store (and the shared settings) and a `SyncSnapshot`.
public enum SyncRecords {
    /// What taking a merged snapshot in changed on this device.
    public struct Applied: Equatable, Sendable {
        /// Every memo whose text or name arrived, changed or went, by id.
        public var notes: Set<UUID> = []
        /// The periods (`SyncKey.note`) those memos belong to, before and after.
        public var periods: Set<String> = []
        /// Any ToDo or link changed.
        public var todosChanged = false
        /// `SyncedSettings` keys whose value changed.
        public var settings: Set<String> = []

        public init() {}

        public var isEmpty: Bool { notes.isEmpty && !todosChanged && settings.isEmpty }
    }

    /// Everything this device shares, as stored now.
    public static func read(from context: ModelContext, defaults: UserDefaults) throws -> SyncSnapshot {
        // Every memo, with or without words (one may be kept for its name). Two copies of one id
        // (never made here) go as the newest.
        var notes: [UUID: SyncNote] = [:]
        for note in try context.fetch(FetchDescriptor<DiaryNote>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])) where notes[note.id] == nil {
            notes[note.id] = SyncNote(id: note.id, scope: note.scopeRaw, periodKey: note.periodKey, body: note.body ?? Data(),
                                      updatedAt: note.updatedAt, title: note.title, createdAt: note.createdAt)
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

        // Memos, by id.
        let wanted = Dictionary(snapshot.notes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var stored = Dictionary(grouping: try context.fetch(FetchDescriptor<DiaryNote>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])),
                                by: \.id)
        for record in wanted.values {
            var copies = stored.removeValue(forKey: record.id) ?? []
            let note = copies.isEmpty ? nil : copies.removeFirst()
            copies.forEach(context.delete)
            let body = record.body.isEmpty ? nil : record.body
            if let note {
                // A new creation time moves the memo among its period's tabs.
                if note.body != body || note.title != record.title || note.scopeRaw != record.scope || note.periodKey != record.periodKey
                    || note.createdAt != record.createdAt {
                    applied.notes.insert(record.id)
                    applied.periods.insert("\(note.scopeRaw)|\(note.periodKey)")
                    applied.periods.insert(record.periodSlot)
                }
                if note.body != body { note.body = body }
                if note.title != record.title { note.title = record.title }
                if note.scopeRaw != record.scope { note.scopeRaw = record.scope }
                if note.periodKey != record.periodKey { note.periodKey = record.periodKey }
                if note.updatedAt != record.updatedAt { note.updatedAt = record.updatedAt }
                if note.createdAt != record.createdAt { note.createdAt = record.createdAt }
            } else {
                let note = DiaryNote(id: record.id, scopeRaw: record.scope, periodKey: record.periodKey)
                note.body = body
                note.title = record.title
                note.createdAt = record.createdAt
                note.updatedAt = record.updatedAt
                context.insert(note)
                applied.notes.insert(record.id)
                applied.periods.insert(record.periodSlot)
            }
        }
        for (id, notes) in stored {
            notes.forEach(context.delete)
            applied.notes.insert(id)
            notes.forEach { applied.periods.insert("\($0.scopeRaw)|\($0.periodKey)") }
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
