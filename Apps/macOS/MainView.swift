import AppKit
import Combine
import SwiftUI
import SimplifyKit

/// The window: toolbar on the wall, the month sheet, and the day panel beside it, with the
/// settings modal over everything when it is open.
struct MainView: View {
    let model: AppModel
    let calendars: CalendarController

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MainToolbar(model: model, calendars: calendars)
                HStack(alignment: .top, spacing: 24) {
                    MonthSheet(model: model, calendars: calendars)
                    if !model.isPanelHidden {
                        DayPanel(model: model, calendars: calendars)
                            .frame(width: 360)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: model.isPanelHidden)
                .padding(.leading, 20)
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
            .allowsHitTesting(!model.isSettingsOpen)
            .accessibilityHidden(model.isSettingsOpen)
            .overlayPreferenceValue(EventAnchorKey.self) { anchors in
                EventPopoverLayer(model: model, calendars: calendars, anchors: anchors)
            }

            if model.isSettingsOpen {
                SettingsModal(model: model, calendars: calendars)
            }
        }
        .background(.wall)
        .foregroundStyle(.ink)
        .onChange(of: model.month, initial: true) {
            calendars.show(days: model.grid.weeks.flatMap { $0 }, calendar: model.calendar)
        }
        .task { calendars.startAutoSync() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            calendars.appBecameActive()
        }
        // The day-change notification can arrive off the main thread.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            model.refreshToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: RunLoop.main)) { _ in
            model.timeZoneDidChange()
        }
        #if DEBUG
        .task { Snapshot.runIfRequested(model: model, calendars: calendars) }
        .task { WriteCheck.runIfRequested(model: model, calendars: calendars) }
        #endif
    }
}

struct MainToolbar: View {
    let model: AppModel
    let calendars: CalendarController
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
                .help("주 보기는 준비 중이에요")
            Spacer()
            if calendars.unsentWrites.isEmpty {
                SyncStatusView(calendars: calendars) { model.isSettingsOpen = true }
            } else {
                UnsentWritesButton(calendars: calendars)
            }
            Button { model.newEvent(on: model.selectedDay, calendars: calendars) } label: { Label("새 일정", systemImage: "plus") }
                .buttonStyle(DrawnButtonStyle(.primary))
                .disabled(calendars.writableSources.isEmpty)
                .help(calendars.writableSources.isEmpty ? "설정에서 Google이나 iCloud를 연결해 주세요" : "새 일정 (⌘N)")
            Button { model.isPanelHidden.toggle() } label: { Image(systemName: "sidebar.right").font(.system(size: 13)) }
                // Never ink-filled: the primary fill belongs to 새 일정 alone.
                .buttonStyle(DrawnButtonStyle(model.isPanelHidden ? .plain : .toggled))
                .help(model.isPanelHidden ? "패널 보기 (⌘\\)" : "패널 숨기기 (⌘\\)")
                .accessibilityLabel(model.isPanelHidden ? "패널 보기" : "패널 숨기기")
        }
        // Lines up with the month sheet; the traffic lights sit in the strip above this row.
        .padding(.leading, 20)
        .padding(.trailing, 24)
        .frame(height: 64)
    }
}
