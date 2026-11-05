import Foundation
import SwiftData

/// Keeps the diary store and the shared settings in step with other devices through a folder the
/// person picked, normally in iCloud Drive (stage 9; a free developer account has no CloudKit).
///
/// Each device writes `Simplify Sync/<its id>.json` and only reads the others' files. A pass reads
/// them, joins them into the store (`SyncMerge`) and writes this device's file again, so the next
/// device to look finds everything this one knows.
@MainActor
public final class DiarySync {
    public static let folderName = "Simplify Sync"
    static let deviceIDKey = "syncDeviceID"
    /// By memo id (by period before format 2), the history of this device's text (`SyncNote.history`).
    static let historyKey = "syncMemoHistory"
    /// By other device id, then memo id (period before format 2): the digest of that device's text
    /// as last taken in.
    static let takenKey = "syncMemoTaken"
    static let lastSyncedKey = "syncLastSyncedAt"

    public enum Failure: Error, Equatable {
        /// This device's own file was written by a newer version; it is left as it is.
        case newerFormat
    }

    public let deviceID: String
    /// `Simplify Sync` inside the picked folder.
    public let folder: URL
    private let container: ModelContainer
    /// The shared settings, and this device's own sync state beside them.
    private let defaults: UserDefaults
    /// The bytes last written, so an unchanged file is not written again.
    private var lastWritten: Data?
    /// The other devices' files as last taken in (name → modified), so an unchanged folder is not read again.
    private var lastSeen: [String: Date]?
    private var watcher: SyncFolderWatcher?

    /// `chosen` is the folder the person picked; picking `Simplify Sync` itself uses it as it is.
    public init(folder chosen: URL, container: ModelContainer, defaults: UserDefaults) {
        folder = chosen.lastPathComponent == Self.folderName ? chosen : chosen.appending(path: Self.folderName, directoryHint: .isDirectory)
        self.container = container
        self.defaults = defaults
        deviceID = Self.deviceID(in: defaults)
    }

    /// This device's id, made the first time it is asked for and kept in `defaults`.
    public static func deviceID(in defaults: UserDefaults) -> String {
        if let id = defaults.string(forKey: deviceIDKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: deviceIDKey)
        return id
    }

    /// When a pass last finished, for 설정.
    public static func lastSyncedAt(in defaults: UserDefaults) -> Date? {
        defaults.object(forKey: lastSyncedKey) as? Date
    }

    /// Forgets the memos' histories when this device leaves a folder: joining one again counts as
    /// meeting for the first time, so no memo text is lost to an old history.
    public static func forget(in defaults: UserDefaults) {
        defaults.removeObject(forKey: historyKey)
        defaults.removeObject(forKey: takenKey)
        defaults.removeObject(forKey: lastSyncedKey)
    }

    public var ownFile: URL { folder.appending(path: deviceID + ".json") }

    static func history(in defaults: UserDefaults) -> [String: [String]] {
        defaults.dictionary(forKey: historyKey) as? [String: [String]] ?? [:]
    }

    /// The store's records with each memo's history attached.
    private func local() throws -> SyncSnapshot {
        var snapshot = try SyncRecords.read(from: ModelContext(container), defaults: defaults)
        let history = Self.history(in: defaults)
        // Histories from before format 2 are kept under the memo's period.
        for index in snapshot.notes.indices {
            let note = snapshot.notes[index]
            snapshot.notes[index].history = history[note.key] ?? history[note.periodSlot] ?? []
        }
        return snapshot
    }

    // MARK: Passes

