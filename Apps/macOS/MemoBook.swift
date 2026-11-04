import Foundation
import Observation
import SwiftData
import SimplifyKit

/// The diary store's memos for the window: what each period's memo says, and which periods have
/// one, for the pencil marks on the month, the week and the panel tabs.
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
    /// `notes` holds the `SyncKey.note` of each changed memo.
    func takeSynced(notes: Set<String>, todosChanged: Bool, calendar: Calendar) {
        readAfresh()
        let periods = notes.compactMap { key -> Period? in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let scope = PeriodScope(rawValue: parts[0]) else { return nil }
            return Period(key: parts[1], scope: scope, calendar: calendar)
        }
        if let open = draft.period, periods.contains(where: { $0.key == open.key && $0.scope == open.scope }) { draft.storedChanged() }
        if todosChanged { draft.refreshChips() }
        periods.forEach { mirror?.memoSaved($0) }
        if !notes.isEmpty { sweepAttachments() }
    }

    private func readAfresh() {
        let fresh = ModelContext(container)
        fresh.autosaveEnabled = context.autosaveEnabled
        context = fresh
        todos.use(fresh)
        keys = (try? Memos.keys(in: fresh)) ?? keys
    }

    func has(_ period: Period) -> Bool {
        keys.contains(period.key)
    }

    /// Nil when a stored memo cannot be read, so the editor does not save over it.
    func text(for period: Period) -> AttributedString? {
        guard let note = try? Memos.note(for: period, in: context) else { return AttributedString() }
        // Formulas from before LaTeX read with their raised and lowered letters as `^{}` and `_{}`.
        return MemoText.decodeIfReadable(note.body).map(MemoMath.upgradingScripts)
    }

    /// Like `text(for:)`, but also nil when the store cannot be read, for the 메모 app's copy,
    /// which a passing read error must not delete.
    func storedText(for period: Period) -> AttributedString? {
        do {
            return MemoText.decodeIfReadable(try Memos.note(for: period, in: context)?.body)
        } catch {
            return nil
        }
    }

    /// False when the store refused the write; the editor keeps the text and tries again.
    func save(_ text: AttributedString, for period: Period) -> Bool {
        guard let hasMemo = try? Memos.save(text, for: period, in: context) else { return false }
        // Only touch `keys` when it changes: every reader of the marks redraws on a write.
        if hasMemo, !keys.contains(period.key) {
            keys.insert(period.key)
        } else if !hasMemo, keys.contains(period.key) {
            keys.remove(period.key)
        }
        mirror?.memoSaved(period)
        onLocalChange?()
        return true
    }

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

    /// Every period with a memo, for 지금 모두 보내기.
    func periodsWithMemos(calendar: Calendar = .simplify) -> [Period] {
        let notes = (try? context.fetch(FetchDescriptor<DiaryNote>())) ?? []
        return notes.compactMap { Period(key: $0.periodKey, scope: $0.scope, calendar: calendar) }
    }

    /// The stored note's id, for a ToDo made from it.
    func noteID(for period: Period) -> UUID? {
        try? Memos.note(for: period, in: context)?.id
    }

    /// The period a note belongs to, for "10월 23일 메모" under a ToDo made from it.
    func period(ofNote id: UUID, calendar: Calendar) -> Period? {
        guard let note = try? context.fetch(FetchDescriptor<DiaryNote>(predicate: #Predicate { $0.id == id })).first else { return nil }
        return Period(key: note.periodKey, scope: note.scope, calendar: calendar)
    }

    /// Every memo's unticked ToDo lines, newest memo first, for 가져오기. Flush the box first so
    /// lines typed a moment ago count.
    func todoLines(calendar: Calendar) -> [(period: Period, line: MemoTodoLine)] {
        let notes = (try? context.fetch(FetchDescriptor<DiaryNote>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        return notes.flatMap { note -> [(period: Period, line: MemoTodoLine)] in
            guard let period = Period(key: note.periodKey, scope: note.scope, calendar: calendar),
                  let text = MemoText.decodeIfReadable(note.body) else { return [] }
            return MemoTodoLines.find(in: text).map { (period, $0) }
        }
    }

    /// Changes a stored memo: through the box when it is the one open, so its unsaved letters are
    /// kept, otherwise straight in the store.
    func rewrite(_ period: Period, _ change: (inout AttributedString) -> Void) {
        if draft.period == period {
            draft.rewrite(change)
            return
        }
        guard var text = text(for: period) else { return }
        change(&text)
        _ = save(text, for: period)
    }
}
