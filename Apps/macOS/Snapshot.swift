#if DEBUG
import AppKit
import SwiftData
import SwiftUI
import SimplifyKit

/// Debug-only: renders the main window to PNGs and quits, for checking the layout without
/// screen-recording access. Run with `open --env SIMPLIFY_SNAPSHOT=1 Simplify.app`; files land in
/// `~/Library/Containers/dev.yoom.simplify/Data/tmp/snapshot-*.png`.
/// `SIMPLIFY_SNAPSHOT=sample` fills an in-memory cache with example events and memos first and also renders
/// the week panel, the week grid, the settings modal, the iCloud connect form and the memo box; nothing is written to the real stores.
@MainActor
enum Snapshot {
    static func runIfRequested(model: AppModel, calendars: CalendarController, memos realMemos: MemoBook) {
        guard let mode = ProcessInfo.processInfo.environment["SIMPLIFY_SNAPSHOT"] else { return }
        if mode == "window" {
            captureWindow(model: model)
            return
        }
        if mode == "resize" {
            measureResize(model: model)
            return
        }
        let shown = mode == "sample" ? sampleController(calendar: model.calendar, days: model.grid.weeks.flatMap { $0 }) : calendars
        let memos = mode == "sample" ? sampleMemos(calendar: model.calendar, isSaved: true) : realMemos
        render(MainView(model: model, calendars: shown, memos: memos), name: "light", appearance: .aqua, scheme: .light)
        render(MainView(model: model, calendars: shown, memos: memos), name: "dark", appearance: .darkAqua, scheme: .dark)
        // The smallest window: an 11-inch iPad's width.
        let smallest = CGSize(width: MainView.minWidth, height: 600)
        render(MainView(model: model, calendars: shown, memos: memos), name: "narrow", appearance: .aqua, scheme: .light, size: smallest)
        if mode == "sample" {
            // Completed reminders are shown struck through for the rest of the pictures.
            shown.showsCompletedReminders = true
            model.panelScope = .week
            render(MainView(model: model, calendars: shown, memos: memos), name: "week", appearance: .aqua, scheme: .light)
            model.panelScope = .day
            let view = model.calendarView
            model.calendarView = .week
            render(MainView(model: model, calendars: shown, memos: memos), name: "weekview", appearance: .aqua, scheme: .light)
            render(MainView(model: model, calendars: shown, memos: memos), name: "weekview-dark", appearance: .darkAqua, scheme: .dark)
            render(MainView(model: model, calendars: shown, memos: memos), name: "weekview-narrow", appearance: .aqua, scheme: .light,
                   size: CGSize(width: MainView.minWidth, height: 600))
            model.calendarView = .year
            shown.show(days: model.shownDays, calendar: model.calendar)
            render(MainView(model: model, calendars: shown, memos: memos), name: "yearview", appearance: .aqua, scheme: .light)
            render(MainView(model: model, calendars: shown, memos: memos), name: "yearview-dark", appearance: .darkAqua, scheme: .dark)
            model.calendarView = view
            shown.show(days: model.shownDays, calendar: model.calendar)
            model.isSettingsOpen = true
            render(MainView(model: model, calendars: shown, memos: memos), name: "settings", appearance: .aqua, scheme: .light)
            render(ZStack { MainView(model: model, calendars: shown, memos: memos); SettingsModal(model: model, calendars: shown, page: .general) },
                   name: "settings-general", appearance: .aqua, scheme: .light)
            render(ZStack { MainView(model: model, calendars: shown, memos: memos); SettingsModal(model: model, calendars: shown, page: .calendars) },
                   name: "settings-calendars-dark", appearance: .darkAqua, scheme: .dark)
            render(ZStack { MainView(model: model, calendars: shown, memos: memos); SettingsModal(model: model, calendars: shown, intro: .icloud) },
                   name: "icloud", appearance: .aqua, scheme: .light)
            render(ZStack { MainView(model: model, calendars: shown, memos: memos); SettingsModal(model: model, calendars: shown, intro: .icloud) },
                   name: "icloud-dark", appearance: .darkAqua, scheme: .dark)
            model.isSettingsOpen = false
            renderEventPopovers(model: model, calendars: shown, memos: memos)
            renderMemos(model: model, calendars: shown)
            renderTodos(model: model, calendars: shown)
            renderComponents()
        }
        NSApp.terminate(nil)
    }

