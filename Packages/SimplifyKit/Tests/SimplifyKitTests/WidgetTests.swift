import Foundation
import SwiftData
import Testing
@testable import SimplifyKit

/// Monday 2 Nov 2026, 13:20 in Seoul, as in the widget mockup.
struct WidgetContentTests {
    let cal = PeriodTests.calendar()
    var now: Date { at(2, 13, 20) }

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func timed(_ title: String, _ start: Date, minutes: Double = 60, palette: Palette = .blue,
               reminder: Bool = false, done: Bool = false, holiday: Bool = false) -> WidgetEvent {
        WidgetEvent(id: title, title: title, start: start, end: reminder ? start : start.addingTimeInterval(minutes * 60),
                    isAllDay: false, isBand: false, palette: palette, isReminder: reminder, isHoliday: holiday, isCompleted: done)
    }

    func allDay(_ title: String, _ day: Int, days: Int = 1, holiday: Bool = false, month: Int = 11) -> WidgetEvent {
        let start = at(day, 0, month: month)
        return WidgetEvent(id: title, title: title, start: start, end: cal.date(byAdding: .day, value: days, to: start)!,
                           isAllDay: true, isBand: true, palette: .teal, isHoliday: holiday)
    }

    var monday: [WidgetEvent] {
        [timed("스탠드업", at(2, 9, 30), minutes: 30), timed("점심 미팅", at(2, 12), palette: .orange),
         timed("디자인 회의", at(2, 14), minutes: 90), timed("영양제 주문", at(2, 17), palette: .yellow, reminder: true),
         timed("필라테스", at(2, 19, 30), palette: .green), timed("독서 모임", at(2, 21), palette: .orange)]
    }

    @Test func dayListsBandsFirstThenTimedThenFinished() {
        let events = [timed("저녁", at(2, 19)), allDay("여행", 1, days: 3), timed("아침", at(2, 8), done: true),
                      timed("점심", at(2, 12)), timed("내일", at(3, 9))]
        #expect(WidgetContent.day(at(2, 15), events: events, calendar: cal).map(\.title) == ["여행", "점심", "저녁", "아침"])
    }

    @Test func upNextKeepsTheOneUnderWayAndSkipsAllDayWhileTimedRemain() {
        let today = WidgetContent.day(now, events: monday + [allDay("휴가 신청", 2)], calendar: cal)
        // 디자인 회의 starts at 14:00, 점심 미팅 ended at 13:00.
        #expect(WidgetContent.upNext(today, now: now).map(\.title) == ["디자인 회의", "영양제 주문"])
        #expect(WidgetContent.upNext(today, now: at(2, 14, 30)).map(\.title) == ["디자인 회의", "영양제 주문"], "under way")
        // A reminder is over once its time comes.
        #expect(WidgetContent.upNext(today, now: at(2, 17, 1)).map(\.title) == ["필라테스", "독서 모임"])
        #expect(WidgetContent.upNext(today, now: at(2, 22, 30)).map(\.title) == ["휴가 신청"], "only all-day left")
        #expect(WidgetContent.upNext([], now: now).isEmpty)
    }

    @Test func upNextLeavesOutFinishedReminders() {
        let today = [timed("약 먹기", at(2, 15), reminder: true, done: true), timed("운동", at(2, 18))]
        #expect(WidgetContent.upNext(today, now: now).map(\.title) == ["운동"])
    }

    @Test func agendaRunsOnIntoTheNextDays() {
        let later = [timed("병원", at(3, 10)), timed("모레 회의", at(4, 9)), timed("약 먹기", at(3, 8), reminder: true, done: true)]
        // 13:20: four of today's six are still to come, more than fit.
        let busy = WidgetContent.agenda(events: monday + later, now: now, calendar: cal, lines: 3)
        #expect(busy.days.map(\.offset) == [0])
        #expect(busy.days[0].rows.map(\.event.title) == ["디자인 회의", "영양제 주문"])
        #expect(busy.more == 2)
        // 20:40: one left today, then tomorrow under its heading (the ticked reminder left out), then the day after.
        let evening = WidgetContent.agenda(events: monday + later, now: at(2, 20, 40), calendar: cal, lines: 5)
        #expect(evening.days.map(\.offset) == [0, 1, 2])
        #expect(evening.days.map { $0.rows.map(\.event.title) } == [["독서 모임"], ["병원"], ["모레 회의"]])
        #expect(evening.more == 0)
        // A later day needs room for its heading and one event.
        #expect(WidgetContent.agenda(events: monday + later, now: at(2, 20, 40), calendar: cal, lines: 2).days.map(\.offset) == [0])
        // Nothing ahead within the week: today's latest past events fill the room, faint.
        let quiet = WidgetContent.agenda(events: monday, now: at(2, 20, 40), calendar: cal, lines: 3)
        #expect(quiet.days[0].rows.map(\.event.title) == ["영양제 주문", "필라테스", "독서 모임"])
        #expect(quiet.days[0].rows.map(\.isPast) == [true, true, false])
        #expect(WidgetContent.agenda(events: [], now: now, calendar: cal, lines: 3).days.isEmpty)
        #expect(WidgetContent.agenda(events: monday, now: now, calendar: cal, lines: 0).days.isEmpty)
    }

