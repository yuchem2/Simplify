import Combine
import SwiftUI
import SimplifyKit

/// The window: toolbar on the wall, the month sheet, and the day panel beside it.
struct MainView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            MainToolbar(model: model)
            HStack(alignment: .top, spacing: 24) {
                MonthSheet(model: model)
                DayPanel(model: model)
                    .frame(width: 360)
            }
            .padding(.leading, 20)
            .padding(.trailing, 24)
            .padding(.bottom, 24)
        }
        .background(.wall)
        .foregroundStyle(.ink)
        // The day-change notification can arrive off the main thread.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            model.refreshToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: RunLoop.main)) { _ in
            model.timeZoneDidChange()
        }
        #if DEBUG
        .task { Snapshot.runIfRequested(model: model) }
        #endif
    }
}

struct MainToolbar: View {
    let model: AppModel
    /// Only the month view exists for now; the week grid arrives with event editing (stage 4).
    @State private var view: CalendarView = .month

    enum CalendarView: Hashable { case month, week }

    var body: some View {
        HStack(spacing: 14) {
            // Sized for the widest title ("2026년 12월") so ‹ › stay put while turning months.
            ZStack(alignment: .leading) {
                Text("2026년 12월").hidden()
                Text(model.month.title)
            }
            .font(.display(30))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.month.title)
            .accessibilityAddTraits(.isHeader)
            HStack(spacing: -Metrics.line) {
                Button { model.turnMonth(by: -1) } label: { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)) }
                    .accessibilityLabel("이전 달")
                Button("오늘") { model.goToToday() }
                Button { model.turnMonth(by: 1) } label: { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)) }
                    .accessibilityLabel("다음 달")
            }
            .buttonStyle(DrawnButtonStyle())
            SegmentedTabs([(CalendarView.month, "월"), (.week, "주")], selection: $view, disabled: [.week])
            Spacer()
            Text("캘린더 연결 전")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.inkSoft)
            Button {} label: { Label("새 일정", systemImage: "plus") }
                .buttonStyle(DrawnButtonStyle(.primary))
                .disabled(true)
        }
        // Lines up with the month sheet; the traffic lights sit in the strip above this row.
        .padding(.leading, 20)
        .padding(.trailing, 24)
        .frame(height: 64)
    }
}