    /// Reads the other devices' files, takes in what they changed, and writes this device's file.
    /// `prepare` runs just before the store is read (to save letters still being typed); returning
    /// false puts the pass off, taking in and writing nothing, and the result is nil. `took` runs
    /// right after the store changed, before anything else can, so the screen shows the new
    /// records before another edit is made over the old ones. Without `force`, a folder whose
    /// other files are as they were last time is not read again (nor `prepare` run).
    @discardableResult
    public func sync(now: Date = .now, force: Bool = false, prepare: () -> Bool = { true },
                     took: (SyncRecords.Applied) -> Void = { _ in }) async throws -> SyncRecords.Applied? {
        let folder = folder, own = ownFile.lastPathComponent, seen = force ? nil : lastSeen, presenter = watcher
        let found = try await Task.detached { try Self.readOthers(in: folder, except: own, unlessUnchangedFrom: seen, presenter: presenter) }.value
        var applied = SyncRecords.Applied()
        if let found {
            guard prepare() else { return nil }
            let local = try local()
            var merged = local
            var taken = defaults.dictionary(forKey: Self.takenKey) as? [String: [String: String]] ?? [:]
            for file in found.files.sorted(by: { $0.device < $1.device }) {
                merged = SyncMerge.merge(local: merged, localDevice: deviceID, remote: file.data, remoteDevice: file.device,
                                         taken: taken[file.device] ?? [:], now: now)
                taken[file.device] = Dictionary(file.data.notes.map { ($0.key, SyncMerge.digest($0.body)) }, uniquingKeysWith: { a, _ in a })
            }
            // Histories alone are not worth a pass over the store.
            if merged.withoutHistory != local.withoutHistory { applied = try SyncRecords.apply(merged, to: ModelContext(container), defaults: defaults) }
            // After the store: a crash in between only leaves a history shorter than it could be.
            defaults.set(Dictionary(merged.notes.map { ($0.key, $0.history) }, uniquingKeysWith: { a, _ in a }), forKey: Self.historyKey)
            defaults.set(taken, forKey: Self.takenKey)
            lastSeen = found.fingerprint
            if !applied.isEmpty { took(applied) }
        }
        try await push()
        defaults.set(now, forKey: Self.lastSyncedKey)
        return applied
    }

    /// Writes this device's file if what it shares changed since the last write.
    public func push() async throws {
        guard let (data, history) = try fileToWrite() else { return }
        let url = ownFile, presenter = watcher
        try await Task.detached { try Self.write(data, to: url, presenter: presenter) }.value
        wrote(data, history)
    }

    /// `push` without leaving the main thread, for the app quitting.
    public func pushNow() throws {
        guard let (data, history) = try fileToWrite() else { return }
        try Self.write(data, to: ownFile, presenter: watcher)
        wrote(data, history)
    }

    /// This device's file as it would be written now, or nil when it is what was written last.
    /// Each memo's text joins its history as it goes out: later edits here grow out of it.
    private func fileToWrite() throws -> (Data, [String: [String]])? {
        var snapshot = try local()
        for index in snapshot.notes.indices {
            snapshot.notes[index].history = SyncMerge.remembered(snapshot.notes[index].history + [SyncMerge.digest(snapshot.notes[index].body)])
        }
        let data = try SyncFile(device: deviceID, data: snapshot).encoded()
        guard data != lastWritten else { return nil }
        return (data, Dictionary(snapshot.notes.map { ($0.key, $0.history) }, uniquingKeysWith: { a, _ in a }))
    }

    private func wrote(_ data: Data, _ history: [String: [String]]) {
        lastWritten = data
        // What was written joins what is stored (a merge may have added to it meanwhile); memos
        // not in the file are gone and lose theirs.
        var stored = Self.history(in: defaults)
        for (key, digests) in history { stored[key] = SyncMerge.remembered((stored[key] ?? []) + digests) }
        defaults.set(stored.filter { history[$0.key] != nil }, forKey: Self.historyKey)
    }

    // MARK: Watching

    /// Calls `onChange` when something in the folder changes: another device's file arriving
    /// through iCloud Drive, or a file put there by hand. This device's own writes are reported by
    /// the folder watch too; the pass that follows finds the other files unchanged and reads nothing.
    public func startWatching(_ onChange: @escaping @MainActor () -> Void) {
        stopWatching()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let watcher = SyncFolderWatcher(folder: folder) {
            DispatchQueue.main.async { MainActor.assumeIsolated { onChange() } }
        }
        watcher.start()
        self.watcher = watcher
    }

