import Foundation
import Testing
@testable import SimplifyKit

@MainActor
struct InkMenuTests {
    /// 고치기 · (꺼진 줄) · 구분선 · 색 라벨 › · 넘기기 › · 지우기.
    private var todoMenu: [InkMenuEntry] {
        [.item("고치기") {},
         .item("붙여넣기", isEnabled: false) {},
         .divider,
         .submenu("색 라벨", [.item("없음", checked: false) {}, .item("파랑", checked: true) {}, .item("초록", checked: false) {}]),
         .submenu("넘기기", [.section("어디에 둘까요"), .item("내일", detail: "11.4") {}, .item("다음 주", detail: "11월 2주차") {}]),
         .item("지우기", isDanger: true) {}]
    }

    private func title(_ cursor: InkMenuCursor) -> String? {
        let level = cursor.levels.last!
        return level.cursor.flatMap { level.entries[$0].item?.title }
    }

    @Test func opensOnTheChosenValueOrTheFirstLine() {
        #expect(title(InkMenuCursor(todoMenu)) == "고치기")
        let colours: [InkMenuEntry] = [.section("색"), .item("없음", checked: false) {}, .item("파랑", checked: true) {}]
        #expect(title(InkMenuCursor(colours)) == "파랑")
        // A chosen line that cannot be used does not take the cursor.
        let off: [InkMenuEntry] = [.item("가", checked: true, isEnabled: false) {}, .item("나", checked: false) {}]
        #expect(title(InkMenuCursor(off)) == "나")
    }

    @Test func arrowsSkipRulesTitlesAndLinesThatCannotBeUsed() {
        var cursor = InkMenuCursor(todoMenu)
        _ = cursor.handle(.down)
        #expect(title(cursor) == "색 라벨")
        _ = cursor.handle(.down)
        _ = cursor.handle(.down)
        #expect(title(cursor) == "지우기")
        // Stops at the end.
        _ = cursor.handle(.down)
        #expect(title(cursor) == "지우기")
        _ = cursor.handle(.up)
        _ = cursor.handle(.up)
        _ = cursor.handle(.up)
        #expect(title(cursor) == "고치기")
    }

    @Test func rightOpensASubmenuOnItsFirstLineAndLeftClosesIt() {
        var cursor = InkMenuCursor(todoMenu)
        _ = cursor.handle(.down)
        _ = cursor.handle(.down)
        #expect(title(cursor) == "넘기기")
        _ = cursor.handle(.right)
        #expect(cursor.levels.count == 2)
        // Past the section title.
        #expect(title(cursor) == "내일")
        _ = cursor.handle(.down)
        #expect(title(cursor) == "다음 주")
        _ = cursor.handle(.left)
        #expect(cursor.levels.count == 1)
        #expect(title(cursor) == "넘기기")
        // Left on the menu itself does nothing.
        _ = cursor.handle(.left)
        #expect(cursor.levels.count == 1)
    }

    @Test func aSubmenuOpensOnItsChosenValue() {
        var cursor = InkMenuCursor(todoMenu)
        _ = cursor.handle(.down)
        _ = cursor.handle(.enter)
        #expect(title(cursor) == "파랑")
    }

    @Test func returnPicksAndEscapeDismisses() {
        var cursor = InkMenuCursor(todoMenu)
        _ = cursor.handle(.up)
        guard case .pick(let item) = cursor.handle(.enter) else { Issue.record("no pick"); return }
        #expect(item.title == "고치기")
        guard case .dismiss = cursor.handle(.escape) else { Issue.record("no dismiss"); return }
    }

    @Test func hoverOpensASubmenuWithoutACursorAndMovingOnClosesIt() {
        var cursor = InkMenuCursor(todoMenu)
        cursor.hover(depth: 0, index: 3)
        #expect(cursor.levels.count == 2)
        #expect(cursor.levels[1].cursor == nil)
        // Down from no cursor goes to the first line that can be used.
        _ = cursor.handle(.down)
        #expect(title(cursor) == "없음")
        cursor.hover(depth: 0, index: 0)
        #expect(cursor.levels.count == 1)
        #expect(title(cursor) == "고치기")
        // Over a line that cannot be used: no cursor.
        cursor.hover(depth: 0, index: 1)
        #expect(cursor.levels[0].cursor == nil)
    }

    @Test func aSubmenuWithNothingToPickDoesNotOpen() {
        var cursor = InkMenuCursor([.submenu("할 일로 만들기", [.section("어디에 둘까요"), .item("이날", isEnabled: false) {}])])
        _ = cursor.handle(.right)
        #expect(cursor.levels.count == 1)
    }

    @Test func lineHeightsFindTheLineUnderThePointer() {
        let entries = todoMenu
        #expect(InkMenuMetrics.index(at: 0, in: entries) == 0)
        #expect(InkMenuMetrics.index(at: InkMenuMetrics.itemHeight * 2 + 1, in: entries) == 2)
        #expect(InkMenuMetrics.index(at: InkMenuMetrics.itemHeight * 2 + InkMenuMetrics.dividerHeight + 1, in: entries) == 3)
        #expect(InkMenuMetrics.index(at: 1000, in: entries) == nil)
        let times = (0..<96).map { InkMenuEntry.item("\($0)") {} }
        #expect(InkMenuMetrics.viewportHeight(times, maxItems: 9) == InkMenuMetrics.itemHeight * 9)
    }
}

