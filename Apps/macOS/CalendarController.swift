import AppKit
import AuthenticationServices
import EventKit
import Foundation
import Network
import Observation
import OSLog
import SwiftData
import SimplifyKit

/// Accounts, calendars, sync, and the events on screen.
///
/// Sync writes through `CalendarSyncEngine` on its own actor; this controller then re-reads the
/// cache into plain values, so views never hold objects another context is changing.
@MainActor
@Observable
final class CalendarController {
    struct Account: Identifiable, Hashable {
        let id: String
        let provider: CalendarProviderKind
        let email: String
        let status: CalendarAccount.Status
        let lastSyncedAt: Date?
        let calendarCount: Int
    }

    struct Source: Identifiable, Hashable {
        let id: String
        let accountID: String
        /// The provider's calendar id and zone, for writing to it.
        let remoteID: String
        let timeZone: String?
        let name: String
        let palette: Palette
        let isVisible: Bool
        let isReadOnly: Bool
        let isHoliday: Bool
        /// A list from the Mac's reminders; its entries get a round mark and never a band.
        let isReminderList: Bool
    }

    enum Status: Equatable {
        case noAccounts
        case syncing
        case upToDate(Date?)
        case needsReauth(email: String)
        case offline(lastSynced: Date?)
        case failed(email: String)
    }

    enum AddState: Equatable {
        case idle
        case signingIn
        case importing(email: String)
        case done(email: String, calendars: Int)
        case failed(String)
    }

    private(set) var accounts: [Account] = [] {
        didSet { if accounts.isEmpty != oldValue.isEmpty { WidgetRefresh.request() } }
    }
    private(set) var sources: [String: Source] = [:] {
        didSet { if sources != oldValue { WidgetRefresh.request() } }
    }
    private(set) var status: Status = .noAccounts
    private(set) var addState: AddState = .idle
    /// The kind of account `addState` is about.
    private(set) var addingKind: CalendarProviderKind = .google
    /// Ticked-off reminders stay on the calendar, struck through (설정 › 일반). Remembered across launches.
    var showsCompletedReminders: Bool {
        didSet {
            defaults.set(showsCompletedReminders, forKey: SharedSettings.showsCompletedReminders)
            rebuildSlots()
            WidgetRefresh.request()
        }
    }
    /// Occurrences overlapping the days on screen, and the same by day.
    private(set) var occurrences: [EventOccurrence] = []
    private(set) var slots: [Date: [OccurrenceBuilder.Slot]] = [:]
    /// Band rows for each week on screen, by the week's first day.
    private(set) var lanes: [Date: BandLanes] = [:]
    private(set) var holidayDays: Set<Date> = []
    /// The last sync error of each account, in words, until a sync of that account succeeds.
    private(set) var problems: [String: String] = [:]
    /// Changes saved while offline, or refused by the provider, that have not reached it yet.
    private(set) var unsentWrites: [PendingWrite] = [] {
        didSet {
            unsentByKey = [:]
            for write in unsentWrites {
                let key: String? = if case .create(let id) = write.kind { write.calendar.sourceID + ":" + id }
                    else { write.event.map { write.calendar.sourceID + ":" + ($0.recurringEventID ?? $0.remoteID) } }
                // A refused write says more than the waiting ones behind it.
                if let key, unsentByKey[key].map({ !$0.isFailed }) ?? true { unsentByKey[key] = write }
            }
        }
    }
    /// The unsent change of each event, by `sourceID:series id`.
    private var unsentByKey: [String: PendingWrite] = [:]
    /// Something sent or waiting is laid over the cache.
    private var hasOverlay = false
    /// Counts reloads, so an overlay worked out for an older one is dropped.
    private var reloadGeneration = 0

