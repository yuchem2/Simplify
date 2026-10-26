import Foundation
import SwiftData

/// Opens the diary store (memos and ToDos) that the app and widgets share.
///
/// It lives in the App Group container so widgets read the same file. CloudKit stays off
/// until a paid developer account exists; the calendar cache gets its own, never-synced
/// configuration when stage 2 adds its models.
public enum SimplifyStore {
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = inMemory
            ? ModelConfiguration("Diary", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration("Diary", schema: schema, url: try storeURL(), cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: SimplifyMigrationPlan.self, configurations: configuration)
    }

    /// `<App Group>/Library/Application Support/Diary.store`, or the app's own
    /// Application Support folder when the build has no App Group (unsigned builds).
    static func storeURL() throws -> URL {
        let base = AppGroup.containerURL()?.appending(path: "Library/Application Support", directoryHint: .isDirectory)
            ?? URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: "Diary.store")
    }
}