    /// The event popover: details, the editor, a new event, and the questions it asks.
    private static func renderEventPopovers(model: AppModel, calendars: CalendarController, memos: MemoBook) {
        let today = model.today
        func occurrence(_ title: String, on day: Date = today) -> EventOccurrence? {
            calendars.slots[day]?.first { $0.occurrence.title == title }?.occurrence
        }
        func light(_ name: String) { render(MainView(model: model, calendars: calendars, memos: memos), name: name, appearance: .aqua, scheme: .light) }
        // A weekly event in this week, whatever weekday today is.
        let week = Period(containing: today, scope: .week, calendar: model.calendar).days
        guard let standupDay = week.first(where: { occurrence("주간 스탠드업", on: $0) != nil }),
              let standup = occurrence("주간 스탠드업", on: standupDay), let review = occurrence("디자인 리뷰") else { return }
        model.openEvent(standup, day: standupDay, anchor: EventAnchor.row(standup.id, day: standupDay, in: .month), calendars: calendars)
        light("event-detail")
        model.popover?.question = .delete
        light("event-delete-scope")
        model.edit(standup, calendars: calendars)
        light("event-edit")
        render(MainView(model: model, calendars: calendars, memos: memos), name: "event-edit-dark", appearance: .darkAqua, scheme: .dark)
        if case .editor(let editor)? = model.popover?.content {
            editor.setStart(editor.fields.start.addingTimeInterval(1800))
            model.popover?.question = .saveScope
            light("event-save-scope")
            model.popover?.question = nil
            editor.phase = .failed(CalendarSyncError.http(status: 503).message)
            light("event-failed")
        }
        model.popover = nil
        model.openEvent(review, day: today, anchor: EventAnchor.row(review.id, day: today, in: .panel), calendars: calendars)
        model.popover?.question = .delete
        light("event-delete")
        model.popover = nil
        let holidayDay = model.calendar.date(byAdding: .day, value: -17, to: today)!
        if let hangul = occurrence("한글날", on: holidayDay) {
            model.openEvent(hangul, day: holidayDay, anchor: EventAnchor.row(hangul.id, day: holidayDay, in: .month), calendars: calendars)
            light("event-readonly")
            model.popover = nil
        }
        model.select(today)
        model.newEvent(on: model.calendar.date(byAdding: .day, value: 2, to: today)!, calendars: calendars)
        light("event-new")
        model.popover = nil
        // The same popovers over the week grid: a block's details, and a new event at its day's head.
        let view = model.calendarView
        model.calendarView = .week
        model.openEvent(review, day: today, anchor: EventAnchor.row(review.id, day: today, in: .weekGrid), calendars: calendars)
        light("weekview-event")
        model.popover = nil
        model.selectedEventID = nil
        model.newEvent(on: today, calendars: calendars)
        light("weekview-new")
        model.popover = nil
        model.calendarView = view
    }

    /// The memo box with formatting, the week and month memos, and the notice when the diary
    /// store would not open.
    private static func renderMemos(model: AppModel, calendars: CalendarController) {
        let memos = sampleMemos(calendar: model.calendar, isSaved: true)
        model.select(model.today)
        // ImageRenderer runs no onChange, so the box is filled by hand.
        memos.draft.open(model.panelPeriod)
        render(MainView(model: model, calendars: calendars, memos: memos), name: "memo", appearance: .aqua, scheme: .light)
        render(MainView(model: model, calendars: calendars, memos: memos), name: "memo-dark", appearance: .darkAqua, scheme: .dark)
        model.panelScope = .month
        memos.draft.open(model.panelPeriod)
        render(MainView(model: model, calendars: calendars, memos: memos), name: "memo-month", appearance: .aqua, scheme: .light)
        model.panelScope = .day
        memos.draft.open(model.panelPeriod)
        let view = model.calendarView
        model.calendarView = .week
        render(MainView(model: model, calendars: calendars, memos: memos), name: "memo-weekview", appearance: .aqua, scheme: .light)
        model.calendarView = view
        render(MainView(model: model, calendars: calendars, memos: sampleMemos(calendar: model.calendar, isSaved: false)),
               name: "memo-unsaved", appearance: .aqua, scheme: .light)
        render(ZStack { Color.wall; MemoFormatBar(draft: memos.draft).padding(40) }.frame(width: 400, height: 200),
               name: "memo-formatbar", appearance: .aqua, scheme: .light, size: CGSize(width: 400, height: 200))
        render(ZStack { Color.wall; MemoFormatBar(draft: memos.draft).padding(40) }.frame(width: 400, height: 200),
               name: "memo-formatbar-dark", appearance: .darkAqua, scheme: .dark, size: CGSize(width: 400, height: 200))
    }