    private let container: ModelContainer
    /// Made off the main actor so its context does its work off the main thread too.
    private let engineTask: Task<CalendarSyncEngine, Never>
    private let tokens: TokenStore
    private let credentials: CalDAVCredentialStore
    private let reminders = RemindersProvider()
    /// Every event change goes through here, so offline changes wait and go out in order.
    private let writer: EventWriter
    private let oauth: GoogleOAuth?
    private var calendar: Calendar
    private var shownDays: [Date] = []
    /// The visible calendars' events with unsent changes on top; a month change only re-expands them.
    private var snapshots: [EventSnapshot] = [] {
        didSet {
            snapshotsByID = Dictionary(snapshots.map { ($0.id, $0) }) { first, _ in first }
            // The widgets read the same cache and unsent changes; a sync that changed nothing leaves them be.
            if snapshots != oldValue { WidgetRefresh.request() }
        }
    }
    private var snapshotsByID: [String: EventSnapshot] = [:]
    /// The same, as the cache has them.
    private var cachedSnapshots: [EventSnapshot] = []
    private var isSyncing = false
    private var syncAllPending = false
    private var remindersSyncPending = false
    /// What the network monitor says; the only thing that gates syncing.
    private var networkReachable = true
    /// The last request failed for lack of network; shown, but never stops the next try.
    private var lastTryWasOffline = false
    private let pathMonitor = NWPathMonitor()
    private static let log = Logger(subsystem: "dev.yoom.simplify", category: "sync")
    private var loop: Task<Void, Never>?
    /// Sync, add and disconnect run one after another, never interleaved.
    private var queue: Task<Void, Never>?
    /// Kept so "다시 시도" after a failed reconnect signs in to the same account.
    private var lastLoginHint: String?

    /// Shared with the widgets (App Group), so they follow the same setting.
    private let defaults: UserDefaults

    init(container: ModelContainer, calendar: Calendar, tokens: TokenStore = KeychainTokenStore(),
         credentials: CalDAVCredentialStore = KeychainCredentialStore(), defaults: UserDefaults = SharedSettings.defaults,
         writer: EventWriter = EventWriter()) {
        self.defaults = defaults
        self.writer = writer
        showsCompletedReminders = defaults.bool(forKey: SharedSettings.showsCompletedReminders)
        self.container = container
        self.calendar = calendar
        self.tokens = tokens
        self.credentials = credentials
        engineTask = Task.detached { CalendarSyncEngine(modelContainer: container) }
        let clientID = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String ?? ""
        oauth = clientID.hasSuffix(".apps.googleusercontent.com") ? GoogleOAuth(clientID: clientID) : nil
        reload()
    }

    var sourcesByAccount: [(Account, [Source])] {
        accounts.map { account in
            (account, sources.values.filter { $0.accountID == account.id }.sorted { $0.name < $1.name })
        }
    }

    // MARK: - Showing days

    /// The days on screen changed (another month, or the calendar's zone).
    func show(days: [Date], calendar: Calendar) {
        self.calendar = calendar
        shownDays = days
        rebuildSlots()
    }

