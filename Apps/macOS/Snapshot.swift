#if DEBUG
import AppKit
import SwiftData
import SwiftUI
import SimplifyKit

/// Debug-only: renders the main window to PNGs and quits, for checking the layout without
/// screen-recording access. Run with `open --env SIMPLIFY_SNAPSHOT=1 Simplify.app`; files land in
/// `~/Library/Containers/dev.yoom.simplify/Data/tmp/snapshot-*.png`.
/// `SIMPLIFY_SNAPSHOT=sample` fills an in-memory cache with example events first and also renders
/// the week panel, the settings modal and the iCloud connect form; nothing is written to the real stores.
@MainActor
enum Snapshot {
    static func runIfRequested(model: AppModel, calendars: CalendarController) {
        guard let mode = ProcessInfo.processInfo.environment["SIMPLIFY_SNAPSHOT"] else { return }
        let shown = mode == "sample" ? sampleController(calendar: model.calendar, days: model.grid.weeks.flatMap { $0 }) : calendars
        render(MainView(model: model, calendars: shown), name: "light", appearance: .aqua, scheme: .light)
        render(MainView(model: model, calendars: shown), name: "dark", appearance: .darkAqua, scheme: .dark)
        if mode == "sample" {
            // Completed reminders are shown struck through for the rest of the pictures.
            shown.showsCompletedReminders = true
            model.panelScope = .week
            render(MainView(model: model, calendars: shown), name: "week", appearance: .aqua, scheme: .light)
            model.panelScope = .day
            model.isSettingsOpen = true
            render(MainView(model: model, calendars: shown), name: "settings", appearance: .aqua, scheme: .light)
            render(ZStack { MainView(model: model, calendars: shown); SettingsModal(model: model, calendars: shown, intro: .icloud) },
                   name: "icloud", appearance: .aqua, scheme: .light)
            render(ZStack { MainView(model: model, calendars: shown); SettingsModal(model: model, calendars: shown, intro: .icloud) },
                   name: "icloud-dark", appearance: .darkAqua, scheme: .dark)
        }
        NSApp.terminate(nil)
    }

    private static func render(_ view: some View, name: String, appearance: NSAppearance.Name, scheme: ColorScheme) {
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view.frame(width: 1260, height: 800).environment(\.colorScheme, scheme).environment(\.isRenderingSnapshot, true))
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
                                            defaults: UserDefaults(suiteName: "dev.yoom.simplify.snapshot")!)
        controller.show(days: days, calendar: calendar)
        return controller
    }
}
#endif
