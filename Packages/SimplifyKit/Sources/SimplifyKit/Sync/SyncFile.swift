import Foundation

/// A memo as it travels between devices.
public struct SyncNote: Codable, Hashable, Sendable {
    public var id: UUID
    public var scope: String
    public var periodKey: String
    /// `MemoText`'s encoding, as stored.
    public var body: Data
    public var updatedAt: Date
    /// `SyncMerge.digest` of texts this one grew out of or took in: each text this device wrote
    /// out, and both sides of every merge. Kept by the sync engine, not the store.
    public var history: [String]

    public init(id: UUID, scope: String, periodKey: String, body: Data, updatedAt: Date, history: [String] = []) {
        self.id = id
        self.scope = scope
        self.periodKey = periodKey
        self.body = body
        self.updatedAt = updatedAt
        self.history = history
    }

    public var key: String { "\(scope)|\(periodKey)" }
}

public struct SyncTodo: Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool
    public var scope: String
    public var periodKey: String
    public var order: Double
    public var colorLabel: String?
    public var sourceNoteID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, title: String, isDone: Bool, scope: String, periodKey: String, order: Double,
                colorLabel: String?, sourceNoteID: UUID?, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.scope = scope
        self.periodKey = periodKey
        self.order = order
        self.colorLabel = colorLabel
        self.sourceNoteID = sourceNoteID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct SyncLink: Codable, Hashable, Sendable {
    public var id: UUID
    public var todoID: UUID
    public var scope: String
    public var periodKey: String
    public var order: Double
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, todoID: UUID, scope: String, periodKey: String, order: Double, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.todoID = todoID
        self.scope = scope
        self.periodKey = periodKey
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A tombstone as it travels between devices.
public struct SyncDeletion: Codable, Hashable, Sendable {
    public var kind: SyncKind
    public var key: String
    public var deletedAt: Date

    public init(kind: SyncKind, key: String, deletedAt: Date) {
        self.kind = kind
        self.key = key
        self.deletedAt = deletedAt
    }

    var id: String { "\(kind.rawValue)|\(key)" }
}

/// Everything one device shares: its memos, ToDos, links, tombstones and shared settings.
public struct SyncSnapshot: Codable, Hashable, Sendable {
    public var notes: [SyncNote]
    public var todos: [SyncTodo]
    public var links: [SyncLink]
    public var deletions: [SyncDeletion]
    /// `SyncedSettings` keys.
    public var settings: [String: SyncSetting]

    public init(notes: [SyncNote] = [], todos: [SyncTodo] = [], links: [SyncLink] = [],
                deletions: [SyncDeletion] = [], settings: [String: SyncSetting] = [:]) {
        self.notes = notes
        self.todos = todos
        self.links = links
        self.deletions = deletions
        self.settings = settings
    }

    var withoutHistory: SyncSnapshot {
        var copy = self
        for index in copy.notes.indices { copy.notes[index].history = [] }
        return copy
    }

    /// The same records in one order, so equal snapshots encode to equal bytes.
    var sorted: SyncSnapshot {
        SyncSnapshot(notes: notes.sorted { $0.key < $1.key },
                     todos: todos.sorted { $0.id.uuidString < $1.id.uuidString },
                     links: links.sorted { $0.id.uuidString < $1.id.uuidString },
                     deletions: deletions.sorted { $0.id < $1.id },
                     settings: settings)
    }
}

/// One device's file in the sync folder, `Simplify Sync/<device id>.json`. Each device writes
/// only its own and reads the others'.
public struct SyncFile: Codable, Hashable, Sendable {
    /// Bumped whenever the shape changes in a way an older version cannot read. A file of a format
    /// this version does not know is neither read nor written over.
    public static let currentFormat = 1

    public var format: Int
    public var device: String
    public var data: SyncSnapshot

    public init(device: String, data: SyncSnapshot) {
        format = Self.currentFormat
        self.device = device
        self.data = data
    }

    public enum Contents: Equatable, Sendable {
        case file(SyncFile)
        /// Written by a version that knows another format.
        case unknownFormat(Int)
        /// Not a sync file, or damaged.
        case unreadable
    }

    public static func decode(_ data: Data) -> Contents {
        struct Header: Decodable { var format: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { return .unreadable }
        guard header.format == currentFormat else { return .unknownFormat(header.format) }
        guard let file = try? JSONDecoder().decode(SyncFile.self, from: data) else { return .unreadable }
        return .file(file)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var file = self
        file.data = data.sorted
        return try encoder.encode(file)
    }
}
