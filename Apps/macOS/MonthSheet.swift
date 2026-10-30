import SwiftUI
import SimplifyKit

/// The month as a ruled grid on a moulded sheet, Sunday first.
struct MonthSheet: View {
    let model: AppModel
    let calendars: CalendarController
    /// The sheet holds keyboard focus so the arrow keys move the chosen day.
    @FocusState private var focused: Bool

    private static let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
    /// Smallest day cell; with six rows this sets the sheet's (and the window's) minimum size.
    static let minCellSize = CGSize(width: 100, height: 80)
    /// Where a date number starts inside its cell; the weekday labels share the same edge.
    static let dateInset = EdgeInsets(top: 8, leading: 14, bottom: 4, trailing: 7)

    var body: some View {
        let grid = model.grid
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(name == "일" ? Color.holiday : Color.inkSoft)
                        .padding(.leading, Self.dateInset.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GeometryReader { geo in
                let width = geo.size.width / 7
                let height = geo.size.height / CGFloat(grid.weeks.count)
                VStack(spacing: 0) {
                    ForEach(grid.weeks, id: \.first) { week in
                        let lanes = calendars.lanes[week[0]]
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { day in
                                DayCell(day: day, model: model, calendars: calendars, inMonth: grid.isInMonth(day),
                                        slots: calendars.slots[day] ?? [], lanes: lanes, sources: calendars.sources,
                                        isHoliday: calendars.holidayDays.contains(day), height: height, textSize: model.cellTextSize) {
                                    // After the click's other handlers: an event click or a double-click opens the
                                    // event popover in the same click, and then the panel and focus stay as they are.
                                    Task { @MainActor in
                                        guard !model.isModalOpen else { return }
                                        // Clicking the chosen day again opens a folded panel.
                                        if model.isSelected(day), model.isPanelHidden { model.isPanelHidden = false }
                                        model.select(day)
                                        focused = true
                                    }
                                }
                                .frame(width: width, height: height)
                            }
                        }
                    }
                }
                .overlay { GridLines(columns: 7, rows: grid.weeks.count).stroke(.ink, lineWidth: Metrics.line) }
            }
            .frame(minWidth: Self.minCellSize.width * 7, minHeight: Self.minCellSize.height * 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .mouldedFrame()
        .calendarKeys(model: model, calendars: calendars, focused: $focused)
    }
}

/// Every row and column edge of an evenly divided rectangle.
private struct GridLines: Shape {
    var columns: Int
    var rows: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for c in 0...columns {
            let x = rect.minX + rect.width * CGFloat(c) / CGFloat(columns)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for r in 0...rows {
            let y = rect.minY + rect.height * CGFloat(r) / CGFloat(rows)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private struct DayCell: View {
    let day: Date
    let model: AppModel
    let calendars: CalendarController
    let inMonth: Bool
    let slots: [OccurrenceBuilder.Slot]
    /// The week's band rows, so a band stays on one row across the week.
    let lanes: BandLanes?
    let sources: [String: CalendarController.Source]
    let isHoliday: Bool
    let height: CGFloat
    let textSize: AppModel.CellTextSize
    let onSelect: () -> Void

    var body: some View {
        let isToday = model.isToday(day)
        let number = model.calendar.component(.day, from: day)
        // Not a Button: anchors of the event rows inside a button label never reach the popover.
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 2) {
                // Numbers start on the same line as the weekday labels; today's disc grows
                // around its number without moving it.
                Text("\(number)")
                    .font(.display(16))
                    .foregroundStyle(numberColor(isToday: isToday))
                    .padding(.horizontal, isToday ? 4 : 0)
                    .frame(minWidth: isToday ? 24 : nil, minHeight: 24)
                    .background { if isToday { Capsule().fill(.ink) } }
                    // The disc's left edge sits 4 pt before the date line, well inside the selection.
                    .padding(.leading, isToday ? -4 : 0)
                let (shown, hidden) = visibleRows
                ForEach(Array(shown.enumerated()), id: \.offset) { _, slot in
                    if let slot {
                        let anchor = EventAnchor.row(slot.occurrence.id, day: day, in: .month)
                        EventRow(slot: slot, source: sources[slot.occurrence.sourceID], textSize: textSize,
                                 // A band repeats its title at the start of each row of the grid.
                                 showsTitle: !slot.continuesFromPrevious || model.calendar.component(.weekday, from: day) == model.calendar.firstWeekday,
                                 isSelected: model.selectedEventID == slot.occurrence.id)
                            .unsentOutline(calendars.isUnsent(slot.occurrence))
                            .eventAnchor(anchor)
                            .opensEvent(slot.occurrence, day: day, anchor: anchor, model: model, calendars: calendars)
                    } else {
                        // A row kept for a band that runs on other days of the week.
                        Color.clear.frame(height: textSize.rowHeight - 2)
                    }
                }
                if hidden > 0 {
                    Text("+\(hidden)개 더")
                        .font(.system(size: textSize.points, weight: .medium))
                        .foregroundStyle(.inkSoft)
                }
            }
            .padding(MonthSheet.dateInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // The selection moulding sits behind the date so today's disc stays whole.
            .background {
                if model.isSelected(day) {
                    Rectangle().inset(by: 4).strokeBorder(.ink, lineWidth: Metrics.line)
                }
            }
            .background(inMonth ? Color.clear : Color.shadeSoft)
            .clipped()
            .contentShape(Rectangle())
        }
        // A double-click on the empty part of a day starts a new event there.
        .onTapGesture(count: 2) { model.newEvent(on: day, calendars: calendars) }
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .eventAnchor(EventAnchor.cell(day))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSelect() }
        .accessibilityLabel(accessibilityText(isToday: isToday))
        .accessibilityAddTraits(model.isSelected(day) ? .isSelected : [])
    }

    /// As many rows as the cell fits, empty band rows included; when some are left over, the last
    /// row says how many events (not empty rows) did not fit.
    private var visibleRows: ([OccurrenceBuilder.Slot?], Int) {
        let rows = lanes?.rows(slots) ?? slots.map(Optional.some)
        let space = height - MonthSheet.dateInset.top - MonthSheet.dateInset.bottom - 24 - 2
        let fits = max(1, Int(space / textSize.rowHeight))
        guard rows.count > fits else { return (rows, 0) }
        return (Array(rows.prefix(fits - 1)), rows.dropFirst(fits - 1).count { $0 != nil })
    }

    private func numberColor(isToday: Bool) -> Color {
        if isToday { return .onInk }
        if !inMonth { return .inkFaint }
        return model.isRedDay(day) || isHoliday ? .holiday : .ink
    }

    private func accessibilityText(isToday: Bool) -> String {
        var text = Period(containing: day, scope: .day, calendar: model.calendar).title
        if isToday { text += ", 오늘" }
        if !slots.isEmpty { text += ", 일정 \(slots.count)개" }
        return text
    }
}

/// One event inside a day cell: a band for all-day and multi-day events, a coloured mark and
/// title for timed ones, red text for public holidays. Reminders always take one row with a round
/// mark, struck through once completed.
private struct EventRow: View {
    let slot: OccurrenceBuilder.Slot
    let source: CalendarController.Source?
    let textSize: AppModel.CellTextSize
    let showsTitle: Bool
    /// Picked with a click or Tab: drawn in ink.
    var isSelected = false

