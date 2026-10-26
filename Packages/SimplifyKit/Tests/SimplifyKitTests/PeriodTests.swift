import Foundation
import Testing
@testable import SimplifyKit

struct PeriodTests {
    static func calendar(_ zone: String = "Asia/Seoul") -> Calendar {
        var calendar = Calendar.simplify
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, in calendar: Calendar = calendar()) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    let cal = PeriodTests.calendar()
    func period(_ y: Int, _ m: Int, _ d: Int, _ scope: PeriodScope) -> Period {
        Period(containing: Self.date(y, m, d, in: cal), scope: scope, calendar: cal)
    }

    @Test func keys() {
        #expect(period(2026, 10, 26, .day).key == "2026-10-26")
        #expect(period(2026, 10, 28, .week).key == "2026-W44")
        #expect(period(2026, 10, 1, .month).key == "2026-10")
    }

    /// Week 1 is the week holding 1 January, so the last days of December can belong to it.
    @Test func weeksAcrossTheYearEnd() {
        #expect(period(2026, 12, 26, .week).key == "2026-W52")
        #expect(period(2026, 12, 31, .week).key == "2027-W01")
        #expect(period(2027, 1, 2, .week).key == "2027-W01")
        #expect(period(2027, 1, 3, .week).key == "2027-W02")
    }

    @Test func weekStartsOnSunday() {
        let week = period(2026, 10, 28, .week)
        #expect(week.start == Self.date(2026, 10, 25, 0, in: cal))
        #expect(week.days.count == 7)
        #expect(week.rangeText == "10.25 – 10.31")
    }

    @Test func titles() {
        #expect(period(2026, 10, 26, .day).title == "10월 26일 월요일")
        #expect(period(2026, 11, 1, .day).title == "11월 1일 일요일")
        #expect(period(2026, 10, 1, .month).title == "2026년 10월")
    }

    /// The week takes the month and number of its Sunday.
    @Test func weekNamesFollowTheirSunday() {
        #expect(period(2026, 10, 28, .week).title == "10월 4주차")
        #expect(period(2026, 10, 1, .week).title == "9월 4주차")
        #expect(period(2026, 7, 2, .week).title == "6월 4주차")
        #expect(period(2026, 10, 5, .week).title == "10월 1주차")
        #expect(period(2026, 11, 1, .week).title == "11월 1주차")
    }

    @Test func monthGridCoversWholeWeeks() {
        let october = MonthGrid(month: Self.date(2026, 10, 15, in: cal), calendar: cal)
        #expect(october.weeks.count == 5)
        #expect(october.weeks.first?.first == Self.date(2026, 9, 27, 0, in: cal))
        #expect(october.weeks.last?.last == Self.date(2026, 10, 31, 0, in: cal))
        #expect(october.weeks.allSatisfy { $0.count == 7 })

        // February 2026 starts on a Sunday and has 28 days: exactly four rows.
        #expect(MonthGrid(month: Self.date(2026, 2, 10, in: cal), calendar: cal).weeks.count == 4)
        // August 2026 starts on a Saturday and needs six rows.
        #expect(MonthGrid(month: Self.date(2026, 8, 10, in: cal), calendar: cal).weeks.count == 6)
    }

    @Test func advancing() {
        #expect(period(2026, 10, 26, .month).advanced(by: 1).key == "2026-11")
        #expect(period(2026, 10, 26, .week).advanced(by: -1).key == "2026-W43")
        #expect(period(2026, 12, 31, .day).advanced(by: 1).key == "2027-01-01")
    }

    @Test func contains() {
        let week = period(2026, 10, 28, .week)
        #expect(week.contains(Self.date(2026, 10, 31, 23, in: cal)))
        #expect(!week.contains(Self.date(2026, 11, 1, 0, in: cal)))
    }

    /// US daylight saving ends on 2026-11-01, a Sunday: that day is 25 hours long.
    @Test func daysAcrossDaylightSaving() {
        let ny = Self.calendar("America/New_York")
        let day = Period(containing: Self.date(2026, 11, 1, in: ny), scope: .day, calendar: ny)
        #expect(day.end == Self.date(2026, 11, 2, 0, in: ny))
        #expect(day.end.timeIntervalSince(day.start) == 25 * 3600)

        let week = Period(containing: Self.date(2026, 11, 4, in: ny), scope: .week, calendar: ny)
        #expect(week.days.map { ny.component(.hour, from: $0) }.allSatisfy { $0 == 0 })
        #expect(week.days.first == Self.date(2026, 11, 1, 0, in: ny))
    }

    /// Egypt starts daylight saving at midnight (2026-04-24, a Friday), so that day begins at
    /// 01:00; the following days must still start at 00:00.
    @Test func daysAfterMidnightDaylightSaving() {
        let cairo = Self.calendar("Africa/Cairo")
        let week = Period(containing: Self.date(2026, 4, 22, in: cairo), scope: .week, calendar: cairo)
        let hours = week.days.map { cairo.component(.hour, from: $0) }
        #expect(week.days.count == 7)
        #expect(hours[0...4].allSatisfy { $0 == 0 })
        #expect(hours[6] == 0)
        #expect(week.days[6] == cairo.startOfDay(for: Self.date(2026, 4, 25, in: cairo)))
    }
}
