import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI
import SimplifyKit

/// 설정 › 일반 › iCloud Drive로 기기끼리 맞추기: memos, ToDos and the shared settings kept in step
/// with this person's other devices through a folder they picked in iCloud Drive (`DiarySync`).
///
/// A change made here is written out a few seconds later; other devices' files are read when
/// Simplify comes to the front and whenever the folder changes. The folder (kept as a
/// security-scoped bookmark) is this Mac's own choice.
@MainActor
@Observable
final class DeviceSync {
    static let shared = DeviceSync()

    enum Problem: Equatable {
        /// The picked folder can no longer be opened (moved, deleted, or access lost).
        case folderLost
        /// The folder is in iCloud Drive's place but iCloud Drive is off (signed out, or turned off).
        case iCloudOff
        /// The picked folder is not in iCloud Drive, so nothing leaves this Mac.
        case outsideICloud
        /// The last read or write failed; the next one tries again.
        case failed
    }

    /// The picked folder's name, while one is picked (even one that can no longer be opened).
    private(set) var folderName: String?
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var problem: Problem?

    @ObservationIgnored private var engine: DiarySync?
    /// The picked folder, opened for this run (security scope).
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private weak var memos: MemoBook?
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private weak var calendars: CalendarController?
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var pullTask: Task<Void, Never>?
    @ObservationIgnored private var isBusy = false
    @ObservationIgnored private var waitingPull = false
    @ObservationIgnored private var waitingPush = false
    @ObservationIgnored private var observer: NSObjectProtocol?
    /// The launch's sweep of unused attachments waits for the first pull, so a memo another
    /// device changed meanwhile counts.
    @ObservationIgnored private var sweepsAfterPull = false

    static let bookmarkKey = "syncFolderBookmark"
    static let folderNameKey = "syncFolderName"
    /// How long a change waits for more changes before it is written out.
    static let pushDelay: Duration = .seconds(3)
    private static let log = Logger(subsystem: "dev.yoom.simplify", category: "device-sync")
    private var defaults: UserDefaults { SharedSettings.defaults }

    private init() {}

