import SwiftUI
import SimplifyKit

/// Beside a wide panel, in place of the calendar: a small month to move between days, and under it
/// the events of the panel's day, week or month, a week's and a month's grouped by day. The panel
/// then leaves its own events out, so none show twice.
struct WideCalendar: View {
    let model: AppModel
    let calendars: CalendarController
    let memos: MemoBook
    /// The column holds keyboard focus so the arrow keys move the chosen day, as the calendar's do.
    @FocusState private var focused: Bool

    var body: some View {
        let day = model.selectedDay
        let parts = model.calendar.dateComponents([.month, .day], from: day)
        let range = model.panelScope == .day ? nil : model.panelPeriod
        VStack(alignment: .leading, spacing: Metrics.spaceL) {
            MiniMonth(model: model, calendars: calendars, memos: memos)
            SectionRule(range.map(title) ?? "\(parts.month!)월 \(parts.day!)일 일정") {
                // On the chosen day, whether the column shows its day, week or month.
                Button("추가") { model.newEvent(on: model.selectedDay, calendars: calendars) }
                    .buttonStyle(DrawnButtonStyle(.text))
                    .disabled(calendars.writableSources.isEmpty)
                    .help(calendars.writableSources.isEmpty ? "설정에서 Google이나 iCloud를 연결해 주세요" : "이날에 새 일정 (⌘N)")
            }
                .padding(.top, Metrics.spaceS)
            ScrollArea {
                Group {
                    if let range {
                        WeekEvents(period: range, model: model, calendars: calendars)
                    } else {
                        DayEvents(slots: calendars.slots[day] ?? [], day: day, model: model, calendars: calendars,
                                  calendar: model.calendar, empty: "이날은 일정이 없어요.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Metrics.spaceXxl)
            }
        }
        .padding(.horizontal, Metrics.spaceXl)
        .padding(.top, Metrics.spaceXl)
        .calendarKeys(model: model, calendars: calendars, focused: $focused, leavesFocus: memos.draft.hasFocus)
    }

    /// `11월 1주차 일정`, `11월 일정`.
    private func title(_ period: Period) -> String {
        period.scope == .week ? "\(period.title) 일정" : "\(model.calendar.component(.month, from: period.start))월 일정"
    }
}

/// The small month: date numbers in figures, Sundays and holidays red, today filled with ink, the
/// chosen day in an ink box, a dot under days with a memo, and the panel's week or month on a
/// raised ground. A click goes to that day, a double-click starts a new event there; ‹ › turn the month.
struct MiniMonth: View {
    let model: AppModel
    let calendars: CalendarController
    let memos: MemoBook

    static let cellHeight: CGFloat = 28

    var body: some View {
        let grid = model.grid
        let range = model.panelScope == .day ? nil : model.panelPeriod
        VStack(alignment: .leading, spacing: Metrics.spaceS) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceM) {
                Text(model.month.title)
                    .textStyle(.subheading)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Metrics.spaceXs)
                HStack(spacing: -Metrics.line) {
                    Button { model.turnMonth(by: -1) } label: { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)) }
                        .accessibilityLabel("이전 달")
                        .help("이전 달")
                    Button { model.turnMonth(by: 1) } label: { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)) }
                        .accessibilityLabel("다음 달")
                        .help("다음 달")
                }
                .buttonStyle(DrawnButtonStyle())
            }
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(model.calendar.weekdaysInOrder, id: \.self) { weekday in
                        Text(Calendar.weekdayName(weekday))
                            .textStyle(.meta)
                            .foregroundStyle(weekday == 1 ? Color.holiday : Color.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, Metrics.spaceXxs)
                    }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(.ink).frame(height: Metrics.lineSpine) }
                .accessibilityHidden(true)
                ForEach(grid.weeks, id: \.first) { week in
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { day in
                            MiniDay(day: day, model: model, calendars: calendars, inMonth: grid.isInMonth(day), isHoliday: calendars.holidayDays.contains(day),
                                    hasMemo: memos.has(Period(containing: day, scope: .day, calendar: model.calendar)),
                                    inRange: range?.contains(day) == true)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("작은 달력")
        }
    }
}

private struct MiniDay: View {
    let day: Date
    let model: AppModel
    let calendars: CalendarController
    let inMonth: Bool
    let isHoliday: Bool
    let hasMemo: Bool
    /// In the week or month the panel shows.
    let inRange: Bool
    @State private var hovering = false
    /// An event row is dragged over the day.
    @State private var dropping = false

    var body: some View {
        let isToday = model.isToday(day)
        let isChosen = model.isSelected(day)
        let red = model.isRedDay(day) || isHoliday
        let color: Color = isToday ? .onInk : !inMonth ? .inkFaint : red ? .holiday : .ink
        Text("\(model.calendar.component(.day, from: day))")
            .textStyle(.small)
            .fontWeight(isToday ? .semibold : .regular)
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: MiniMonth.cellHeight)
            .background(isToday ? Tokens.selection : hovering || dropping ? Color.hover : inRange ? Color.raised : Color.clear)
            // An event dragged over the day: the pointer's ground, outlined in ink.
            .overlay {
                if dropping {
                    Rectangle().strokeBorder(isToday ? Color.onInk : Color.ink, lineWidth: Metrics.line)
                }
            }
            .overlay {
                if isChosen {
                    Rectangle().inset(by: Metrics.spaceXxs).strokeBorder(isToday ? Color.onInk : Color.ink, lineWidth: Metrics.lineBox)
                }
            }
            .overlay(alignment: .bottom) {
                if hasMemo {
                    Rectangle().fill(isToday ? Color.onInk : Color.inkSoft).frame(width: 3, height: 3).padding(.bottom, Metrics.spaceXs)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            // ⌘N and new events point here, as they point at a day cell of the month.
            .eventAnchor(EventAnchor.cell(day))
            // As on the month's day cells: a double-click makes an event, and the first click
            // still picks the day at once rather than after the double-click wait.
            .onTapGesture(count: 2) { model.newEvent(on: day, calendars: calendars) }
            .simultaneousGesture(TapGesture().onEnded { if !model.isModalOpen { model.select(day) } })
            .takesEvent(on: day, isTargeted: $dropping, model: model, calendars: calendars)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(isToday: isToday))
            .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.select(day) }
    }

    private func label(isToday: Bool) -> String {
        var text = Period(containing: day, scope: .day, calendar: model.calendar).title
        if isToday { text += ", 오늘" }
        if hasMemo { text += ", 메모 있음" }
        return text
    }
}