    @Test func scheduleFillsTheColumnByHeight() {
        let costs = WidgetContent.ScheduleCosts(heading: 16, allDay: 19, timed: 32, more: 16, gap: 4)
        let later = [allDay("생일", 4), timed("특강", at(4, 16)), allDay("다른 생일", 5), timed("주간회의", at(5, 10)),
                     timed("약 먹기", at(3, 8), reminder: true, done: true)]
        // 20:40: one event left today, then the 4th (the 3rd has only a ticked reminder).
        let column = WidgetContent.schedule(events: monday + later, now: at(2, 20, 40), calendar: cal, height: 140, costs: costs)
        #expect(column.days.map(\.offset) == [0, 2])
        // Today has no heading: 4+32 = 36, then 4+16 + 4+19 + 4+32 = 115 for the 4th. The 5th's
        // heading and first block would reach 158; its two events are counted, with room for the line.
        #expect(column.days.map { $0.rows.map(\.event.title) } == [["독서 모임"], ["생일", "특강"]])
        #expect(column.more == 2)
        // With room for the 5th's heading, one block and the line, the 5th shows in part.
        let roomy = WidgetContent.schedule(events: monday + later, now: at(2, 20, 40), calendar: cal, height: 180, costs: costs)
        #expect(roomy.days.map(\.offset) == [0, 2, 3])
        #expect(roomy.days.last?.rows.map(\.event.title) == ["다른 생일"])
        #expect(roomy.more == 1)
        // Everything fits: no "그 밖에" line.
        let all = WidgetContent.schedule(events: later, now: now, calendar: cal, height: 400, costs: costs)
        #expect(all.days.map(\.offset) == [2, 3] && all.more == 0)
        #expect(WidgetContent.schedule(events: [], now: now, calendar: cal, height: 140, costs: costs).days.isEmpty)
    }

    @Test func aReminderTickedEarlyKeepsItsPlaceInTime() {
        let events = [timed("회의", at(2, 10)), timed("약 먹기", at(2, 18), reminder: true, done: true), timed("운동", at(2, 19))]
        let list = WidgetContent.agenda(events: events, now: now, calendar: cal, lines: 3)
        #expect(list.days[0].rows.map(\.event.title) == ["회의", "약 먹기", "운동"])
        #expect(list.days[0].rows.map(\.isPast) == [true, false, false])
    }

    @Test func rangeReachesIntoNextMonthOnItsLastDay() {
        let lastDay = at(31, 15, month: 10)
        let range = WidgetStore.range(now: lastDay, calendar: cal)
        // October's grid starts on Sun 27 Sep; November's ends on Sat 5 Dec.
        #expect(range.start == at(27, 0, month: 9))
        #expect(range.end == at(6, 0, month: 12))
        let midday = WidgetStore.range(now: now, calendar: cal)
        #expect(midday.start == at(1, 0) && midday.end == at(6, 0, month: 12))
        // Late in a month the week ahead reaches past the grid.
        #expect(WidgetStore.range(now: at(28, 15), calendar: cal).end == at(7, 0, month: 12))
    }