    /// Starts with the app's books, from the window. A book that is not saved (the store would not
    /// open) is never synced, so an empty memory store cannot be written over the others.
    func attach(memos: MemoBook, model: AppModel, calendars: CalendarController) {
        guard self.memos == nil, memos.isSaved else { return }
        self.memos = memos
        self.model = model
        self.calendars = calendars
        memos.onLocalChange = { DeviceSync.shared.localChanged() }
        observer = NotificationCenter.default.addObserver(forName: SyncedSettings.didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DeviceSync.shared.localChanged() }
        }
        lastSyncedAt = DiarySync.lastSyncedAt(in: defaults)
        folderName = defaults.string(forKey: Self.folderNameKey)
        openSavedFolder()
    }

    // MARK: The folder

    /// At launch: attachments an earlier run left unused are cleared now, or after the first pull
    /// when this Mac syncs.
    func sweepAttachmentsWhenReady() {
        guard let memos else { return }
        if engine == nil { memos.sweepAttachments() } else { sweepsAfterPull = true }
    }

    /// 폴더 고르기…: a folder in iCloud Drive, opened at iCloud Drive's top.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "고르기"
        panel.message = "다른 기기와 함께 쓸 iCloud Drive 폴더를 골라 주세요. 그 안에 Simplify Sync 폴더를 만들어요."
        panel.directoryURL = Self.iCloudDrive
        panel.begin { response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url else { return }
                DeviceSync.shared.use(url)
            }
        }
    }

    /// 연결 끊기: this Mac stops syncing. The folder and every device's file stay as they are, and
    /// nothing here is deleted; connecting again later joins the other devices afresh.
    func disconnect() {
        close()
        // Nothing is on its way any more.
        AttachmentShelf.shared.synced(waiting: [], changed: [])
        defaults.removeObject(forKey: Self.bookmarkKey)
        defaults.removeObject(forKey: Self.folderNameKey)
        DiarySync.forget(in: defaults)
        folderName = nil
        lastSyncedAt = nil
        problem = nil
    }

    private func use(_ url: URL) {
        guard memos != nil else { return }
        // The same folder again: nothing to start over.
        if engine != nil, folder?.standardizedFileURL == url.standardizedFileURL { return }
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            problem = .folderLost
            return
        }
        if engine != nil || defaults.data(forKey: Self.bookmarkKey) != nil { disconnect() }
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        defaults.set(Self.name(of: url), forKey: Self.folderNameKey)
        folderName = Self.name(of: url)
        guard url.startAccessingSecurityScopedResource() else {
            problem = .folderLost
            return
        }
        open(url)
    }

    private func openSavedFolder() {
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else {
            problem = .folderLost
            return
        }
        // Moved or renamed since: keep the new place.
        if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
        folderName = Self.name(of: url)
        defaults.set(folderName, forKey: Self.folderNameKey)
        open(url)
    }

    private func open(_ url: URL) {
        guard let memos else { return }
        folder = url
        problem = Self.iCloudProblem(url)
        let engine = DiarySync(folder: url, container: memos.container, defaults: defaults)
        self.engine = engine
        engine.startWatching { DeviceSync.shared.folderChanged() }
        Task { await run(pull: true, force: true) }
    }

    private func close() {
        pushTask?.cancel()
        pullTask?.cancel()
        engine?.stopWatching()
        engine = nil
        folder?.stopAccessingSecurityScopedResource()
        folder = nil
    }

    /// As Finder shows it: `iCloud Drive` rather than `com~apple~CloudDocs`.
    private static func name(of url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName ?? url.lastPathComponent
    }

    /// iCloud Drive's top folder in the person's home (not the sandbox's).
    private static var iCloudDrive: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home)).appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
    }

    /// Judged by the folder itself: an app without an iCloud container cannot ask iCloud whether
    /// someone is signed in.
    private static func iCloudProblem(_ url: URL) -> Problem? {
        guard (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == false else { return nil }
        return url.path.contains("/Library/Mobile Documents/") ? .iCloudOff : .outsideICloud
    }

    // MARK: When to sync

    /// Something changed here: written out once changes pause.
    func localChanged() {
        guard engine != nil else { return }
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: Self.pushDelay)
            guard !Task.isCancelled else { return }
            await run(pull: false)
        }
    }

    /// The folder changed: read once the changes settle.
    private func folderChanged() {
        guard engine != nil else { return }
        pullTask?.cancel()
        pullTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await run(pull: true)
        }
    }

    /// Simplify came to the front.
    func appBecameActive() {
        guard engine != nil else { return }
        // iCloud Drive may have been turned on or off meanwhile.
        if problem != .failed { problem = folder.flatMap(Self.iCloudProblem) }
        Task { await run(pull: true) }
    }

    /// The app is quitting: a change still waiting is written now.
    func flushOnQuit() {
        guard let engine, let task = pushTask, !task.isCancelled else { return }
        task.cancel()
        try? engine.pushNow()
    }

    /// One pass at a time; one asked for meanwhile runs right after.
    private func run(pull: Bool, force: Bool = false) async {
        guard let engine else { return }
        if isBusy {
            if pull { waitingPull = true } else { waitingPush = true }
            return
        }
        isBusy = true
        isSyncing = true
        do {
            // Attached files go up before the memos that use them, and come down after.
            await syncAttachments(engine, uploadsOnly: pull)
            if pull {
                let applied = try await engine.sync(force: force, prepare: { DeviceSync.shared.prepare() },
                                                    took: { DeviceSync.shared.take($0) })
                if applied == nil {
                    // A letter was being composed; try again in a moment.
                    folderChanged()
                }
                // Files left unused in an earlier run are cleared once this one has the others' memos.
                if sweepsAfterPull, applied != nil {
                    sweepsAfterPull = false
                    memos?.sweepAttachments()
                }
                await syncAttachments(engine)
            } else {
                try await engine.push()
            }
            if self.engine === engine {
                lastSyncedAt = .now
                if problem == .failed { problem = folder.flatMap(Self.iCloudProblem) }
            }
        } catch {
            Self.log.error("Sync failed: \(String(describing: error), privacy: .private)")
            if self.engine === engine { problem = .failed }
        }
        isBusy = false
        isSyncing = false
        if waitingPull {
            waitingPull = false
            waitingPush = false
            await run(pull: true)
        } else if waitingPush {
            waitingPush = false
            await run(pull: false)
        }
    }

    /// One pass over `Simplify Sync/Attachments` (`AttachmentSync`) for the files the stored
    /// memos use. Nothing when a memo cannot be read, as nothing is then known to be unused.
    private func syncAttachments(_ engine: DiarySync, uploadsOnly: Bool = false) async {
        #if DEBUG
        // The format check puts a test folder in the store's place; none of it goes to the real folder.
        if ProcessInfo.processInfo.environment["SIMPLIFY_MEMO_CHECK"] != nil { return }
        #endif
        guard let memos, let referenced = memos.attachmentsInUse() else { return }
        let store = AttachmentShelf.shared.store, folder = engine.folder
        do {
            let report = try await Task.detached {
                try AttachmentSync.pass(store: store, syncFolder: folder, referenced: referenced, uploadsOnly: uploadsOnly)
            }.value
            // Before the others' memos are read, nothing is known to be on its way yet.
            if uploadsOnly { return }
            guard self.engine === engine else { return }
            AttachmentShelf.shared.synced(waiting: report.waiting, changed: report.changed)
        } catch {
            Self.log.error("Attachment sync failed: \(String(describing: error), privacy: .private)")
        }
    }

    /// Right before the store is read: letters typed a moment ago are saved first, so they take
    /// part. Not while a syllable is being composed, which a new text would break up.
    private func prepare() -> Bool {
        guard let memos else { return false }
        if memos.draft.isComposing { return false }
        memos.draft.flush()
        return true
    }

    private func take(_ applied: SyncRecords.Applied) {
        guard !applied.isEmpty else { return }
        if !applied.notes.isEmpty || applied.todosChanged {
            memos?.takeSynced(notes: applied.notes, periods: applied.periods, todosChanged: applied.todosChanged, calendar: model?.calendar ?? .simplify)
        }
        if !applied.settings.isEmpty {
            model?.takeSyncedSettings()
            calendars?.takeSyncedSettings()
        }
        WidgetRefresh.request()
    }
}

