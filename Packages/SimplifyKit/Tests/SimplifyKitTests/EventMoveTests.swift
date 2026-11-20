import Foundation
import Testing
@testable import SimplifyKit

/// Dragging an event to another day: only its days change.
struct EventMoveTests {
    @Test func allDayKeepsMidnights() {
        // 11/16–11/17 (ends at midnight after the 17th), dropped from the 16th onto the 20th.
        let days = EventMove.days(from: kst(11, 16), to: kst(11, 20), calendar: seoul)
        #expect(days == 4)
        let moved = EventMove.shift(start: kst(11, 16), end: kst(11, 18), byDays: days, calendar: seoul)
        #expect(moved.start == kst(11, 20))
        #expect(moved.end == kst(11, 22))
    }

    @Test func timedKeepsClockAndLength() {
        // Picked up anywhere in the day: the time of day of the drop day does not matter.
        let days = EventMove.days(from: kst(11, 16, 23, 30), to: kst(11, 13, 0, 5), calendar: seoul)
        #expect(days == -3)
        let moved = EventMove.shift(start: kst(11, 16, 9, 30), end: kst(11, 16, 11), byDays: days, calendar: seoul)
        #expect(moved.start == kst(11, 13, 9, 30))
        #expect(moved.end == kst(11, 13, 11))
    }

    @Test func bandMovesFromTheDayPickedUp() {
        // A band over 11/16–11/18, picked up on its middle day (17th) and dropped on the 25th:
        // the 17th goes to the 25th, so the band runs 11/24–11/26.
        let days = EventMove.days(from: kst(11, 17), to: kst(11, 25), calendar: seoul)
        #expect(days == 8)
        let moved = EventMove.shift(start: kst(11, 16), end: kst(11, 19), byDays: days, calendar: seoul)
        #expect(moved.start == kst(11, 24))
        #expect(moved.end == kst(11, 27))
        // A timed band too: 11/16 22:00 → 11/18 08:00.
        let timed = EventMove.shift(start: kst(11, 16, 22), end: kst(11, 18, 8), byDays: days, calendar: seoul)
        #expect(timed.start == kst(11, 24, 22))
        #expect(timed.end == kst(11, 26, 8))
    }

    @Test func daylightSavingKeepsClockTimes() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        func ny(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
            newYork.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }
        // Clocks go forward on Sunday 2026-03-08: 9 to 10 on the 6th becomes 9 to 10 on the 9th,
        // not 10 to 11 as a move by 72 hours would.
        let days = EventMove.days(from: ny(3, 6), to: ny(3, 9), calendar: newYork)
        #expect(days == 3)
        let moved = EventMove.shift(start: ny(3, 6, 9), end: ny(3, 6, 10), byDays: days, calendar: newYork)
        #expect(moved.start == ny(3, 9, 9))
        #expect(moved.end == ny(3, 9, 10))
        #expect(moved.start.timeIntervalSince(ny(3, 6, 9)) == 3 * 86400 - 3600)
        // All day across the change still runs midnight to midnight.
        let allDay = EventMove.shift(start: ny(3, 7), end: ny(3, 8), byDays: 1, calendar: newYork)
        #expect(allDay.start == ny(3, 8))
        #expect(allDay.end == ny(3, 9))
    }

    @Test func sameDayIsNoMove() {
        #expect(EventMove.days(from: kst(11, 16, 1), to: kst(11, 16, 23), calendar: seoul) == 0)
        let moved = EventMove.shift(start: kst(11, 16, 9), end: kst(11, 16, 10), byDays: 0, calendar: seoul)
        #expect(moved.start == kst(11, 16, 9))
        #expect(moved.end == kst(11, 16, 10))
    }

    @Test func dragItemReadsBack() throws {
        let item = EventDragItem(occurrenceID: "google:abc:20261116T090000Z", day: kst(11, 16))
        let data = try JSONEncoder().encode(item)
        #expect(try JSONDecoder().decode(EventDragItem.self, from: data) == item)
    }
}