    func reload() {
        let context = ModelContext(container)
        let sourceModels = (try? context.fetch(FetchDescriptor<CalendarSource>(sortBy: [SortDescriptor(\.order)]))) ?? []
        let accountModels = (try? context.fetch(FetchDescriptor<CalendarAccount>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let reminderAccounts = Set(accountModels.filter { $0.provider == .reminders }.map(\.id))
        sources = Dictionary(uniqueKeysWithValues: sourceModels.map {
            ($0.id, Source(id: $0.id, accountID: $0.accountID, remoteID: $0.remoteID, timeZone: $0.timeZone, name: $0.name, palette: $0.palette,
                           isVisible: $0.isVisible, isReadOnly: $0.isReadOnly, isHoliday: $0.isHoliday,
                           isReminderList: reminderAccounts.contains($0.accountID)))
        })
        accounts = accountModels.map { model in
            Account(id: model.id, provider: model.provider, email: model.email, status: model.status, lastSyncedAt: model.lastSyncedAt,
                    calendarCount: sourceModels.filter { $0.accountID == model.id }.count)
        }
        cachedSnapshots = CalendarCache.visibleSnapshots(context: context)
        if !isSyncing { status = settledStatus() }
        // Without anything to lay on top there is no reason to draw twice.
        if !hasOverlay { snapshots = cachedSnapshots }
        rebuildSlots()
        reloadGeneration += 1
        let generation = reloadGeneration
        Task { await applyUnsentWrites(generation) }
    }

    /// Lays the changes that have not come back from the provider over the cache.
    private func applyUnsentWrites(_ generation: Int) async {
        let cache = cachedSnapshots
        let pending = await writer.pending
        let shown = await writer.overlay(cache, calendar: calendar)
        // A newer reload has started meanwhile; it brings its own.
        guard generation == reloadGeneration else { return }
        hasOverlay = !pending.isEmpty
        unsentWrites = pending.filter { if case .sent = $0.status { false } else { true } }
        let visible = shown.filter { sources[$0.sourceID]?.isVisible == true }
        guard visible != snapshots else { return }
        snapshots = visible
        rebuildSlots()
    }

    private func rebuildSlots() {
        guard let first = shownDays.first, let last = shownDays.last else { return }
        let range = DateInterval(start: first, end: calendar.date(byAdding: .day, value: 1, to: last)!)
        let shown = showsCompletedReminders ? snapshots : snapshots.filter { !$0.isCompleted }
        occurrences = OccurrenceBuilder.occurrences(from: shown, in: range, calendar: calendar)
        slots = OccurrenceBuilder.byDay(occurrences, days: shownDays, calendar: calendar)
        // The days on screen are whole weeks of the month grid.
        lanes = Dictionary(uniqueKeysWithValues: stride(from: 0, to: shownDays.count, by: 7).map { index in
            let week = Array(shownDays[index..<min(index + 7, shownDays.count)])
            return (week[0], BandLanes(occurrences, days: week, calendar: calendar))
        })
        holidayDays = Set(slots.compactMap { day, daySlots in
            daySlots.contains { sources[$0.occurrence.sourceID]?.isHoliday == true } ? day : nil
        })
    }

    private func settledStatus() -> Status {
        if accounts.isEmpty { return .noAccounts }
        if let stale = accounts.first(where: { $0.status == .needsReauth }) { return .needsReauth(email: stale.email) }
        if let failing = accounts.first(where: { problems[$0.id] != nil }) { return .failed(email: failing.email) }
        let last = accounts.compactMap(\.lastSyncedAt).min()
        return networkReachable && !lastTryWasOffline ? .upToDate(last) : .offline(lastSynced: last)
    }

    // MARK: - Sync

    /// Syncs now, then every minute while the app is in front and every five minutes behind.
    /// Safe to call again (a second window, a re-run task): it starts only once.
    func startAutoSync() {
        guard loop == nil else { return }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let cameBack = !self.networkReachable && path.status == .satisfied
                self.networkReachable = path.status == .satisfied
                if cameBack { await self.syncAll() } else { self.reload() }
            }
        }
        pathMonitor.start(queue: .main)
        // The Reminders app (or iCloud behind it) changed something: show it now, not next minute.
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.syncReminders() }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncAll()
                let active = NSApplication.shared.isActive
                try? await Task.sleep(for: .seconds(active ? 60 : 300))
            }
        }
    }

    /// The app came to the front: catch up unless a sync just ran.
    func appBecameActive() {
        if case .upToDate(let last?) = status, Date.now.timeIntervalSince(last) < 30 { return }
        Task { await syncAll() }
    }

    func syncAll() async {
        // A timer tick or a return to the app while a sync is queued or running adds nothing.
        guard !syncAllPending else { return }
        syncAllPending = true
        await serially { [self] in
            syncAllPending = false
            let ready = accounts.filter { account in
                // Reminders need no network, and come back by themselves once access is turned on again.
                if account.provider == .reminders { return account.status != .needsReauth || RemindersProvider.isAuthorized }
                // A build without a Google client ID leaves Google accounts as they are.
                if account.provider == .google, oauth == nil { return false }
                return account.status != .needsReauth && networkReachable
            }
            guard !ready.isEmpty else { reload(); return }
            isSyncing = true
            status = .syncing
            // Changes kept while offline go out first, so this round brings them back.
            if networkReachable { await sendUnsentWrites() }
            for account in ready {
                await sync(account.id)
            }
            isSyncing = false
            reload()
        }
    }

    /// Runs `work` after everything queued before it has finished.
    private func serially(_ work: @escaping @MainActor () async -> Void) async {
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        queue = task
        await task.value
    }

    /// Reads the reminders again after a change in the Reminders app.
    /// Changes arrive in bursts (typing in the Reminders app, an iCloud download); one queued read covers them all.
    private func syncReminders() async {
        guard !remindersSyncPending, let account = accounts.first(where: { $0.provider == .reminders }) else { return }
        remindersSyncPending = true
        await serially { [self] in
            remindersSyncPending = false
            await sync(account.id)
            reload()
            // A reminder ticked here was already drawn before the cache had it; the widgets read the cache.
            WidgetRefresh.request()
        }
    }

    /// Ticks a reminder off (or back on) in the Reminders app from its ring, shows the change at
    /// once, then reads the lists again. Nil when it worked, otherwise what to tell the person.
    func setReminderDone(_ occurrence: EventOccurrence, _ isDone: Bool) async -> String? {
        guard let event = snapshotsByID[occurrence.eventID], sources[event.sourceID]?.isReminderList == true else { return nil }
        do {
            try await reminders.setCompleted(isDone, reminderID: event.remoteID)
        } catch {
            return (error as? CalendarSyncError)?.message ?? "미리알림을 바꾸지 못했어요."
        }
        snapshots = snapshots.map { snapshot in
            guard snapshot.id == event.id else { return snapshot }
            var changed = snapshot
            changed.isCompleted = isDone
            return changed
        }
        rebuildSlots()
        await syncReminders()
        return nil
    }

    private func provider(for accountID: String) throws -> any CalendarProvider {
        switch accounts.first(where: { $0.id == accountID })?.provider ?? .google {
        case .google:
            guard let oauth else { throw CalendarSyncError.needsReauth }
            return GoogleCalendarAPI(session: GoogleSession(accountID: accountID, oauth: oauth, store: tokens))
        case .icloud:
            guard let saved = try credentials.load(accountID), let home = saved.home else { throw CalendarSyncError.needsReauth }
            return CalDAVProvider(client: CalDAVClient(credentials: saved), home: home)
        case .reminders:
            return reminders
        }
    }

    private func sync(_ accountID: String) async {
        // Only network accounts say anything about being offline; reminders sync without one.
        let usesNetwork = accounts.first { $0.id == accountID }?.provider != .reminders
        do {
            let provider: any CalendarProvider
            do {
                provider = try self.provider(for: accountID)
            } catch CalendarSyncError.needsReauth {
                // The sign-in is gone (no password in the keychain): mark the account so 다시 연결 shows.
                try? await engineTask.value.markNeedsReauth(accountID)
                throw CalendarSyncError.needsReauth
            }
            let started = Date.now
            try await engineTask.value.sync(accountID, provider: provider, calendar: calendar)
            // What was written before this sync is in the cache now.
            await writer.didSync(accountID, startedAt: started)
            problems[accountID] = nil
            if usesNetwork { lastTryWasOffline = false }
        } catch CalendarSyncError.offline {
            lastTryWasOffline = true
        } catch {
            // Shown on the account and in the toolbar; the next round tries again.
            problems[accountID] = (error as? CalendarSyncError)?.message ?? "일정을 맞추지 못했어요."
            // Error details can carry calendar ids (often email addresses), so they stay private.
            Self.log.error("Sync of \(accountID, privacy: .private) failed: \(String(describing: error), privacy: .private)")
        }
        reload()
    }

    // MARK: - Accounts

    /// Runs Google sign-in through `authenticate` (the system web-auth sheet), then imports the account.
    /// Pass `loginHint` to reconnect a known account.
    func addGoogleAccount(loginHint: String? = nil, authenticate: (URL, String) async throws -> URL) async {
        guard let oauth else {
            addState = .failed("Google 클라이언트 ID가 설정되지 않았어요.")
            return
        }
        lastLoginHint = loginHint
        addingKind = .google
        addState = .signingIn
        do {
            let pkce = GoogleOAuth.PKCE()
            let state = UUID().uuidString
            let callback = try await authenticate(oauth.authorizationURL(pkce: pkce, state: state, loginHint: loginHint), oauth.callbackScheme)
            guard let code = oauth.code(fromCallback: callback, state: state) else {
                addState = .failed("로그인 응답을 확인하지 못했어요. 다시 시도해 주세요.")
                return
            }
            let newTokens = try await oauth.exchange(code: code, pkce: pkce)
            guard let identity = newTokens.identity else {
                addState = .failed("계정 정보를 읽지 못했어요. 다시 시도해 주세요.")
                return
            }
            let accountID = "google:" + identity.id
            try tokens.save(newTokens, for: accountID)
            try await importAccount(accountID, provider: .google, email: identity.email)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            addState = .idle // The person closed the sign-in sheet.
        } catch let error as CalendarSyncError {
            addState = .failed(error.message)
        } catch {
            addState = .failed("로그인하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.")
        }
    }

    /// Checks the Apple ID and app-specific password against iCloud, finds the account's
    /// calendars, then imports them. Also reconnects a known account with a new password.
    func addICloudAccount(appleID: String, password: String) async {
        addingKind = .icloud
        addState = .signingIn
        var login = CalDAVCredentials(username: appleID.trimmingCharacters(in: .whitespacesAndNewlines),
                                      password: password.filter { !$0.isWhitespace })
        do {
            let (principal, home) = try await CalDAVClient(credentials: login).discover()
            login.home = home
            let accountID = "icloud:" + principal
            try credentials.save(login, for: accountID)
            try await importAccount(accountID, provider: .icloud, email: login.username)
        } catch CalendarSyncError.needsReauth {
            addState = .failed("Apple ID나 앱 전용 암호가 맞지 않아요. Apple ID 암호가 아니라 앱 전용 암호를 넣어 주세요.")
        } catch let error as CalendarSyncError {
            addState = .failed(error.message)
        } catch {
            addState = .failed("연결하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.")
        }
    }

    /// Asks for access to the Mac's reminders (the system prompt, the first time), then imports the lists.
    func addReminders() async {
        addingKind = .reminders
        addState = .signingIn
        guard await reminders.requestAccess() else {
            addState = .failed(CalendarSyncError.remindersAccessDenied.message)
            return
        }
        do {
            try await importAccount("reminders:local", provider: .reminders, email: "미리알림")
        } catch {
            addState = .failed("미리알림을 가져오지 못했어요. 다시 시도해 주세요.")
        }
    }

    /// Records the account and runs its first sync, reporting progress in `addState`.
    private func importAccount(_ accountID: String, provider: CalendarProviderKind, email: String) async throws {
        problems[accountID] = nil
        try await engineTask.value.upsertAccount(id: accountID, provider: provider, email: email)
        addState = .importing(email: email)
        reload()
        await serially { [self] in
            isSyncing = true
            status = .syncing
            await sync(accountID)
            isSyncing = false
            reload()
        }
        // The person may have closed the page meanwhile; then there is nothing to report.
        if addState == .importing(email: email) {
            addState = .done(email: email, calendars: accounts.first { $0.id == accountID }?.calendarCount ?? 0)
        }
    }

    /// "다시 시도" on a failed Google sign-in: same account as before when it was a reconnect.
    func retryAdd(authenticate: (URL, String) async throws -> URL) async {
        await addGoogleAccount(loginHint: lastLoginHint, authenticate: authenticate)
    }

    func resetAddState() {
        addState = .idle
    }

    /// Waits for any sync in progress, then removes the account and its cache.
    func disconnect(_ accountID: String) async {
        await serially { [self] in
            switch accounts.first(where: { $0.id == accountID })?.provider {
            case .google?:
                if let saved = tokens.load(accountID), let oauth { await oauth.revoke(saved) }
                tokens.delete(accountID)
            case .icloud?:
                credentials.delete(accountID)
            case .reminders?, nil:
                break
            }
            // With no network account left, an old timeout no longer says anything.
            if !accounts.contains(where: { $0.id != accountID && $0.provider != .reminders }) { lastTryWasOffline = false }
            problems[accountID] = nil
            try? await engineTask.value.removeAccount(id: accountID)
            reload()
        }
    }

    // MARK: - Writing events

    /// How much of a repeating event a change or a delete reaches.
    enum WriteScope: Hashable { case thisOccurrence, thisAndFollowing, allOccurrences }

    /// Calendars a new or changed event can go to: Google and iCloud calendars that are not
    /// read-only, of accounts that are still signed in.
    var writableSources: [(Account, [Source])] {
        sourcesByAccount
            .filter { account, _ in account.provider != .reminders && account.status != .needsReauth }
            .map { account, sources in (account, sources.filter { !$0.isReadOnly && !$0.isHoliday }) }
            .filter { !$0.1.isEmpty }
    }

    func isWritable(_ sourceID: String) -> Bool {
        writableSources.contains { $0.1.contains { $0.id == sourceID } }
    }

    /// The stored event an occurrence on screen came from.
    func event(id: String) -> EventSnapshot? {
        snapshotsByID[id]
    }

    var isOffline: Bool { !networkReachable }

    /// The change to this event that has not reached its calendar yet, if there is one.
    func unsentWrite(for occurrence: EventOccurrence) -> PendingWrite? {
        guard !unsentByKey.isEmpty, let event = event(id: occurrence.eventID) else { return nil }
        return unsentByKey[event.sourceID + ":" + (event.recurringEventID ?? event.remoteID)]
    }

    func isUnsent(_ occurrence: EventOccurrence) -> Bool {
        unsentWrite(for: occurrence) != nil
    }

    /// The calendar a new event starts in: the one saved to last, while it can still be written.
    var defaultSourceForNewEvent: String? {
        if let last = defaults.string(forKey: "lastEventSourceID"), isWritable(last) { return last }
        return writableSources.first?.1.first?.id
    }

    func rememberSource(_ sourceID: String) {
        defaults.set(sourceID, forKey: "lastEventSourceID")
    }

    /// Syncs the account of `sourceID` now, after whatever is queued.
    func resync(sourceID: String) async {
        guard let accountID = sources[sourceID]?.accountID else { return }
        await serially { [self] in
            await sync(accountID)
            reload()
        }
    }

    /// Saves the editor's event. Online it goes to the provider (`.saved`); bring it onto the calendar
    /// with `resync`. Offline it waits in the queue (`.queued`) and shows from there at once.
    func save(_ editor: EventEditorModel, scope: WriteScope) async throws -> EventWriter.Outcome {
        guard let source = sources[editor.fields.sourceID] else { throw CalendarSyncError.readOnly }
        let draft = editor.draft()
        let outcome: EventWriter.Outcome
        if let event = editor.event, let occurrence = editor.occurrence {
            let scope = Self.editScope(scope, occurrence: occurrence, event: event, calendar: calendar)
            outcome = try await writer.update(event, to: draft, scope: scope, in: reference(source), accountID: source.accountID,
                                              provider: provider(for: source.accountID), calendar: calendar)
        } else {
            outcome = try await writer.create(draft, in: reference(source), accountID: source.accountID,
                                              provider: provider(for: source.accountID), calendar: calendar)
        }
        reload()
        return outcome
    }

    @discardableResult
    func delete(_ occurrence: EventOccurrence, scope: WriteScope) async throws -> EventWriter.Outcome {
        guard let source = sources[occurrence.sourceID], let event = event(id: occurrence.eventID) else { throw CalendarSyncError.readOnly }
        let outcome = try await writer.delete(event, scope: Self.editScope(scope, occurrence: occurrence, event: event, calendar: calendar),
                                              in: reference(source), accountID: source.accountID,
                                              provider: provider(for: source.accountID), calendar: calendar)
        reload()
        return outcome
    }

    /// Gives a refused change another go on the next round.
    func retryWrite(_ id: UUID) {
        Task {
            await writer.retry(id)
            reload()
            await syncAll()
        }
    }

    /// Drops a change that will not be sent (and later changes to the same event).
    func discardWrite(_ id: UUID) {
        Task {
            await writer.discard(id)
            reload()
        }
    }

    private func reference(_ source: Source) -> RemoteCalendar.Reference {
        RemoteCalendar.Reference(sourceID: source.id, remoteID: source.remoteID, timeZone: source.timeZone)
    }

    /// Sends the queue and leaves the accounts it reached for the sync that follows.
    private func sendUnsentWrites() async {
        _ = await writer.flush(calendar: calendar) { [weak self] accountID in
            guard let self else { throw CalendarSyncError.offline }
            return try await MainActor.run { try self.provider(for: accountID) }
        }
    }

    /// The occurrence as the provider knows it: a changed occurrence by where it was meant to start.
    private static func editScope(_ scope: WriteScope, occurrence: EventOccurrence, event: EventSnapshot, calendar: Calendar) -> EditScope {
        var original = occurrence.start
        if event.recurringEventID != nil {
            original = event.originalStartDay.flatMap { DayKey.date($0, calendar: calendar) } ?? event.originalStart ?? original
        }
        switch scope {
        case .thisOccurrence: return .thisOccurrence(originalStart: original)
        case .thisAndFollowing: return .thisAndFollowing(originalStart: original)
        case .allOccurrences: return .allOccurrences
        }
    }

    func setVisible(_ sourceID: String, _ visible: Bool) {
        let context = ModelContext(container)
        guard let source = try? context.fetch(FetchDescriptor<CalendarSource>(predicate: #Predicate { $0.id == sourceID })).first else { return }
        source.isVisible = visible
        try? context.save()
        reload()
    }
}
