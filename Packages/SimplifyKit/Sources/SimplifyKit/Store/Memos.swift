import Foundation
import SwiftData

/// Reading and writing the memo of a day, week or month.
///
/// Nothing in the store keeps a period to one note (CloudKit allows no unique fields), so a
/// period may end up with two after a sync; the most recently changed one wins and saving folds
/// the others away.
public enum Memos {
    public static func note(for period: Period, in context: ModelContext) throws -> DiaryNote? {
        try notes(for: period, in: context).first
    }

    public static func text(for period: Period, in context: ModelContext) throws -> AttributedString {
        MemoText.decode(try note(for: period, in: context)?.body)
    }

    /// Writes `text` as the period's memo: the note is made on the first letter and deleted once
    /// the text is blank. An unchanged body is left alone so `updatedAt` stays put. Returns
    /// whether the period has a memo afterwards.
    @discardableResult
    public static func save(_ text: AttributedString, for period: Period, in context: ModelContext, now: Date = .now) throws -> Bool {
        let body = MemoText.encode(text)
        var existing = try notes(for: period, in: context)
        let kept = existing.isEmpty ? nil : existing.removeFirst()
        existing.forEach(context.delete)
        switch (kept, body) {
        case (nil, nil):
            break
        case (let note?, nil):
            context.delete(note)
        case (nil, let body?):
            let note = DiaryNote(period: period)
            note.body = body
            note.updatedAt = now
            context.insert(note)
        case (let note?, let body?):
            if note.body != body {
                note.body = body
                note.updatedAt = now
            }
        }
        if context.hasChanges { try context.save() }
        return body != nil
    }

    /// The keys of every period with a memo, for the marks on the month and week.
    public static func keys(in context: ModelContext) throws -> Set<String> {
        var descriptor = FetchDescriptor<DiaryNote>()
        descriptor.propertiesToFetch = [\.periodKey]
        return Set(try context.fetch(descriptor).map(\.periodKey))
    }

    private static func notes(for period: Period, in context: ModelContext) throws -> [DiaryNote] {
        var descriptor = DiaryNote.descriptor(for: period)
        descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]
        return try context.fetch(descriptor).filter { $0.scope == period.scope }
    }
}