/// 설정 › 일반 › 기기: the folder, how syncing stands, and changing or leaving it.
struct DeviceSyncRow: View {
    @Bindable private var sync = DeviceSync.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceS) {
            HStack(spacing: Metrics.spaceL) {
                VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
                    Text("iCloud Drive로 기기끼리 맞추기").textStyle(.item)
                    // Redrawn now and then so 방금 맞춤 turns into a time.
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(note)
                            .textStyle(.small)
                            .foregroundStyle(.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if sync.folderName == nil {
                    Button("폴더 고르기…") { sync.chooseFolder() }
                        .buttonStyle(DrawnButtonStyle())
                } else {
                    Button("폴더 바꾸기…") { sync.chooseFolder() }
                        .buttonStyle(DrawnButtonStyle())
                    Button("연결 끊기") { sync.disconnect() }
                        .buttonStyle(DrawnButtonStyle())
                }
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .textStyle(.small)
                    .foregroundStyle(Tokens.error)
            }
        }
    }

    private var note: String {
        guard let name = sync.folderName else {
            return "iCloud Drive의 폴더를 고르면 같은 Apple 계정의 다른 기기와 메모·할 일·설정을 맞춰요."
        }
        if sync.problem == .folderLost { return "\(name) 폴더" }
        return "\(name) 폴더 · " + (sync.isSyncing ? "맞추는 중…" : SyncStatusView.syncedText(sync.lastSyncedAt))
    }

    private var warning: String? {
        switch sync.problem {
        case .folderLost: "폴더를 열 수 없어요. 폴더를 다시 골라 주세요."
        case .iCloudOff: "iCloud Drive를 쓸 수 없어요. 시스템 설정에서 iCloud Drive를 켜 주세요."
        case .outsideICloud: "고른 폴더가 iCloud Drive 밖에 있어서 이 Mac에만 남아요."
        case .failed: "맞추지 못했어요. 다음에 다시 맞춰 볼게요."
        case nil: nil
        }
    }
}
