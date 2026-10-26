import AppKit
import AuthenticationServices
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
    /// Occurrences for the days on screen, by day.
    private(set) var slots: [Date: [OccurrenceBuilder.Slot]] = [:]
    private(set) var holidayDays: Set<Date> = []
    /// The last sync error of each account, in words, until a sync of that account succeeds.
    private(set) var problems: [String: String] = [:]

    private let container: ModelContainer
    /// Made off the main actor so its context does its work off the main thread too.
    private let engineTask: Task<CalendarSyncEngine, Never>
    private let tokens: TokenStore
    private let oauth: GoogleOAuth?
    private var calendar: Calendar
    private var shownDays: [Date] = []
    /// The visible calendars' events, decoded once per reload; a month change only re-expands them.
    private var snapshots: [EventSnapshot] = []
    private var isSyncing = false
    private var syncAllPending = false
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

    init(container: ModelContainer, calendar: Calendar, tokens: TokenStore = KeychainTokenStore()) {
        self.container = container
        self.calendar = calendar
        self.tokens = tokens
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
        sources = Dictionary(uniqueKeysWithValues: sourceModels.map {
            ($0.id, Source(id: $0.id, accountID: $0.accountID, name: $0.name, palette: $0.palette,
                           isVisible: $0.isVisible, isReadOnly: $0.isReadOnly, isHoliday: $0.isHoliday))
        })
        let accountModels = (try? context.fetch(FetchDescriptor<CalendarAccount>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        accounts = accountModels.map { model in
            Account(id: model.id, email: model.email, status: model.status, lastSyncedAt: model.lastSyncedAt,
                    calendarCount: sourceModels.filter { $0.accountID == model.id }.count)
        }
        snapshots = CalendarCache.visibleSnapshots(context: context)
        if !isSyncing { status = settledStatus() }
        rebuildSlots()
    }

    private func rebuildSlots() {
        guard let first = shownDays.first, let last = shownDays.last else { return }
        let range = DateInterval(start: first, end: calendar.date(byAdding: .day, value: 1, to: last)!)
        let occurrences = OccurrenceBuilder.occurrences(from: snapshots, in: range, calendar: calendar)
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
            guard networkReachable, let oauth else { reload(); return }
            let ready = accounts.filter { $0.status != .needsReauth }
            guard !ready.isEmpty else { reload(); return }
            isSyncing = true
            status = .syncing
            for account in ready {
                await sync(account.id, oauth: oauth)
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

    private func sync(_ accountID: String, oauth: GoogleOAuth) async {
        let api = GoogleCalendarAPI(session: GoogleSession(accountID: accountID, oauth: oauth, store: tokens))
        do {
            try await engineTask.value.syncGoogleAccount(accountID, api: api, calendar: calendar)
            problems[accountID] = nil
            lastTryWasOffline = false
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
            problems[accountID] = nil
            try await engineTask.value.upsertAccount(id: accountID, provider: .google, email: identity.email)
            addState = .importing(email: identity.email)
            reload()
            await serially { [self] in
                isSyncing = true
                status = .syncing
                await sync(accountID, oauth: oauth)
                isSyncing = false
                reload()
            }
            // The person may have closed the page meanwhile; then there is nothing to report.
            if addState == .importing(email: identity.email) {
                addState = .done(email: identity.email, calendars: accounts.first { $0.id == accountID }?.calendarCount ?? 0)
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            addState = .idle // The person closed the sign-in sheet.
        } catch let error as CalendarSyncError {
            addState = .failed(error.message)
        } catch {
            addState = .failed("로그인하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.")
        }
    }

    /// "다시 시도" on a failed sign-in: same account as before when it was a reconnect.
    func retryAdd(authenticate: (URL, String) async throws -> URL) async {
        await addGoogleAccount(loginHint: lastLoginHint, authenticate: authenticate)
    }

    func resetAddState() {
        addState = .idle
    }

    /// Waits for any sync in progress, then removes the account and its cache.
    func disconnect(_ accountID: String) async {
        await serially { [self] in
            if let saved = tokens.load(accountID), let oauth { await oauth.revoke(saved) }
            tokens.delete(accountID)
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