    var body: some View {
        let palette = source?.palette ?? .grey
        let done = slot.occurrence.isCompleted
        let title = Text(slot.occurrence.title)
            .font(.system(size: textSize.points))
            .strikethrough(done)
            .foregroundStyle(isSelected ? Color.onInk : EventTime.titleColor(slot.occurrence, source: source))
            .lineLimit(1)
        if source?.isHoliday == true {
            title.background { if isSelected { Rectangle().fill(.ink).padding(.horizontal, -2) } }
        } else if slot.occurrence.isBand, source?.isReminderList != true {
            title
                .opacity(showsTitle ? 1 : 0)
                .padding(.leading, slot.continuesFromPrevious ? 6 : 9)
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, minHeight: textSize.rowHeight - 2, alignment: .leading)
                .background(isSelected ? Color.ink : palette.tint)
                .overlay(alignment: .leading) {
                    if !slot.continuesFromPrevious {
                        Rectangle().fill(palette.ink).frame(width: 6)
                            .overlay(alignment: .trailing) { Rectangle().fill(.ink).frame(width: Metrics.line) }
                    }
                }
                .overlay {
                    // Outline only the band's own ends, so it reads as one band across cells.
                    BandOutline(open: (slot.continuesFromPrevious, slot.continuesToNext)).stroke(.ink, lineWidth: Metrics.line)
                }
                // Run to the cell edges where the band continues.
                .padding(.leading, slot.continuesFromPrevious ? -MonthSheet.dateInset.leading : -8)
                .padding(.trailing, slot.continuesToNext ? -MonthSheet.dateInset.trailing : 0)
        } else {
            // Timed rows start a little left of the date line to give the title more room.
            HStack(spacing: 4) {
                EventMark(occurrence: slot.occurrence, source: source, size: textSize.markSize)
                title
            }
            .background { if isSelected { Rectangle().fill(.ink).padding(.horizontal, -2) } }
            .padding(.leading, -6)
        }
    }
}

/// The mark in front of an event's title: a square in its calendar's colour, or a ring for a reminder.
struct EventMark: View {
    let occurrence: EventOccurrence
    let source: CalendarController.Source?
    let size: CGFloat

    var body: some View {
        if source?.isReminderList == true {
            ReminderMark(source?.palette.ink, size: size, isCompleted: occurrence.isCompleted)
        } else {
            Mark(source?.palette.ink, size: size)
        }
    }
}

/// A rectangle outline missing its left and/or right side.
struct BandOutline: Shape {
    var open: (leading: Bool, trailing: Bool)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.insetBy(dx: 0.5, dy: 0.5)
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        if open.trailing { path.move(to: CGPoint(x: r.maxX, y: r.maxY)) } else { path.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        if !open.leading { path.addLine(to: CGPoint(x: r.minX, y: r.minY)) }
        return path
    }
}
