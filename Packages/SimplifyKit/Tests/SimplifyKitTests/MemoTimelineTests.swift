import Foundation
import Testing
@testable import SimplifyKit

struct MemoTimelineTests {
    let cal = PeriodTests.calendar()

    @Test func rulesAreOneLetterMoreThanThreeTimes() {
        #expect(MemoTimeline.isRule("────────────"))
        #expect(MemoTimeline.isRule("━━━━"))
        #expect(MemoTimeline.isRule("----"))
        #expect(MemoTimeline.isRule("===================="))
        #expect(MemoTimeline.isRule("  ────  "))
        #expect(MemoTimeline.isRule("____\t"))
        // Three is not more than three.
        #expect(!MemoTimeline.isRule("───"))
        #expect(!MemoTimeline.isRule("---"))
        // Mixed letters, breaks in the run, or words.
        #expect(!MemoTimeline.isRule("──━━"))
        #expect(!MemoTimeline.isRule("── ──"))
        #expect(!MemoTimeline.isRule("──── 회의"))
        #expect(!MemoTimeline.isRule("****"))
        #expect(!MemoTimeline.isRule(""))
        #expect(!MemoTimeline.isRule("    "))
    }

    @Test func timelineLinesStartWithTheirTime() {
        #expect(MemoTimeline.stampLength("11.02 08:30 AI 허브 배포 확인") == 11)
        #expect(MemoTimeline.stampLength("11.02 08:30") == 11)
        #expect(MemoTimeline.stampLength("11.02 08:30-09:15 회의") == 17)
        #expect(MemoTimeline.stampLength("01.31 23:59\t끝") == 11)
        // A range cut short is a plain time followed by letters.
        #expect(MemoTimeline.stampLength("11.02 08:30-9 회의") == nil)
        #expect(MemoTimeline.stampLength("11.02 08:30회의") == nil)
        #expect(MemoTimeline.stampLength("11.2 08:30 회의") == nil)
        #expect(MemoTimeline.stampLength(" 11.02 08:30 회의") == nil)
        #expect(MemoTimeline.stampLength("13.02 08:30 회의") == nil)
        #expect(MemoTimeline.stampLength("11.32 08:30 회의") == nil)
        #expect(MemoTimeline.stampLength("11.02 24:00 회의") == nil)
        #expect(MemoTimeline.stampLength("11.02 08:60 회의") == nil)
        #expect(MemoTimeline.stampLength("１１.02 08:30 회의") == nil)
        #expect(MemoTimeline.stampLength("회의 11.02 08:30") == nil)
    }

    @Test func stampsAreZeroPadded() {
        let day = PeriodTests.date(2026, 3, 4)
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9, minute: 5))!
        #expect(MemoTimeline.stamp(day: day, now: now, calendar: cal) == "03.04 09:05")
    }

    @Test func aDayMemoNamesItsOwnDay() {
        let memo = Period(containing: PeriodTests.date(2026, 11, 2), scope: .day, calendar: cal)
        let today = PeriodTests.date(2026, 11, 3)
        #expect(MemoTimeline.stampDay(for: memo, today: today, chosen: memo.start) == memo.start)
    }

    @Test func weekAndMonthMemosNameTodayInsideThemAndTheChosenDayOutside() {
        let today = cal.startOfDay(for: PeriodTests.date(2026, 11, 3))
        let chosen = cal.startOfDay(for: PeriodTests.date(2026, 11, 5))
        let week = Period(containing: chosen, scope: .week, calendar: cal)
        #expect(MemoTimeline.stampDay(for: week, today: today, chosen: chosen) == today)
        let month = Period(containing: chosen, scope: .month, calendar: cal)
        #expect(MemoTimeline.stampDay(for: month, today: today, chosen: chosen) == today)

        let later = cal.startOfDay(for: PeriodTests.date(2026, 12, 9))
        let nextWeek = Period(containing: later, scope: .week, calendar: cal)
        #expect(MemoTimeline.stampDay(for: nextWeek, today: today, chosen: later) == later)
        let nextMonth = Period(containing: later, scope: .month, calendar: cal)
        #expect(MemoTimeline.stampDay(for: nextMonth, today: today, chosen: later) == later)
    }

    @Test func anEmptyLineTakesTheTimeAtItsFront() {
        let memo = "회의\n\n끝"
        let put = MemoTimeline.insertion(in: memo, caret: 3, stamp: "11.03 14:25")
        #expect(put.offset == 3)
        #expect(put.text == "11.03 14:25 ")
        #expect(put.caretAfter == 15)
        let empty = MemoTimeline.insertion(in: "", caret: 0, stamp: "11.03 14:25")
        #expect(empty.offset == 0 && empty.text == "11.03 14:25 " && empty.caretAfter == 12)
    }

    @Test func aLineWithWordsGetsANewLineUnderIt() {
        let memo = "11.02 09:30 배포 확인\n다음 줄"
        // The caret in the middle of the first line.
        let put = MemoTimeline.insertion(in: memo, caret: 4, stamp: "11.03 14:25")
        #expect(put.offset == 17)
        #expect(put.text == "\n11.03 14:25 ")
        #expect(put.caretAfter == 30)
        var letters = Array(memo)
        letters.insert(contentsOf: put.text, at: put.offset)
        #expect(String(letters) == "11.02 09:30 배포 확인\n11.03 14:25 \n다음 줄")
        // At the very end of the memo.
        let last = MemoTimeline.insertion(in: memo, caret: memo.count, stamp: "11.03 14:25")
        #expect(last.offset == memo.count && last.text == "\n11.03 14:25 ")
        #expect(MemoTimeline.stampLength(String(letters).split(separator: "\n")[1]) == 11)
    }
}

