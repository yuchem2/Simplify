import Foundation
import Testing
@testable import SimplifyKit

struct BandLanesTests {
    let cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    func date(_ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }

    /// Sunday 10.25 to Saturday 10.31.
    var week: [Date] { (25...31).map { date(10, $0) } }

    /// All-day from `first` to `last` October, inclusive.
    func band(_ title: String, _ first: Int, _ last: Int, completed: Bool = false) -> EventOccurrence {
        EventOccurrence(id: title, eventID: title, sourceID: "s", title: title, location: nil, isAllDay: true,
                        start: date(10, first), end: date(10, last + 1), isCompleted: completed)
    }

    func timed(_ title: String, _ day: Int, _ hour: Int) -> EventOccurrence {
        EventOccurrence(id: title, eventID: title, sourceID: "s", title: title, location: nil, isAllDay: false,
                        start: date(10, day, hour), end: date(10, day, hour + 1))
    }

    func lanes(_ occurrences: [EventOccurrence]) -> [String: Int] {
        let lanes = BandLanes(occurrences, days: week, calendar: cal)
        return Dictionary(uniqueKeysWithValues: occurrences.compactMap { o in lanes.lane(of: o).map { (o.title, $0) } })
    }

    @Test func bandKeepsItsRowAfterAnEarlierBandEnds() {
        let result = lanes([band("마감", 25, 27), band("스프린트", 26, 29), band("워크숍", 29, 31)])
        #expect(result == ["마감": 0, "스프린트": 1, "워크숍": 0])
    }

    @Test func longerBandFirstOnTheSameStart() {
        let result = lanes([band("짧은", 26, 26), band("긴", 26, 30)])
        #expect(result == ["긴": 0, "짧은": 1])
    }

    @Test func bandsFromAnotherWeekAreCutAtTheWeekEdges() {
        let lanes = BandLanes([band("여행", 20, 27), band("휴가", 30, 31),
            EventOccurrence(id: "다음", eventID: "다음", sourceID: "s", title: "다음", location: nil, isAllDay: true,
                            start: date(10, 30), end: date(11, 4)),
        ], days: week, calendar: cal)
        let spans = lanes.placements.map { "\($0.occurrence.title) \($0.lane) \($0.firstDay)-\($0.lastDay)" }
        #expect(spans == ["여행 0 0-2", "다음 0 5-6", "휴가 1 5-6"])
        #expect(lanes.count == 2)
    }

    @Test func timedEventsTakeNoRow() {
        let lanes = BandLanes([timed("회의", 26, 9), band("휴가", 26, 26)], days: week, calendar: cal)
        #expect(lanes.placements.map(\.occurrence.title) == ["휴가"])
        #expect(lanes.lane(of: timed("회의", 26, 9)) == nil)
    }

    @Test func completedRemindersGoBelowOpenOnes() {
        let result = lanes([band("반품", 25, 25, completed: true), band("서류", 25, 25)])
        #expect(result == ["서류": 0, "반품": 1])
    }

    @Test func rowsLeaveGapsAndKeepTimedAfter() {
        let occurrences = [band("마감", 25, 27), band("스프린트", 26, 29), band("워크숍", 29, 31), timed("회의", 28, 9)]
        let lanes = BandLanes(occurrences, days: week, calendar: cal)
        let slots = OccurrenceBuilder.byDay(occurrences, days: week, calendar: cal)
        // Wednesday 10.28: 마감 is over, 스프린트 stays on the second row.
        let wednesday = lanes.rows(slots[date(10, 28)]!).map { $0?.occurrence.title }
        #expect(wednesday == [nil, "스프린트", "회의"])
        let thursday = lanes.rows(slots[date(10, 29)]!).map { $0?.occurrence.title }
        #expect(thursday == ["워크숍", "스프린트"])
    }
}
