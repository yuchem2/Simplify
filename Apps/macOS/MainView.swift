import AppKit
import Combine
import SwiftUI
import SimplifyKit

/// The window: the title bar with the view switch, then one sheet of paper to the window's edges:
/// the calendar (its own heading over the month, week or year) and the day panel past an ink
/// spine, with settings floating over the dimmed window when it is open.
struct MainView: View {
    let model: AppModel
    let calendars: CalendarController
    let memos: MemoBook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The window's width; the panel takes about a third of it.
    @State private var width: CGFloat = 0

    /// The panel's narrowest and widest.
    static let panelWidth: ClosedRange<CGFloat> = 300...460
    /// The spine, the narrowest panel and seven of the smallest day cells with the sheet's padding:
    /// narrower than an 11-inch iPad (834 pt).
    static let minWidth: CGFloat = (Metrics.lineSpine + panelWidth.lowerBound
                                    + MonthSheet.sheetPadding * 2 + MonthSheet.minCellSize.width * 7).rounded(.up)

    private var panelWidth: CGFloat {
        min(max(width * 0.32, Self.panelWidth.lowerBound), Self.panelWidth.upperBound)
    }

    var body: some View {
        ZStack {
            // One sheet of paper: the calendar and the panel, with a single ink spine between them.
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    CalendarHeader(model: model)
                    switch model.calendarView {
                    case .month: MonthSheet(model: model, calendars: calendars, memos: memos)
                    case .week: WeekGrid(model: model, calendars: calendars, memos: memos)
                    case .year: YearGrid(model: model, calendars: calendars)
                    }
                }
                if !model.isPanelHidden {
                    HStack(spacing: 0) {
                        Rectangle().fill(.ink).frame(width: Metrics.lineSpine)
                        DayPanel(model: model, calendars: calendars, memos: memos)
                            .frame(width: panelWidth)
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(.paper)
            // Where the paper meets the title bar.
            .overlay(alignment: .top) { Rectangle().fill(.shade).frame(height: Metrics.line) }
            .clipped()
            .animation(.easeOut(duration: Metrics.motionPanel), value: model.isPanelHidden)
            .allowsHitTesting(!model.isSettingsOpen)
            // Under settings nothing takes keyboard focus either; its controls show disabled under the dimming, as intended.
            .disabled(model.isSettingsOpen)
            .accessibilityHidden(model.isSettingsOpen)
            .overlayPreferenceValue(EventAnchorKey.self) { anchors in
                EventPopoverLayer(model: model, calendars: calendars, anchors: anchors)
            }

            // Settings floats over the dimmed window.
            if model.isSettingsOpen {
                SettingsModal(model: model, calendars: calendars)
            }
        }
        // The title bar's own row: native dragging and double-click on every empty part of it.
        .toolbar { MainToolbar(model: model, calendars: calendars) }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // The wall shows through the title bar, above the paper.
        .background(Color.wall.ignoresSafeArea())
        .foregroundStyle(.ink)
        // Every drawn control shows its own focus ring (a paper gap, then ink), so the system's round blue one stays off.
        .focusEffectDisabled()
        .environment(\.showsPalettePatterns, model.showsPatterns)
        .environment(\.toggleReminder, ReminderToggle { occurrence in
            Task {
                // Nothing to point at for a failure; the ring stays as it was and the Mac says no.
                if await calendars.setReminderDone(occurrence, !occurrence.isCompleted) != nil { NSSound.beep() }
            }
        })
        // The whole app follows the chosen theme; every token colour reads the window's appearance.
        .onChange(of: model.theme) { model.theme.apply() }
        // The month grid's weeks, or the whole year in the year view.
        .onChange(of: model.shownRange, initial: true) {
            calendars.show(days: model.shownDays, calendar: model.calendar)
        }
        .task { calendars.startAutoSync() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            memos.draft.flush()
            DeviceSync.shared.flushOnQuit()
            WidgetRefresh.flush()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            calendars.appBecameActive()
            // A ToDo ticked in a widget.
            memos.reloadIfChangedElsewhere()
            // Other devices' changes.
            DeviceSync.shared.appBecameActive()
        }
        .task { SharedSettings.observeDiaryChanges { memos.reloadIfChangedElsewhere(force: true) } }
        .task {
            // Not for the snapshot runs, which bring their own books.
            guard ProcessInfo.processInfo.environment["SIMPLIFY_SNAPSHOT"] == nil else { return }
            DeviceSync.shared.attach(memos: memos, model: model, calendars: calendars)
        }
        .onOpenURL { url in
            memos.reloadIfChangedElsewhere()
            model.open(url)
        }
        // The day-change notification can arrive off the main thread.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            model.refreshToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: RunLoop.main)) { _ in
            model.timeZoneDidChange()
            WidgetRefresh.request()
        }
        #if DEBUG
        .task { Snapshot.runIfRequested(model: model, calendars: calendars, memos: memos) }
        .task { WriteCheck.runIfRequested(model: model, calendars: calendars) }
        #endif
    }
}

