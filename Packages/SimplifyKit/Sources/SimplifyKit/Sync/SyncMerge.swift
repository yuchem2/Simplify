import CryptoKit
import Foundation

/// Joins this device's records with another device's (stage 9). Pure: no store, no files.
///
/// Every record keeps the version changed last, and a tombstone newer than a record removes it;
/// on equal times the device whose id sorts later wins, so both devices reach the same result.
///
/// Memos are matched by id, so each of a period's memos stays its own. Their texts go by their
/// history instead (`SyncNote.history`): a text that grew out of the other replaces it, whatever
/// the clocks say (deleting still goes by time). When neither grew out of the other, both devices
/// wrote it apart: the later text stays and the earlier one is added after a dividing line, so no
/// one's writing is lost. Their names go by time. Two devices that each wrote a day before they
/// first met keep both memos.
public enum SyncMerge {
    /// The line between a memo and the other device's text added under it.
    public static let divider = "─── 다른 기기에서 쓴 글 ───"
    /// How many earlier versions a memo remembers. A text from further back that was never taken
    /// in here reads as written apart and is added under the line.
    static let historyLimit = 64

    /// `remote` (from the device `remoteDevice`) joined into `local`. `taken` holds, by memo key,
    /// the digest of that device's text as last taken in here: unchanged since, it brings nothing
    /// new, however far behind it is (a device switched off for weeks, or disconnected).
    public static func merge(local: SyncSnapshot, localDevice: String, remote: SyncSnapshot, remoteDevice: String,
                             taken: [String: String] = [:], now: Date = .now) -> SyncSnapshot {
        let remoteWinsTies = remoteDevice > localDevice
        func remoteIsNewer(_ remote: Date, _ local: Date) -> Bool {
            remote > local || (remote == local && remoteWinsTies)
        }

        // Tombstones: every one from both sides, the latest per record.
        var deletions: [String: SyncDeletion] = [:]
        for deletion in local.deletions + remote.deletions where (deletions[deletion.id]?.deletedAt ?? .distantPast) < deletion.deletedAt {
            deletions[deletion.id] = deletion
        }
        func isBuried(_ kind: SyncKind, _ key: String, changedAt: Date) -> Bool {
            guard let deletion = deletions["\(kind.rawValue)|\(key)"] else { return false }
            return deletion.deletedAt >= changedAt
        }

        // Memos, by id. A tombstone from a version before a period could have several (format 1)
        // names the period instead; it buries the period's memo that version knew: one without a
        // name of its own, not changed since. Named memos were made with `+ 새 메모` here, which
        // such a version never sees.
        func isBuried(_ note: SyncNote) -> Bool {
            isBuried(.note, note.key, changedAt: note.updatedAt)
                || (note.title.isEmpty && isBuried(.note, note.periodSlot, changedAt: note.updatedAt))
        }
        var notes: [String: SyncNote] = [:]
        // Each side meets the tombstones first, so a text deleted since is not joined to a new one.
        let localNotes = Dictionary(local.notes.filter { !isBuried($0) }.map { ($0.key, $0) }, uniquingKeysWith: newest)
        let remoteNotes = Dictionary(remote.notes.filter { !isBuried($0) }.map { ($0.key, $0) }, uniquingKeysWith: newest)
        for key in Set(localNotes.keys).union(remoteNotes.keys) {
            switch (localNotes[key], remoteNotes[key]) {
            case (let mine?, nil):
                notes[key] = mine
            case (nil, let theirs?):
                notes[key] = theirs
            case (let mine?, let theirs?):
                // `taken` from before format 2 names the memo by its period.
                let lastTaken = taken[key] ?? taken[theirs.periodSlot]
                var note: SyncNote
                if lastTaken == digest(theirs.body) {
                    note = mine
                    note.history = remembered(theirs.history + mine.history)
                } else {
                    note = mergeNote(mine, theirs, remoteIsNewer: remoteIsNewer, now: now)
                }
                // The name goes by time on its own: renaming does not change the text's history. Taken
                // from the newer side, the time comes too, so the next merge does not take it back.
                let named = remoteIsNewer(theirs.updatedAt, mine.updatedAt) ? theirs : mine
                note.title = named.title
                note.updatedAt = max(note.updatedAt, named.updatedAt)
                note.createdAt = min(mine.createdAt, theirs.createdAt)
                notes[key] = note
            case (nil, nil):
                break
            }
        }

        // ToDos and links: the later version of each, whole.
        let todos = lastWriterWins(local.todos, remote.todos, id: \.id, changedAt: \.updatedAt, remoteIsNewer: remoteIsNewer)
            .filter { !isBuried(.todo, $0.id.uuidString, changedAt: $0.updatedAt) }
        // A link made elsewhere to a ToDo deleted here goes with the ToDo.
        let kept = Set(todos.map(\.id))
        let links = lastWriterWins(local.links, remote.links, id: \.id, changedAt: \.updatedAt, remoteIsNewer: remoteIsNewer)
            .filter { !isBuried(.link, $0.id.uuidString, changedAt: $0.updatedAt) }
            .filter { kept.contains($0.todoID) || deletions["\(SyncKind.todo.rawValue)|\($0.todoID.uuidString)"] == nil }

        // Settings: each one on its own.
        var settings = local.settings
        for (key, theirs) in remote.settings {
            guard let mine = settings[key] else {
                settings[key] = theirs
                continue
            }
            if mine != theirs, remoteIsNewer(theirs.changedAt, mine.changedAt) { settings[key] = theirs }
        }

        return SyncSnapshot(notes: Array(notes.values), todos: todos, links: links,
                            deletions: Array(deletions.values), settings: settings).sorted
    }

