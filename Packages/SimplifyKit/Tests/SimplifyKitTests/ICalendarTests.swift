import Foundation
import Testing
@testable import SimplifyKit

struct ICalendarTests {
    let cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    func ics(_ body: String) -> String {
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" + body.replacingOccurrences(of: "\n", with: "\r\n") + "\r\nEND:VCALENDAR\r\n"
    }

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func timedEventWithZoneFoldingAndEscapes() {
        let text = ics("""
        BEGIN:VEVENT
        UID:abc-1
        DTSTART;TZID=America/New_York:20261026T090000
        DTEND;TZID=America/New_York:20261026T100000
        SUMMARY:디자인 리뷰\\, 2차 \\; 최종
        LOCATION:3층 회의
         실 A
        BEGIN:VALARM
        SUMMARY:알림
        TRIGGER:-PT10M
        END:VALARM
        END:VEVENT
        """)
        let events = ICalendar.events(in: text, sourceID: "s", href: "/c/abc-1.ics", calendar: cal)
        #expect(events.count == 1)
        let event = events[0]
        #expect(event.id == "s:abc-1")
        #expect(event.title == "디자인 리뷰, 2차 ; 최종")
        #expect(event.location == "3층 회의실 A")
        #expect(event.resourceHref == "/c/abc-1.ics")
        #expect(event.timeZone == "America/New_York")
        // 9:00 in New York (EDT, UTC-4) is 22:00 in Seoul.
        #expect(event.start == at(26, 22))
        #expect(event.end == at(26, 23))
    }

    @Test func allDayWithEndOrDuration() {
        let text = ics("""
        BEGIN:VEVENT
        UID:trip
        DTSTART;VALUE=DATE:20261029
        DTEND;VALUE=DATE:20261101
        SUMMARY:제주 여행
        END:VEVENT
        BEGIN:VEVENT
        UID:day
        DTSTART;VALUE=DATE:20261009
        DURATION:P1D
        SUMMARY:한글날
        END:VEVENT
        """)
        let events = ICalendar.events(in: text, sourceID: "s", href: "/h", calendar: cal)
        #expect(events.map(\.startDay) == ["2026-10-29", "2026-10-09"])
        #expect(events.map(\.endDay) == ["2026-11-01", "2026-10-10"])
        #expect(events.allSatisfy { $0.isAllDay })
    }

    @Test func utcFloatingAndWindowsZones() {
        let text = ics("""
        BEGIN:VEVENT
        UID:utc
        DTSTART:20261026T000000Z
        DURATION:PT1H30M
        END:VEVENT
        BEGIN:VEVENT
        UID:floating
        DTSTART:20261026T090000
        END:VEVENT
        BEGIN:VEVENT
        UID:outlook
        DTSTART;TZID="Korea Standard Time":20261026T140000
        DTEND;TZID="Korea Standard Time":20261026T150000
        STATUS:CANCELLED
        END:VEVENT
        """)
        let events = ICalendar.events(in: text, sourceID: "s", href: "/h", calendar: cal, defaultZone: "Asia/Tokyo")
        #expect(events[0].start == at(26, 9))
        #expect(events[0].end == at(26, 10, 30))
        #expect(events[0].title == "(제목 없음)")
        // Floating: in the calendar collection's zone (Tokyo, same offset as Seoul), and repeats there.
        #expect(events[1].start == at(26, 9))
        #expect(events[1].timeZone == "Asia/Tokyo")
        #expect(events[2].timeZone == "Asia/Seoul")
        #expect(events[2].start == at(26, 14))
        #expect(events[2].isCancelled)
    }

    @Test func seriesWithExceptionAndMovedOccurrence() {
        let text = ics("""
        BEGIN:VEVENT
        UID:standup
        DTSTART;TZID=Asia/Seoul:20261005T093000
        DTEND;TZID=Asia/Seoul:20261005T100000
        RRULE:FREQ=WEEKLY;BYDAY=MO
        EXDATE;TZID=Asia/Seoul:20261012T093000
        SUMMARY:스탠드업
        END:VEVENT
        BEGIN:VEVENT
        UID:standup
        RECURRENCE-ID;TZID=Asia/Seoul:20261019T093000
        DTSTART;TZID=Asia/Seoul:20261020T110000
        DTEND;TZID=Asia/Seoul:20261020T113000
        SUMMARY:스탠드업 (화요일로)
        END:VEVENT
        """)
        let events = ICalendar.events(in: text, sourceID: "s", href: "/h", calendar: cal)
        #expect(events.count == 2)
        #expect(events[0].recurrence?.frequency == .weekly)
        #expect(events[1].id == "s:standup@20261019T093000")
        #expect(events[1].recurringEventID == "standup")
        #expect(events[1].originalStart == at(19, 9, 30))

        let october = DateInterval(start: at(1, 0), end: at(1, 0, month: 11))
        let starts = OccurrenceBuilder.occurrences(from: events, in: october, calendar: cal).map(\.start)
        #expect(starts == [at(5, 9, 30), at(20, 11), at(26, 9, 30)])
    }

    @Test func allDaySeriesExcludesByDay() {
        let text = ics("""
        BEGIN:VEVENT
        UID:gym
        DTSTART;VALUE=DATE:20261001
        DTEND;VALUE=DATE:20261002
        RRULE:FREQ=DAILY;INTERVAL=10;UNTIL=20261031
        EXDATE;VALUE=DATE:20261011
        SUMMARY:정기 점검
        END:VEVENT
        """)
        let events = ICalendar.events(in: text, sourceID: "s", href: "/h", calendar: cal)
        let october = DateInterval(start: at(1, 0), end: at(1, 0, month: 11))
        let days = OccurrenceBuilder.occurrences(from: events, in: october, calendar: cal).map { cal.component(.day, from: $0.start) }
        #expect(days == [1, 21, 31])
    }

    @Test func extraDatesAndOddRulesAreLeftToTheServer() {
        let text = ics("""
        BEGIN:VEVENT
        UID:rdate
        DTSTART:20261001T000000Z
        RRULE:FREQ=MONTHLY
        RDATE:20261015T000000Z
        END:VEVENT
        BEGIN:VEVENT
        UID:weekno
        DTSTART:20261001T000000Z
        RRULE:FREQ=YEARLY;BYWEEKNO=20
        END:VEVENT
        """)
        let events = ICalendar.events(in: text, sourceID: "s", href: "/h", calendar: cal)
        #expect(events.map(\.recurrenceUnsupported) == [true, true])
        #expect(events.allSatisfy { $0.recurrence == nil })
    }

    @Test func durations() {
        func parts(_ text: String) -> [Double]? { ICalendar.parseDuration(text).map { [Double($0.days), $0.seconds] } }
        #expect(parts("P1D") == [1, 0])
        #expect(parts("PT1H30M") == [0, 5400])
        #expect(parts("P2W") == [14, 0])
        #expect(parts("P1DT2H") == [1, 7200])
        #expect(parts("bogus") == nil)
    }

    @Test func zoneNames() {
        #expect(ICalendar.timeZoneID("Asia/Seoul") == "Asia/Seoul")
        #expect(ICalendar.timeZoneID("Pacific Standard Time") == "America/Los_Angeles")
        #expect(ICalendar.timeZoneID("/mozilla.org/20050126_1/Europe/Berlin") == "Europe/Berlin")
        #expect(ICalendar.timeZoneID("Nowhere Time") == nil)
    }
}