    public func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    // MARK: Files

    struct Found: Sendable {
        var files: [SyncFile]
        var fingerprint: [String: Date]
    }

    /// The other devices' files, or nil when the folder holds the same files as `lastSeen`. Files
    /// iCloud Drive has not brought down yet are asked for and skipped this time.
    nonisolated static func readOthers(in folder: URL, except own: String, unlessUnchangedFrom lastSeen: [String: Date]?,
                                       presenter: SyncFolderWatcher?) throws -> Found? {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .ubiquitousItemDownloadingStatusKey]
        var fingerprint: [String: Date] = [:]
        var readable: [URL] = []
        for url in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) {
            let name = url.lastPathComponent
            // An older iCloud Drive leaves `.<name>.icloud` in place of a file not downloaded.
            if name.hasPrefix("."), name.hasSuffix(".json.icloud") {
                let real = String(name.dropFirst().dropLast(".icloud".count))
                if real != own { try? fm.startDownloadingUbiquitousItem(at: folder.appending(path: real)) }
                continue
            }
            guard name.hasSuffix(".json"), name != own else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.ubiquitousItemDownloadingStatus == .notDownloaded {
                try? fm.startDownloadingUbiquitousItem(at: url)
                continue
            }
            fingerprint[name] = values?.contentModificationDate ?? .distantPast
            readable.append(url)
        }
        if let lastSeen, lastSeen == fingerprint { return nil }
        var files: [SyncFile] = []
        for url in readable {
            var data: Data?
            var error: NSError?
            NSFileCoordinator(filePresenter: presenter).coordinate(readingItemAt: url, options: [], error: &error) { data = try? Data(contentsOf: $0) }
            // Another device's id only: a copy of this device's file under another name is not taken in.
            if let data, case .file(let file) = SyncFile.decode(data), file.device + ".json" != own { files.append(file) }
        }
        return Found(files: files, fingerprint: fingerprint)
    }

    /// Replaces this device's file in one step. A file there in a format this version does not
    /// know (a newer version of the app wrote it) is left alone.
    nonisolated static func write(_ data: Data, to url: URL, presenter: SyncFolderWatcher?) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordination: NSError?
        var failure: (any Error)?
        NSFileCoordinator(filePresenter: presenter).coordinate(writingItemAt: url, options: .forReplacing, error: &coordination) { url in
            if let old = try? Data(contentsOf: url), case .unknownFormat = SyncFile.decode(old) {
                failure = Failure.newerFormat
                return
            }
            do { try data.write(to: url, options: .atomic) } catch { failure = error }
        }
        if let error = coordination ?? failure { throw error }
    }
}

/// Reports changes in the sync folder: as a file presenter, which iCloud Drive tells when it
/// brings down another device's file, and by watching the folder itself, which also catches a file
/// moved in by hand (and this device's own writes, which the presenter alone would skip).
public final class SyncFolderWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    public let presentedItemURL: URL?
    public let presentedItemOperationQueue = OperationQueue()
    private let onChange: @Sendable () -> Void
    private var source: (any DispatchSourceFileSystemObject)?

    init(folder: URL, onChange: @escaping @Sendable () -> Void) {
        presentedItemURL = folder
        self.onChange = onChange
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
    }

    func start() {
        NSFileCoordinator.addFilePresenter(self)
        guard let path = presentedItemURL?.path else { return }
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .global())
        let onChange = onChange
        source.setEventHandler { onChange() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        NSFileCoordinator.removeFilePresenter(self)
        source?.cancel()
        source = nil
    }

    public func presentedItemDidChange() { onChange() }
    public func presentedSubitemDidChange(at url: URL) { onChange() }
    public func presentedSubitemDidAppear(at url: URL) { onChange() }
}
