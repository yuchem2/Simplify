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
    @ObservationIgnored private let context: ModelContext
    /// Held so an in-memory store (tests, snapshots) lives as long as the book.
    @ObservationIgnored private let container: ModelContainer
    /// The panel's memo box; one window, one box.
    @ObservationIgnored private(set) lazy var draft = MemoDraft(book: self)
    /// The ToDos, kept in the same store; memo chips stand for them.
    let todos: TodoBook

    init(container: ModelContainer, isSaved: Bool) {
        self.container = container
        context = container.mainContext
        self.isSaved = isSaved
        todos = TodoBook(context: context)
        keys = (try? Memos.keys(in: context)) ?? []
    }

    func has(_ period: Period) -> Bool {
        keys.contains(period.key)
    }

    /// Nil when a stored memo cannot be read, so the editor does not save over it.
    func text(for period: Period) -> AttributedString? {
        guard let note = try? Memos.note(for: period, in: context) else { return AttributedString() }
        return MemoText.decodeIfReadable(note.body)
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
        return true
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
