import Foundation
import SwiftData

// Every stored property has a default and nothing is unique: CloudKit's rules,
// so iCloud sync can be switched on later without a migration.

/// One memo of a day, week or month; a period may have several (`Memos`).
@Model
public final class DiaryNote {
    public var id: UUID = UUID()
    public var scopeRaw: String = PeriodScope.day.rawValue
    public var periodKey: String = ""
    /// Rich text, encoded by the memo editor (stage 5). Kept outside the record (a CKAsset under
    /// CloudKit) so long memos stay clear of the 1 MB record limit.
    @Attribute(.externalStorage) public var body: Data?
    public var updatedAt: Date = Date.now
    /// The name on its tab, as typed or given (`새 메모(1)`); empty for a memo from before a period
    /// could have several, which shows as `새 메모` and keeps its date-only name in the 메모 app.
    public var title: String = ""
    /// When it was made, for the order of the period's tabs. Memos from before V4 all get the
    /// moment the store was brought up to it.
    public var createdAt: Date = Date.now

    public init(period: Period, title: String = "", createdAt: Date = .now) {
        scopeRaw = period.scope.rawValue
        periodKey = period.key
        self.title = title
        self.createdAt = createdAt
    }

    /// A memo another device wrote, by its stored names.
    init(id: UUID, scopeRaw: String, periodKey: String) {
        self.id = id
        self.scopeRaw = scopeRaw
        self.periodKey = periodKey
    }

    public var scope: PeriodScope { PeriodScope(rawValue: scopeRaw) ?? .day }

    public static func descriptor(for period: Period) -> FetchDescriptor<DiaryNote> {
        let key = period.key
        return FetchDescriptor(predicate: #Predicate { $0.periodKey == key })
    }
}

/// A ToDo filed under one day, week or month.
@Model
public final class TodoItem {
    public var id: UUID = UUID()
    public var title: String = ""
    public var isDone: Bool = false
    public var scopeRaw: String = PeriodScope.day.rawValue
    public var periodKey: String = ""
    /// Position within its period; fractional so a row can move between two others.
    public var order: Double = 0
    /// A `Palette` raw value, or nil for no label.
    public var colorLabel: String?
    /// The memo it was made from, if any.
    public var sourceNoteID: UUID?
    public var createdAt: Date = Date.now
    /// The last change, so another device's copy can be told older or newer (stage 9).
    public var updatedAt: Date = Date.now

    public init(title: String, period: Period, order: Double) {
        self.title = title
        scopeRaw = period.scope.rawValue
        periodKey = period.key
        self.order = order
    }

    /// A ToDo another device made; `SyncRecords` fills in the rest.
    init(id: UUID) {
        self.id = id
    }

    public var scope: PeriodScope { PeriodScope(rawValue: scopeRaw) ?? .day }

    public static func descriptor(for period: Period) -> FetchDescriptor<TodoItem> {
        let key = period.key
        return FetchDescriptor(predicate: #Predicate { $0.periodKey == key }, sortBy: [SortDescriptor(\.order)])
    }
}

/// One more place a ToDo shows up besides its own period: "잇기" files the same ToDo under another
/// day, week or month, so ticking it anywhere ticks it everywhere. Points at the ToDo by id rather
/// than a relationship, which keeps CloudKit's rules simple; a link whose ToDo is gone (a sync
/// race) is ignored.
@Model
public final class TodoLink {
    public var id: UUID = UUID()
    public var todoID: UUID = UUID()
    public var scopeRaw: String = PeriodScope.day.rawValue
    public var periodKey: String = ""
    /// Position among that period's rows, in the same order space as `TodoItem.order`.
    public var order: Double = 0
    public var createdAt: Date = Date.now
    /// The last move, as on `TodoItem` (stage 9).
    public var updatedAt: Date = Date.now

    public init(todoID: UUID, period: Period, order: Double) {
        self.todoID = todoID
        scopeRaw = period.scope.rawValue
        periodKey = period.key
        self.order = order
    }

    /// A link another device made; `SyncRecords` fills in the rest.
    init(id: UUID) {
        self.id = id
    }

    public var scope: PeriodScope { PeriodScope(rawValue: scopeRaw) ?? .day }
}

/// Something deleted on this device or another, kept with the time it went so a copy still on
/// another device is not brought back by the next sync (stage 9). `key` is a ToDo's, link's or
/// memo's id; tombstones from before V4 name a memo by its period (`SyncKey.note`).
@Model
public final class SyncTombstone {
    public var kindRaw: String = SyncKind.todo.rawValue
    public var key: String = ""
    public var deletedAt: Date = Date.now

    public init(kind: SyncKind, key: String, deletedAt: Date) {
        kindRaw = kind.rawValue
        self.key = key
        self.deletedAt = deletedAt
    }

    public var kind: SyncKind? { SyncKind(rawValue: kindRaw) }
}

/// What a tombstone stands for.
public enum SyncKind: String, Codable, Sendable, CaseIterable {
    case note, todo, link
}

/// Version 1, frozen as it shipped in stage 5 so it keeps describing the shape already on disk.
/// Never edit these classes; change the live ones and add a version instead.
public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { [DiaryNote.self, TodoItem.self] }