/// The title bar: 새 일정 by the window buttons, the view switch in the middle, sync and the panel
/// on the right. Our own drawn controls, without the system's glass behind them.
struct MainToolbar: ToolbarContent {
    @Bindable var model: AppModel
    let calendars: CalendarController

    var body: some ToolbarContent {
        // Settings dims the window, title bar included; its controls step out of the way.
        ToolbarItem(placement: .navigation) {
            Button { model.newEvent(on: model.selectedDay, calendars: calendars) } label: { Label("새 일정", systemImage: "plus") }
                .labelStyle(.titleAndIcon)
                .buttonStyle(DrawnButtonStyle(.primary))
                .disabled(model.isModalOpen || calendars.writableSources.isEmpty)
                .help(calendars.writableSources.isEmpty ? "설정에서 Google이나 iCloud를 연결해 주세요" : "새 일정 (⌘N)")
                .settingsHidden(model.isSettingsOpen)
        }
        .sharedBackgroundVisibility(.hidden)
        // Like the menu commands, the title bar waits while settings or an event popover is open.
        ToolbarItem(placement: .principal) {
            SegmentedTabs(AppModel.CalendarView.allCases.map { ($0, $0.label) }, selection: $model.calendarView)
                .disabled(model.isModalOpen)
                .accessibilityLabel("보기")
                .settingsHidden(model.isSettingsOpen)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) {
            Group {
                if calendars.unsentWrites.isEmpty {
                    SyncStatusView(calendars: calendars) { model.isSettingsOpen = true }
                } else {
                    UnsentWritesButton(calendars: calendars)
                }
            }
            .disabled(model.isModalOpen)
            .settingsHidden(model.isSettingsOpen)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) {
            Button { model.isPanelHidden.toggle() } label: { Image(systemName: "sidebar.right").font(.system(size: 13)) }
                // Never ink-filled: the primary fill belongs to 새 일정 alone.
                .buttonStyle(DrawnButtonStyle(model.isPanelHidden ? .plain : .toggled))
                .disabled(model.isModalOpen)
                .help(model.isPanelHidden ? "패널 보기 (⌘\\)" : "패널 숨기기 (⌘\\)")
                .accessibilityLabel(model.isPanelHidden ? "패널 보기" : "패널 숨기기")
                .settingsHidden(model.isSettingsOpen)
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

private extension View {
    func settingsHidden(_ isHidden: Bool) -> some View {
        opacity(isHidden ? 0 : 1).accessibilityHidden(isHidden)
    }
}

/// The calendar's own heading on the paper: the year, month or week name, and ‹ 오늘 › to turn pages.
struct CalendarHeader: View {
    let model: AppModel

    var body: some View {
        let view = model.calendarView
        let title = switch view {
        case .week: model.shownWeek.title
        case .month: model.month.title
        case .year: "\(model.shownYear)년"
        }
        let range = view == .week ? model.shownWeek.rangeText : nil
        HStack(alignment: .center, spacing: Metrics.spaceL) {
            // Sized for the widest title of the view so the heading never jumps while turning pages.
            ZStack(alignment: .leading) {
                TitleLine(title: view == .week ? "12월 5주차" : view == .month ? "2026년 12월" : "2026년", range: range == nil ? nil : "10.25 – 10.31").hidden()
                TitleLine(title: title, range: range)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(range.map { "\(title), \($0)" } ?? title)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Metrics.spaceM)
            HStack(spacing: -Metrics.line) {
                Button { model.turnPage(by: -1) } label: { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)) }
                    .accessibilityLabel("이전 \(view.unit)")
                    .help("이전 \(view.unit) (⌘←)")
                Button("오늘") { model.goToToday() }
                    .help("오늘 (⌘T)")
                Button { model.turnPage(by: 1) } label: { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)) }
                    .accessibilityLabel("다음 \(view.unit)")
                    .help("다음 \(view.unit) (⌘→)")
            }
            .buttonStyle(DrawnButtonStyle())
        }
        .padding(.horizontal, MonthSheet.sheetPadding)
        .padding(.top, Metrics.spaceXl)
        .padding(.bottom, Metrics.spaceS)
    }
}

/// The calendar heading: the year, month or week name, and a week's dates after it.
private struct TitleLine: View {
    let title: String
    let range: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceM) {
            Text(title).textStyle(.title)
            if let range {
                Text(range).textStyle(.meta).foregroundStyle(.inkSoft)
            }
        }
    }
}
