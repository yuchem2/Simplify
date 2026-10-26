import Foundation
import Testing
@testable import SimplifyKit

struct RecurrenceTests {
    let cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 30, in calendar: Calendar? = nil) -> Date {
        (calendar ?? cal).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func days(_ dates: [Date], in calendar: Calendar? = nil) -> [String] {
        dates.map {
            let c = (calendar ?? cal).dateComponents([.month, .day], from: $0)
            return "\(c.month!)/\(c.day!)"
        }
    }

    func expand(_ rrule: String, from start: Date, through end: Date, excluding: Set<Date> = []) -> [Date] {
        let rule = Recurrence(rrule: rrule, calendar: cal)!
        return RecurrenceExpander.occurrences(of: rule, start: start, calendar: cal, in: DateInterval(start: start, end: end), excluding: excluding)
    }

    // MARK: Parsing

    @Test func parsesCommonRules() throws {
        let rule = try #require(Recurrence(rrule: "RRULE:FREQ=MONTHLY;INTERVAL=2;BYDAY=2TU,-1FR;COUNT=6", calendar: cal))
        #expect(rule.frequency == .monthly)
        #expect(rule.interval == 2)
        #expect(rule.count == 6)
        #expect(rule.byWeekday == [.init(weekday: 3, ordinal: 2), .init(weekday: 6, ordinal: -1)])
    }

    @Test func untilFormats() throws {
        let utc = try #require(Recurrence(rrule: "RRULE:FREQ=DAILY;UNTIL=20261031T145959Z", calendar: cal))
        #expect(utc.until == date(2026, 10, 31, 23, 59).addingTimeInterval(59))
        let dateOnly = try #require(Recurrence(rrule: "RRULE:FREQ=DAILY;UNTIL=20261031", calendar: cal))
        #expect(dateOnly.until == date(2026, 10, 31, 23, 59).addingTimeInterval(59))
    }

    @Test func rejectsWhatItCannotExpand() {
        #expect(Recurrence(rrule: "RRULE:FREQ=HOURLY", calendar: cal) == nil)
        #expect(Recurrence(rrule: "RRULE:FREQ=YEARLY;BYWEEKNO=20", calendar: cal) == nil)
        #expect(Recurrence(rrule: "RRULE:FREQ=WEEKLY;BYDAY=2MO", calendar: cal) == nil)
        #expect(Recurrence(rrule: "RRULE:FREQ=MONTHLY;BYMONTHDAY=0", calendar: cal) == nil)
    }

    @Test func exceptionDates() {
        let dates = Recurrence.exceptionDates(from: [
            "EXDATE;TZID=Asia/Seoul:20261028T093000,20261104T093000",
            "EXDATE;VALUE=DATE:20261225",
            "EXDATE:20261111T003000Z",
        ], calendar: cal)
        #expect(dates == [date(2026, 10, 28), date(2026, 11, 4), date(2026, 12, 25, 0, 0), date(2026, 11, 11)])
    }

    // MARK: Expanding

    @Test func weeklyOnSeveralDays() {
        let result = expand("RRULE:FREQ=WEEKLY;BYDAY=MO,WE", from: date(2026, 10, 26), through: date(2026, 11, 9))
        #expect(days(result) == ["10/26", "10/28", "11/2", "11/4"])
    }

    @Test func everyOtherWeek() {
        let result = expand("RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TU", from: date(2026, 10, 27), through: date(2026, 12, 1))
        #expect(days(result) == ["10/27", "11/10", "11/24"])
    }

    @Test func secondTuesdayAndLastFriday() {
        let second = expand("RRULE:FREQ=MONTHLY;BYDAY=2TU", from: date(2026, 10, 13), through: date(2027, 1, 1))
        #expect(days(second) == ["10/13", "11/10", "12/8"])
        let last = expand("RRULE:FREQ=MONTHLY;BYDAY=-1FR", from: date(2026, 10, 30), through: date(2027, 1, 1))
        #expect(days(last) == ["10/30", "11/27", "12/25"])
    }

    @Test func the31stSkipsShortMonths() {
        let result = expand("RRULE:FREQ=MONTHLY", from: date(2026, 10, 31), through: date(2027, 4, 1))
        #expect(days(result) == ["10/31", "12/31", "1/31", "3/31"])
    }

    @Test func lastDayOfMonth() {
        let result = expand("RRULE:FREQ=MONTHLY;BYMONTHDAY=-1", from: date(2027, 1, 31), through: date(2027, 4, 1))
        #expect(days(result) == ["1/31", "2/28", "3/31"])
    }

    @Test func leapDayYearly() {
        let result = expand("RRULE:FREQ=YEARLY", from: date(2028, 2, 29), through: date(2033, 1, 1))
        #expect(result.map { cal.component(.year, from: $0) } == [2028, 2032])
    }

    @Test func countAndUntil() {
        let counted = expand("RRULE:FREQ=DAILY;COUNT=3", from: date(2026, 10, 26), through: date(2026, 12, 1))
        #expect(days(counted) == ["10/26", "10/27", "10/28"])
        let until = expand("RRULE:FREQ=WEEKLY;UNTIL=20261109T003000Z", from: date(2026, 10, 26), through: date(2026, 12, 1))
        #expect(days(until) == ["10/26", "11/2", "11/9"])
    }

    /// COUNT is spent from DTSTART, even for occurrences before the range asked about.
    @Test func countIsSpentBeforeTheRange() {
        let rule = Recurrence(rrule: "RRULE:FREQ=WEEKLY;COUNT=4", calendar: cal)!
        let result = RecurrenceExpander.occurrences(of: rule, start: date(2026, 10, 5), calendar: cal,
                                                    in: DateInterval(start: date(2026, 10, 20, 0, 0), end: date(2026, 12, 1)))
        #expect(days(result) == ["10/26"])
    }

    @Test func weekdaysOnlyDaily() {
        let result = expand("RRULE:FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR", from: date(2026, 10, 30), through: date(2026, 11, 4))
        #expect(days(result) == ["10/30", "11/2", "11/3"])
    }

    @Test func lastWeekdayOfMonthBySetPosition() {
        let result = expand("RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", from: date(2026, 10, 30), through: date(2027, 1, 1))
        #expect(days(result) == ["10/30", "11/30", "12/31"])
    }

    @Test func exceptionsAreLeftOut() {
        let result = expand("RRULE:FREQ=WEEKLY", from: date(2026, 10, 26), through: date(2026, 11, 17), excluding: [date(2026, 11, 2)])
        #expect(days(result) == ["10/26", "11/9", "11/16"])
    }

    /// DTSTART counts even when it does not fit the rule (a Monday start for a Tuesday rule).
    @Test func startAlwaysCounts() {
        let result = expand("RRULE:FREQ=WEEKLY;BYDAY=TU;COUNT=3", from: date(2026, 10, 26), through: date(2026, 12, 1))
        #expect(days(result) == ["10/26", "10/27", "11/3"])
    }

    /// 9:00 in New York stays 9:00 local across the November DST change.
    @Test func wallClockHoldsAcrossDaylightSaving() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let start = date(2026, 10, 30, 9, 0, in: ny)
        let rule = Recurrence(rrule: "RRULE:FREQ=DAILY;COUNT=4", calendar: ny)!
        let result = RecurrenceExpander.occurrences(of: rule, start: start, calendar: ny, in: DateInterval(start: start, end: date(2026, 12, 1, in: ny)))
        #expect(result.map { ny.component(.hour, from: $0) } == [9, 9, 9, 9])
        #expect(days(result, in: ny) == ["10/30", "10/31", "11/1", "11/2"])
    }

    /// An occurrence that started before the range but is still going shows up.
    @Test func overlapUsesDuration() {
        let rule = Recurrence(rrule: "RRULE:FREQ=WEEKLY", calendar: cal)!
        let start = date(2026, 10, 25, 22, 0)
        let result = RecurrenceExpander.occurrences(of: rule, start: start, duration: 4 * 3600, calendar: cal,
                                                    in: DateInterval(start: date(2026, 11, 2, 0, 0), end: date(2026, 11, 3, 0, 0)))
        #expect(days(result) == ["11/1"])
    }

    /// Combinations the expander would get wrong are left to the provider.
    @Test func rejectsCombinationsItWouldGetWrong() {
        #expect(Recurrence(rrule: "RRULE:FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13", calendar: cal) == nil)
        #expect(Recurrence(rrule: "RRULE:FREQ=YEARLY;BYDAY=MO", calendar: cal) == nil)
        #expect(Recurrence(rrule: "RRULE:FREQ=YEARLY;BYMONTHDAY=1", calendar: cal) == nil)
        #expect(Recurrence(rrule: "RRULE:FREQ=WEEKLY;BYMONTHDAY=1", calendar: cal) == nil)
        #expect(Recurrence(rrule: "RRULE:FREQ=YEARLY;BYMONTH=5;BYMONTHDAY=8", calendar: cal) != nil)
    }
}
