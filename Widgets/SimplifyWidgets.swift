import SwiftUI
import WidgetKit
import SimplifyKit

@main
struct SimplifyWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

/// Stage 0 placeholder: today's date only, to confirm the extension loads.
/// Events and ToDos arrive in stage 7.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("오늘")
        .description("오늘 날짜를 보여 줘요.")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        // A second entry at the next midnight flips the date on time; adding a day (not 86,400 s) stays right across DST.
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        completion(Timeline(entries: [TodayEntry(date: .now), TodayEntry(date: midnight)], policy: .atEnd))
    }
}

struct TodayView: View {
    let entry: TodayEntry

    var body: some View {
        VStack(spacing: 4) {
            Text(entry.date, format: .dateTime.weekday(.wide))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.date, format: .dateTime.day())
                .font(.system(size: 44, weight: .bold, design: .serif))
            Text(AppGroup.identifier() == nil ? "서명 전" : "연결됨")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
