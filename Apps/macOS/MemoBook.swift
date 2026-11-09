import Foundation
import Observation
import SwiftData
import SimplifyKit

/// The diary store's memos for the window: each period's memos and what they say, and which periods
/// have one, for the pencil marks on the month, the week and the panel tabs.
@MainActor
@Observable
final class MemoBook {
    /// False when the diary store would not open and memos only live in memory this run.
    let isSaved: Bool
    private(set) var keys: Set<String> = []
    @ObservationIgnored private var context: ModelContext
    /// The last widget change already read, so coming to the front only rereads after a new one.
    @ObservationIgnored private var seenOutsideChange: Date?
    /// Held so an in-memory store (tests, snapshots) lives as long as the book.
    @ObservationIgnored let container: ModelContainer
    /// The panel's memo box; one window, one box.
    @ObservationIgnored private(set) lazy var draft = MemoDraft(book: self)
    /// The ToDos, kept in the same store; memo chips stand for them.
    let todos: TodoBook
    /// Copies saved memos into the 메모 app; nil for books that are not the app's own.
    @ObservationIgnored private let mirror: NotesMirror?
    /// Called after this Mac changes the store (a memo, a ToDo, a widget's tick), so another
    /// device can be told (`DeviceSync`).
    @ObservationIgnored var onLocalChange: (() -> Void)? {
        didSet { todos.onChange = onLocalChange }
    }

    /// Clears away attached files no memo uses; only the app's own book does (not the checks'
    /// and pictures' books, whose memos are not the stored ones).
    @ObservationIgnored let sweepsAttachments: Bool

    init(container: ModelContainer, isSaved: Bool, mirror: NotesMirror? = nil, sweepsAttachments: Bool = false) {
        self.container = container
        self.sweepsAttachments = sweepsAttachments
        context = container.mainContext
        self.isSaved = isSaved
        self.mirror = mirror
        todos = TodoBook(context: context)
        keys = (try? Memos.keys(in: context)) ?? []
        seenOutsideChange = SharedSettings.diaryChangedAt(in: SharedSettings.defaults)
        mirror?.book = self
        mirror?.adoptPeriodKeys()
    }

    /// A widget ticked a ToDo since the last look: read the store afresh. Memo letters not yet
    /// saved stay in the box; they are saved through the new context. `force` skips the check, for
    /// the widget's own notice, which can arrive before its note in the shared defaults does.
    func reloadIfChangedElsewhere(force: Bool = false) {
        let changed = SharedSettings.diaryChangedAt(in: SharedSettings.defaults)
        guard force || changed != seenOutsideChange else { return }
        seenOutsideChange = changed
        readAfresh()
        onLocalChange?()
    }

    /// Another device's changes were written to the store (`DeviceSync`): read it afresh, show the
    /// open memo's new text (and its chips' ToDos), and copy the changed memos to the 메모 app.
    /// `notes` holds the id of each changed memo, `periods` their periods (`SyncKey.note`).
    func takeSynced(notes: Set<UUID>, periods: Set<String>, todosChanged: Bool, calendar: Calendar) {
        readAfresh()
        if !notes.isEmpty { changed() }
        if let open = draft.noteID, notes.contains(open) {
            draft.storedChanged()
        } else if draft.noteID == nil, let period = draft.period, periods.contains(Self.slot(period)) {
            // The first memo of the period open with none: it is shown, not left beside a new one.
            draft.storedChanged()
        }
        if todosChanged { draft.refreshChips() }
        notes.forEach { mirror?.memoSaved($0) }
        if !notes.isEmpty { sweepAttachments() }
    }

    private func readAfresh() {
        let fresh = ModelContext(container)
        fresh.autosaveEnabled = context.autosaveEnabled
        context = fresh
        todos.use(fresh)
        tabCache = [:]
        textCache = [:]
        refreshKeys()
    }

    private func refreshKeys() {
        let fresh = (try? Memos.keys(in: context)) ?? keys
        // Only touch `keys` when it changes: every reader of the marks redraws on a write.
        if fresh != keys { keys = fresh }
    }

