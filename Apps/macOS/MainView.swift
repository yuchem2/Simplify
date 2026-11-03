import AppKit
import Combine
import SwiftUI
import SimplifyKit

/// The window: the title bar with the view switch, then one sheet of paper to the window's edges:
/// the calendar (its own heading over the month, week or year) and the day panel past an ink
/// spine, with settings floating over the dimmed window when it is open. A wide panel folds the
/// calendar into a small month; dragging the spine moves the line between them.
struct MainView: View {
    let model: AppModel
    let calendars: CalendarController
    let memos: MemoBook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The window's width; the panel takes about a third of it until the spine is dragged.
    @State private var width: CGFloat = 0

    /// The spine, the narrowest panel and seven of the smallest day cells with the sheet's padding:
    /// narrower than an 11-inch iPad (834 pt).
    static let minWidth: CGFloat = (Metrics.lineSpine + PanelLayout.normalMin + calendarMinWidth).rounded(.up)
    /// The calendar's narrowest: seven of the smallest day cells with the sheet's padding.
    static let calendarMinWidth: CGFloat = MonthSheet.sheetPadding * 2 + MonthSheet.minCellSize.width * 7

    private var space: PanelLayout.Space {
        PanelLayout.Space(window: width, calendarMin: Self.calendarMinWidth, spine: Metrics.lineSpine)
    }

    /// The panel's width beside the full calendar, or the small month's beside a wide panel.
    private var panelWidth: CGFloat { PanelLayout.normalWidth(model.panelWidth, in: space) }
    private var miniWidth: CGFloat { PanelLayout.miniWidth(model.miniMonthWidth) }
    private var isWide: Bool { model.isPanelWide && !model.isPanelHidden }

    var body: some View {
        ZStack {
            // One sheet of paper: the calendar and the panel, with a single ink spine between them.
            HStack(alignment: .top, spacing: 0) {
                if isWide {
                    WideCalendar(model: model, calendars: calendars, memos: memos)
                        .frame(width: miniWidth)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 0) {
                        CalendarHeader(model: model)
                        switch model.calendarView {
                        case .month: MonthSheet(model: model, calendars: calendars, memos: memos)
                        case .week: WeekGrid(model: model, calendars: calendars, memos: memos)
                        case .year: YearGrid(model: model, calendars: calendars)
                        }
                    }
                    .transition(.opacity)
                }
                if !model.isPanelHidden {
                    HStack(spacing: 0) {
                        Rectangle().fill(.ink).frame(width: Metrics.lineSpine)
                            .overlay { SpineHandle(model: model, space: space) }
                            .zIndex(1)
                        DayPanel(model: model, calendars: calendars, memos: memos)
                            .frame(width: isWide ? nil : panelWidth)
                            .frame(maxWidth: isWide ? .infinity : nil)
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(.paper)
            // Where the paper meets the title bar.
            .overlay(alignment: .top) { Rectangle().fill(.shade).frame(height: Metrics.line) }
            .clipped()
            .animation(.easeOut(duration: Metrics.motionPanel), value: model.isPanelHidden)
            // The panel's width does not slide under reduced motion; the calendars still cross-fade.
            .animation(reduceMotion ? nil : .easeOut(duration: Metrics.motionPanel), value: model.isPanelWide)
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
            IconSegments(AppModel.PanelMode.allCases.map { .init($0, label: $0.label, help: $0.help) },
                         selection: $model.panelMode) { PanelGlyph(mode: $0) }
                .disabled(model.isModalOpen)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("패널")
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

/// The panel segments' picture: a window with the part the panel takes filled in, none, some or most.
private struct PanelGlyph: View {
    let mode: AppModel.PanelMode

    var body: some View {
        let filled: CGFloat = switch mode {
        case .hidden: 0
        case .normal: 6
        case .wide: 12
        }
        ZStack(alignment: .trailing) {
            Rectangle().fill(.foreground).frame(width: filled)
            Rectangle().strokeBorder(.foreground, lineWidth: Metrics.lineMark)
        }
        .frame(width: 18, height: 12)
        .accessibilityHidden(true)
    }
}

/// A few points either side of the spine where the pointer turns into the column-resize arrows;
/// nothing is drawn. Dragging moves the panel's edge, and past the calendar's narrowest folds the
/// calendar into the small month (and back), as a Finder sidebar folds. A double-click puts the
/// width back to its default. The mouse only: the panel segments and ⌘⇧\ do the same from the keys.
private struct SpineHandle: View {
    let model: AppModel
    let space: PanelLayout.Space
    /// The calendar's width when the drag began; the spine then follows the pointer's travel (in
    /// the window, since the handle itself moves).
    @State private var start: CGFloat?

    static let reach: CGFloat = 4

    var body: some View {
        Color.clear
            .frame(width: Metrics.lineSpine + Self.reach * 2)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let from = start ?? calendarWidth
                    start = from
                    switch PanelLayout.drag(to: from + drag.translation.width, isWide: model.isPanelWide, in: space) {
                    // Only what changed, so a still pointer writes nothing.
                    case .normal(let panel):
                        if model.isPanelWide { model.isPanelWide = false }
                        if model.panelWidth != panel { model.panelWidth = panel }
                    case .wide(let mini):
                        if !model.isPanelWide { model.isPanelWide = true }
                        if model.miniMonthWidth != mini { model.miniMonthWidth = mini }
                    }
                }
                .onEnded { _ in start = nil })
            .onTapGesture(count: 2) {
                if model.isPanelWide { model.miniMonthWidth = nil } else { model.panelWidth = nil }
            }
            .accessibilityHidden(true)
    }

    private var calendarWidth: CGFloat {
        model.isPanelWide ? PanelLayout.miniWidth(model.miniMonthWidth)
            : space.window - space.spine - PanelLayout.normalWidth(model.panelWidth, in: space)
    }
}
