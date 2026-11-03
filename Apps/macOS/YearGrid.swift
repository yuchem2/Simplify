import SwiftUI
import SimplifyKit

/// The year as twelve small months on the window's paper. A dot under a date: something is on that
/// day. Clicking a date chooses it (the panel follows); a double-click or the month's name opens
/// that month.
struct YearGrid: View {
    let model: AppModel
    let calendars: CalendarController
    /// The grid holds keyboard focus so the arrow keys move the chosen day, as in the month.
    @FocusState private var focused: Bool

    /// Smallest month block; four across and three down fit the window's minimum size.
    static let minMonthSize = CGSize(width: 104, height: 100)

    var body: some View {
        GeometryReader { geo in
            // Four months across when there is room, three in a narrow window.
            let columns = geo.size.width >= 4 * 150 ? 4 : 3
            let rows = 12 / columns
            let spacingX = Metrics.spaceXxl, spacingY = Metrics.spaceL
            let width = (geo.size.width - spacingX * CGFloat(columns - 1)) / CGFloat(columns)
            let height = (geo.size.height - spacingY * CGFloat(rows - 1)) / CGFloat(rows)
            VStack(alignment: .leading, spacing: spacingY) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: spacingX) {
                        ForEach(0..<columns, id: \.self) { column in
                            MiniMonth(month: row * columns + column + 1, model: model, calendars: calendars) { focused = true }
                                .frame(width: width, height: height, alignment: .top)
                        }
                    }
                }
            }
        }
        // Three across and four down in the smallest window.
        .frame(minWidth: Self.minMonthSize.width * 3 + Metrics.spaceXxl * 2, minHeight: Self.minMonthSize.height * 4 + Metrics.spaceL * 3)
        .padding(.horizontal, MonthSheet.sheetPadding)
        .padding(.top, Metrics.spaceS)
        .padding(.bottom, Metrics.spaceXxl)
        .calendarKeys(model: model, calendars: calendars, focused: $focused)
    }
}

/// One month of the year: its name over an ink rule, weekday letters, and the dates.
private struct MiniMonth: View {
    let month: Int
    let model: AppModel
    let calendars: CalendarController
    /// Gives the arrow keys back to the year after a click.
    let takeFocus: () -> Void

    var body: some View {
        let calendar = model.calendar
        let first = calendar.date(from: DateComponents(year: model.shownYear, month: month, day: 1))!
        let grid = MonthGrid(month: first, calendar: calendar)
        VStack(alignment: .leading, spacing: Metrics.spaceXs) {
            Button { open(first) } label: {
                Text("\(month)월")
                    .textStyle(.date)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FocusOnlyStyle())
            .help("\(month)월 보기")
            Rectangle().fill(.ink).frame(height: Metrics.line)
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(calendar.weekdaysInOrder, id: \.self) { weekday in
                        Text(Calendar.weekdayName(weekday))
                            .textStyle(.meta)
                            .foregroundStyle(weekday == 1 ? Color.holiday : Color.inkSoft)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(grid.weeks, id: \.first) { week in
                    GridRow {
                        ForEach(week, id: \.self) { day in
                            if grid.isInMonth(day) {
                                YearDay(day: day, model: model, calendars: calendars, takeFocus: takeFocus) { open(day) }
                            } else {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }
                // Always six rows, so dates line up across months of five and six weeks.
                ForEach(grid.weeks.count..<6, id: \.self) { _ in
                    GridRow { Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).gridCellColumns(7) }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(month)월")
    }

    /// The month view, on `day`.
    private func open(_ day: Date) {
        model.select(day)
        model.calendarView = .month
    }
}

/// A date in a small month: today bold and ink-ruled under, the chosen day filled with ink, a dot
/// under a day that has something on it.
private struct YearDay: View {
    let day: Date
    let model: AppModel
    let calendars: CalendarController
    let takeFocus: () -> Void
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        let isToday = model.isToday(day)
        let chosen = model.isSelected(day)
        let busy = calendars.slots[day]?.contains { calendars.sources[$0.occurrence.sourceID]?.isHoliday != true } ?? false
        let red = model.isRedDay(day) || calendars.holidayDays.contains(day)
        VStack(spacing: 1) {
            Text("\(model.calendar.component(.day, from: day))")
                .textStyle(.meta)
                .fontWeight(isToday ? .bold : .medium)
                .foregroundStyle(chosen ? Color.onInk : red ? Color.holiday : Color.ink)
                .frame(minWidth: 20)
                .padding(.vertical, 1)
                .background(chosen ? Tokens.selection : hovering ? Color.hover : Color.clear)
                .overlay(alignment: .bottom) {
                    if isToday && !chosen { Rectangle().fill(.ink).frame(height: 2).offset(y: 2) }
                }
            Circle()
                .fill(busy ? Color.inkSoft : Color.clear)
                .frame(width: 3, height: 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onOpen() }
        .simultaneousGesture(TapGesture().onEnded {
            guard !model.isModalOpen else { return }
            model.select(day)
            takeFocus()
        })
        // ⌘N on the chosen day points its popover here.
        .eventAnchor(EventAnchor.cell(day))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Period(containing: day, scope: .day, calendar: model.calendar).title + (isToday ? ", 오늘" : "") + (busy ? ", 일정 있음" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityAction { model.select(day) }
    }
}
