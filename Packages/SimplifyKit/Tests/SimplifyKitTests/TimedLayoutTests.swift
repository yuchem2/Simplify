import Foundation
import Testing
@testable import SimplifyKit

struct TimedLayoutTests {
    let cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    func date(_ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: min))!
    }

    func event(_ title: String, _ start: Date, minutes: Int = 60) -> EventOccurrence {
        EventOccurrence(id: title, eventID: title, sourceID: "s", title: title, location: nil, isAllDay: false,
                        start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    func layout(_ events: [EventOccurrence], minimum: TimeInterval = 0) -> [String] {
        TimedLayout.blocks(events, on: date(30, 0), calendar: cal, minimumDuration: minimum)
            .map { "\($0.occurrence.title) \($0.column)/\($0.columns)" }
    }

    @Test func separateEventsTakeTheFullWidth() {
        #expect(layout([event("A", date(30, 9)), event("B", date(30, 10))]) == ["A 0/1", "B 0/1"])
    }

    @Test func overlappingEventsSitSideBySide() {
        #expect(layout([event("리뷰", date(30, 14)), event("면담", date(30, 14, 30))]) == ["리뷰 0/2", "면담 1/2"])
    }

    @Test func aFreedColumnIsReusedWithinTheGroup() {
        // A runs long; B ends before C starts, so C takes B's column and the group stays two wide.
        let result = layout([event("A", date(30, 9), minutes: 180), event("B", date(30, 9, 30)), event("C", date(30, 11))])
        #expect(result == ["A 0/2", "B 1/2", "C 1/2"])
    }

    @Test func zeroLengthEventsOverlapByTheirDrawnHeight() {
        let events = [event("미리알림", date(30, 17), minutes: 0), event("회의", date(30, 17, 10))]
        #expect(layout(events) == ["미리알림 0/1", "회의 0/1"])
        #expect(layout(events, minimum: 20 * 60) == ["미리알림 0/2", "회의 1/2"])
    }

    @Test func eventOverMidnightIsCutOnBothDays() {
        let late = event("야간", date(29, 23), minutes: 120)
        let blocks = TimedLayout.blocks([late], on: date(30, 0), calendar: cal)
        #expect(blocks.count == 1)
        #expect(blocks[0].start == date(30, 0))
        #expect(blocks[0].end == date(30, 1))
        let before = TimedLayout.blocks([late], on: date(29, 0), calendar: cal)
        #expect(before[0].start == date(29, 23))
        #expect(before[0].end == date(30, 0))
    }

    @Test func bandsAndOtherDaysAreLeftOut() {
        let allDay = EventOccurrence(id: "휴가", eventID: "휴가", sourceID: "s", title: "휴가", location: nil, isAllDay: true,
                                     start: date(30, 0), end: date(31, 0))
        #expect(layout([allDay, event("어제", date(29, 9)), event("오늘", date(30, 9))]) == ["오늘 0/1"])
    }
}
