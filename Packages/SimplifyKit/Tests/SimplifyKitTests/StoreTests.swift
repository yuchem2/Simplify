import Foundation
import SwiftData
import Testing
@testable import SimplifyKit

@MainActor
struct StoreTests {
    let cal = PeriodTests.calendar()

    @Test func todosAreFiledByPeriodInOrder() throws {
        let container = try SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let monday = Period(containing: PeriodTests.date(2026, 10, 26, in: cal), scope: .day, calendar: cal)
        let week = Period(containing: monday.start, scope: .week, calendar: cal)

        context.insert(TodoItem(title: "피드백 반영안 정리", period: monday, order: 2))
        context.insert(TodoItem(title: "회의록 정리", period: monday, order: 1))
        context.insert(TodoItem(title: "워크숍 숙소 확인", period: week, order: 1))
        try context.save()

        let day = try context.fetch(TodoItem.descriptor(for: monday))
        #expect(day.map(\.title) == ["회의록 정리", "피드백 반영안 정리"])
        #expect(try context.fetch(TodoItem.descriptor(for: week)).map(\.scope) == [.week])
    }

    @Test func noteIsFoundByItsPeriod() throws {
        let container = try SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let month = Period(containing: PeriodTests.date(2026, 10, 15, in: cal), scope: .month, calendar: cal)
        context.insert(DiaryNote(period: month))
        try context.save()

        #expect(try context.fetch(DiaryNote.descriptor(for: month)).first?.scope == .month)
        #expect(try context.fetch(DiaryNote.descriptor(for: month.advanced(by: 1))).isEmpty)
    }
}
