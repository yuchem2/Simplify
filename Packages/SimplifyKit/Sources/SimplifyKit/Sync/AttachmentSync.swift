import Foundation

/// Keeps attached files in step between devices, beside the memos (`DiarySync`): each device
/// copies its files to `Simplify Sync/Attachments/<id>/<name>` and brings down the ones its memos
/// use and it lacks. An attachment cleared away leaves `<id>.deleted` there, so the others clear
/// theirs. The devices' own `<device>.json` files are not changed by it.
///
/// The memos are the truth, as they are synced first: an attachment some memo here uses is kept
/// (and its marks taken back), whatever was marked; one marked and used by no memo here goes.
public enum AttachmentSync {
    /// What one pass does. Pure: no files.
    public struct Plan: Equatable, Sendable {
        /// Copied into the sync folder.
        public var upload: Set<String> = []
        /// Copied from the sync folder.
        public var download: Set<String> = []
        /// Removed here, and from the sync folder.
        public var removeLocal: Set<String> = []
        public var removeRemote: Set<String> = []
        /// `<id>.deleted` written here or there.
        public var markLocal: Set<String> = []
        public var markRemote: Set<String> = []
        /// `<id>.deleted` taken back: the attachment is in use again.
        public var unmarkLocal: Set<String> = []
        public var unmarkRemote: Set<String> = []

        public init() {}
    }

    /// `referenced`: ids the memos here use. `local` / `remote`: ids whose file is here / in the
    /// sync folder (brought down or not). The marks likewise.
    public static func plan(referenced: Set<String>, local: Set<String>, localMarks: Set<String>,
                            remote: Set<String>, remoteMarks: Set<String>) -> Plan {
        var plan = Plan()
        for id in referenced {
            if localMarks.contains(id) { plan.unmarkLocal.insert(id) }
            if remoteMarks.contains(id) { plan.unmarkRemote.insert(id) }
            if local.contains(id), !remote.contains(id) { plan.upload.insert(id) }
            if !local.contains(id), remote.contains(id) { plan.download.insert(id) }
        }
        for id in localMarks.union(remoteMarks) where !referenced.contains(id) {
            if local.contains(id) { plan.removeLocal.insert(id) }
            if remote.contains(id) { plan.removeRemote.insert(id) }
            if !localMarks.contains(id) { plan.markLocal.insert(id) }
            if !remoteMarks.contains(id) { plan.markRemote.insert(id) }
        }
        return plan
    }

    /// How attachments stand after a pass.
    public struct Report: Equatable, Sendable {
        /// Used here, not here yet, and in the sync folder: on its way.
        public var waiting: Set<String> = []
        /// Brought down or cleared away by this pass, so their cards are drawn again.
        public var changed: Set<String> = []

        public init() {}
    }

    /// One pass between the store here and `Simplify Sync/Attachments`. `referenced` holds the
    /// memos' attachments by id. `uploadsOnly` copies this device's files up and does nothing
    /// else, for the pass before the other devices' memos are read (which may still use a file
    /// marked here, or no longer use one sent from there). A file that cannot be copied is left
    /// for the next pass; the rest goes on. Off the main thread: copying can take a while.
    public static func pass(store: AttachmentStore, syncFolder: URL, referenced: [String: MemoAttachments.Ref],
                            uploadsOnly: Bool = false) throws -> Report {
        let fm = FileManager.default
        let remoteRoot = syncFolder.appending(path: AttachmentStore.folderName, directoryHint: .isDirectory)
        try fm.createDirectory(at: remoteRoot, withIntermediateDirectories: true)
        let here = AttachmentStore.list(store.root)
        let there = AttachmentStore.list(remoteRoot)
        var plan = plan(referenced: Set(referenced.keys), local: here.downloaded, localMarks: here.marks, remote: there.ids, remoteMarks: there.marks)
        if uploadsOnly {
            var upload = Plan()
            upload.upload = plan.upload
            plan = upload
        }
        let remote = AttachmentStore(root: remoteRoot)
        var report = Report()
        for id in plan.upload {
            guard let ref = referenced[id] else { continue }
            try? copy(store.url(for: ref), to: remote.url(for: ref))
        }
        for id in plan.download {
            guard let ref = referenced[id] else { continue }
            let source = remote.url(for: ref)
            if there.downloaded.contains(id), fm.fileExists(atPath: source.path) {
                guard (try? copy(source, to: store.url(for: ref))) != nil else { continue }
                report.changed.insert(id)
            } else {
                // Asked for; the folder watch brings the next pass when it is down.
                try? fm.startDownloadingUbiquitousItem(at: source)
                report.waiting.insert(id)
            }
        }
        for id in plan.removeLocal {
            try? fm.removeItem(at: store.root.appending(path: id, directoryHint: .isDirectory))
            report.changed.insert(id)
        }
        for id in plan.removeRemote { coordinatedRemove(remoteRoot.appending(path: id, directoryHint: .isDirectory)) }
        plan.markLocal.forEach(store.mark)
        plan.markRemote.forEach(remote.mark)
        plan.unmarkLocal.forEach(store.unmark)
        plan.unmarkRemote.forEach(remote.unmark)
        return report
    }

    /// `source` copied whole to `target`, through a file coordinator so iCloud Drive sees one change.
    static func copy(_ source: URL, to target: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordination: NSError?
        var failure: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], writingItemAt: target, options: .forReplacing, error: &coordination) { from, to in
            do {
                let temporary = to.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).part")
                try fm.copyItem(at: from, to: temporary)
                if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
                try fm.moveItem(at: temporary, to: to)
            } catch {
                failure = error
            }
        }
        if let error = coordination ?? failure { throw error }
    }

    static func coordinatedRemove(_ url: URL) {
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { try? FileManager.default.removeItem(at: $0) }
    }
}