struct TimeTypeaheadTests {
    /// Quarter hours of a day, in minutes after midnight.
    let quarters = (0..<96).map { $0 * 15 }

    @Test func typedHoursAndMinutes() {
        #expect(TimeTypeahead.minutes("14", near: nil) == 14 * 60)
        #expect(TimeTypeahead.minutes("1415", near: nil) == 14 * 60 + 15)
        #expect(TimeTypeahead.minutes("0", near: nil) == 0)
        #expect(TimeTypeahead.minutes("12", near: 9 * 60) == 12 * 60)
        #expect(TimeTypeahead.minutes("975", near: nil) == nil)
        #expect(TimeTypeahead.minutes("ㄱ", near: nil) == nil)
        #expect(TimeTypeahead.minutes("25", near: nil) == nil)
    }

    /// `230` is 2:30 in the afternoon next to a 2 pm event, and in the night next to a 1 am one.
    @Test func morningOrAfternoonFollowsTheChosenTime() {
        #expect(TimeTypeahead.minutes("230", near: 14 * 60) == 14 * 60 + 30)
        #expect(TimeTypeahead.minutes("230", near: 60) == 2 * 60 + 30)
        #expect(TimeTypeahead.minutes("9", near: 8 * 60) == 9 * 60)
        #expect(TimeTypeahead.minutes("9", near: 20 * 60) == 21 * 60)
    }

    @Test func theNearestTimeInTheList() {
        #expect(TimeTypeahead.nearest("14", in: quarters, near: nil) == 56)
        #expect(TimeTypeahead.nearest("230", in: quarters, near: 14 * 60) == 58)
        // 14:07 lies between 14:00 and 14:15; the nearer is 14:00.
        #expect(TimeTypeahead.nearest("1407", in: quarters, near: nil) == 56)
        #expect(TimeTypeahead.nearest("1408", in: quarters, near: nil) == 57)
        #expect(TimeTypeahead.nearest("", in: quarters, near: nil) == nil)
    }
}

struct DatePickerKeysTests {
    private func cal(_ firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar.simplify(firstWeekday: firstWeekday)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func daysAndWeeksCrossTheMonthEdge() {
        let c = cal()
        let today = day(2026, 11, 3, in: c)
        #expect(DatePickerKeys.move(day(2026, 11, 30, in: c), .nextDay, today: today, calendar: c) == day(2026, 12, 1, in: c))
        #expect(DatePickerKeys.move(day(2026, 11, 1, in: c), .previousDay, today: today, calendar: c) == day(2026, 10, 31, in: c))
        #expect(DatePickerKeys.move(day(2026, 11, 26, in: c), .nextWeek, today: today, calendar: c) == day(2026, 12, 3, in: c))
        #expect(DatePickerKeys.move(day(2026, 12, 31, in: c), .nextDay, today: today, calendar: c) == day(2027, 1, 1, in: c))
    }

    @Test func aMonthOnKeepsTheDayWhereItCan() {
        let c = cal()
        let today = day(2026, 11, 3, in: c)
        #expect(DatePickerKeys.move(day(2027, 1, 31, in: c), .nextMonth, today: today, calendar: c) == day(2027, 2, 28, in: c))
        #expect(DatePickerKeys.move(day(2026, 3, 31, in: c), .previousMonth, today: today, calendar: c) == day(2026, 2, 28, in: c))
        #expect(DatePickerKeys.move(day(2026, 11, 12, in: c), .nextMonth, today: today, calendar: c) == day(2026, 12, 12, in: c))
    }

    @Test func todayGoesToTodayWhereverThePickIs() {
        let c = cal()
        let today = c.date(byAdding: .hour, value: 15, to: day(2026, 11, 3, in: c))!
        #expect(DatePickerKeys.move(day(2025, 4, 9, in: c), .today, today: today, calendar: c) == day(2026, 11, 3, in: c))
    }

    /// The month's rows start on the calendar's first weekday: November 2026 starts on a Sunday.
    @Test func theGridFollowsTheFirstWeekday() {
        let sunday = cal(1), monday = cal(2)
        let november = day(2026, 11, 12, in: sunday)
        let sundayGrid = MonthGrid(month: november, calendar: sunday)
        #expect(sundayGrid.weeks.first?.first == day(2026, 11, 1, in: sunday))
        #expect(sundayGrid.weeks.count == 5)
        let mondayGrid = MonthGrid(month: november, calendar: monday)
        #expect(mondayGrid.weeks.first?.first == day(2026, 10, 26, in: monday))
        #expect(mondayGrid.weeks.count == 6)
        #expect(monday.weekdaysInOrder == [2, 3, 4, 5, 6, 7, 1])
    }

    @Test func theFootSaysTheDayInFull() {
        let c = cal()
        #expect(InkDatePicker.longDay(day(2026, 11, 12, in: c), calendar: c) == "11월 12일 목요일")
    }
}
