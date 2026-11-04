import Foundation

/// The attached files on this device: `<root>/<id>/<original name>`, normally in the App Group
/// container's `Attachments` folder. Beside them, `<id>.deleted` marks one cleared away (so other
/// devices clear theirs, `AttachmentSync`) and `.pending.json` the unused ones still waiting
/// (`MemoAttachments.sweep`). It never touches the diary store.
public struct AttachmentStore: Sendable {
    public static let folderName = "Attachments"
    static let deletedSuffix = ".deleted"
    static let pendingName = ".pending.json"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `Attachments` in the App Group container; nil when the build has no group.
    public static func shared() -> AttachmentStore? {
        AppGroup.containerURL().map { AttachmentStore(root: $0.appending(path: folderName, directoryHint: .isDirectory)) }
    }

    public enum Failure: Error, Equatable {
        case tooLarge
        case unreadable
    }

    public func url(for ref: MemoAttachments.Ref) -> URL {
        root.appending(path: ref.id, directoryHint: .isDirectory).appending(path: ref.name)
    }

    public func exists(_ ref: MemoAttachments.Ref) -> Bool {
        FileManager.default.fileExists(atPath: url(for: ref).path)
    }

    /// The file's size in bytes, or nil when it is not here.
    public func size(_ ref: MemoAttachments.Ref) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url(for: ref).path)[.size] as? NSNumber)?.int64Value
    }

    /// A copy of the file at `source` under a new id. Over the size limit it is refused.
    public func add(copying source: URL) throws -> MemoAttachments.Ref {
        let values = try? source.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .totalFileAllocatedSizeKey])
        if values?.isDirectory == true { throw Failure.unreadable }
        guard let size = values?.fileSize else { throw Failure.unreadable }
        guard Int64(size) <= MemoAttachments.limit else { throw Failure.tooLarge }
        let ref = MemoAttachments.Ref(id: UUID().uuidString, name: Self.safeName(source.lastPathComponent))
        try FileManager.default.createDirectory(at: url(for: ref).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: url(for: ref))
        return ref
    }

    /// `data` as a new file named `name`, for a pasted picture.
    public func add(data: Data, name: String) throws -> MemoAttachments.Ref {
        guard Int64(data.count) <= MemoAttachments.limit else { throw Failure.tooLarge }
        let ref = MemoAttachments.Ref(id: UUID().uuidString, name: Self.safeName(name))
        try FileManager.default.createDirectory(at: url(for: ref).deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url(for: ref), options: .atomic)
        return ref
    }

    /// A name that stays one file: no slashes, not hidden, not empty.
    static func safeName(_ name: String) -> String {
        var name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while name.hasPrefix(".") { name.removeFirst() }
        return name.isEmpty ? "첨부" : name
    }

    /// Every attachment folder here.
    public func ids() -> Set<String> {
        Self.list(root).ids
    }

    public func marks() -> Set<String> {
        Self.list(root).marks
    }

    /// Removes the attachment's folder and leaves the mark that tells other devices.
    public func clear(_ id: String) {
        try? FileManager.default.removeItem(at: root.appending(path: id, directoryHint: .isDirectory))
        mark(id)
    }

    /// Through a file coordinator, as the marks also live in the iCloud Drive folder.
    public func mark(_ id: String) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: id + Self.deletedSuffix)
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error) { try? Data().write(to: $0) }
    }

    public func unmark(_ id: String) {
        let url = root.appending(path: id + Self.deletedSuffix)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { try? FileManager.default.removeItem(at: $0) }
    }

    /// Attachments no memo uses are removed once their wait is over (`MemoAttachments.sweep`).
    /// `referenced` nil (a memo could not be read) removes nothing. Returns the ids removed.
    @discardableResult
    public func sweep(referenced: Set<String>?, launch: String, now: Date = .now) -> Set<String> {
        guard let referenced else { return [] }
        let stored = ids()
        let pendingURL = root.appending(path: Self.pendingName)
        let pending = (try? Data(contentsOf: pendingURL)).flatMap { try? JSONDecoder().decode([String: MemoAttachments.Pending].self, from: $0) } ?? [:]
        let result = MemoAttachments.sweep(stored: stored, referenced: referenced, pending: pending, launch: launch, now: now)
        result.remove.forEach(clear)
        // One in use again (undo brought it back) is no longer cleared away elsewhere either.
        for id in marks() where referenced.contains(id) && stored.contains(id) { unmark(id) }
        if result.pending != pending {
            if result.pending.isEmpty {
                try? FileManager.default.removeItem(at: pendingURL)
            } else if let data = try? JSONEncoder().encode(result.pending) {
                try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try? data.write(to: pendingURL, options: .atomic)
            }
        }
        return result.remove
    }

    /// What a folder laid out like this one holds: attachment folders (by UUID name) with a file
    /// in them, the ones whose file is here in full (not an iCloud Drive placeholder still to be
    /// brought down), and the `<id>.deleted` marks.
    static func list(_ folder: URL) -> (ids: Set<String>, downloaded: Set<String>, marks: Set<String>) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return ([], [], []) }
        var ids: Set<String> = [], downloaded: Set<String> = [], marks: Set<String> = []
        for name in names {
            if name.hasSuffix(deletedSuffix) {
                let id = String(name.dropLast(deletedSuffix.count))
                if UUID(uuidString: id) != nil { marks.insert(id) }
                continue
            }
            guard UUID(uuidString: name) != nil else { continue }
            let inside = folder.appending(path: name, directoryHint: .isDirectory)
            for file in (try? fm.contentsOfDirectory(at: inside, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey])) ?? [] {
                let fileName = file.lastPathComponent
                // An older iCloud Drive leaves `.<name>.icloud` for a file not brought down.
                if fileName.hasPrefix("."), fileName.hasSuffix(".icloud") {
                    ids.insert(name)
                    continue
                }
                guard !fileName.hasPrefix(".") else { continue }
                ids.insert(name)
                let status = (try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
                if status == nil || status == .current || status == .downloaded { downloaded.insert(name) }
            }
        }
        return (ids, downloaded, marks)
    }
}