struct PanelLayoutTests {
    let space = PanelLayout.Space(window: 1440, calendarMin: 488, spine: 1.75)

    @Test func theNormalPanelStartsAtAThirdUpTo460() {
        #expect(PanelLayout.normalWidth(nil, in: space) == 460)
        let small = PanelLayout.Space(window: 1000, calendarMin: 488, spine: 1.75)
        #expect(PanelLayout.normalWidth(nil, in: small) == 320)
        let smallest = PanelLayout.Space(window: 790, calendarMin: 488, spine: 1.75)
        #expect(PanelLayout.normalWidth(nil, in: smallest) == 300)
    }

    @Test func aDraggedPanelKeepsTheCalendarAtItsNarrowest() {
        #expect(PanelLayout.normalWidth(1200, in: space) == 1440 - 1.75 - 488)
        #expect(PanelLayout.normalWidth(200, in: space) == 300)
        #expect(PanelLayout.normalWidth(620, in: space) == 620)
        // A window made smaller later squeezes the chosen width back.
        let smaller = PanelLayout.Space(window: 900, calendarMin: 488, spine: 1.75)
        #expect(PanelLayout.normalWidth(620, in: smaller) == 900 - 1.75 - 488)
    }

    @Test func draggingPastTheCalendarsNarrowestFoldsIt() {
        // The calendar at 500: still normal, the panel takes the rest.
        #expect(PanelLayout.drag(to: 500, isWide: false, in: space) == .normal(panel: 1440 - 1.75 - 500))
        // Just under the narrowest: held there, not folded yet.
        #expect(PanelLayout.drag(to: 450, isWide: false, in: space) == .normal(panel: 1440 - 1.75 - 488))
        // Well past it: the small month at its widest, then as dragged.
        #expect(PanelLayout.drag(to: 390, isWide: false, in: space) == .wide(mini: 360))
        #expect(PanelLayout.drag(to: 300, isWide: true, in: space) == .wide(mini: 300))
        #expect(PanelLayout.drag(to: 100, isWide: true, in: space) == .wide(mini: 248))
    }

    @Test func draggingPastTheSmallMonthsWidestUnfoldsIt() {
        // Between the two edges the state stays as it is, either way.
        #expect(PanelLayout.drag(to: 420, isWide: true, in: space) == .wide(mini: 360))
        #expect(PanelLayout.drag(to: 420, isWide: false, in: space) == .normal(panel: 1440 - 1.75 - 488))
        #expect(PanelLayout.drag(to: 460, isWide: true, in: space) == .normal(panel: 1440 - 1.75 - 488))
        #expect(PanelLayout.drag(to: 900, isWide: true, in: space) == .normal(panel: 1440 - 1.75 - 900))
    }

    @Test func theSmallMonthStaysInItsRange() {
        #expect(PanelLayout.miniWidth(nil) == 248)
        #expect(PanelLayout.miniWidth(400) == 360)
        #expect(PanelLayout.miniWidth(250) == 250)
    }
}
