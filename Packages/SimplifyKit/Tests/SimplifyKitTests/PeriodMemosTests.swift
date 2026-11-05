import Foundation
import SwiftData
import Testing
@testable import SimplifyKit

/// Several memos in one day, week or month: names, making, renaming, leaving, and the store from before.
@MainActor
struct PeriodMemosTests {
    let cal = PeriodTests.calendar()

    private var day: Period { Period(containing: PeriodTests.date(2026, 11, 4, in: cal), scope: .day, calendar: cal) }

    @Test func namesFollowTheNewMemoRule() {
        #expect(Memos.names([]) == [])
        // A memo from before shows as 새 메모; a stored 새 메모 pushes it on to the first free number.
        #expect(Memos.names([""]) == ["새 메모"])
        #expect(Memos.names(["", "새 메모"]) == ["새 메모(1)", "새 메모"])
        #expect(Memos.names(["회의록", "", "새 메모(1)"]) == ["회의록", "새 메모", "새 메모(1)"])
        // Two of one name (made apart on two devices) show apart.
        #expect(Memos.names(["회의록", "회의록"]) == ["회의록", "회의록(1)"])
        #expect(Memos.freeName("새 메모", taken: ["새 메모", "새 메모(1)", "새 메모(3)"]) == "새 메모(2)")
        #expect(Memos.isDefaultName("새 메모") && Memos.isDefaultName("새 메모(12)"))
        #expect(!Memos.isDefaultName("새 메모 정리") && !Memos.isDefaultName("새 메모()") && !Memos.isDefaultName("새 메모(a)"))
    }