    /// Memos on today (with every kind of formatting), two other days, this week and this month,
    /// in an in-memory diary store.
    private static func sampleMemos(calendar: Calendar, isSaved: Bool) -> MemoBook {
        let container = try! SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let today = Date.now
        func styled(_ string: String, _ build: (inout AttributeContainer) -> Void) -> AttributedString {
            var container = AttributeContainer()
            build(&container)
            return AttributedString(string, attributes: container)
        }
        var memo = AttributedString("스탠드업에서 ")
        memo += styled("제주 워크숍") { $0[MemoAttributes.Ink.self] = .blue }
        memo += AttributedString(" 일정 확정. ")
        memo += styled("숙소는") { $0[MemoAttributes.Bold.self] = true }
        memo += AttributedString(" 이번 주 안에 정리하기로.\n")
        memo += styled("견적서 최종본") { $0[MemoAttributes.Highlight.self] = .yellow }
        memo += AttributedString(" 금요일까지.\n")
        memo += styled("운동은 세 번.") { $0[MemoAttributes.Italic.self] = true }
        memo += AttributedString(" 목표 ")
        memo += styled("w = 0.9w") { $0[MemoAttributes.Math.self] = true }
        memo += styled("0") { $0[MemoAttributes.Math.self] = true; $0[MemoAttributes.Script.self] = .lowered }
        memo += AttributedString("\n")
        memo += styled("brew upgrade --cask xcode") { $0[MemoAttributes.Code.self] = true }
        memo += AttributedString("\n다음 주 월요일 회의 안건 미리 보내기\n[ ] 필라테스 회원권 연장 문의\n")
        func day(_ offset: Int) -> Period {
            Period(containing: calendar.date(byAdding: .day, value: offset, to: today)!, scope: .day, calendar: calendar)
        }
        // ToDos: today's own, one linked in from the week, the week's and the month's, a few days around.
        func todo(_ title: String, _ period: Period, done: Bool = false, label: Palette? = nil) -> TodoItem {
            let item = try! Todos.add(title, to: period, in: context)!
            if done { try! Todos.setDone(item.id, true, in: context) }
            if let label { try! Todos.setLabel(item.id, label, in: context) }
            return item
        }
        let week = Period(containing: today, scope: .week, calendar: calendar)
        let month = Period(containing: today, scope: .month, calendar: calendar)
        _ = todo("회의록 정리", day(0), done: true)
        let report = todo("분기 리포트 초안 보내기", month, label: .red)
        try! Todos.link(report.id, to: day(0), in: context)
        let lodging = todo("워크숍 숙소 확인", week, label: .teal)
        try! Todos.link(lodging.id, to: day(0), in: context)
        _ = todo("견적서 회신", day(0))
        _ = todo("워크숍 발표 자료 준비", week)
        _ = todo("건강검진 예약", month, done: true)
        _ = todo("책 두 권 읽기", month)
        _ = todo("가글 사기", day(1))
        _ = todo("세탁소 맡기기", day(3))
        _ = todo("항공권 체크인", day(3))
        _ = todo("지난 일", day(-3), done: true)
        memo += AttributedString("워크숍 전에 ")
        memo += MemoChips.chip(id: lodging.id, title: lodging.title, isDone: false)
        try! Memos.save(memo, for: day(0), in: context)
        try! Memos.save(AttributedString("TODO: 세금계산서 발행"), for: day(-4), in: context)
        try! Memos.save(AttributedString("치과 다녀와서 가글 사기"), for: day(1), in: context)
        try! Memos.save(AttributedString("가족 저녁 메뉴 정하기"), for: day(-2), in: context)
        try! Memos.save(AttributedString("워크숍 준비 끝내기. 운동은 세 번."), for: Period(containing: today, scope: .week, calendar: calendar), in: context)
        try! Memos.save(AttributedString("분기 마감이 겹쳐 촘촘했던 달.\n다음 달에는 오전을 비워 두기."), for: Period(containing: today, scope: .month, calendar: calendar), in: context)
        return MemoBook(container: container, isSaved: isSaved)
    }

