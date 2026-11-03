import SwiftUI
import SimplifyKit

/// The month as a ledger on the window's paper, from the calendar's first weekday: an ink rule under each week and no
/// column lines; weekends sit a step off the paper.
struct MonthSheet: View {
    let model: AppModel
    let calendars: CalendarController
    let memos: MemoBook
    /// The sheet holds keyboard focus so the arrow keys move the chosen day.
    @FocusState private var focused: Bool

    /// Smallest day cell; with six rows this sets the sheet's (and the window's) minimum size.
    /// Narrow enough that the month and the panel fit side by side on an 11-inch iPad's width (834 pt).
    static let minCellSize = CGSize(width: 64, height: 72)
    /// Left and right of the grid, inside the paper.
    static let sheetPadding = Metrics.spaceXxl
    /// Below this a cell leaves out start times, so titles still show.
    static let timedCellWidth: CGFloat = 96
    /// Where a date number starts inside its cell; the weekday labels share the same edge.
    static let dateInset = EdgeInsets(top: Metrics.spaceXs, leading: Metrics.spaceM, bottom: Metrics.spaceXs, trailing: Metrics.spaceM)

    var body: some View {
        let grid = model.grid
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(model.calendar.weekdaysInOrder, id: \.self) { weekday in
                    Text(Calendar.weekdayName(weekday))
                        .textStyle(.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(weekday == 1 ? Color.holiday : Color.inkSoft)
                        .padding(.leading, Self.dateInset.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 24)
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
                                        isHoliday: calendars.holidayDays.contains(day), hasMemo: memos.has(Period(containing: day, scope: .day, calendar: model.calendar)),
                                        todoCount: memos.todos.remaining(on: day, calendar: model.calendar),
                                        height: height, textSize: model.cellTextSize,
                                        // A narrow cell has room for the title or the time, not both: the title wins.
                                        showsTimes: model.showsCellTimes && width >= Self.timedCellWidth) {
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
                .overlay { WeekRules(rows: grid.weeks.count).stroke(.ink, lineWidth: Metrics.line) }
                .overlay(alignment: .top) { Rectangle().fill(.ink).frame(height: Metrics.lineSpine) }
            }
            .frame(minWidth: Self.minCellSize.width * 7, minHeight: Self.minCellSize.height * 6)
        }
        .padding(.horizontal, Self.sheetPadding)
        .padding(.bottom, Metrics.spaceXxl)
        .calendarKeys(model: model, calendars: calendars, focused: $focused)
    }
}