    @Model
    public final class DiaryNote {
        public var id: UUID = UUID()
        public var scopeRaw: String = PeriodScope.day.rawValue
        public var periodKey: String = ""
        @Attribute(.externalStorage) public var body: Data?
        public var updatedAt: Date = Date.now

        public init(period: Period) {
            scopeRaw = period.scope.rawValue
            periodKey = period.key
        }
    }

    @Model
    public final class TodoItem {
        public var id: UUID = UUID()
        public var title: String = ""
        public var isDone: Bool = false
        public var scopeRaw: String = PeriodScope.day.rawValue
        public var periodKey: String = ""
        public var order: Double = 0
        public var colorLabel: String?
        public var sourceNoteID: UUID?
        public var createdAt: Date = Date.now

        public init(title: String, period: Period, order: Double) {
            self.title = title
            scopeRaw = period.scope.rawValue
            periodKey = period.key
            self.order = order
        }
    }
}

/// Version 2 (stage 6) adds `TodoLink`; notes and ToDos keep their shape. Frozen as it shipped,
/// like `SchemaV1`.
public enum SchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)
    public static var models: [any PersistentModel.Type] { [DiaryNote.self, TodoItem.self, TodoLink.self] }

    @Model
    public final class DiaryNote {
        public var id: UUID = UUID()
        public var scopeRaw: String = PeriodScope.day.rawValue
        public var periodKey: String = ""
        @Attribute(.externalStorage) public var body: Data?
        public var updatedAt: Date = Date.now

        public init(period: Period) {
            scopeRaw = period.scope.rawValue
            periodKey = period.key
        }
    }

    @Model
    public final class TodoItem {
        public var id: UUID = UUID()
        public var title: String = ""
        public var isDone: Bool = false
        public var scopeRaw: String = PeriodScope.day.rawValue
        public var periodKey: String = ""
        public var order: Double = 0
        public var colorLabel: String?
        public var sourceNoteID: UUID?
        public var createdAt: Date = Date.now

        public init(title: String, period: Period, order: Double) {
            self.title = title
            scopeRaw = period.scope.rawValue
            periodKey = period.key
            self.order = order
        }
    }

    @Model
    public final class TodoLink {
        public var id: UUID = UUID()
        public var todoID: UUID = UUID()
        public var scopeRaw: String = PeriodScope.day.rawValue
        public var periodKey: String = ""
        public var order: Double = 0
        public var createdAt: Date = Date.now

        public init(todoID: UUID, period: Period, order: Double) {
            self.todoID = todoID
            scopeRaw = period.scope.rawValue
            periodKey = period.key
            self.order = order
        }
    }
}

/// Version 3 (stage 9, syncing through an iCloud Drive folder) gives ToDos and links `updatedAt`
/// and adds `SyncTombstone`. Frozen as it shipped, like `SchemaV1`.
public enum SchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)
    public static var models: [any PersistentModel.Type] { [DiaryNote.self, TodoItem.self, TodoLink.self, SyncTombstone.self] }

    @Model
    public final class DiaryNote {
        public var id: UUID = UUID()
        public var scopeRaw: String = PeriodScope.day.rawValue
        public var periodKey: String = ""
        @Attribute(.externalStorage) public var body: Data?
        public var updatedAt: Date = Date.now

        public init(period: Period) {
            scopeRaw = period.scope.rawValue
            periodKey = period.key
        }
    }

    @Model
    public final class TodoItem {
        public var id: UUID = UUID()
        public var title: String = ""
        public var isDone: Bool = false
        public var scopeRaw: String = PeriodScope.day.rawValue
        public var periodKey: String = ""
        public var order: Double = 0
        public var colorLabel: String?
        public var sourceNoteID: UUID?
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public init(title: String, period: Period, order: Double) {
            self.title = title
            scopeRaw = period.scope.rawValue
            periodKey = period.key
            self.order = order
        }
    }

    @Model
    public final class TodoLink {
        public var id: UUID = UUID()
        public var todoID: UUID = UUID()
        public var scopeRaw: String = PeriodScope.day.rawValue
        public var periodKey: String = ""
        public var order: Double = 0
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public init(todoID: UUID, period: Period, order: Double) {
            self.todoID = todoID
            scopeRaw = period.scope.rawValue
            periodKey = period.key
            self.order = order
        }
    }

    @Model
    public final class SyncTombstone {
        public var kindRaw: String = SyncKind.todo.rawValue
        public var key: String = ""
        public var deletedAt: Date = Date.now

        public init(kind: SyncKind, key: String, deletedAt: Date) {
            kindRaw = kind.rawValue
            self.key = key
            self.deletedAt = deletedAt
        }
    }
}

/// Version 4 lets a period have several memos: `DiaryNote` gets `title` and `createdAt`. The
/// live classes.
public enum SchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)
    public static var models: [any PersistentModel.Type] { [DiaryNote.self, TodoItem.self, TodoLink.self, SyncTombstone.self] }
}

public enum SimplifyMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self] }
    /// New entities and new attributes with defaults: SwiftData adds them and leaves every row as it was.
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
         .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
         .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self)]
    }
}
