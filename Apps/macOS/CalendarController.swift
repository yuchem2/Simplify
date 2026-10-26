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

    private(set) var accounts: [Account] = []
    private(set) var sources: [String: Source] = [:]
    private(set) var status: Status = .noAccounts
    private(set) var addState: AddState = .idle
    /// The kind of account `addState` is about.
    private(set) var addingKind: CalendarProviderKind = .google
    /// Ticked-off reminders stay on the calendar, struck through (설정 › 일반). Remembered across launches.
    var showsCompletedReminders: Bool {
        didSet {
            defaults.set(showsCompletedReminders, forKey: "showsCompletedReminders")
            rebuildSlots()
        }
    }
    /// Occurrences for the days on screen, by day.
    private(set) var slots: [Date: [OccurrenceBuilder.Slot]] = [:]
    private(set) var holidayDays: Set<Date> = []
    /// The last sync error of each account, in words, until a sync of that account succeeds.
    private(set) var problems: [String: String] = [:]

    private let container: ModelContainer
    /// Made off the main actor so its context does its work off the main thread too.
    private let engineTask: Task<CalendarSyncEngine, Never>
    private let tokens: TokenStore
    private let credentials: CalDAVCredentialStore
    private let reminders = RemindersProvider()
    private let oauth: GoogleOAuth?
    private var calendar: Calendar
    private var shownDays: [Date] = []
    /// The visible calendars' events, decoded once per reload; a month change only re-expands them.
    private var snapshots: [EventSnapshot] = []
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

    private let defaults: UserDefaults

    init(container: ModelContainer, calendar: Calendar, tokens: TokenStore = KeychainTokenStore(),
         credentials: CalDAVCredentialStore = KeychainCredentialStore(), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsCompletedReminders = defaults.bool(forKey: "showsCompletedReminders")
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
            ($0.id, Source(id: $0.id, accountID: $0.accountID, name: $0.name, palette: $0.palette,
                           isVisible: $0.isVisible, isReadOnly: $0.isReadOnly, isHoliday: $0.isHoliday,
                           isReminderList: reminderAccounts.contains($0.accountID)))
        })
        accounts = accountModels.map { model in
            Account(id: model.id, provider: model.provider, email: model.email, status: model.status, lastSyncedAt: model.lastSyncedAt,
                    calendarCount: sourceModels.filter { $0.accountID == model.id }.count)
        }
        snapshots = CalendarCache.visibleSnapshots(context: context)
        if !isSyncing { status = settledStatus() }
        rebuildSlots()
    }

    private func rebuildSlots() {
        guard let first = shownDays.first, let last = shownDays.last else { return }
        let range = DateInterval(start: first, end: calendar.date(byAdding: .day, value: 1, to: last)!)
        let shown = showsCompletedReminders ? snapshots : snapshots.filter { !$0.isCompleted }
        let occurrences = OccurrenceBuilder.occurrences(from: shown, in: range, calendar: calendar)
        slots = OccurrenceBuilder.byDay(occurrences, days: shownDays, calendar: calendar)
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
        }
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
            try await engineTask.value.sync(accountID, provider: provider, calendar: calendar)
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

    func setVisible(_ sourceID: String, _ visible: Bool) {
        let context = ModelContext(container)
        guard let source = try? context.fetch(FetchDescriptor<CalendarSource>(predicate: #Predicate { $0.id == sourceID })).first else { return }
        source.isVisible = visible
        try? context.save()
        reload()
    }
}