    /// After a change to one period's memos: only its own mark is looked at again.
    private func refreshKey(_ period: Period) {
        guard let marked = try? Memos.isMarked(period, in: context) else { return }
        if marked, !keys.contains(period.key) {
            keys.insert(period.key)
        } else if !marked, keys.contains(period.key) {
            // Another scope of the same key (a day and a month never share one) may still mark it.
            refreshKeys()
        }
    }

    /// The period of a stored memo, for `refreshKey` after it changed.
    private func period(of id: UUID) -> Period? {
        (try? Memos.note(id: id, in: context)).flatMap { $0.flatMap { Memos.period(of: $0) } }
    }

    /// The tabs and the read-only memos' letters are read again after this.
    private func changed() {
        revision += 1
        tabCache = [:]
        textCache = [:]
    }

    func has(_ period: Period) -> Bool {
        keys.contains(period.key)
    }

    // MARK: A period's memos

    /// One memo's tab: its id (nil for the empty memo a period with none shows) and the name it shows.
    struct Tab: Identifiable, Equatable {
        var id: UUID?
        var name: String
        /// No name of its own: a memo from before a period could have several, or one not written yet.
        var isUntitled: Bool
    }

    /// The period's memos in their order (`Memos.ordered`), named (`Memos.names`); a period with none
    /// shows one empty memo, saved on its first letter.
    func tabs(for period: Period) -> [Tab] {
        _ = revision
        let slot = Self.slot(period)
        if let cached = tabCache[slot] { return cached }
        // A store that cannot be read now is asked again next time, not remembered as empty.
        guard let notes = try? Memos.notes(for: period, in: context) else { return [Tab(id: nil, name: Memos.defaultName, isUntitled: true)] }
        let tabs = notes.isEmpty ? [Tab(id: nil, name: Memos.defaultName, isUntitled: true)]
            : zip(notes, Memos.names(notes.map(\.title))).map { Tab(id: $0.id, name: $1, isUntitled: $0.title.isEmpty) }
        tabCache[slot] = tabs
        return tabs
    }

    /// Kept between the panel's redraws until a period's memos change (`changed`).
    @ObservationIgnored private var tabCache: [String: [Tab]] = [:]
    /// 모아 보기's read-only memos, decoded once until they change.
    @ObservationIgnored private var textCache: [UUID: AttributedString?] = [:]

    /// A memo of 모아 보기 that is not being written, as `text(note:)`, read once until it changes.
    func shownText(note id: UUID?) -> AttributedString? {
        guard let id else { return AttributedString() }
        if let cached = textCache[id] { return cached }
        let text = text(note: id)
        textCache[id] = text
        return text
    }

    /// The memo last open in each period this run, so coming back opens it again.
    @ObservationIgnored private var chosen: [String: UUID] = [:]

    func chosenNote(in period: Period) -> UUID? {
        let notes = (try? Memos.notes(for: period, in: context)) ?? []
        if let id = chosen[Self.slot(period)], notes.contains(where: { $0.id == id }) { return id }
        return notes.first?.id
    }

    func choose(_ id: UUID?, in period: Period) {
        chosen[Self.slot(period)] = id
    }

    static func slot(_ period: Period) -> String { SyncKey.note(scope: period.scope, periodKey: period.key) }

    /// Nil when a stored memo cannot be read, so the editor does not save over it. No memo (`id`
    /// nil, or gone) reads as empty.
    func text(note id: UUID?) -> AttributedString? {
        guard let id, let note = try? Memos.note(id: id, in: context) else { return AttributedString() }
        // Formulas from before LaTeX read with their raised and lowered letters as `^{}` and `_{}`.
        return MemoText.decodeIfReadable(note.body).map(MemoMath.upgradingScripts)
    }

    /// The memo still exists in the store.
    func exists(_ id: UUID) -> Bool {
        (try? Memos.note(id: id, in: context)) != nil
    }

    /// The text of the memo `period` opens with (the one last open there, else its first).
    func text(for period: Period) -> AttributedString? {
        text(note: chosenNote(in: period))
    }

    /// A memo as the 메모 app's copy needs it.
    enum Stored {
        /// Its period, words, and the name its note goes by after the date: nil for a memo without
        /// a name of its own, which keeps the period's date alone.
        case memo(period: Period, text: AttributedString, name: String?)
        /// Deleted: its note goes too.
        case gone
        /// The memo or the store cannot be read now: its note is left alone, since a passing read
        /// error must not delete it.
        case unreadable
    }