    /// A short fingerprint of a memo's stored text.
    public static func digest(_ body: Data) -> String {
        SHA256.hash(data: body).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// One memo both devices have.
    static func mergeNote(_ mine: SyncNote, _ theirs: SyncNote, remoteIsNewer: (Date, Date) -> Bool, now: Date) -> SyncNote {
        let mineDigest = digest(mine.body), theirsDigest = digest(theirs.body)
        let history = remembered(mine.history + theirs.history + [mineDigest, theirsDigest])
        var note: SyncNote
        if mineDigest == theirsDigest {
            note = mine
            note.updatedAt = max(mine.updatedAt, theirs.updatedAt)
        } else if mine.history.contains(theirsDigest), theirs.history.contains(mineDigest) {
            // Each passed through the other's text (one was put back the way it was): the later.
            note = remoteIsNewer(theirs.updatedAt, mine.updatedAt) ? theirs : mine
        } else if mine.history.contains(theirsDigest) {
            // Theirs is a text this one grew out of: a device that has not caught up yet.
            note = mine
        } else if theirs.history.contains(mineDigest) {
            note = theirs
        } else {
            // Written apart: the later text stays, the earlier goes under the line.
            let (winner, loser) = remoteIsNewer(theirs.updatedAt, mine.updatedAt) ? (theirs, mine) : (mine, theirs)
            note = winner
            if let body = joined(winner.body, under: loser.body), body != winner.body {
                note.body = body
                note.updatedAt = SyncStamp.after(max(mine.updatedAt, theirs.updatedAt), now: now)
            }
        }
        note.history = history
        return note
    }

    /// `digests` without repeats, keeping the last `historyLimit` in list order (a repeat keeps its
    /// last place).
    static func remembered(_ digests: [String]) -> [String] {
        var seen: Set<String> = []
        let unique = digests.reversed().filter { seen.insert($0).inserted }
        return Array(unique.prefix(historyLimit).reversed())
    }

    /// `winner`'s text with `loser`'s added after the dividing line, formatting and ToDo chips
    /// kept. Nothing is added when each part of `loser` between dividing lines is already a whole
    /// part of `winner`, as when a joined memo comes back (even joined in another order on a third
    /// device); nil when either text cannot be read.
    static func joined(_ winner: Data, under loser: Data) -> Data? {
        guard let top = MemoText.decodeIfReadable(winner), let bottom = MemoText.decodeIfReadable(loser) else { return nil }
        func parts(_ text: AttributedString) -> Set<String> {
            Set(String(text.characters).components(separatedBy: divider)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        }
        guard !parts(bottom).isSubset(of: parts(top)) else { return winner }
        var text = top
        while text.characters.last?.isNewline == true { text.characters.removeLast() }
        text += AttributedString("\n\n\(divider)\n")
        text += bottom
        return MemoText.encode(text)
    }

    private static func newest(_ a: SyncNote, _ b: SyncNote) -> SyncNote {
        a.updatedAt >= b.updatedAt ? a : b
    }

    private static func lastWriterWins<T>(_ mine: [T], _ theirs: [T], id: KeyPath<T, UUID>, changedAt: KeyPath<T, Date>,
                                          remoteIsNewer: (Date, Date) -> Bool) -> [T] {
        var result = Dictionary(mine.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { a, b in a[keyPath: changedAt] >= b[keyPath: changedAt] ? a : b })
        for record in theirs {
            let key = record[keyPath: id]
            if let existing = result[key], !remoteIsNewer(record[keyPath: changedAt], existing[keyPath: changedAt]) { continue }
            result[key] = record
        }
        return Array(result.values)
    }
}
