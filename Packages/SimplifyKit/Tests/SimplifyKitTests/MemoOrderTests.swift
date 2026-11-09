import Foundation
import SwiftData
import Testing
@testable import SimplifyKit

/// A period's memos put in another order by dragging: places in the store, on the way between
/// devices, and the store from before places.
@MainActor
struct MemoOrderTests {
    let cal = PeriodTests.calendar()
    let t = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private var day: Period { Period(containing: PeriodTests.date(2026, 11, 4, in: cal), scope: .day, calendar: cal) }

    private func three(_ context: ModelContext) throws -> [DiaryNote] {
        try (0..<3).map { try Memos.create(in: day, in: context, now: t.addingTimeInterval(Double($0))) }
    }

    @Test func movingGivesPlacesOnceThenOnlyTheMovedMemoChanges() throws {
        let container = try SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let memos = try three(context)
        let (a, b, c) = (memos[0], memos[1], memos[2])
        #expect(memos.allSatisfy { $0.order == nil })
        // C to the front: every memo gets its place first, then C goes before A.
        let before = c.updatedAt
        #expect(try Memos.move(c.id, to: 0, in: context, now: t.addingTimeInterval(10)))
        #expect(try Memos.notes(for: day, in: context).map(\.id) == [c.id, a.id, b.id])
        #expect([a.order, b.order, c.order] == [0, 1, -1])
        #expect(c.updatedAt > before)
        let (aTime, bTime) = (a.updatedAt, b.updatedAt)
        // A to the end (index counted before the move): only A changes.
        #expect(try Memos.move(a.id, to: 3, in: context, now: t.addingTimeInterval(20)))
        #expect(try Memos.notes(for: day, in: context).map(\.id) == [c.id, b.id, a.id])
        #expect([a.order, b.order, c.order] == [2, 1, -1])
        #expect(b.updatedAt == bTime && a.updatedAt > aTime)
        // Between two others: the middle value.
        #expect(try Memos.move(a.id, to: 1, in: context, now: t.addingTimeInterval(30)))
        #expect(a.order == 0)
        #expect(try Memos.notes(for: day, in: context).map(\.id) == [c.id, a.id, b.id])
        // Onto its own place: nothing moves.
        #expect(try !Memos.move(a.id, to: 1, in: context))
        #expect(try !Memos.move(a.id, to: 2, in: context))
        // A memo made afterwards comes last.
        let d = try Memos.create(in: day, in: context, now: t.addingTimeInterval(40))
        #expect(try Memos.notes(for: day, in: context).map(\.id) == [c.id, a.id, b.id, d.id])
        // Dragged next, only it is given a place after the others: places already given stay,
        // so another device that has them agrees.
        let (bTime2, cTime) = (b.updatedAt, c.updatedAt)
        #expect(try Memos.move(d.id, to: 1, in: context, now: t.addingTimeInterval(50)))
        #expect(try Memos.notes(for: day, in: context).map(\.id) == [c.id, d.id, a.id, b.id])
        #expect([a.order, b.order, c.order] == [0, 1, -1] && d.order == -0.5)
        #expect(b.updatedAt == bTime2 && c.updatedAt == cTime)
    }

    @Test func memosWithoutAPlaceComeAfterTheOnesWithOne() throws {
        let container = try SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let memos = try three(context)
        // Another device's build gave only C a place.
        memos[2].order = 5
        #expect(Memos.ordered(memos).map(\.id) == [memos[2].id, memos[0].id, memos[1].id])
        memos[2].order = nil
        #expect(Memos.ordered(memos.reversed()).map(\.id) == memos.map(\.id))
    }