    /// The ToDo pops over the panel: 가져오기, the memo's `[[` search and ⌘⇧T.
    private static func renderTodos(model: AppModel, calendars: CalendarController) {
        let memos = sampleMemos(calendar: model.calendar, isSaved: true)
        model.select(model.today)
        model.panelScope = .day
        memos.draft.open(model.panelPeriod)
        func light(_ name: String) { render(MainView(model: model, calendars: calendars, memos: memos), name: name, appearance: .aqua, scheme: .light) }
        light("todo")
        render(MainView(model: model, calendars: calendars, memos: memos), name: "todo-dark", appearance: .darkAqua, scheme: .dark)
        memos.todos.pop = .importer(model.panelPeriod)
        light("todo-import")
        memos.todos.pop = .search(at: 0, typed: false)
        light("todo-search")
        memos.todos.pop = .makeTodos(lines: [0])
        light("todo-make")
        memos.todos.pop = nil
        model.panelScope = .month
        memos.draft.open(model.panelPeriod)
        light("todo-month")
        model.panelScope = .day
        let view = model.calendarView
        model.calendarView = .month
        light("todo-monthview")
        model.calendarView = view
        // Chips as the memo box draws them, open and done.
        var chips = AttributedString("워크숍 전에 확인할 것\n")
        chips += MemoChips.chip(id: UUID(), title: "워크숍 숙소 확인", isDone: false)
        chips += AttributedString("\n")
        chips += MemoChips.chip(id: UUID(), title: "참석자 명단 회신", isDone: true)
        chips += AttributedString(" 은 어제 보냄\n– 발표는 20분 안쪽으로")
        for (name, appearance, scheme) in [("todo-chips", NSAppearance.Name.aqua, ColorScheme.light), ("todo-chips-dark", .darkAqua, .dark)] {
            render(ZStack(alignment: .topLeading) {
                Color.paper
                Text(MemoStyle.rendered(chips)).lineHeight(.exact(points: MemoStyle.lineHeight)).padding(.horizontal, Metrics.spaceM + MemoStyle.textViewInset.width).padding(.vertical, Metrics.spaceS + MemoStyle.textViewInset.height)
                    .frame(width: 316, alignment: .leading).overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line)).padding(20)
            }.frame(width: 360, height: 180), name: name, appearance: appearance, scheme: scheme, size: CGSize(width: 360, height: 180))
        }
    }

    /// `SIMPLIFY_SNAPSHOT=window`: the real window with its title bar (which ImageRenderer never
    /// draws), at its size and then at the smallest size, as `snapshot-window*.png`. It shows this
    /// Mac's own calendars, so the files stay in the app's temporary folder.
    private static func captureWindow(model: AppModel) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { NSApp.terminate(nil); return }
            @MainActor func capture(_ name: String) {
                guard let frame = window.contentView?.superview,
                      let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
                frame.cacheDisplay(in: frame.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: FileManager.default.temporaryDirectory.appending(path: "snapshot-\(name).png"))
            }
            let original = (model.calendarView, window.frame)
            window.setContentSize(NSSize(width: 1260, height: 800))
            try? await Task.sleep(for: .seconds(1))
            capture("window")
            model.isSettingsOpen = true
            try? await Task.sleep(for: .seconds(1))
            capture("window-settings")
            model.isSettingsOpen = false
            model.calendarView = .week
            try? await Task.sleep(for: .seconds(1))
            capture("window-week")
            window.setContentSize(window.contentMinSize)
            try? await Task.sleep(for: .seconds(1))
            capture("window-week-narrow")
            model.calendarView = original.0
            window.setFrame(original.1, display: false)
            NSApp.terminate(nil)
        }
    }

    /// `SIMPLIFY_SNAPSHOT=resize`: times a live window resize in each view, one layout and draw per
    /// step, and writes the milliseconds to `resize.txt` in the app's temporary folder.
    private static func measureResize(model: AppModel) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { NSApp.terminate(nil); return }
            var report = ""
            let original = (model.calendarView, model.isPanelHidden, window.frame)
            let cases: [(String, AppModel.CalendarView, Bool)] = [
                ("month+panel", .month, false), ("month", .month, true),
                ("week+panel", .week, false), ("year+panel", .year, false),
            ]
            for (name, view, hidden) in cases {
                model.calendarView = view
                model.isPanelHidden = hidden
                window.setContentSize(NSSize(width: 1500, height: 800))
                try? await Task.sleep(for: .seconds(1.5))
                var times: [Double] = []
                for step in 0..<60 {
                    // 1200 to 1780 pt and back: wider than either window's minimum, so every step resizes.
                    let width = 1200 + Double(step < 30 ? step : 59 - step) * 20
                    let start = CACurrentMediaTime()
                    window.setContentSize(NSSize(width: width, height: 800))
                    window.contentView?.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    times.append((CACurrentMediaTime() - start) * 1000)
                }
                let sorted = times.sorted()
                report += String(format: "%@\tmedian %.1f ms\tp90 %.1f ms\tmax %.1f ms\n", name, sorted[30], sorted[54], sorted[59])
            }
            (model.calendarView, model.isPanelHidden) = (original.0, original.1)
            window.setFrame(original.2, display: false)
            try? report.write(to: FileManager.default.temporaryDirectory.appending(path: "resize.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    /// The shared controls in every state side by side, since hover and keyboard focus never show
    /// in a rendered picture of the window.
    private static func renderComponents() {
        let gallery = ComponentGallery()
        let size = CGSize(width: 960, height: 520)
        render(gallery, name: "components", appearance: .aqua, scheme: .light, size: size)
        render(gallery, name: "components-dark", appearance: .darkAqua, scheme: .dark, size: size)
    }

    private static func render(_ view: some View, name: String, appearance: NSAppearance.Name, scheme: ColorScheme, size: CGSize = CGSize(width: 1260, height: 800)) {
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, scheme).environment(\.isRenderingSnapshot, true))
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
            try? png.write(to: FileManager.default.temporaryDirectory.appending(path: "snapshot-\(name).png"))
        }
    }

    /// Google, iCloud and reminders accounts' worth of events around today, in an in-memory cache.
    private static func sampleController(calendar: Calendar, days: [Date]) -> CalendarController {
        let container = try! SimplifyStore.makeCacheContainer(inMemory: true)
        let context = container.mainContext
        let me = CalendarAccount(id: "google:me", provider: .google, email: "me.simplify@gmail.com")
        me.lastSyncedAt = .now
        let team = CalendarAccount(id: "google:team", provider: .google, email: "team@example.com")
        team.status = .needsReauth
        let icloud = CalendarAccount(id: "icloud:/1/principal/", provider: .icloud, email: "me@icloud.com")
        icloud.lastSyncedAt = .now
        let reminders = CalendarAccount(id: "reminders:local", provider: .reminders, email: "미리알림")
        reminders.lastSyncedAt = .now
        [me, team, icloud, reminders].forEach(context.insert)

        func source(_ account: String, _ id: String, _ name: String, _ palette: Palette, holiday: Bool = false) -> CalendarSource {
            let s = CalendarSource(accountID: account, remoteID: id, name: name)
            s.paletteRaw = palette.rawValue
            s.isHoliday = holiday
            s.isReadOnly = holiday
            context.insert(s)
            return s
        }
        let work = source("google:me", "work", "업무", .blue)
        let personal = source("google:me", "personal", "개인", .orange)
        let fitness = source("google:me", "fitness", "운동", .green)
        let holidays = source("google:me", "ko#holiday", "대한민국의 휴일", .red, holiday: true)
        let teamCal = source("google:team", "team", "팀 일정", .purple)
        let family = source("icloud:/1/principal/", "family", "가족", .teal)
        let todo = source("reminders:local", "todo", "할 일", .yellow)

        let today = calendar.startOfDay(for: .now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: .minute, value: hour * 60 + minute, to: calendar.date(byAdding: .day, value: dayOffset, to: today)!)!
        }
        func key(_ dayOffset: Int) -> String {
            let c = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: dayOffset, to: today)!)
            return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        }
        func timed(_ source: CalendarSource, _ id: String, _ title: String, _ start: Date, minutes: Int = 60, rule: String? = nil) {
            var e = EventSnapshot(id: source.id + ":" + id, sourceID: source.id, remoteID: id, title: title, isAllDay: false)
            e.start = start
            e.end = start.addingTimeInterval(TimeInterval(minutes * 60))
            e.timeZone = calendar.timeZone.identifier
            e.recurrence = rule.flatMap { Recurrence(rrule: $0, calendar: calendar) }
            context.insert(EventRecord(e))
        }
        func allDay(_ source: CalendarSource, _ id: String, _ title: String, _ from: Int, _ to: Int) {
            var e = EventSnapshot(id: source.id + ":" + id, sourceID: source.id, remoteID: id, title: title, isAllDay: true)
            e.startDay = key(from)
            e.endDay = key(to)
            context.insert(EventRecord(e))
        }
        timed(work, "standup", "주간 스탠드업", at(-21, 9, 30), minutes: 30, rule: "RRULE:FREQ=WEEKLY;BYDAY=MO")
        timed(work, "review", "디자인 리뷰", at(0, 14))
        // Long enough to wrap in the day panel, where the mark has to stay on the first line.
        timed(work, "offsite", "2027년 상반기 제품 로드맵과 팀별 목표를 맞추는 전사 워크숍 사전 회의", at(0, 16))
        timed(fitness, "pilates", "필라테스", at(0, 19, 30), rule: "RRULE:FREQ=WEEKLY;BYDAY=MO,TH")
        timed(personal, "book", "독서 모임", at(0, 21))
        timed(personal, "dentist", "치과", at(1, 18))
        allDay(teamCal, "workshop", "제주 워크숍", 3, 5)
        timed(personal, "party", "할로윈 파티", at(5, 19))
        allDay(holidays, "hangul", "한글날", -17, -16)
        timed(work, "client", "고객사 미팅", at(-14, 14))
        allDay(personal, "mom", "엄마 생신", -11, -10)
        timed(work, "qreview", "분기 리뷰", at(-6, 15))
        timed(work, "longtitle", "4분기 마케팅 캠페인 최종 검토 회의", at(2, 10))
        // A crowded day, to show "+N개 더".
        for (i, title) in ["조찬 모임", "주간 보고", "점심 미팅", "코드 리뷰", "운영 회의", "저녁 약속"].enumerated() {
            timed(i.isMultiple(of: 2) ? work : personal, "busy\(i)", title, at(1, 8 + i * 2))
        }
        allDay(family, "trip", "부모님 방문", 8, 10)
        // Overlapping bands, to show each keeping its row through the week.
        allDay(work, "deadline", "마감 주간", -5, -2)
        allDay(work, "sprint", "디자인 스프린트", -4, 0)
        timed(family, "dinner", "가족 저녁", at(-2, 18, 30))
        allDay(todo, "tax", "연말정산 서류 내기", 2, 3)
        timed(todo, "pills", "영양제 주문", at(0, 17), minutes: 0)
        var done = EventSnapshot(id: todo.id + ":done", sourceID: todo.id, remoteID: "done", title: "택배 반품", isAllDay: true)
        done.startDay = key(0)
        done.isCompleted = true
        context.insert(EventRecord(done))
        try! context.save()

        UserDefaults.standard.removePersistentDomain(forName: "dev.yoom.simplify.snapshot")
        let controller = CalendarController(container: container, calendar: calendar, tokens: KeychainTokenStore(service: "dev.yoom.simplify.snapshot"),
                                            credentials: KeychainCredentialStore(service: "dev.yoom.simplify.snapshot"),
                                            defaults: UserDefaults(suiteName: "dev.yoom.simplify.snapshot")!,
                                            writer: EventWriter(fileURL: FileManager.default.temporaryDirectory.appending(path: "snapshot-pending.json")))
        controller.show(days: days, calendar: calendar)
        return controller
    }
}

