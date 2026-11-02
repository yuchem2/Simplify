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
    /// The panel's memo box; one window, one box.
    @ObservationIgnored private(set) lazy var draft = MemoDraft(book: self)

    init(container: ModelContainer, isSaved: Bool) {
        context = container.mainContext
        self.isSaved = isSaved
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
}
