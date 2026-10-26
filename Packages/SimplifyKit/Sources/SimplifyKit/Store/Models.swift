import Foundation
import SwiftData

// Every stored property has a default and nothing is unique: CloudKit's rules,
// so iCloud sync can be switched on later without a migration.

/// The memo for one day, week or month.
@Model
public final class DiaryNote {
    public var id: UUID = UUID()
    public var scopeRaw: String = PeriodScope.day.rawValue
    public var periodKey: String = ""
    /// Rich text, encoded by the memo editor (stage 5). Kept outside the record (a CKAsset under
    /// CloudKit) so long memos stay clear of the 1 MB record limit.
    @Attribute(.externalStorage) public var body: Data?
    public var updatedAt: Date = Date.now

    public init(period: Period) {
        scopeRaw = period.scope.rawValue
        periodKey = period.key
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

    public init(title: String, period: Period, order: Double) {
        self.title = title
        scopeRaw = period.scope.rawValue
        periodKey = period.key
        self.order = order
    }

    public var scope: PeriodScope { PeriodScope(rawValue: scopeRaw) ?? .day }

    public static func descriptor(for period: Period) -> FetchDescriptor<TodoItem> {
        let key = period.key
        return FetchDescriptor(predicate: #Predicate { $0.periodKey == key }, sortBy: [SortDescriptor(\.order)])
    }
}

/// Version 1 lists the live model classes. Before changing a model for V2, copy these classes
/// into this enum as they are, so V1 keeps describing the shape already on disk.
public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { [DiaryNote.self, TodoItem.self] }
}

public enum SimplifyMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