/// Every state of the Kit controls on one sheet: rest, hover, focus, chosen, disabled, error.
/// Text stands in for TextField here: ImageRenderer cannot draw AppKit-backed fields.
private struct ComponentGallery: View {
    @State private var tab = 0

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.spaceXxxl) {
            VStack(alignment: .leading, spacing: Metrics.spaceXl) {
                SectionRule("버튼")
                HStack(spacing: Metrics.spaceL) {
                    Button("기본") {}.buttonStyle(DrawnButtonStyle())
                    Button("새 일정") {}.buttonStyle(DrawnButtonStyle(.primary))
                    Button("켜짐") {}.buttonStyle(DrawnButtonStyle(.toggled))
                    Button("삭제") {}.buttonStyle(DrawnButtonStyle(.danger))
                    Button("가져오기") {}.buttonStyle(DrawnButtonStyle(.text))
                    Button("못 누름") {}.buttonStyle(DrawnButtonStyle()).disabled(true)
                }
                HStack(spacing: Metrics.spaceL) {
                    Text("포커스").textStyle(.body).padding(.horizontal, Metrics.spaceL).frame(height: 28)
                        .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line)).focusRing(true)
                    Text("hover").textStyle(.body).padding(.horizontal, Metrics.spaceL).frame(height: 28).background(.hover)
                        .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
                    SegmentedTabs([(0, "하루"), (1, "한 주"), (2, "한 달")], selection: $tab)
                }
                SectionRule("입력 칸")
                HStack(spacing: Metrics.spaceL) {
                    Text("기본").foregroundStyle(.inkFaint).frame(maxWidth: .infinity, alignment: .leading).drawnField(focused: false)
                    Text("포커스").frame(maxWidth: .infinity, alignment: .leading).drawnField(focused: true)
                    Text("비활성").frame(maxWidth: .infinity, alignment: .leading).drawnField(focused: false).disabled(true)
                    Text("오류").frame(maxWidth: .infinity, alignment: .leading).drawnField(focused: false, error: true)
                }
                .frame(width: 520)
                HStack(spacing: Metrics.spaceL) {
                    Text("줄 안 · 고치는 중").textStyle(.item).frame(maxWidth: .infinity, alignment: .leading).drawnField(.inline, focused: true)
                    Text("디자인 리뷰").frame(maxWidth: .infinity, alignment: .leading).drawnField(.title, focused: true)
                }
                .frame(width: 520)
                SectionRule("알림 띠 · 태그")
                NoticeBar("이번 실행에서 쓴 메모는 남지 않아요.", title: "메모를 저장할 수 없어요.").frame(width: 520)
                HStack(spacing: Metrics.spaceM) {
                    Tag("오늘")
                    Tag("읽기 전용", color: .inkSoft)
                    Tag("다시 연결 필요", color: Tokens.error)
                }
            }
            VStack(alignment: .leading, spacing: Metrics.spaceXl) {
                SectionRule("목록 줄")
                VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
                    Text("고른 줄").textStyle(.item).foregroundStyle(.onInk).frame(maxWidth: .infinity, alignment: .leading).selectableRow(chosen: true)
                    Text("고치는 줄").textStyle(.item).frame(maxWidth: .infinity, alignment: .leading).selectableRow(chosen: false, active: true)
                    Text("보통 줄").textStyle(.item).frame(maxWidth: .infinity, alignment: .leading).selectableRow(chosen: false)
                }
                SectionRule("체크 상자")
                HStack(spacing: Metrics.spaceL) {
                    CheckBox(isOn: false)
                    CheckBox(isOn: false, isHovered: true)
                    CheckBox(isOn: true)
                    CheckBox(isOn: false).focusRing(true)
                    CheckBox(isOn: true, size: 12)
                    ReminderMark(Palette.yellow.ink, size: 10)
                    Mark(Palette.blue.ink, size: 10)
                }
                SectionRule("하루 띠")
                DayStrip(items: [
                    .init(id: "1", start: 9 * 60 + 30, end: 10 * 60 + 30, palette: .blue),
                    .init(id: "2", start: 12 * 60, end: 13 * 60, palette: .orange),
                    .init(id: "3", start: 14 * 60, end: 15 * 60 + 30, palette: .blue),
                    .init(id: "4", start: 17 * 60, end: 17 * 60 + 15, palette: .yellow, isReminder: true),
                    .init(id: "5", start: 19 * 60 + 30, end: 20 * 60 + 30, palette: .green),
                ], now: 13 * 60 + 20)
                SectionRule("위젯 (7단계)")
                VStack(spacing: Metrics.spaceS) {
                    DateOval(day: 8)
                    Text("10월 · 목요일").textStyle(.meta).foregroundStyle(.inkSoft)
                }
                .frame(width: 170, height: 150)
                .widgetSurface()
            }
            .frame(width: 320)
        }
        .padding(Metrics.spaceXxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.paper)
        .foregroundStyle(.ink)
    }
}
#endif