    @Test func ledgerCoversWholeWeeksWithMarksAndRedDays() {
        let events = monday + [allDay("UX 컨퍼런스", 11, days: 3), allDay("공휴일", 5, holiday: true), allDay("가을", 30, month: 10)]
        let weeks = WidgetContent.ledger(month: now, today: now, events: events, calendar: cal)
        // November 2026 starts on a Sunday and has 30 days: five rows, ending on Sat 5 Dec.
        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.count == 7 })
        let days = weeks.flatMap { $0 }
        #expect(days.first?.number == 1 && days.first?.isRed == true)
        #expect(days.last?.number == 5 && days.last?.isInMonth == false)
        let today = days.first { $0.isToday }!
        #expect(today.number == 2)
        #expect(today.marks.map(\.title) == ["스탠드업", "점심 미팅", "디자인 회의"], "three at most")
        #expect(today.first?.title == "스탠드업")
        let holiday = days.first { $0.number == 5 && $0.isInMonth }!
        #expect(holiday.isRed && holiday.marks.isEmpty && holiday.first == nil, "holidays only redden")
        #expect(days.filter { $0.isInMonth && $0.first?.title == "UX 컨퍼런스" }.map(\.number) == [11, 12, 13])
        // Saturday 31 Oct belongs to no week of November's grid.
        #expect(!days.contains { $0.first?.title == "가을" })
    }

    @Test func timelineHasEveryChangeUntilTheDayAfterTomorrow() {
        let tomorrow = [timed("병원", at(3, 10)), timed("모레", at(4, 9))]
        let dates = WidgetContent.timeline(now: now, events: monday + tomorrow + [allDay("여행", 2)], calendar: cal)
        #expect(dates.first == now)
        #expect(dates == dates.sorted() && Set(dates).count == dates.count)
        #expect(dates.contains(at(2, 14)) && dates.contains(at(2, 15, 30)), "start and end")
        #expect(dates.contains(at(2, 17)), "a reminder's time once")
        #expect(dates.contains(at(3, 0)) && dates.contains(at(3, 10)) && dates.contains(at(3, 11)))
        // The data ends with tomorrow: no entry for the day after, the timeline is renewed then.
        #expect(dates.last == at(3, 11))
        #expect(WidgetContent.renewal(now: now, calendar: cal) == at(4, 0))
        #expect(!dates.contains(at(2, 9, 30)) && !dates.contains(at(4, 0)) && !dates.contains(at(4, 9)), "past and too far")
        #expect(WidgetContent.timeline(now: now, events: monday, calendar: cal, limit: 3).count == 3)
    }

    @Test func todosPutFinishedOnesLast() {
        func entry(_ title: String, done: Bool) -> TodoEntry {
            TodoEntry(todoID: UUID(), linkID: nil, title: title, isDone: done, label: nil, order: 0,
                      home: PeriodRef(scope: .day, key: "2026-11-02"), elsewhere: [], sourceNoteID: nil)
        }
        let rows = WidgetContent.todoRows([entry("회의록", done: true), entry("리포트", done: false), entry("정산", done: false)])
        #expect(rows.map(\.title) == ["리포트", "정산", "회의록"])
    }

    @Test func dayLinkRoundTrips() {
        let url = DayLink.url(for: now, calendar: cal)
        #expect(url.absoluteString == "simplify://day/2026-11-02")
        #expect(DayLink.day(from: url, calendar: cal) == at(2, 0))
        #expect(DayLink.day(from: URL(string: "simplify://day/2026-02-31")!, calendar: cal) == nil)
        #expect(DayLink.day(from: URL(string: "simplify://memo/2026-11-02")!, calendar: cal) == nil)
        #expect(DayLink.day(from: URL(string: "https://day/2026-11-02")!, calendar: cal) == nil)
    }
}