    @Test func versionFourFileOpensAsVersionFive() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "simplify-v5-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Diary.store")
        var ids: [UUID] = []
        do {
            let schema = Schema(versionedSchema: SchemaV4.self)
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration("Diary", schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(old)
            for (index, name) in ["회의록", "새 메모"].enumerated() {
                let note = SchemaV4.DiaryNote(period: day, title: name, createdAt: t.addingTimeInterval(Double(index)))
                note.body = MemoText.encode(AttributedString("\(name) 글"))
                context.insert(note)
                ids.append(note.id)
            }
            try context.save()
        }
        let context = ModelContext(try SimplifyStore.makeContainer(url: url))
        let notes = try Memos.notes(for: day, in: context)
        #expect(notes.map(\.id) == ids)
        #expect(notes.allSatisfy { $0.order == nil })
        #expect(notes.map(\.title) == ["회의록", "새 메모"])
        #expect(String(MemoText.decode(notes[0].body).characters) == "회의록 글")
        #expect(try Memos.move(ids[1], to: 0, in: context))
        #expect(try Memos.notes(for: day, in: context).map(\.id) == [ids[1], ids[0]])
    }

    // MARK: Between devices

    private func note(_ id: UUID, at seconds: Double, order: Double?, title: String = "") -> SyncNote {
        SyncNote(id: id, scope: "day", periodKey: "2026-11-04", body: MemoText.encode(AttributedString("글"))!,
                 updatedAt: t.addingTimeInterval(seconds), title: title, order: order)
    }

    @Test func aPlaceTravelsAndAnOlderFileWithoutOneStillReads() throws {
        let id = UUID()
        let encoded = try JSONEncoder().encode(note(id, at: 0, order: 2.5))
        #expect(try JSONDecoder().decode(SyncNote.self, from: encoded).order == 2.5)
        // Before a memo is dragged, the key is left out.
        let plain = try JSONEncoder().encode(note(id, at: 0, order: nil))
        #expect(!String(decoding: plain, as: UTF8.self).contains("order"))
        #expect(try JSONDecoder().decode(SyncNote.self, from: plain).order == nil)
    }

    @Test func theNewerPlaceWinsAndNoPlaceTakesNothingAway() {
        let id = UUID()
        func merged(_ mine: SyncNote, _ theirs: SyncNote) -> Double? {
            SyncMerge.merge(local: SyncSnapshot(notes: [mine]), localDevice: "A", remote: SyncSnapshot(notes: [theirs]),
                            remoteDevice: "B", taken: [:], now: t).notes.first?.order
        }
        #expect(merged(note(id, at: 10, order: 1), note(id, at: 20, order: 3)) == 3)
        #expect(merged(note(id, at: 30, order: 1), note(id, at: 20, order: 3)) == 1)
        // A build that did not know about places wrote the newer side: the place stays.
        #expect(merged(note(id, at: 10, order: 1), note(id, at: 20, order: nil)) == 1)
        #expect(merged(note(id, at: 30, order: nil), note(id, at: 20, order: 4)) == 4)
        #expect(merged(note(id, at: 30, order: nil), note(id, at: 20, order: nil)) == nil)
    }

    @Test func aPlaceGoesIntoTheStoreAndBackOut() throws {
        let container = try SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let defaults = WidgetStoreTests().defaults()
        let memos = try three(context)
        var snapshot = try SyncRecords.read(from: context, defaults: defaults)
        #expect(snapshot.notes.allSatisfy { $0.order == nil })
        let index = try #require(snapshot.notes.firstIndex { $0.id == memos[2].id })
        snapshot.notes[index].order = -1
        snapshot.notes[index].updatedAt = t.addingTimeInterval(50)
        let applied = try SyncRecords.apply(snapshot, to: context, defaults: defaults)
        #expect(applied.notes == [memos[2].id])
        #expect(applied.periods == ["day|\(day.key)"])
        #expect(try Memos.notes(for: day, in: context).map(\.id) == [memos[2].id, memos[0].id, memos[1].id])
        #expect(try SyncRecords.read(from: context, defaults: defaults) == snapshot.sorted)
        #expect(try SyncRecords.apply(snapshot, to: context, defaults: defaults).isEmpty)
    }
}