    func stored(note id: UUID, calendar: Calendar) -> Stored {
        do {
            guard let note = try Memos.note(id: id, in: context), let period = Memos.period(of: note, calendar: calendar) else { return .gone }
            guard let text = MemoText.decodeIfReadable(note.body) else { return .unreadable }
            let notes = try Memos.notes(for: period, in: context)
            let names = Memos.names(notes.map(\.title))
            let name = note.title.isEmpty ? nil : notes.firstIndex { $0.id == id }.map { names[$0] }
            return .memo(period: period, text: text, name: name)
        } catch {
            return .unreadable
        }
    }

    /// Saves the open memo's letters: into `id`, or, for a period's first memo (`id` nil), into a
    /// new memo without a name on the first letter. Returns the memo's id afterwards (nil while the
    /// first memo is still blank), or `.failed` when the store refused the write; the editor keeps
    /// the text and tries again.
    func save(_ text: AttributedString, note id: UUID?, in period: Period) -> SaveResult {
        let saved: UUID?
        do {
            if let id, try Memos.save(text, note: id, in: context) {
                saved = id
            } else {
                // A period's first letters, or a memo deleted elsewhere while it was being written:
                // the words are kept in a new one.
                let made = try Memos.saveFirst(text, for: period, in: context)
                saved = made?.id
                if let made {
                    choose(made.id, in: period)
                    changed()
                }
            }
        } catch {
            return .failed
        }
        if let saved {
            textCache[saved] = nil
            // A memo not open (rewritten from 가져오기) is drawn again in 모아 보기.
            if saved != draft.noteID { revision += 1 }
        }
        refreshKey(period)
        if let saved { mirror?.memoSaved(saved) }
        onLocalChange?()
        return .saved(saved)
    }

    enum SaveResult: Equatable {
        case saved(UUID?)
        case failed
    }

    /// `+ 새 메모`: a new memo in `period` named `새 메모` or the first free `새 메모(n)`.
    func create(in period: Period) -> UUID? {
        guard let note = try? Memos.create(in: period, in: context) else { return nil }
        changed()
        choose(note.id, in: period)
        onLocalChange?()
        return note.id
    }

    /// Names the memo after `typed` (`Memos.rename`), and its 메모 app note after it.
    @discardableResult
    func rename(_ id: UUID, to typed: String) -> String? {
        let before = (try? Memos.note(id: id, in: context))?.title
        guard let name = try? Memos.rename(id, to: typed, in: context) else { return nil }
        if (try? Memos.note(id: id, in: context))?.title != before {
            changed()
            if let period = period(of: id) { refreshKey(period) }
            mirror?.memoSaved(id)
            onLocalChange?()
        }
        return name
    }

    /// Drags memo `id` to `index` among its period's tabs (counted before the move, `Memos.move`).
    func move(_ id: UUID, to index: Int) {
        guard (try? Memos.move(id, to: index, in: context)) == true else { return }
        changed()
        onLocalChange?()
    }

    /// 앞으로 옮기기 (-1) and 뒤로 옮기기 (1): one place over among its period's tabs.
    func move(_ id: UUID, by step: Int) {
        guard let period = period(of: id), let index = tabs(for: period).firstIndex(where: { $0.id == id }) else { return }
        move(id, to: step < 0 ? index - 1 : index + 2)
    }

    /// The memo can be dragged to another place: one that cannot be read (a newer version's, or
    /// damaged) is left where it is.
    func canMove(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return id == draft.noteID ? !draft.isUnreadable : shownText(note: id) != nil
    }

    /// 메모 지우기, and its 메모 app note with it.
    func delete(_ id: UUID) {
        let period = period(of: id)
        guard (try? Memos.delete(id, in: context)) != nil else { return }
        changed()
        if let period { refreshKey(period) }
        mirror?.memoSaved(id)
        onLocalChange?()
        sweepAttachments()
    }

    /// The memo being left goes if nobody would miss it (blank and still `새 메모(n)`).
    func discardIfEmpty(_ id: UUID) {
        let period = period(of: id)
        guard (try? Memos.discardIfEmpty(id, in: context)) == true else { return }
        changed()
        if let period { refreshKey(period) }
        mirror?.memoSaved(id)
        onLocalChange?()
    }