@MainActor
struct WidgetStoreTests {
    let cal = PeriodTests.calendar()
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 13, minute: 20))! }
    let cache = try! SimplifyStore.makeCacheContainer(inMemory: true)
    let diary = try! SimplifyStore.makeContainer(inMemory: true)

    func defaults() -> UserDefaults {
        let name = "widget-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func event(_ id: String, source: String, hour: Int, done: Bool = false) -> EventRecord {
        var snapshot = EventSnapshot(id: source + ":" + id, sourceID: source, remoteID: id, title: id, isAllDay: false)
        snapshot.start = cal.date(byAdding: .hour, value: hour, to: cal.startOfDay(for: now))
        snapshot.end = snapshot.start!.addingTimeInterval(3600)
        snapshot.isCompleted = done
        return EventRecord(snapshot)
    }

    /// One Google account with a shown and a hidden calendar, and the Mac's reminders.
    func fillCache() throws {
        let context = ModelContext(cache)
        context.insert(CalendarAccount(id: "google:1", provider: .google, email: "me@example.com"))
        context.insert(CalendarAccount(id: "reminders:local", provider: .reminders, email: ""))
        let work = CalendarSource(accountID: "google:1", remoteID: "work", name: "업무")
        work.paletteRaw = Palette.purple.rawValue
        let hidden = CalendarSource(accountID: "google:1", remoteID: "hidden", name: "숨김")
        hidden.isVisible = false
        let list = CalendarSource(accountID: "reminders:local", remoteID: "list", name: "미리알림")
        [work, hidden, list].forEach(context.insert)
        context.insert(event("회의", source: work.id, hour: 14))
        context.insert(event("비밀", source: hidden.id, hour: 15))
        context.insert(event("약", source: list.id, hour: 9, done: true))
        context.insert(event("우유", source: list.id, hour: 18))
        try context.save()
    }

    @Test func readsVisibleCalendarsWithTheirKind() throws {
        try fillCache()
        let data = WidgetStore.load(now: now, calendar: cal, cache: cache, diary: diary, pending: [], defaults: defaults())
        #expect(data.state == .ready)
        #expect(data.events.map(\.title) == ["회의", "우유"], "hidden calendar and finished reminder left out")
        #expect(data.events[0].palette == .purple && !data.events[0].isReminder)
        #expect(data.events[1].isReminder)
    }

    @Test func followsTheCompletedRemindersSetting() throws {
        try fillCache()
        let shared = defaults()
        shared.set(true, forKey: SharedSettings.showsCompletedReminders)
        let data = WidgetStore.load(now: now, calendar: cal, cache: cache, diary: diary, pending: [], defaults: shared)
        #expect(data.events.map(\.title) == ["약", "회의", "우유"])
    }

    @Test func showsUnsentChanges() throws {
        try fillCache()
        let reference = RemoteCalendar.Reference(sourceID: "google:1|work", remoteID: "work", timeZone: nil)
        let start = cal.date(byAdding: .hour, value: 16, to: cal.startOfDay(for: now))!
        let draft = EventDraft(title: "오프라인에서 만든 일정", isAllDay: false, start: start, end: start.addingTimeInterval(1800))
        let write = PendingWrite(id: UUID(), accountID: "google:1", calendar: reference, kind: .create(id: "new"),
                                 event: nil, draft: draft, createdAt: .now)
        let data = WidgetStore.load(now: now, calendar: cal, cache: cache, diary: diary, pending: [write], defaults: defaults())
        #expect(data.events.map(\.title) == ["회의", "오프라인에서 만든 일정", "우유"])
    }

    @Test func emptyAndBrokenStores() throws {
        let empty = WidgetStore.load(now: now, calendar: cal, cache: cache, diary: diary, pending: [], defaults: defaults())
        #expect(empty.state == .noAccounts)
        let broken = WidgetStore.load(now: now, calendar: cal, cache: nil, diary: nil, pending: [], defaults: defaults())
        #expect(broken.state == .unavailable)
        #expect(broken.todos(on: now, calendar: cal) == nil)
    }

    @Test func readsTodayAndTomorrowsTodos() throws {
        let context = ModelContext(diary)
        let today = Period(containing: now, scope: .day, calendar: cal)
        let tomorrow = today.advanced(by: 1)
        try Todos.add("리포트", to: today, in: context)
        try Todos.add("정산", to: tomorrow, in: context)
        let data = WidgetStore.load(now: now, calendar: cal, cache: nil, diary: diary, pending: [], defaults: defaults())
        #expect(data.todos(on: now, calendar: cal)?.map(\.title) == ["리포트"])
        #expect(data.todos(on: tomorrow.start, calendar: cal)?.map(\.title) == ["정산"])
        #expect(data.todos(on: tomorrow.advanced(by: 1).start, calendar: cal) == [])
    }

    @Test func tickingFromAWidgetSavesAndLeavesANote() throws {
        let today = Period(containing: now, scope: .day, calendar: cal)
        let item = try #require(try Todos.add("리포트", to: today, in: ModelContext(diary)))
        let shared = defaults()
        #expect(SharedSettings.diaryChangedAt(in: shared) == nil)
        try WidgetStore.setTodo(item.id, done: true, in: diary, defaults: shared)
        #expect(try Todos.entries(for: today, in: ModelContext(diary)).map(\.isDone) == [true])
        #expect(SharedSettings.diaryChangedAt(in: shared) != nil)
        try WidgetStore.setTodo(item.id, done: false, in: diary, defaults: shared)
        #expect(try Todos.entries(for: today, in: ModelContext(diary)).map(\.isDone) == [false])
    }

    @Test func settingsMoveToTheSharedDefaultsOnce() {
        let old = defaults(), shared = defaults()
        old.set(true, forKey: SharedSettings.showsCompletedReminders)
        old.set(false, forKey: SharedSettings.showsCellTimes)
        old.set("dark", forKey: "theme")
        SharedSettings.migrate(from: old, to: shared)
        #expect(shared.bool(forKey: SharedSettings.showsCompletedReminders))
        #expect(!SharedSettings.showsCellTimes(in: shared))
        #expect(old.object(forKey: SharedSettings.showsCellTimes) == nil)
        #expect(old.string(forKey: "theme") == "dark", "the theme stays with the app")
        // A value already in the shared defaults wins over a stale copy.
        old.set(true, forKey: SharedSettings.showsCellTimes)
        SharedSettings.migrate(from: old, to: shared)
        #expect(!SharedSettings.showsCellTimes(in: shared))
        // Nothing chosen yet: the defaults hold.
        #expect(SharedSettings.showsCellTimes(in: defaults()))
        // Same store (no App Group): nothing moves or disappears.
        SharedSettings.migrate(from: shared, to: shared)
        #expect(shared.object(forKey: SharedSettings.showsCompletedReminders) != nil)
    }
}
