import Foundation
import SwiftData

/// Opens the diary store (memos and ToDos) that the app and widgets share.
///
/// It lives in the App Group container so widgets read the same file. CloudKit stays off
/// until a paid developer account exists.
public enum SimplifyStore {
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try makeContainer(url: inMemory ? nil : storeURL())
    }

    /// The diary store at `url`, or in memory for nil. Older files are brought up to the current
    /// schema on opening.
    static func makeContainer(url: URL?) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = if let url {
            ModelConfiguration("Diary", schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            ModelConfiguration("Diary", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: SimplifyMigrationPlan.self, configurations: configuration)
    }

    /// The local copy of the calendar providers' data, beside the diary store. Never synced to
    /// iCloud; deleting it only costs a full re-download.
    public static func makeCacheContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CacheSchemaV1.self)
        let configuration = inMemory
            ? ModelConfiguration("Cache", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration("Cache", schema: schema, url: try storeURL(named: "Cache.store"), cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Opens the calendar cache. If the file cannot be opened (damaged, or a model change without a
    /// migration), it is moved aside as `Cache.store.broken` and a new one is made: events download
    /// again, but connected accounts have to be added again too, since the account list lives here.
    /// Only if that also fails does the app run on an in-memory cache.
    public static func openCache() -> ModelContainer {
        if let container = try? makeCacheContainer() { return container }
        if let url = try? storeURL(named: "Cache.store") {
            let fm = FileManager.default
            for suffix in ["", "-shm", "-wal"] {
                let file = URL(fileURLWithPath: url.path + suffix)
                let aside = URL(fileURLWithPath: url.path + ".broken" + suffix)
                try? fm.removeItem(at: aside)
                try? fm.moveItem(at: file, to: aside)
            }
            if let container = try? makeCacheContainer() { return container }
        }
        return try! makeCacheContainer(inMemory: true)
    }

    /// `<App Group>/Library/Application Support/<name>`, or the app's own Application Support
    /// folder when the build has no App Group (unsigned builds).
    static func storeURL(named name: String = "Diary.store") throws -> URL {
        let base = AppGroup.containerURL()?.appending(path: "Library/Application Support", directoryHint: .isDirectory)
            ?? URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: name)
    }
}
