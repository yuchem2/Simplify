import SwiftUI
import WidgetKit
import SimplifyKit

@main
struct SimplifyWidgets: WidgetBundle {
    init() {
        SimplifyFonts.register()
    }

    var body: some Widget {
        TodayWidget()
        TodayTodoWidget()
        MonthWidget()
    }
}

/// Small: today's number and the next two events. Keeps the stage 0 kind so a placed widget stays.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: DayProvider()) { entry in
            SmallWidgetView(entry.moment)
                .containerBackground(Color.widgetSurface, for: .widget)
        }
        .configurationDisplayName("다음 일정")
        .description("오늘 날짜와 다음 일정 두 개를 보여 줘요.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

/// Medium: the date and what is left of today beside the coming days' events. The kind still says
/// ToDo from when the medium widget held them; renaming it would drop widgets already placed.
struct TodayTodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayTodoWidget", provider: DayProvider()) { entry in
            MediumWidgetView(entry.moment)
                .containerBackground(Color.widgetSurface, for: .widget)
        }
        .configurationDisplayName("오늘")
        .description("오늘 남은 일정과 다가오는 일정을 보여 줘요.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

/// Extra large: the month as a ledger with titles, the coming events and today's ToDos (which tick from the widget) beside it.
/// A kind of its own: reusing the large widget's kind left the system looking for the old family.
struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MonthLedgerWidget", provider: DayProvider()) { entry in
            ExtraLargeWidgetView(entry.moment, todoIntent: ToggleTodoIntent.make)
                .containerBackground(Color.widgetSurface, for: .widget)
        }
        .configurationDisplayName("이번 달")
        .description("이번 달 장부와 다가오는 일정, 오늘 할 일을 보여 줘요. 할 일은 위젯에서 바로 체크해요.")
        .supportedFamilies([.systemExtraLarge])
        .contentMarginsDisabled()
    }
}

struct DayEntry: TimelineEntry {
    let date: Date
    let moment: WidgetMoment
}

/// Reads the shared stores once per timeline and makes an entry for every moment the content
/// changes on its own (an event starting or ending, midnight). The app asks for a new timeline
/// whenever it changes the stores.
struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        entry(.sample(), at: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        // The gallery shows example contents; on the desktop the real ones.
        completion(entry(context.isPreview ? .sample() : WidgetStore.load(), at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        // The extension process outlives a time zone change; read the zone afresh.
        NSTimeZone.resetSystemTimeZone()
        let now = Date.now
        let calendar = Calendar.simplify
        let data = WidgetStore.load(now: now, calendar: calendar)
        let dates = WidgetContent.timeline(now: now, events: data.events, calendar: calendar)
        completion(Timeline(entries: dates.map { entry(data, at: $0, calendar: calendar) },
                            policy: .after(WidgetContent.renewal(now: now, calendar: calendar))))
    }

    private func entry(_ data: WidgetData, at date: Date, calendar: Calendar = .simplify) -> DayEntry {
        DayEntry(date: date, moment: WidgetMoment(data: data, date: date, calendar: calendar))
    }
}

#Preview("소형", as: .systemSmall) {
    TodayWidget()
} timeline: {
    DayEntry(date: .now, moment: WidgetMoment(data: .sample(), date: .now))
}

#Preview("중형", as: .systemMedium) {
    TodayTodoWidget()
} timeline: {
    DayEntry(date: .now, moment: WidgetMoment(data: .sample(), date: .now))
}

#Preview("아주 큰", as: .systemExtraLarge) {
    MonthWidget()
} timeline: {
    DayEntry(date: .now, moment: WidgetMoment(data: .sample(), date: .now))
}