    @Test func makingRenamingAndLeavingMemos() throws {
        let container = try SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let t = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let first = try #require(try Memos.saveFirst(AttributedString("그냥 쓴 메모"), for: day, in: context, now: t))
        #expect(first.title == "")
        #expect(try Memos.saveFirst(AttributedString(" \n"), for: day, in: context) == nil)
        let second = try Memos.create(in: day, in: context, now: t.addingTimeInterval(1))
        let third = try Memos.create(in: day, in: context, now: t.addingTimeInterval(2))
        #expect([second.title, third.title] == ["새 메모(1)", "새 메모(2)"])
        #expect(try Memos.notes(for: day, in: context).map(\.id) == [first.id, second.id, third.id])

        // A typed name another memo shows gets a number; cleared, it takes the 새 메모 rule.
        #expect(try Memos.rename(second.id, to: "  회의록 ", in: context) == "회의록")
        #expect(try Memos.rename(third.id, to: "회의록", in: context) == "회의록(1)")
        #expect(try Memos.rename(third.id, to: "", in: context) == "새 메모(1)")
        // The name a memo from before shows, unchanged, keeps its empty title.
        #expect(try Memos.rename(first.id, to: "새 메모", in: context) == "새 메모")
        #expect(first.title == "")
        let renamedAt = second.updatedAt
        #expect(try Memos.rename(second.id, to: "회의록", in: context) == "회의록")
        #expect(second.updatedAt == renamedAt)

        // Blank and still 새 메모(n): it goes when left. Renamed: it stays, empty.
        try Memos.save(AttributedString(), note: second.id, in: context)
        #expect(try !Memos.discardIfEmpty(second.id, in: context))
        #expect(try Memos.discardIfEmpty(third.id, in: context))
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).map(\.key) == [third.id.uuidString])
        // An empty 회의록 still marks the day; the memo from before, emptied and left, goes.
        try Memos.save(AttributedString(" "), note: first.id, in: context)
        #expect(try Memos.discardIfEmpty(first.id, in: context))
        #expect(try Memos.keys(in: context) == [day.key])
        #expect(try Memos.notes(for: day, in: context).map(\.title) == ["회의록"])
        // A memo made after the last one went is 새 메모 again.
        try Memos.delete(second.id, in: context)
        #expect(try Memos.create(in: day, in: context).title == "새 메모")
        #expect(try Memos.keys(in: context).isEmpty)
    }

    @Test func savingByIdLeavesTheOtherMemosAlone() throws {
        let container = try SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let a = try Memos.create(in: day, in: context), b = try Memos.create(in: day, in: context)
        try Memos.save(AttributedString("가"), note: a.id, in: context)
        try Memos.save(AttributedString("나"), note: b.id, in: context)
        #expect(try Memos.notes(for: day, in: context).map { String(MemoText.decode($0.body).characters) } == ["가", "나"])
        try Memos.delete(a.id, in: context)
        #expect(try !Memos.save(AttributedString("다"), note: a.id, in: context))
        #expect(String(try Memos.text(for: day, in: context).characters) == "나")
    }

    @Test func notesNamesCarryTheMemosName() {
        let week = Period(containing: day.start, scope: .week, calendar: cal)
        let month = Period(containing: day.start, scope: .month, calendar: cal)
        #expect(NotesHTML.noteName(for: day, memo: nil) == "2026년 11월 4일 (수)")
        #expect(NotesHTML.noteName(for: day, memo: "새 메모(1)") == "2026년 11월 4일 (수) - 새 메모(1)")
        #expect(NotesHTML.noteName(for: week, memo: "회의록") == "2026년 11월 1주차 (11.1 – 11.7) - 회의록")
        #expect(NotesHTML.noteName(for: month, memo: "새 메모") == "2026년 11월 - 새 메모")
    }

    @Test func versionThreeFileOpensAsVersionFour() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "simplify-v4-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Diary.store")
        let noteID: UUID
        do {
            let schema = Schema(versionedSchema: SchemaV3.self)
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration("Diary", schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(old)
            let note = SchemaV3.DiaryNote(period: day)
            note.body = MemoText.encode(AttributedString("온톨로지 특강"))
            context.insert(note)
            context.insert(SchemaV3.SyncTombstone(kind: .note, key: "day|2026-11-03", deletedAt: .now))
            noteID = note.id
            try context.save()
        }
        let before = Date.now
        let context = ModelContext(try SimplifyStore.makeContainer(url: url))
        let notes = try Memos.notes(for: day, in: context)
        #expect(notes.map(\.id) == [noteID])
        #expect(notes.first?.title == "")
        #expect(String(MemoText.decode(notes.first?.body).characters) == "온톨로지 특강")
        #expect(Memos.names(notes.map(\.title)) == ["새 메모"])
        // A second memo of the day comes after it.
        let second = try Memos.create(in: day, in: context, now: before.addingTimeInterval(60))
        #expect(second.title == "새 메모(1)")
        #expect(try Memos.notes(for: day, in: context).map(\.id) == [noteID, second.id])
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).count == 1)
    }
}

/// A copy of a real diary store (`SIMPLIFY_STORE_COPY`, a folder holding `Diary.store*`), opened
/// as V3 and then brought up to V4: every memo is still there with the same words. Skipped
/// without the variable; never pointed at the live store.
@MainActor
struct RealStoreUpgradeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SIMPLIFY_STORE_COPY"] != nil))
    func aRealStoreKeepsEveryMemo() throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIMPLIFY_STORE_COPY"]!).appending(path: "Diary.store")
        let before: [UUID: Data?]
        do {
            let schema = Schema(versionedSchema: SchemaV3.self)
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration("Diary", schema: schema, url: url, cloudKitDatabase: .none))
            before = Dictionary(uniqueKeysWithValues: try ModelContext(old).fetch(FetchDescriptor<SchemaV3.DiaryNote>()).map { ($0.id, $0.body) })
        }
        let context = ModelContext(try SimplifyStore.makeContainer(url: url))
        let after = try context.fetch(FetchDescriptor<DiaryNote>())
        print("real store: \(before.count) memos before, \(after.count) after")
        #expect(after.count == before.count)
        #expect(after.allSatisfy { before[$0.id] == $0.body && $0.title.isEmpty })
        #expect(after.allSatisfy { MemoText.decodeIfReadable($0.body) != nil })
    }
}
