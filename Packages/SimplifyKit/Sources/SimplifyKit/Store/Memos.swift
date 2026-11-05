import Foundation
import SwiftData

/// Reading and writing the memos of a day, week or month. A period has any number of memos, each
/// its own `DiaryNote` found by id, in the order they were made.
///
/// Names: a memo made with `+ 새 메모` is `새 메모`, or `새 메모(1)`, `새 메모(2)` … when the period
/// has that name already; a typed name the period has already gets `(1)` and up the same way, and
/// a name cleared away is given the `새 메모` one again. A memo from before a period could have
/// several has no stored name and shows as `새 메모` by the same rule.
public enum Memos {
    /// The name every new memo starts from.
    public static let defaultName = "새 메모"

    // MARK: Reading

    /// The period's memos, oldest first (by `createdAt`, then id, so every device shows one order).
    public static func notes(for period: Period, in context: ModelContext) throws -> [DiaryNote] {
        try context.fetch(DiaryNote.descriptor(for: period)).filter { $0.scope == period.scope }.sorted(by: isBefore)
    }

    public static func note(id: UUID, in context: ModelContext) throws -> DiaryNote? {
        try context.fetch(FetchDescriptor<DiaryNote>(predicate: #Predicate { $0.id == id })).first
    }

    /// The period's first memo, for the places that think of a period as having one memo (the
    /// sample pictures, older tests).
    public static func note(for period: Period, in context: ModelContext) throws -> DiaryNote? {
        try notes(for: period, in: context).first
    }

    public static func text(for period: Period, in context: ModelContext) throws -> AttributedString {
        MemoText.decode(try note(for: period, in: context)?.body)
    }

    static func isBefore(_ a: DiaryNote, _ b: DiaryNote) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.id.uuidString < b.id.uuidString
    }

    // MARK: Names

    /// The names the memos show, in their order: each stored name, `(1)` and up added to one an
    /// earlier memo already shows (two devices may each have made a `새 메모`), and the `새 메모`
    /// rule for one without a name. Stored names are taken first, so a memo without one never
    /// takes a name another memo has.
    public static func names(_ titles: [String]) -> [String] {
        var taken: Set<String> = []
        var shown = titles.map { title -> String? in
            guard !title.isEmpty else { return nil }
            let name = freeName(title, taken: taken)
            taken.insert(name)
            return name
        }
        for index in shown.indices where shown[index] == nil {
            let name = freeName(defaultName, taken: taken.union(titles))
            taken.insert(name)
            shown[index] = name
        }
        return shown.map { $0! }
    }

    /// `name`, or `name(1)`, `name(2)` … the first one not in `taken`.
    public static func freeName(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        var number = 1
        while taken.contains("\(name)(\(number))") { number += 1 }
        return "\(name)(\(number))"
    }

    /// `새 메모`, `새 메모(3)`: a name nobody typed.
    public static func isDefaultName(_ name: String) -> Bool {
        guard name.hasPrefix(defaultName) else { return false }
        let rest = name.dropFirst(defaultName.count)
        guard !rest.isEmpty else { return true }
        guard rest.first == "(", rest.last == ")" else { return false }
        let number = rest.dropFirst().dropLast()
        return !number.isEmpty && number.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// A memo nobody would miss: no words and no name of its own. It goes when it is left.
    public static func isDisposable(_ note: DiaryNote) -> Bool {
        guard note.title.isEmpty || isDefaultName(note.title) else { return false }
        guard let body = note.body else { return true }
        // Unreadable letters are someone's writing.
        return MemoText.decodeIfReadable(body).map(MemoText.isBlank) ?? false
    }

    // MARK: Writing

    /// A new memo in `period`, named `새 메모` or the first free `새 메모(n)`. Saved with no words.
    @discardableResult
    public static func create(in period: Period, in context: ModelContext, now: Date = .now) throws -> DiaryNote {
        let shown = names(try notes(for: period, in: context).map(\.title))
        let note = DiaryNote(period: period, title: freeName(defaultName, taken: Set(shown)), createdAt: now)
        note.updatedAt = try afterLegacyDeletion(of: period, in: context, now: now)
        context.insert(note)
        try context.save()
        return note
    }

    /// Writes `text` into the memo `id`. An unchanged body is left alone so `updatedAt` stays put;
    /// a blank one is stored as no body and the memo stays (it goes once left, `discardIfEmpty`).
    /// False when there is no such memo (deleted elsewhere meanwhile).
    @discardableResult
    public static func save(_ text: AttributedString, note id: UUID, in context: ModelContext, now: Date = .now) throws -> Bool {
        guard let note = try note(id: id, in: context) else { return false }
        let body = MemoText.encode(text)
        if note.body != body {
            note.body = body
            note.updatedAt = SyncStamp.after(note.updatedAt, now: now)
        }
        if context.hasChanges { try context.save() }
        return true
    }

    /// The first letters of a period that had no memo: a memo without a name, as one was before a
    /// period could have several (its 메모 app note keeps a date-only name). Nil for blank text.
    public static func saveFirst(_ text: AttributedString, for period: Period, in context: ModelContext, now: Date = .now) throws -> DiaryNote? {
        guard let body = MemoText.encode(text) else { return nil }
        let note = DiaryNote(period: period, createdAt: now)
        note.body = body
        note.updatedAt = try afterLegacyDeletion(of: period, in: context, now: now)
        context.insert(note)
        try context.save()
        return note
    }

    /// Writes `text` as the period's first memo, made on the first letter and deleted once the
    /// text is blank, as when a period had one memo. For the sample pictures and older tests.
    /// Returns whether the period has a memo afterwards.
    @discardableResult
    public static func save(_ text: AttributedString, for period: Period, in context: ModelContext, now: Date = .now) throws -> Bool {
        guard let first = try note(for: period, in: context) else {
            return try saveFirst(text, for: period, in: context, now: now) != nil
        }
        guard MemoText.encode(text) != nil else {
            try delete(first.id, in: context, now: now)
            return try !notes(for: period, in: context).isEmpty
        }
        return try save(text, note: first.id, in: context, now: now)
    }

    /// Names the memo after `typed`: trimmed, `(1)` and up when another memo of the period shows
    /// that name, the `새 메모` rule when nothing is left. The name it shows now, unchanged, keeps
    /// what is stored (a memo from before keeps its date-only 메모 app name). Returns the name it
    /// shows afterwards, or nil when there is no such memo.
    @discardableResult
    public static func rename(_ id: UUID, to typed: String, in context: ModelContext, now: Date = .now) throws -> String? {
        guard let note = try note(id: id, in: context), let period = period(of: note) else { return nil }
        let all = try notes(for: period, in: context)
        let shown = names(all.map(\.title))
        guard let index = all.firstIndex(where: { $0.id == id }) else { return nil }
        let wanted = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if wanted == shown[index] { return shown[index] }
        let others = Set(shown.enumerated().filter { $0.offset != index }.map(\.element))
        let name = freeName(wanted.isEmpty ? defaultName : wanted, taken: others)
        if note.title != name {
            note.title = name
            note.updatedAt = SyncStamp.after(note.updatedAt, now: now)
            try context.save()
        }
        return name
    }

    /// Deletes the memo, leaving a tombstone so another device's copy goes too.
    public static func delete(_ id: UUID, in context: ModelContext, now: Date = .now) throws {
        guard let note = try note(id: id, in: context) else { return }
        context.delete(note)
        SyncStamp.bury(.note, id.uuidString, at: SyncStamp.after(note.updatedAt, now: now), in: context)
        try context.save()
    }

    /// Deletes the memo if nobody would miss it (`isDisposable`). Returns whether it went.
    @discardableResult
    public static func discardIfEmpty(_ id: UUID, in context: ModelContext, now: Date = .now) throws -> Bool {
        guard let note = try note(id: id, in: context), isDisposable(note) else { return false }
        try delete(id, in: context, now: now)
        return true
    }

    /// The keys of every period with a memo worth marking, for the marks on the month and week: a
    /// memo with words, or one given a name of its own.
    public static func keys(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<DiaryNote>()).filter { !isDisposable($0) }.map(\.periodKey))
    }

    /// Whether `period` has a memo worth marking (`keys`), for one period after a change to it.
    public static func isMarked(_ period: Period, in context: ModelContext) throws -> Bool {
        try notes(for: period, in: context).contains { !isDisposable($0) }
    }

    public static func period(of note: DiaryNote, calendar: Calendar = .simplify) -> Period? {
        Period(key: note.periodKey, scope: note.scope, calendar: calendar)
    }

    /// After the period's last deletion from before V4 (a tombstone named by period), even one
    /// stamped ahead by a faster clock elsewhere, so the new memo is not taken for the deleted one.
    private static func afterLegacyDeletion(of period: Period, in context: ModelContext, now: Date) throws -> Date {
        let key = SyncKey.note(scope: period.scope, periodKey: period.key)
        let kind = SyncKind.note.rawValue
        let deleted = try context.fetch(FetchDescriptor<SyncTombstone>(predicate: #Predicate { $0.kindRaw == kind && $0.key == key }))
        return deleted.map(\.deletedAt).max().map { SyncStamp.after($0, now: now) } ?? now
    }
}