    /// Bumped when a period's memos come or go or are renamed or moved, for the tabs.
    private(set) var revision = 0

    /// Every attachment the stored memos use, by id; nil when a memo cannot be read (it may use
    /// any) or the store cannot be read.
    func attachmentsInUse() -> [String: MemoAttachments.Ref]? {
        guard let notes = try? context.fetch(FetchDescriptor<DiaryNote>()) else { return nil }
        var found: [String: MemoAttachments.Ref] = [:]
        for note in notes {
            guard let text = MemoText.decodeIfReadable(note.body) else { return nil }
            for item in MemoAttachments.attachments(in: text) { found[item.ref.id] = item.ref }
        }
        return found
    }

    /// Attached files no memo uses are cleared away once their wait is over: when a memo drops
    /// one, at launch, and after another device's memos arrive.
    func sweepAttachments() {
        guard sweepsAttachments, isSaved else { return }
        AttachmentShelf.shared.sweep(referenced: attachmentsInUse().map { Set($0.keys) })
    }

    /// Every memo, for 지금 모두 보내기.
    func allNoteIDs() -> [UUID] {
        ((try? context.fetch(FetchDescriptor<DiaryNote>())) ?? []).map(\.id)
    }

    /// The memo a period's 메모 app note was kept under before a period could have several (by
    /// period key): the period's oldest memo without a name of its own.
    func legacyNote(periodKey: String) -> UUID? {
        let notes = (try? context.fetch(FetchDescriptor<DiaryNote>(predicate: #Predicate { $0.periodKey == periodKey }))) ?? []
        return notes.filter { $0.title.isEmpty }.sorted(by: Memos.isOlder).first?.id
    }

    /// The period a note belongs to, for "10월 23일 메모" under a ToDo made from it.
    func period(ofNote id: UUID, calendar: Calendar) -> Period? {
        guard let note = try? Memos.note(id: id, in: context) else { return nil }
        return Memos.period(of: note, calendar: calendar)
    }

    /// The name a memo goes by beside its period (`11월 4일 · 회의록`), for the places that name it;
    /// nil for a period's one memo without a name, which is just `11월 4일 메모` as before.
    func label(ofNote id: UUID, calendar: Calendar) -> String? {
        guard let period = period(ofNote: id, calendar: calendar) else { return nil }
        return labels(in: period)[id] ?? nil
    }

    private func labels(in period: Period) -> [UUID: String?] {
        let tabs = tabs(for: period)
        let alone = tabs.count == 1 && tabs[0].isUntitled
        return Dictionary(uniqueKeysWithValues: tabs.compactMap { tab in tab.id.map { ($0, alone ? nil : tab.name) } })
    }

    /// A line found in a memo for 가져오기: the memo's period and id, and its name where the period
    /// has more than its one memo without a name.
    struct FoundLine {
        var period: Period
        var note: UUID
        var name: String?
        var line: MemoTodoLine
    }

    /// Every memo's unticked ToDo lines, newest memo first, for 가져오기. Flush the box first so
    /// lines typed a moment ago count.
    func todoLines(calendar: Calendar) -> [FoundLine] {
        let notes = (try? context.fetch(FetchDescriptor<DiaryNote>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        var names: [String: [UUID: String?]] = [:]
        return notes.flatMap { note -> [FoundLine] in
            guard let period = Memos.period(of: note, calendar: calendar),
                  let text = MemoText.decodeIfReadable(note.body) else { return [] }
            let slot = Self.slot(period)
            if names[slot] == nil { names[slot] = labels(in: period) }
            let name = names[slot]?[note.id] ?? nil
            return MemoTodoLines.find(in: text).map { FoundLine(period: period, note: note.id, name: name, line: $0) }
        }
    }

    /// Changes a stored memo: through the box when it is the one open, so its unsaved letters are
    /// kept, otherwise straight in the store.
    func rewrite(note id: UUID, _ change: (inout AttributedString) -> Void) {
        if draft.noteID == id {
            draft.rewrite(change)
            return
        }
        guard var text = text(note: id), let note = try? Memos.note(id: id, in: context), let period = Memos.period(of: note, calendar: draft.period?.calendar ?? .simplify) else { return }
        change(&text)
        _ = save(text, note: id, in: period)
    }
}