/// The rule under each week (the heavy rule above the first is drawn apart).
private struct WeekRules: Shape {
    var rows: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for r in 1...rows {
            let y = rect.minY + rect.height * CGFloat(r) / CGFloat(rows) - Metrics.line / 2
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
    let hasMemo: Bool
    /// Unfinished ToDos on the day, shown as ✓N at the end of the date line.
    let todoCount: Int
    let height: CGFloat
    let textSize: AppModel.CellTextSize
    let showsTimes: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        let isToday = model.isToday(day)
        let number = model.calendar.component(.day, from: day)
        // Not a Button: anchors of the event rows inside a button label never reach the popover.
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 2) {
                // Numbers start on the same line as the weekday labels; today's is bold under the
                // cell's ink bar. A pencil after it: the day has a memo.
                HStack(spacing: Metrics.spaceXs) {
                    Text("\(number)")
                        .textStyle(.date)
                        .fontWeight(isToday ? .bold : .semibold)
                        .foregroundStyle(numberColor)
                        .frame(minHeight: 24)
                    if hasMemo { MemoMark() }
                    if todoCount > 0 {
                        Spacer(minLength: 0)
                        TodoCount(todoCount)
                    }
                }
                let (shown, hidden) = visibleRows
                ForEach(Array(shown.enumerated()), id: \.offset) { _, slot in
                    if let slot {
                        let anchor = EventAnchor.row(slot.occurrence.id, day: day, in: .month)
                        EventRow(slot: slot, source: sources[slot.occurrence.sourceID], textSize: textSize,
                                 time: showsTimes ? cellTime(slot) : nil,
                                 // A band repeats its title at the start of each row of the grid.
                                 showsTitle: !slot.continuesFromPrevious || model.calendar.component(.weekday, from: day) == model.calendar.firstWeekday,
                                 isSelected: model.selectedEventID == slot.occurrence.id)
                            .unsentOutline(calendars.isUnsent(slot.occurrence))
                            // Days of the next or last month step back with their date.
                            .opacity(inMonth ? 1 : Metrics.opacityOutOfMonth)
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
                        .lineLimit(1)
                        .padding(.leading, textSize.markSize + Metrics.spaceXs)
                        .foregroundStyle(.inkSoft)
                }
            }
            .padding(MonthSheet.dateInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // The chosen day: ink sides that meet the week rules above and below. The pointer: a
            // hairline box in shade.
            .background {
                if model.isSelected(day) {
                    ChosenSides().stroke(.ink, lineWidth: Metrics.line)
                } else if hovering {
                    Rectangle().inset(by: Metrics.spaceXs).strokeBorder(.shade, lineWidth: Metrics.line)
                }
            }
            // Today: a 3 pt ink bar just under the rule above the cell, so it still shows below the
            // heavy rule over the first week.
            .overlay(alignment: .top) {
                if isToday { Rectangle().fill(.ink).frame(height: 3).padding(.top, Metrics.lineSpine) }
            }
            .background(isWeekend ? Color.raised : Color.clear)
            .clipped()
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
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

    /// `09:30` for a timed event; nothing for a reminder due on a day without a time.
    private func cellTime(_ slot: OccurrenceBuilder.Slot) -> String? {
        let start = slot.occurrence.start
        if sources[slot.occurrence.sourceID]?.isReminderList == true, start == model.calendar.startOfDay(for: start) { return nil }
        return DateText.shortClock(start, calendar: model.calendar)
    }

    private var isWeekend: Bool {
        let weekday = model.calendar.component(.weekday, from: day)
        return weekday == 1 || weekday == 7
    }

    private var numberColor: Color {
        if !inMonth { return .inkFaint }
        return model.isRedDay(day) || isHoliday ? .holiday : .ink
    }

    private func accessibilityText(isToday: Bool) -> String {
        var text = Period(containing: day, scope: .day, calendar: model.calendar).title
        if isToday { text += ", 오늘" }
        if !slots.isEmpty { text += ", 일정 \(slots.count)개" }
        if hasMemo { text += ", 메모 있음" }
        if todoCount > 0 { text += ", 남은 할 일 \(todoCount)개" }
        return text
    }
}

/// The left, bottom and right edges of a rectangle, for the chosen day.
private struct ChosenSides: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.insetBy(dx: 0.5, dy: 0.5)
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return path
    }
}

/// One event inside a day cell: a band for all-day and multi-day events, a coloured mark, start
/// time and title for timed ones, red text for public holidays. Reminders always take one row with a round
/// mark, struck through once completed.
private struct EventRow: View {
    let slot: OccurrenceBuilder.Slot
    let source: CalendarController.Source?
    let textSize: AppModel.CellTextSize
    /// `09:30` before a timed title, or nil when 설정 turns times off.
    let time: String?
    let showsTitle: Bool
    /// Picked with a click or Tab: drawn in ink.
    var isSelected = false
    @Environment(\.showsPalettePatterns) private var showsPatterns

