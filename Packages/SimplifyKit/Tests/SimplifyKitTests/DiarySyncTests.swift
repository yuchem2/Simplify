import Foundation
import SwiftData
import Testing
@testable import SimplifyKit

/// Stage 9: memos, ToDos, links and shared settings kept in step through an iCloud Drive folder.
@MainActor
struct DiarySyncTests {
    let cal = PeriodTests.calendar()
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func day(_ d: Int) -> Period {
        Period(containing: PeriodTests.date(2026, 11, d, in: cal), scope: .day, calendar: cal)
    }

    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    private func body(_ text: AttributedString) -> Data { MemoText.encode(text)! }
    private func body(_ text: String) -> Data { body(AttributedString(text)) }

    /// `from`: the earlier texts this one grew out of. Without `id`, the one memo of the period
    /// both devices know (`memoID`).
    private func note(_ text: String, at seconds: Double, id: UUID? = nil, key: String = "2026-11-03", from: [String] = [],
                      title: String = "") -> SyncNote {
        SyncNote(id: id ?? memoID(key), scope: "day", periodKey: key, body: body(text), updatedAt: at(seconds),
                 history: from.map { SyncMerge.digest(body($0)) }, title: title)
    }

    /// The same id for a period's memo on every device, as after their first meeting.
    private func memoID(_ key: String) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-" + String(format: "%012d", Int(key.filter(\.isNumber))! % 1_000_000_000_000))!
    }

    private func todo(_ id: UUID, _ title: String, done: Bool = false, at seconds: Double) -> SyncTodo {
        SyncTodo(id: id, title: title, isDone: done, scope: "day", periodKey: "2026-11-03", order: 1, colorLabel: nil,
                 sourceNoteID: nil, createdAt: t0, updatedAt: at(seconds))
    }

    private func text(_ note: SyncNote?) -> String {
        String(MemoText.decode(note?.body).characters)
    }

    private func merge(_ local: SyncSnapshot, _ remote: SyncSnapshot, local a: String = "A", remote b: String = "B",
                       taken: [String: String] = [:], now seconds: Double = 1000) -> SyncSnapshot {
        SyncMerge.merge(local: local, localDevice: a, remote: remote, remoteDevice: b, taken: taken, now: at(seconds))
    }

    // MARK: Records

    @Test func changesMadeApartBothArrive() {
        let one = UUID(), two = UUID()
        let start = [todo(one, "견적서", at: 0), todo(two, "회의록", at: 0)]
        let a = SyncSnapshot(todos: [todo(one, "견적서 보내기", at: 10), start[1]])
        let b = SyncSnapshot(todos: [start[0], todo(two, "회의록", done: true, at: 20), todo(UUID(), "새 할 일", at: 30)])
        let fromA = merge(a, b)
        let fromB = merge(b, a, local: "B", remote: "A")
        #expect(fromA == fromB, "both devices reach the same records")
        let byID = Dictionary(uniqueKeysWithValues: fromA.todos.map { ($0.id, $0) })
        #expect(byID[one]?.title == "견적서 보내기")
        #expect(byID[two]?.isDone == true)
        #expect(fromA.todos.count == 3)
    }

    @Test func deepListsArriveAsWritten() {
        let deep = "• 하나\n\t• 둘\n\t\t• 셋\n\t\t\t• 넷\n\t\t\t\t\t1. 여섯"
        let local = SyncSnapshot(notes: [note("• 하나", at: 0)])
        let remote = SyncSnapshot(notes: [note(deep, at: 10, from: ["• 하나"])])
        #expect(text(merge(local, remote).notes.first) == deep)
    }

    @Test func aDeletionAndAnEditMeetByTime() {
        let id = UUID()
        let gone = SyncSnapshot(deletions: [SyncDeletion(kind: .todo, key: id.uuidString, deletedAt: at(20))])
        // Edited before it was deleted elsewhere: it goes.
        #expect(merge(SyncSnapshot(todos: [todo(id, "고침", at: 10)]), gone).todos.isEmpty)
        // Edited after: it stays, and the tombstone travels on.
        let kept = merge(SyncSnapshot(todos: [todo(id, "고침", at: 30)]), gone)
        #expect(kept.todos.map(\.title) == ["고침"])
        #expect(kept.deletions.count == 1)
        // A memo deleted on one device is deleted on the other unless written again after.
        let memo = SyncSnapshot(notes: [note("오늘", at: 10)])
        let memoGone = SyncSnapshot(deletions: [SyncDeletion(kind: .note, key: "day|2026-11-03", deletedAt: at(20))])
        #expect(merge(memo, memoGone).notes.isEmpty)
        let written = SyncSnapshot(notes: [note("다시 씀", at: 30)])
        #expect(merge(written, memoGone).notes.count == 1)
        // Since format 2 a memo's tombstone names its id: the period's other memo stays.
        let two = SyncSnapshot(notes: [note("하나", at: 10), note("둘", at: 10, id: UUID())])
        let oneGone = SyncSnapshot(deletions: [SyncDeletion(kind: .note, key: memoID("2026-11-03").uuidString, deletedAt: at(20))])
        #expect(merge(two, oneGone).notes.map(text) == ["둘"])
    }

    @Test func equalTimesGoTheSameWayOnBothDevices() {
        let id = UUID()
        let a = SyncSnapshot(todos: [todo(id, "가", at: 10)], settings: ["firstWeekday": SyncSetting(value: .int(1), changedAt: at(5))])
        let b = SyncSnapshot(todos: [todo(id, "나", at: 10)], settings: ["firstWeekday": SyncSetting(value: .int(2), changedAt: at(5))])
        let fromA = merge(a, b)
        let fromB = merge(b, a, local: "B", remote: "A")
        #expect(fromA.todos == fromB.todos)
        #expect(fromA.settings == fromB.settings)
        // The device whose id sorts later wins.
        #expect(fromA.todos.first?.title == "나")
    }

    // MARK: Memos

    @Test func aMemoWrittenOnBothDevicesKeepsBothTexts() {
        var bold = AttributedString("굵은 글")
        bold[MemoAttributes.Bold.self] = true
        let chip = MemoChips.chip(id: UUID(), title: "견적서", isDone: false)
        let mine = SyncSnapshot(notes: [SyncNote(id: memoID("2026-11-03"), scope: "day", periodKey: "2026-11-03", body: body(bold + AttributedString("\n") + chip),
                                                 updatedAt: at(10), history: [SyncMerge.digest(body("처음"))])])
        let theirs = SyncSnapshot(notes: [note("저쪽에서 고침", at: 20, from: ["처음"])])

        let result = merge(mine, theirs)
        let joined = MemoText.decode(result.notes.first?.body)
        // The later text first, then the line, then the earlier text with its bold and its chip.
        #expect(String(joined.characters) == "저쪽에서 고침\n\n\(SyncMerge.divider)\n굵은 글\n□ 견적서")
        #expect(joined.runs.contains { $0[MemoAttributes.Bold.self] == true })
        #expect(MemoChips.chips(in: joined).count == 1)
        #expect(result.notes.first!.updatedAt > at(20))

        // The other device, still on its own text, takes the joined memo without adding again.
        let back = merge(theirs, result, local: "B", remote: "A")
        #expect(text(back.notes.first) == text(result.notes.first))
        // And more rounds change nothing.
        var a = result, b = back
        for _ in 0..<3 {
            a = merge(a, b)
            b = merge(b, a, local: "B", remote: "A")
        }
        #expect(text(a.notes.first) == text(result.notes.first))
        #expect(text(b.notes.first) == text(result.notes.first))
    }

    @Test func bothDevicesJoiningAtOnceReachTheSameText() {
        let a = SyncSnapshot(notes: [note("이쪽", at: 10, from: ["처음"])])
        let b = SyncSnapshot(notes: [note("저쪽", at: 20, from: ["처음"])])
        let onA = merge(a, b, now: 100)
        let onB = merge(b, a, local: "B", remote: "A", now: 200)
        #expect(text(onA.notes.first) == text(onB.notes.first))
        // Their files then meet: same words, nothing added.
        let again = merge(onA, onB)
        #expect(text(again.notes.first) == "저쪽\n\n\(SyncMerge.divider)\n이쪽")
    }

    @Test func aTextThatGrewOutOfTheOtherReplacesIt() {
        let unchanged = SyncSnapshot(notes: [note("처음", at: 0, from: ["처음"])])
        let edited = SyncSnapshot(notes: [note("처음에서 지운 줄", at: 20, from: ["처음"])])
        #expect(text(merge(unchanged, edited).notes.first) == "처음에서 지운 줄")
        #expect(text(merge(edited, unchanged, local: "B", remote: "A").notes.first) == "처음에서 지운 줄")
        // The same words on both sides are not added under each other.
        let same = merge(SyncSnapshot(notes: [note("같은 글", at: 10)]), SyncSnapshot(notes: [note("같은 글", at: 20)]))
        #expect(text(same.notes.first) == "같은 글")
        // A short text found inside a longer one is still its own writing.
        let short = merge(SyncSnapshot(notes: [note("ok", at: 10)]), SyncSnapshot(notes: [note("book list", at: 20)]))
        #expect(text(short.notes.first) == "book list\n\n\(SyncMerge.divider)\nok")
    }

    @Test func aTextPutBackTheWayItWasStillSettles() {
        // X wrote A, then B (which Y took), then put A back. Each has passed through the other's text.
        let onX = SyncSnapshot(notes: [note("abc", at: 30, from: ["abc", "abcd"])])
        let onY = SyncSnapshot(notes: [note("abcd", at: 20, from: ["abc", "abcd"])])
        #expect(text(merge(onX, onY).notes.first) == "abc")
        #expect(text(merge(onY, onX, local: "B", remote: "A").notes.first) == "abc")
    }

    @Test func aMemoDeletedAndWrittenAgainDoesNotBringTheOldTextBack() {
        let gone = SyncDeletion(kind: .note, key: "day|2026-11-03", deletedAt: at(20))
        let mine = SyncSnapshot(notes: [note("새 글", at: 30)], deletions: [gone])
        // A device switched off since still has the text from before the deletion.
        let old = SyncSnapshot(notes: [note("지운 글", at: 10)])
        #expect(text(merge(mine, old).notes.first) == "새 글")
    }

    @Test func anOldFileAlreadyTakenInBringsNothingNew() {
        // Far more edits than the history keeps, made after the old text was taken in.
        let old = note("오래된 글", at: 10)
        let edits = (0..<100).map { "고친 글 \($0)" }
        let mine = SyncSnapshot(notes: [note("오늘의 글", at: 500, from: edits)])
        let theirs = SyncSnapshot(notes: [old])
        #expect(text(merge(mine, theirs, taken: [old.key: SyncMerge.digest(old.body)]).notes.first) == "오늘의 글")
        // Without having taken it in, it is written apart and kept under the line.
        #expect(text(merge(mine, theirs).notes.first) == "오늘의 글\n\n\(SyncMerge.divider)\n오래된 글")
    }

    @Test func threeDevicesWritingAtOnceSettleOnOneText() {
        let a = SyncSnapshot(notes: [note("사과", at: 10)]), b = SyncSnapshot(notes: [note("포도", at: 20)]), c = SyncSnapshot(notes: [note("귤", at: 30)])
        // Each joins the other two in its own order.
        var onA = merge(merge(a, b, local: "A", remote: "B", now: 100), c, local: "A", remote: "C", now: 100)
        var onB = merge(merge(b, a, local: "B", remote: "A", now: 200), c, local: "B", remote: "C", now: 200)
        var onC = merge(merge(c, b, local: "C", remote: "B", now: 300), a, local: "C", remote: "A", now: 300)
        for _ in 0..<2 {
            onA = merge(merge(onA, onB, local: "A", remote: "B"), onC, local: "A", remote: "C")
            onB = merge(merge(onB, onA, local: "B", remote: "A"), onC, local: "B", remote: "C")
            onC = merge(merge(onC, onA, local: "C", remote: "A"), onB, local: "C", remote: "B")
        }
        let texts = Set([onA, onB, onC].map { text($0.notes.first) })
        #expect(texts.count == 1)
        // Each text once.
        let only = try? #require(texts.first)
        for word in ["사과", "포도", "귤"] { #expect(only?.components(separatedBy: word).count == 2) }
    }

    @Test func meetingForTheFirstTimeKeepsEverything() {
        // Each Mac wrote a memo of the same day before they met: two memos of that day.
        let mine = SyncSnapshot(notes: [note("이 Mac", at: 10, id: UUID()), note("이 Mac만", at: 10, key: "2026-11-04")],
                                todos: [todo(UUID(), "이 Mac 할 일", at: 10)])
        let theirs = SyncSnapshot(notes: [note("저 Mac", at: 20, id: UUID()), note("저 Mac만", at: 20, key: "2026-11-05")],
                                  todos: [todo(UUID(), "저 Mac 할 일", at: 20)])
        let result = merge(mine, theirs)
        #expect(result.todos.count == 2)
        let byKey = Dictionary(grouping: result.notes, by: \.periodKey).mapValues { Set($0.map(text)) }
        #expect(byKey == ["2026-11-03": ["이 Mac", "저 Mac"], "2026-11-04": ["이 Mac만"], "2026-11-05": ["저 Mac만"]])
        // Either coming back changes nothing.
        #expect(merge(result, theirs).withoutHistory.notes == result.withoutHistory.notes)
        #expect(merge(result, mine).withoutHistory.notes == result.withoutHistory.notes)
    }

    @Test func aClockBehindDoesNotLoseAnEdit() {
        // B's text arrived; this Mac's clock is behind, so its next edit carries an earlier time.
        let theirs = note("저쪽 글", at: 100, from: ["옛 글"])
        let edited = SyncSnapshot(notes: [note("저쪽 글에 덧붙임", at: 50, from: ["옛 글", "저쪽 글"])])
        #expect(text(merge(edited, SyncSnapshot(notes: [theirs])).notes.first) == "저쪽 글에 덧붙임")
        // A device still holding an older text does not bring it back, whatever its time.
        let stale = SyncSnapshot(notes: [note("옛 글", at: 500)])
        #expect(text(merge(SyncSnapshot(notes: [theirs]), stale).notes.first) == "저쪽 글")
        // Changes made here are always stamped after what they change.
        #expect(SyncStamp.after(at(100), now: at(50)) > at(100))
        #expect(SyncStamp.after(at(10), now: at(50)) == at(50))
    }

    @Test func twoMemosOfOnePeriodSurviveAMerge() {
        // A made a second memo of the day and named it; B wrote on in the first.
        let second = UUID()
        var made = todo(UUID(), "회의록에서 만든 할 일", at: 30)
        made.sourceNoteID = second
        let onA = SyncSnapshot(notes: [note("처음", at: 10), note("안건", at: 30, id: second, title: "회의록")], todos: [made])
        let onB = SyncSnapshot(notes: [note("처음 고침", at: 20, from: ["처음"])])
        let fromA = merge(onA, onB), fromB = merge(onB, onA, local: "B", remote: "A")
        #expect(fromA.withoutHistory == fromB.withoutHistory)
        #expect(Set(fromA.notes.map(text)) == ["처음 고침", "안건"])
        #expect(fromA.notes.first { $0.id == second }?.title == "회의록")
        // The ToDo keeps pointing at the memo it was made from.
        #expect(fromA.todos.first?.sourceNoteID == second)
    }

    @Test func aNameGoesByTimeAndTheTextByItsHistory() {
        // B renamed the memo later; A wrote on in it, from the text B has.
        let onA = SyncSnapshot(notes: [note("처음\n덧붙임", at: 20, from: ["처음"], title: "새 메모")])
        let onB = SyncSnapshot(notes: [note("처음", at: 30, title: "회의록")])
        let result = merge(onA, onB)
        #expect(text(result.notes.first) == "처음\n덧붙임")
        #expect(result.notes.first?.title == "회의록")
        // The name's time comes with it, so merging again keeps it.
        #expect(result.notes.first?.updatedAt == at(30))
        #expect(merge(result, onA).notes.first?.title == "회의록")
        #expect(result.withoutHistory == merge(onB, onA, local: "B", remote: "A").withoutHistory)
    }

    @Test func aFormatOneFileIsTakenInMemoByMemo() throws {
        // An older version's file: no title or creation time, memos matched by period then.
        let id = memoID("2026-11-03")
        let old = Data(#"{"format":1,"device":"B","data":{"notes":[{"id":"\#(id.uuidString)","scope":"day","periodKey":"2026-11-03","body":"\#(body("저쪽 글").base64EncodedString())","updatedAt":\#(at(40).timeIntervalSinceReferenceDate),"history":["\#(SyncMerge.digest(body("처음")))"]}],"todos":[],"links":[],"deletions":[{"kind":"note","key":"day|2026-11-04","deletedAt":\#(at(50).timeIntervalSinceReferenceDate)}],"settings":{}}}"#.utf8)
        guard case .file(let file) = SyncFile.decode(old) else {
            Issue.record("a format 1 file is read")
            return
        }
        #expect(file.data.notes.first?.title == "")
        #expect(file.data.notes.first?.createdAt == SyncNote.unknownCreation)
        // Here: that memo, renamed after B last wrote, a second one of the day, and the 4th's memo from before its
        // deletion there (an older version names the period).
        let second = UUID()
        let mine = SyncSnapshot(notes: [note("처음", at: 45, title: "회의록"), note("둘째", at: 60, id: second),
                                        note("4일 메모", at: 30, key: "2026-11-04"), note("4일에 새로", at: 60, id: UUID(), key: "2026-11-04"),
                                        note("4일 회의록", at: 30, id: UUID(), key: "2026-11-04", title: "회의록")])
        let result = merge(mine, file.data, remote: "B")
        let texts = Dictionary(grouping: result.notes, by: \.periodKey).mapValues { Set($0.map(text)) }
        // The older version's deletion takes the 4th's memo it knew, not one named here since.
        #expect(texts == ["2026-11-03": ["저쪽 글", "둘째"], "2026-11-04": ["4일에 새로", "4일 회의록"]])
        // Its text grew out of this one; the name it has here is newer than its file.
        #expect(result.notes.first { $0.id == id }?.title == "회의록")
        // Written back as format 2.
        let written = try SyncFile(device: "A", data: result).encoded()
        #expect(String(decoding: written, as: UTF8.self).contains(#""format":2"#))
    }

    // MARK: Settings

    @Test func settingsAndCalendarColoursMergeOneByOne() {
        let defaults = WidgetStoreTests().defaults()
        // Chosen before stage 9, with no time: beats a device that never chose.
        defaults.set(true, forKey: SharedSettings.showsPatterns)
        CalendarStyles.set(CalendarStyle(palette: .teal), for: "google:me|work", in: defaults)
        let mine = SyncedSettings.snapshot(in: defaults)
        #expect(mine[SharedSettings.showsPatterns]?.changedAt == SyncedSettings.chosenLongAgo)
        #expect(mine[SharedSettings.firstWeekday] == SyncSetting(value: nil, changedAt: .distantPast))

        let other = WidgetStoreTests().defaults()
        SyncedSettings.set(.int(2), forKey: SharedSettings.firstWeekday, in: other, now: at(10))
        CalendarStyles.set(CalendarStyle(hex: "#123456"), for: "google:me|home", in: other)
        let theirs = SyncedSettings.snapshot(in: other)
        #expect(theirs[SharedSettings.showsPatterns]?.value == nil)

        let merged = merge(SyncSnapshot(settings: mine), SyncSnapshot(settings: theirs)).settings
        let changed = SyncedSettings.apply(merged, in: other)
        #expect(changed == [SharedSettings.showsPatterns, "calendarStyles|google:me|work"])
        #expect(SharedSettings.showsPatterns(in: other))
        #expect(SharedSettings.firstWeekday(in: other) == 2)
        #expect(CalendarStyles.all(in: other) == ["google:me|work": CalendarStyle(palette: .teal), "google:me|home": CalendarStyle(hex: "#123456")])

        // A calendar set back to 자동 later wins over the colour picked before.
        CalendarStyles.set(CalendarStyle(), for: "google:me|work", in: other)
        let cleared = merge(SyncSnapshot(settings: SyncedSettings.snapshot(in: defaults)), SyncSnapshot(settings: SyncedSettings.snapshot(in: other))).settings
        SyncedSettings.apply(cleared, in: defaults)
        #expect(CalendarStyles.all(in: defaults)["google:me|work"] == nil)
        #expect(SharedSettings.firstWeekday(in: defaults) == 2)
    }

    @Test func choosingTheSameValueAgainIsNotAChange() {
        let defaults = WidgetStoreTests().defaults()
        SyncedSettings.set(.bool(false), forKey: SharedSettings.showsCellTimes, in: defaults, now: at(10))
        SyncedSettings.set(.bool(false), forKey: SharedSettings.showsCellTimes, in: defaults, now: at(20))
        #expect(SyncedSettings.snapshot(in: defaults)[SharedSettings.showsCellTimes]?.changedAt == at(10))
        // This device's own choices are never written out: the folder, the 메모 app copies.
        SyncedSettings.set(.bool(true), forKey: SharedSettings.mirrorsToNotes, in: defaults)
        #expect(SyncedSettings.snapshot(in: defaults)[SharedSettings.mirrorsToNotes] == nil)
    }

    // MARK: Files

    @Test func aFileOfAnotherFormatIsNeitherReadNorWrittenOver() throws {
        let file = SyncFile(device: "A", data: SyncSnapshot(todos: [todo(UUID(), "할 일", at: 1)]))
        let data = try file.encoded()
        #expect(SyncFile.decode(data) == .file(file))
        let newer = Data(#"{"format":3,"device":"A","everything":"else"}"#.utf8)
        #expect(SyncFile.decode(newer) == .unknownFormat(3))
        #expect(SyncFile.decode(Data("아님".utf8)) == .unreadable)

        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "A.json")
        try newer.write(to: url)
        #expect(throws: DiarySync.Failure.newerFormat) { try DiarySync.write(data, to: url, presenter: nil) }
        #expect(try Data(contentsOf: url) == newer)
        try newer.write(to: folder.appending(path: "B.json"))
        #expect(try DiarySync.readOthers(in: folder, except: "C.json", unlessUnchangedFrom: nil, presenter: nil)?.files.isEmpty == true)
    }

    // MARK: The store

    @Test func storeChangesLeaveTimesAndTombstones() throws {
        let container = try SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let item = try #require(try Todos.add("견적서", to: day(3), in: context))
        let made = item.updatedAt
        try Todos.setDone(item.id, true, in: context)
        #expect(item.updatedAt > made)
        #expect(try Todos.link(item.id, to: day(4), in: context))
        let link = try #require(try Todos.entries(for: day(4), in: context).first)
        try Todos.remove(link, in: context)
        try Todos.delete(item.id, in: context)
        let buried = try context.fetch(FetchDescriptor<SyncTombstone>()).map { "\($0.kindRaw)|\($0.key)" }.sorted()
        #expect(buried == ["link|\(link.linkID!.uuidString)", "todo|\(item.id.uuidString)"])

        try Memos.save(AttributedString("오늘"), for: day(3), in: context)
        let memo = try #require(try Memos.note(for: day(3), in: context))
        try Memos.save(AttributedString(" "), for: day(3), in: context)
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).contains { $0.kindRaw == "note" && $0.key == memo.id.uuidString })
    }

    @Test func aMergedSnapshotGoesIntoTheStoreAndBackOut() throws {
        let container = try SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let defaults = WidgetStoreTests().defaults()
        try Memos.save(AttributedString("지울 메모"), for: day(5), in: context)
        let goneMemo = try #require(try Memos.note(for: day(5), in: context)).id
        let kept = try #require(try Todos.add("남을 할 일", to: day(3), in: context))
        let gone = try #require(try Todos.add("지울 할 일", to: day(3), in: context))

        var snapshot = try SyncRecords.read(from: context, defaults: defaults)
        let arrived = note("새 메모", at: 10, key: day(3).key, title: "회의록")
        snapshot.notes = [arrived]
        snapshot.todos.removeAll { $0.id == gone.id }
        snapshot.todos[0].title = "이름 바뀐 할 일"
        snapshot.settings[SharedSettings.firstWeekday] = SyncSetting(value: .int(2), changedAt: at(5))
        let applied = try SyncRecords.apply(snapshot, to: context, defaults: defaults)
        #expect(applied.notes == [arrived.id, goneMemo])
        #expect(applied.periods == ["day|\(day(3).key)", "day|\(day(5).key)"])
        #expect(try Memos.note(for: day(3), in: context)?.title == "회의록")
        #expect(applied.todosChanged)
        #expect(applied.settings == [SharedSettings.firstWeekday])
        #expect(String(try Memos.text(for: day(3), in: context).characters) == "새 메모")
        #expect(try Memos.note(for: day(5), in: context) == nil)
        #expect(try Todos.entries(for: day(3), in: context).map(\.title) == ["이름 바뀐 할 일"])
        #expect(try Todos.item(kept.id, in: context) != nil)
        // Reading it back gives what went in; applying again changes nothing.
        #expect(try SyncRecords.read(from: context, defaults: defaults) == snapshot.sorted)
        #expect(try SyncRecords.apply(snapshot, to: context, defaults: defaults).isEmpty)
    }

    @Test func versionTwoFileOpensAsVersionThree() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Diary.store")
        let todoID: UUID
        do {
            let schema = Schema(versionedSchema: SchemaV2.self)
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration("Diary", schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(old)
            let note = SchemaV2.DiaryNote(period: day(2))
            note.body = MemoText.encode(AttributedString("견적서 보내기"))
            context.insert(note)
            let item = SchemaV2.TodoItem(title: "회의록 정리", period: day(2), order: 1)
            item.isDone = true
            context.insert(item)
            context.insert(SchemaV2.TodoLink(todoID: item.id, period: day(3), order: 1))
            todoID = item.id
            try context.save()
        }

        let context = ModelContext(try SimplifyStore.makeContainer(url: url))
        #expect(String(try Memos.text(for: day(2), in: context).characters) == "견적서 보내기")
        #expect(try Todos.entries(for: day(2), in: context).map(\.title) == ["회의록 정리"])
        #expect(try Todos.entries(for: day(3), in: context).map(\.isDone) == [true])
        #expect(try Todos.item(todoID, in: context)?.isDone == true)
        // The new table works in the old file.
        try Todos.delete(todoID, in: context)
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).count == 2)
    }

    // MARK: Two devices, one folder

    @Test func twoDevicesTradeThroughOneFolder() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeA = try SimplifyStore.makeContainer(inMemory: true), storeB = try SimplifyStore.makeContainer(inMemory: true)
        let defaultsA = WidgetStoreTests().defaults(), defaultsB = WidgetStoreTests().defaults()
        let a = DiarySync(folder: folder, container: storeA, defaults: defaultsA)
        let b = DiarySync(folder: folder, container: storeB, defaults: defaultsB)
        #expect(a.deviceID != b.deviceID)

        // A writes a memo and a ToDo, and picks Monday.
        try Memos.save(AttributedString("A에서 쓴 메모"), for: day(3), in: storeA.mainContext)
        let item = try #require(try Todos.add("A의 할 일", to: day(3), in: storeA.mainContext))
        SyncedSettings.set(.int(2), forKey: SharedSettings.firstWeekday, in: defaultsA)
        try await a.sync()
        #expect(FileManager.default.fileExists(atPath: a.ownFile.path))

        let applied = try #require(try await b.sync())
        let contextB = ModelContext(storeB)
        #expect(applied.notes == [try #require(try Memos.note(for: day(3), in: storeA.mainContext)).id])
        #expect(String(try Memos.text(for: day(3), in: contextB).characters) == "A에서 쓴 메모")
        #expect(try Todos.entries(for: day(3), in: contextB).map(\.title) == ["A의 할 일"])
        #expect(SharedSettings.firstWeekday(in: defaultsB) == 2)

        // B ticks it and deletes the memo; A takes both in.
        try Todos.setDone(item.id, true, in: contextB)
        try Memos.save(AttributedString(), for: day(3), in: contextB)
        try await b.sync()
        try await a.sync()
        let contextA = ModelContext(storeA)
        #expect(try Todos.item(item.id, in: contextA)?.isDone == true)
        #expect(try Memos.note(for: day(3), in: contextA) == nil)

        // An unchanged folder is not read again, and a pass put off takes nothing in.
        #expect(try await a.sync() == SyncRecords.Applied())
        #expect(try await b.sync(force: true, prepare: { false }) == nil)
    }

    @Test func aDeviceThatFellBehindDoesNotBringOldTextBack() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stores = try (0..<3).map { _ in try SimplifyStore.makeContainer(inMemory: true) }
        let engines = stores.map { DiarySync(folder: folder, container: $0, defaults: WidgetStoreTests().defaults()) }
        let (a, b, c) = (engines[0], engines[1], engines[2])
        func memo(_ index: Int) throws -> String { String(try Memos.text(for: day(3), in: ModelContext(stores[index])).characters) }

        // All three agree on the first text.
        try Memos.save(AttributedString("처음 글"), for: day(3), in: stores[0].mainContext)
        try await a.sync(); try await b.sync(); try await c.sync()
        #expect(try memo(2) == "처음 글")
        // C is away while A and B move on, and A then cuts a line.
        try Memos.save(AttributedString("처음 글\n덧붙인 줄"), for: day(3), in: ModelContext(stores[1]))
        try await b.sync(); try await a.sync()
        try Memos.save(AttributedString("덧붙인 줄"), for: day(3), in: ModelContext(stores[0]))
        try await a.sync(force: true)
        // C's old file is no news: nothing comes back under the line.
        #expect(try memo(0) == "덧붙인 줄")
        try await c.sync(); try await b.sync(); try await a.sync(force: true)
        #expect(try (0..<3).map(memo) == ["덧붙인 줄", "덧붙인 줄", "덧붙인 줄"])
    }

    @Test func aMemoWrittenAgainOutlivesItsDeletion() throws {
        let container = try SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        // Deleted with a time ahead of this Mac's clock (the memo came from a faster one).
        let ahead = Date.now.addingTimeInterval(3600)
        context.insert(SyncTombstone(kind: .note, key: "day|\(day(3).key)", deletedAt: ahead))
        try Memos.save(AttributedString("다시 씀"), for: day(3), in: context)
        #expect(try #require(try Memos.note(for: day(3), in: context)).updatedAt > ahead)
    }

    @Test func aLinkToADeletedTodoGoesWithIt() {
        let todoID = UUID()
        let link = SyncLink(id: UUID(), todoID: todoID, scope: "day", periodKey: "2026-11-04", order: 1, createdAt: t0, updatedAt: at(30))
        let deleted = SyncSnapshot(deletions: [SyncDeletion(kind: .todo, key: todoID.uuidString, deletedAt: at(20))])
        #expect(merge(SyncSnapshot(todos: [todo(todoID, "할 일", at: 10)], links: [link]), deleted).links.isEmpty)
        // A link to a ToDo that is simply not here yet stays.
        #expect(merge(SyncSnapshot(links: [link]), SyncSnapshot()).links == [link])
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "simplify-sync-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
