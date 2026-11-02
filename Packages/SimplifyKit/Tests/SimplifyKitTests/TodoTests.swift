import Foundation
import SwiftData
import Testing
@testable import SimplifyKit

@MainActor
struct TodoTests {
    let cal = PeriodTests.calendar()

    private func day(_ d: Int, month: Int = 11) -> Period {
        Period(containing: PeriodTests.date(2026, month, d, in: cal), scope: .day, calendar: cal)
    }

    /// Held here: a context does not keep its container alive.
    let container = try! SimplifyStore.makeContainer(inMemory: true)

    private func context() throws -> ModelContext {
        container.mainContext
    }

    // MARK: Store version

    @Test func versionOneFileOpensAsVersionTwo() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "simplify-v1-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Diary.store")
        let monday = day(2)

        // A file written by stage 5, with V1's own classes.
        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration("Diary", schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(old)
            let note = SchemaV1.DiaryNote(period: monday)
            note.body = MemoText.encode(AttributedString("견적서 보내기"))
            context.insert(note)
            context.insert(SchemaV1.TodoItem(title: "회의록 정리", period: monday, order: 1))
            try context.save()
        }

        let context = ModelContext(try SimplifyStore.makeContainer(url: url))
        #expect(String(try Memos.text(for: monday, in: context).characters) == "견적서 보내기")
        let rows = try Todos.entries(for: monday, in: context)
        #expect(rows.map(\.title) == ["회의록 정리"])
        // The new table works in the old file.
        #expect(try Todos.link(rows[0].todoID, to: day(3), in: context))
        #expect(try Todos.entries(for: day(3), in: context).map(\.title) == ["회의록 정리"])
    }

    // MARK: Links

    @Test func oneTickShowsEverywhereItIsLinked() throws {
        let context = try context()
        let week = Period(containing: day(2).start, scope: .week, calendar: cal)
        let todo = try #require(try Todos.add("워크숍 숙소 확인", to: week, in: context))
        #expect(try Todos.link(todo.id, to: day(2), in: context))
        #expect(try !Todos.link(todo.id, to: day(2), in: context), "a second link to the same day adds nothing")
        #expect(try !Todos.link(todo.id, to: week, in: context), "its own period is not linked again")

        let linked = try #require(try Todos.entries(for: day(2), in: context).first)
        #expect(linked.isLink)
        #expect(linked.elsewhere == [PeriodRef(week)])
        try Todos.setDone(linked.todoID, true, in: context)
        #expect(try Todos.entries(for: week, in: context).first?.isDone == true)
        #expect(try Todos.entries(for: week, in: context).first?.elsewhere == [PeriodRef(day(2))])

        // ⌫ on the link only leaves that day.
        try Todos.remove(linked, in: context)
        #expect(try Todos.entries(for: day(2), in: context).isEmpty)
        #expect(try Todos.entries(for: week, in: context).count == 1)

        // ⌫ on its own row deletes it and its links.
        _ = try Todos.link(todo.id, to: day(3), in: context)
        try Todos.remove(try #require(try Todos.entries(for: week, in: context).first), in: context)
        #expect(try Todos.entries(for: day(3), in: context).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TodoLink>()).isEmpty)
    }

    @Test func renameAndLabelChangeTheOneTodo() throws {
        let context = try context()
        let todo = try #require(try Todos.add("분기 리포트", to: day(2), in: context))
        _ = try Todos.link(todo.id, to: day(5), in: context)
        try Todos.rename(todo.id, to: "  분기 리포트 초안  ", in: context)
        try Todos.rename(todo.id, to: "   ", in: context)
        try Todos.setLabel(todo.id, .red, in: context)
        let row = try #require(try Todos.entries(for: day(5), in: context).first)
        #expect(row.title == "분기 리포트 초안")
        #expect(row.label == .red)
        #expect(try Todos.add("  ", to: day(2), in: context) == nil)
    }

    // MARK: 넘기기

    @Test func passingMovesTheHomeOrTheLink() throws {
        let context = try context()
        let month = Period(containing: day(2).start, scope: .month, calendar: cal)
        let todo = try #require(try Todos.add("견적서 회신", to: day(2), in: context))
        _ = try Todos.add("이미 있는 일", to: day(3), in: context)

        try Todos.pass(try #require(try Todos.entries(for: day(2), in: context).first), to: day(3), in: context)
        #expect(try Todos.entries(for: day(2), in: context).isEmpty)
        #expect(try Todos.entries(for: day(3), in: context).map(\.title) == ["이미 있는 일", "견적서 회신"], "lands at the end")
        #expect(try Todos.item(todo.id, in: context)?.periodKey == day(3).key)

        // A link moves on its own; the home stays.
        _ = try Todos.link(todo.id, to: month, in: context)
        let link = try #require(try Todos.entries(for: month, in: context).first)
        try Todos.pass(link, to: day(4), in: context)
        #expect(try Todos.entries(for: month, in: context).isEmpty)
        #expect(try Todos.entries(for: day(4), in: context).first?.isLink == true)
        #expect(try Todos.item(todo.id, in: context)?.periodKey == day(3).key)

        // Passing the home where a link already is: the link gives way, nothing doubles.
        try Todos.pass(try #require(try Todos.entries(for: day(3), in: context).last), to: day(4), in: context)
        let there = try Todos.entries(for: day(4), in: context)
        #expect(there.count == 1)
        #expect(there.first?.isLink == false)
        #expect(try context.fetch(FetchDescriptor<TodoLink>()).isEmpty)

        // A link passed to the period it already sits in stays.
        let week = Period(containing: day(4).start, scope: .week, calendar: cal)
        _ = try Todos.link(todo.id, to: week, in: context)
        try Todos.pass(try #require(try Todos.entries(for: week, in: context).first), to: week, in: context)
        #expect(try Todos.entries(for: week, in: context).first?.isLink == true)
    }

    // MARK: Order

    @Test func movingARowSlotsItBetweenItsNeighbours() throws {
        let context = try context()
        for title in ["가", "나", "다", "라"] { _ = try Todos.add(title, to: day(2), in: context) }
        var rows = try Todos.entries(for: day(2), in: context)
        try Todos.move(rows[3], to: 1, in: day(2), in: context)
        rows = try Todos.entries(for: day(2), in: context)
        #expect(rows.map(\.title) == ["가", "라", "나", "다"])
        #expect(rows[1].order == 1.5)
        try Todos.move(rows[0], to: 4, in: day(2), in: context)
        #expect(try Todos.entries(for: day(2), in: context).map(\.title) == ["라", "나", "다", "가"])
        // Links share the order space with the day's own rows.
        let other = try #require(try Todos.add("이은 일", to: day(9), in: context))
        _ = try Todos.link(other.id, to: day(2), in: context)
        rows = try Todos.entries(for: day(2), in: context)
        try Todos.move(rows[4], to: 0, in: day(2), in: context)
        #expect(try Todos.entries(for: day(2), in: context).first?.title == "이은 일")
        #expect(Todos.order(between: nil, and: nil) == 1)
        #expect(Todos.order(between: nil, and: 1) == 0)
    }

    // MARK: Counts

    @Test func remainingCountsUnfinishedPerPeriod() throws {
        let context = try context()
        let week = Period(containing: day(2).start, scope: .week, calendar: cal)
        let a = try #require(try Todos.add("가", to: day(2), in: context))
        _ = try Todos.add("나", to: day(2), in: context)
        let c = try #require(try Todos.add("다", to: week, in: context))
        _ = try Todos.link(c.id, to: day(2), in: context)
        try Todos.setDone(a.id, true, in: context)
        let counts = try Todos.remaining(in: context)
        #expect(counts[day(2).key] == 2)
        #expect(counts[week.key] == 1)
        #expect(counts[day(3).key] == nil)
    }

    @Test func monthTallyCountsDaysWeeksAndMonthOnce() throws {
        let context = try context()
        let november = Period(containing: day(2).start, scope: .month, calendar: cal)
        let first = try #require(try Todos.add("월간", to: november, in: context))
        _ = try Todos.link(first.id, to: day(2), in: context)
        _ = try Todos.add("주간", to: Period(containing: day(2).start, scope: .week, calendar: cal), in: context)
        let done = try #require(try Todos.add("하루", to: day(20), in: context))
        try Todos.setDone(done.id, true, in: context)
        // 2026-11-29 (Sunday) starts a week named after November; 10-25 starts one named after October.
        _ = try Todos.add("10월 주", to: Period(containing: day(31, month: 10).start, scope: .week, calendar: cal), in: context)
        _ = try Todos.add("다른 달", to: day(1, month: 12), in: context)
        let tally = try Todos.tally(for: november, in: context)
        #expect(tally.done == 1)
        #expect(tally.total == 3)
    }

    @Test func importListAndSearch() throws {
        let context = try context()
        let here = try #require(try Todos.add("여기 있는 일", to: day(2), in: context))
        _ = try Todos.add("워크숍 숙소 확인", to: day(1), in: context)
        let done = try #require(try Todos.add("워크숍 명단 회신", to: day(1), in: context))
        try Todos.setDone(done.id, true, in: context)
        #expect(try Todos.open(notIn: day(2), in: context).map(\.title) == ["워크숍 숙소 확인"])
        #expect(try Todos.search("워크숍", in: context).map(\.title) == ["워크숍 숙소 확인", "워크숍 명단 회신"])
        #expect(try Todos.search("", in: context).first?.id != done.id)
        _ = here
    }

    // MARK: Memo

    @Test func todoLinesAreFound() {
        var text = AttributedString("오늘 할 것\n[ ] 필라테스 회원권 연장 문의\n- [ ] 우유\nTODO: 세금계산서 발행\ntodo:  \n[x] 끝난 일\n그냥 메모\n")
        text.append(MemoChips.chip(id: UUID(), title: "이미 칩", isDone: false))
        let found = MemoTodoLines.find(in: text)
        #expect(found.map(\.title) == ["필라테스 회원권 연장 문의", "우유", "세금계산서 발행"])
        #expect(found.map(\.line) == [1, 2, 3])
        #expect(MemoTodoLines.title(of: "– 피드백 반영안 정리 ") == "피드백 반영안 정리")
        #expect(MemoTodoLines.title(of: "TODO: 보고") == "보고")
    }

    @Test func lineBecomesAChipThatSurvivesSaving() throws {
        let id = UUID()
        var text = AttributedString("디자인 리뷰\n  [ ] 피드백 반영안\n끝")
        MemoTodoLines.replaceLine(1, in: &text, with: MemoChips.chip(id: id, title: "피드백 반영안", isDone: false))
        #expect(String(text.characters) == "디자인 리뷰\n  □ 피드백 반영안\n끝")

        let back = MemoText.decode(MemoText.encode(text))
        #expect(back == text)
        let chip = try #require(MemoChips.chips(in: back).first)
        #expect(chip.todo == MemoTodo(id: id, isDone: false))
        let json = String(decoding: try #require(MemoText.encode(back)), as: UTF8.self)
        #expect(json.contains("\"td\":\"\(id.uuidString)\""))
        #expect(json.contains("\"tb\":true"), "the box letter keeps its own mark")
        #expect(back.runs[back.characters.firstIndex(of: "□")!][MemoAttributes.TodoBox.self] == true)
    }

    @Test func tickingKeepsAChipsFormatting() throws {
        let id = UUID()
        var text = MemoChips.chip(id: id, title: "숙소", isDone: false)
        text[text.startIndex..<text.endIndex][MemoAttributes.Highlight.self] = .yellow
        let ticked = try #require(MemoChips.refreshed(text) { _ in ("숙소", true) })
        #expect(String(ticked.characters) == "☑ 숙소")
        #expect(ticked.runs[MemoAttributes.Highlight.self].allSatisfy { $0.0 == .yellow })
        #expect(MemoChips.chips(in: ticked).map(\.todo) == [MemoTodo(id: id, isDone: true)])
        #expect(ticked.runs[ticked.startIndex][MemoAttributes.TodoBox.self] == true)
    }

    @Test func boxMarkCopiedOverAChipIsAStray() {
        var text = MemoChips.chip(id: UUID(), title: "숙소", isDone: false)
        // What formatting the whole chip can do: the box's mark lands on every letter.
        text[text.startIndex..<text.endIndex][MemoAttributes.TodoBox.self] = true
        let strays = MemoChips.strayBoxMarks(in: text)
        #expect(String(text[strays].characters) == " 숙소")
        #expect(MemoChips.strayBoxMarks(in: MemoChips.chip(id: UUID(), title: "숙소", isDone: false)).isEmpty)
    }

    @Test func chipsSavedWithoutABoxMarkAreRedrawn() throws {
        let id = UUID()
        var container = AttributeContainer()
        container[MemoAttributes.Todo.self] = MemoTodo(id: id, isDone: false)
        let old = AttributedString("□ 숙소", attributes: container)
        let fresh = try #require(MemoChips.refreshed(old) { _ in ("숙소", false) })
        #expect(fresh.runs[fresh.startIndex][MemoAttributes.TodoBox.self] == true)
        // A box mark on letters that stopped being a chip is a stray.
        var broken = fresh
        broken[broken.startIndex..<broken.endIndex][MemoAttributes.Todo.self] = nil
        #expect(!MemoChips.strays(in: broken) { _ in "숙소" }.isEmpty)
    }

    @Test func chipsFollowTheirTodo() throws {
        let kept = UUID(), gone = UUID()
        var text = AttributedString("앞 ")
        text.append(MemoChips.chip(id: kept, title: "옛 제목", isDone: false))
        text.append(AttributedString("\n"))
        text.append(MemoChips.chip(id: gone, title: "지운 일", isDone: false))
        let fresh = try #require(MemoChips.refreshed(text) { $0 == kept ? ("새 제목", true) : nil })
        #expect(String(fresh.characters) == "앞 ☑ 새 제목\n□ 지운 일")
        #expect(MemoChips.chips(in: fresh).map(\.todo) == [MemoTodo(id: kept, isDone: true)])
        #expect(MemoChips.refreshed(fresh) { _ in ("새 제목", true) } == nil)
    }

    @Test func lettersTypedNextToAChipAreStrays() throws {
        let id = UUID()
        var text = MemoChips.chip(id: id, title: "숙소", isDone: false)
        // Typing after a chip takes on its attributes.
        text.append(AttributedString(" 확인", attributes: chipAttributes(id)))
        let strays = MemoChips.strays(in: text) { _ in "숙소" }
        #expect(String(text[strays].characters) == " 확인")

        // Editing inside breaks the chip back into words.
        let broken = AttributedString("□ 숙", attributes: chipAttributes(id))
        #expect(String(broken[MemoChips.strays(in: broken) { _ in "숙소" }].characters) == "□ 숙")

        let chip = MemoChips.chip(id: id, title: "숙소", isDone: false)
        #expect(MemoChips.chip(withBoxAt: chip.characters.index(after: chip.startIndex), in: chip)?.todo.id == id)
        #expect(MemoChips.chip(withBoxAt: chip.startIndex, in: chip) == nil)
    }

    private func chipAttributes(_ id: UUID) -> AttributeContainer {
        var container = AttributeContainer()
        container[MemoAttributes.Todo.self] = MemoTodo(id: id, isDone: false)
        return container
    }

    // MARK: Period keys

    @Test func periodsComeBackFromTheirKeys() {
        for scope in PeriodScope.allCases {
            for date in [PeriodTests.date(2026, 1, 1, in: cal), PeriodTests.date(2026, 11, 2, in: cal), PeriodTests.date(2026, 12, 31, in: cal)] {
                let period = Period(containing: date, scope: scope, calendar: cal)
                #expect(Period(key: period.key, scope: scope, calendar: cal) == period)
            }
        }
        #expect(Period(key: "2026-13", scope: .month, calendar: cal) == nil)
        #expect(Period(key: "nonsense", scope: .day, calendar: cal) == nil)
    }
}