    var body: some View {
        let look = source?.look ?? CalendarLook(.grey)
        let done = slot.occurrence.isCompleted
        let color = isSelected ? Color.onInk : EventTime.titleColor(slot.occurrence, source: source)
        let title = Text(slot.occurrence.title)
            .font(.system(size: textSize.points))
            .foregroundStyle(color)
            .lineLimit(1)
            .ledgerStrikethrough(done, color: color)
        if source?.isHoliday == true {
            title.background { if isSelected { Rectangle().fill(.ink).padding(.horizontal, -2) } }
        } else if slot.occurrence.isBand, source?.isReminderList != true {
            // With patterns on, the band starts with its calendar's shape in place of the colour cap.
            let capped = !slot.continuesFromPrevious && !showsPatterns
            HStack(spacing: Metrics.spaceXs) {
                if showsPatterns, !slot.continuesFromPrevious {
                    Mark(isSelected ? .onInk : look.ink, size: textSize.markSize, shape: look.shape)
                }
                title
            }
            .opacity(showsTitle ? 1 : 0)
            .padding(.leading, capped ? 9 : slot.continuesFromPrevious ? 6 : Metrics.spaceXs)
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity, minHeight: textSize.rowHeight - 2, alignment: .leading)
            .background(isSelected ? Color.ink : look.tint)
            .overlay(alignment: .leading) {
                if capped {
                    Rectangle().fill(look.ink).frame(width: 6)
                        .overlay(alignment: .trailing) { Rectangle().fill(.ink).frame(width: Metrics.line) }
                }
            }
            .overlay {
                // Outline only the band's own ends, so it reads as one band across cells.
                BandOutline(open: (slot.continuesFromPrevious, slot.continuesToNext)).stroke(.ink, lineWidth: Metrics.line)
            }
            // Run to the cell edges where the band continues.
            .padding(.leading, slot.continuesFromPrevious ? -MonthSheet.dateInset.leading : -Metrics.spaceXs)
            .padding(.trailing, slot.continuesToNext ? -MonthSheet.dateInset.trailing : 0)
        } else {
            HStack(spacing: Metrics.spaceXs) {
                EventMark(occurrence: slot.occurrence, source: source, size: textSize.markSize)
                if let time {
                    Text(time)
                        .font(.system(size: textSize.points).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.onInk : Color.inkSoft)
                        .fixedSize()
                        // The cell is read as before; the time is in the event's own details.
                        .accessibilityHidden(true)
                }
                title
            }
            .background { if isSelected { Rectangle().fill(Tokens.selection).padding(.horizontal, -2) } }
        }
    }
}

/// The mark in front of an event's title: a square in its calendar's colour, or a ring for a reminder.
/// Clicking a reminder's ring ticks it off (or back on) in the Reminders app.
struct EventMark: View {
    let occurrence: EventOccurrence
    let source: CalendarController.Source?
    let size: CGFloat
    @Environment(\.toggleReminder) private var toggleReminder

    var body: some View {
        if source?.isReminderList == true {
            let ring = ReminderMark(source?.look.ink, size: size, isCompleted: occurrence.isCompleted)
            if let toggleReminder, source?.isReadOnly != true {
                Button { toggleReminder(occurrence) } label: {
                    // A few points of slack around the ring, so a small one is still easy to hit.
                    ring.padding(Metrics.spaceXs).contentShape(Rectangle()).padding(-Metrics.spaceXs)
                }
                .buttonStyle(FocusOnlyStyle())
                .help(occurrence.isCompleted ? "완료 취소" : "완료로 표시")
                .accessibilityLabel(occurrence.isCompleted ? "\(occurrence.title) 완료 취소" : "\(occurrence.title) 완료로 표시")
            } else {
                ring
            }
        } else {
            Mark(source?.look.ink, size: size, shape: source?.look.shape)
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

/// Ticks a reminder off or back on from its ring. Set once on the window and never replaced, so
/// any two count as equal and setting it never redraws what reads it.
struct ReminderToggle: Equatable {
    let run: (EventOccurrence) -> Void

    func callAsFunction(_ occurrence: EventOccurrence) { run(occurrence) }

    static func == (lhs: ReminderToggle, rhs: ReminderToggle) -> Bool { true }
}

extension EnvironmentValues {
    /// Nil where reminder rings only show.
    @Entry var toggleReminder: ReminderToggle?
}
