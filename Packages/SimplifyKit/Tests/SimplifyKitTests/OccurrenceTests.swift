import Foundation
import Testing
@testable import SimplifyKit

struct OccurrenceTests {
    let cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    func date(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
    }

    func timed(_ id: String, _ start: Date, hours: Double = 1) -> EventSnapshot {
        var e = EventSnapshot(id: "s:" + id, sourceID: "s", remoteID: id, title: id, isAllDay: false)
        e.start = start
        e.end = start.addingTimeInterval(hours * 3600)
        e.timeZone = "Asia/Seoul"
        return e
    }

    func allDay(_ id: String, _ startDay: String, _ endDay: String) -> EventSnapshot {
        var e = EventSnapshot(id: "s:" + id, sourceID: "s", remoteID: id, title: id, isAllDay: true)
        e.startDay = startDay
        e.endDay = endDay
        return e
    }

    var october: DateInterval { DateInterval(start: date(9, 28), end: date(11, 2)) }

    @Test func allDayEndIsExclusive() {
        let result = OccurrenceBuilder.occurrences(from: [allDay("휴일", "2026-10-09", "2026-10-10")], in: october, calendar: cal)
        let days = OccurrenceBuilder.byDay(result, days: [date(10, 9), date(10, 10)], calendar: cal)
        #expect(days[date(10, 9)]?.count == 1)
        #expect(days[date(10, 10)]?.isEmpty == true)
    }

    @Test func multiDayBandFlags() {
        let result = OccurrenceBuilder.occurrences(from: [allDay("워크숍", "2026-10-29", "2026-10-31")], in: october, calendar: cal)
        let days = OccurrenceBuilder.byDay(result, days: [date(10, 29), date(10, 30), date(10, 31)], calendar: cal)
        #expect(days[date(10, 29)]?.first?.continuesToNext == true)
        #expect(days[date(10, 29)]?.first?.continuesFromPrevious == false)
        #expect(days[date(10, 30)]?.first?.continuesFromPrevious == true)
        #expect(days[date(10, 30)]?.first?.continuesToNext == false)
        #expect(days[date(10, 31)]?.isEmpty == true)
    }

    /// A late-night event that ends after midnight stays on the day it starts.
    @Test func timedAcrossMidnightStaysOnItsDay() {
        let result = OccurrenceBuilder.occurrences(from: [timed("야간", date(10, 26, 23), hours: 2)], in: october, calendar: cal)
        let days = OccurrenceBuilder.byDay(result, days: [date(10, 26), date(10, 27)], calendar: cal)
        #expect(days[date(10, 26)]?.count == 1)
        #expect(days[date(10, 27)]?.isEmpty == true)
    }

    @Test func bandsComeBeforeTimedEvents() {
        let events = [timed("스탠드업", date(10, 29, 9, 30)), allDay("워크숍", "2026-10-29", "2026-10-31")]
        let result = OccurrenceBuilder.occurrences(from: events, in: october, calendar: cal)
        let slots = OccurrenceBuilder.byDay(result, days: [date(10, 29)], calendar: cal)[date(10, 29)]!
        #expect(slots.map(\.occurrence.title) == ["워크숍", "스탠드업"])
    }

    @Test func seriesWithMovedAndCancelledOccurrences() {
        var series = timed("standup", date(10, 5, 9, 30))
        series.recurrence = Recurrence(rrule: "RRULE:FREQ=WEEKLY;BYDAY=MO", calendar: cal)
        series.exceptionDates = [date(10, 12, 9, 30)]

        var moved = timed("standup_20261019", date(10, 20, 10))
        moved.recurringEventID = "standup"
        moved.originalStart = date(10, 19, 9, 30)
        moved.title = "스탠드업(화)"

        var cancelled = timed("standup_20261026", date(10, 26, 9, 30))
        cancelled.recurringEventID = "standup"
        cancelled.originalStart = date(10, 26, 9, 30)
        cancelled.isCancelled = true

        let result = OccurrenceBuilder.occurrences(from: [series, moved, cancelled], in: october, calendar: cal)
        #expect(result.map { cal.component(.day, from: $0.start) } == [5, 20])
        #expect(result.last?.title == "스탠드업(화)")
    }

    @Test func allDaySeries() {
        var birthday = allDay("생일", "2025-10-15", "2025-10-16")
        birthday.recurrence = Recurrence(rrule: "RRULE:FREQ=YEARLY", calendar: cal)
        let result = OccurrenceBuilder.occurrences(from: [birthday], in: october, calendar: cal)
        #expect(result.count == 1)
        #expect(result.first?.start == date(10, 15))
        #expect(result.first?.end == date(10, 16))
    }

    /// A series the engine cannot expand shows only the occurrences stored for it.
    @Test func unsupportedSeriesUsesStoredOccurrences() {
        var series = timed("odd", date(10, 1, 9))
        series.recurrenceUnsupported = true
        var instance = timed("odd_1", date(10, 7, 9))
        instance.recurringEventID = "odd"
        instance.originalStart = date(10, 7, 9)
        let result = OccurrenceBuilder.occurrences(from: [series, instance], in: october, calendar: cal)
        #expect(result.map { cal.component(.day, from: $0.start) } == [7])
    }

    @Test func cancelledSingleEventIsHidden() {
        var event = timed("취소", date(10, 26, 9))
        event.isCancelled = true
        #expect(OccurrenceBuilder.occurrences(from: [event], in: october, calendar: cal).isEmpty)
    }

    /// An all-day series keeps its EXDATE and date-only UNTIL on the same calendar days after the
    /// person moves to another time zone.
    @Test func allDaySeriesExceptionsSurviveAZoneChange() throws {
        let event = try JSONDecoder().decode(GoogleEvent.self, from: Data(#"""
        {"id":"gym","summary":"헬스","start":{"date":"2026-10-05"},"end":{"date":"2026-10-06"},
         "recurrence":["RRULE:FREQ=WEEKLY;UNTIL=20261026","EXDATE;VALUE=DATE:20261012"]}
        """#.utf8)).snapshot(sourceID: "s", calendar: cal, defaultZone: "Asia/Seoul")
        for zone in ["Asia/Seoul", "America/Los_Angeles", "Pacific/Kiritimati"] {
            var local = Calendar(identifier: .gregorian)
            local.timeZone = TimeZone(identifier: zone)!
            let october = DateInterval(start: local.date(from: DateComponents(year: 2026, month: 10, day: 1))!,
                                       end: local.date(from: DateComponents(year: 2026, month: 11, day: 1))!)
            let days = OccurrenceBuilder.occurrences(from: [event], in: october, calendar: local).map { local.component(.day, from: $0.start) }
            #expect(days == [5, 19, 26], "\(zone)")
        }
    }
}
