import AppKit
import SwiftUI
import SimplifyKit

/// The chosen day's week on the main paper (MainView draws the sheet): day heads, a strip of
/// all-day and multi-day bands under an ink spine, then the hours of each day from midnight to
/// midnight, scrolled to about now when it opens.
struct WeekGrid: View {
    let model: AppModel
    let calendars: CalendarController
    let memos: MemoBook
    @FocusState private var focused: Bool

    static let hourHeight: CGFloat = 44
    /// Room for the hour labels left of the days; the bands strip says 종일 there.
    static let gutter: CGFloat = 56
    static let laneHeight: CGFloat = 20
    /// Band rows shown before the last one turns into "+N개".
    static let maxLanes = 4
    /// The shortest a block is drawn, so a 10-minute event or a reminder still fits its title.
    static let minBlockHeight: CGFloat = 20
    /// Height of the ink bar over today's head, as on today's cell in the month.
    static let todayBar: CGFloat = 3

    var body: some View {
        let days = model.shownWeek.days
        VStack(spacing: 0) {
            DayHeads(days: days, model: model, calendars: calendars, memos: memos) { day in
                if model.isSelected(day), model.isPanelHidden { model.isPanelHidden = false }
                model.select(day)
                focused = true
            }
            Rectangle().fill(.shade).frame(height: Metrics.line)
            BandStrip(days: days, lanes: calendars.lanes[days[0]], model: model, calendars: calendars)
            // The one heavy rule of the grid, as under the month's weekday row.
            Rectangle().fill(.ink).frame(height: Metrics.lineSpine)
            HourGrid(days: days, model: model, calendars: calendars) { day in
                // After the click's other handlers, as in the month: an event click opens the
                // popover in the same click, and then the chosen day and focus stay as they are.
                Task { @MainActor in
                    guard !model.isModalOpen else { return }
                    // Clicking the chosen day again opens a folded panel.
                    if model.isSelected(day), model.isPanelHidden { model.isPanelHidden = false }
                    model.select(day)
                    focused = true
                }
            }
        }
        // The same footprint as the month, so switching views never resizes the window.
        .frame(minWidth: MonthSheet.minCellSize.width * 7, minHeight: MonthSheet.minCellSize.height * 6)
        .padding(.horizontal, Metrics.spaceXxl)
        .padding(.bottom, Metrics.spaceXxl)
        .calendarKeys(model: model, calendars: calendars, focused: $focused)
    }

    static func weekdayName(_ day: Date, calendar: Calendar) -> String {
        Calendar.weekdayName(calendar.component(.weekday, from: day))
    }

    /// Sunday and Saturday columns sit one step off the paper, as in the month.
    static func isWeekend(_ day: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: day)
        return weekday == 1 || weekday == 7
    }

    /// How far down `day`'s grid `date` sits, by the clock rather than elapsed time, so the hours
    /// stay on their rows on days the clocks change. The day's end is the bottom.
    static func y(of date: Date, on day: Date, calendar: Calendar) -> CGFloat {
        guard date < calendar.date(byAdding: .day, value: 1, to: day)! else { return hourHeight * 24 }
        guard date > day else { return 0 }
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return CGFloat(c.hour! * 3600 + c.minute! * 60 + c.second!) / 3600 * hourHeight
    }
}

/// The row of day heads. It keeps its own width, so a resize redraws the heads alone and each head
/// is told how much of itself fits instead of trying every arrangement on every step.
private struct DayHeads: View {
    let days: [Date]
    let model: AppModel
    let calendars: CalendarController
    let memos: MemoBook
    let onSelect: (Date) -> Void
    @State private var columnWidth: CGFloat = .infinity

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: WeekGrid.gutter, height: 1)
            ForEach(days, id: \.self) { day in
                let hasMemo = memos.has(Period(containing: day, scope: .day, calendar: model.calendar))
                let todoCount = memos.todos.remaining(on: day, calendar: model.calendar)
                DayHead(day: day, model: model, isHoliday: calendars.holidayDays.contains(day),
                        count: calendars.slots[day]?.count ?? 0, hasMemo: hasMemo, todoCount: todoCount,
                        fit: DayHead.Fit(width: columnWidth, day: day, calendar: model.calendar, hasMemo: hasMemo, todoCount: todoCount)) {
                    onSelect(day)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = ($0 - WeekGrid.gutter) / 7 }
    }
}

/// A day's number and weekday over its column. Today has a bold number and an ink bar along the
/// top, as in the month; the chosen day is boxed in ink below that bar.
private struct DayHead: View {
    let day: Date
    let model: AppModel
    let isHoliday: Bool
    let count: Int
    let hasMemo: Bool
    /// Unfinished ToDos on the day, as ✓N at the head's trailing end.
    let todoCount: Int
    let fit: Fit
    let onSelect: () -> Void
    @State private var hovering = false

    /// What a head shows in its column: in a narrow window the weekday gives way first, then the
    /// pencil, so ✓N never spills into the next day.
    enum Fit {
        case full, noWeekday, bare

        @MainActor init(width: CGFloat, day: Date, calendar: Calendar, hasMemo: Bool, todoCount: Int) {
            func textWidth(_ text: String, _ font: NSFont) -> CGFloat { ceil((text as NSString).size(withAttributes: [.font: font]).width) }
            let meta = NSFont.monospacedDigitSystemFont(ofSize: TextStyle.meta.size, weight: .medium)
            let date = textWidth("\(calendar.component(.day, from: day))", .monospacedDigitSystemFont(ofSize: TextStyle.date.size, weight: .bold))
            // Leading padding, then with ToDos the trailing padding and ✓N (glyph, gap, count). The
            // spacer before ✓N takes the stack's spacing on both of its sides.
            let base = Metrics.spaceM + date + (todoCount > 0 ? Metrics.spaceM + Metrics.spaceS * 2 + 9 + 2 + textWidth("\(todoCount)", meta) : 0)
            let memo = hasMemo ? Metrics.spaceS + 11 : 0
            let weekday = Metrics.spaceS + textWidth(WeekGrid.weekdayName(day, calendar: calendar), meta)
            self = width >= base + memo + weekday ? .full : width >= base + memo ? .noWeekday : .bare
        }
    }

    private func head(isToday: Bool, red: Bool, weekday: Bool, memo: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceS) {
            Text("\(model.calendar.component(.day, from: day))")
                .textStyle(.date)
                .fontWeight(isToday ? .bold : .semibold)
                .foregroundStyle(red ? Color.holiday : Color.ink)
                .fixedSize()
            if weekday {
                Text(WeekGrid.weekdayName(day, calendar: model.calendar))
                    .textStyle(.meta)
                    .foregroundStyle(.inkSoft)
                    .fixedSize()
            }
            if hasMemo && memo { MemoMark() }
            if todoCount > 0 {
                Spacer(minLength: 0)
                TodoCount(todoCount)
            }
        }
    }

    var body: some View {
        let isToday = model.isToday(day)
        let isSelected = model.isSelected(day)
        let red = model.isRedDay(day) || isHoliday
        let weekend = WeekGrid.isWeekend(day, calendar: model.calendar)
        Button(action: onSelect) {
            head(isToday: isToday, red: red, weekday: fit == .full, memo: fit != .bare)
            .padding(.leading, Metrics.spaceM)
            .padding(.trailing, todoCount > 0 ? Metrics.spaceM : 0)
            .padding(.top, Metrics.spaceS)
            .padding(.bottom, Metrics.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering && !isSelected ? Color.hover : weekend ? Color.raised : Color.clear)
            .overlay {
                // Sides and bottom only, under today's bar, like the month's chosen cell.
                if isSelected {
                    ZStack {
                        Rectangle().fill(.ink).frame(width: Metrics.line).frame(maxWidth: .infinity, alignment: .leading)
                        Rectangle().fill(.ink).frame(width: Metrics.line).frame(maxWidth: .infinity, alignment: .trailing)
                        Rectangle().fill(.ink).frame(height: Metrics.line).frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .padding(.top, WeekGrid.todayBar)
                }
            }
            .overlay(alignment: .top) {
                if isToday { Rectangle().fill(.ink).frame(height: WeekGrid.todayBar) }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
        .buttonStyle(FocusOnlyStyle())
        // A new event's popover (⌘N, double-click in the column) points at the day's head.
        .eventAnchor(EventAnchor.cell(day))
        .accessibilityLabel(label(isToday: isToday))
        .accessibilityAddTraits(model.isSelected(day) ? .isSelected : [])
    }

    private func label(isToday: Bool) -> String {
        var text = Period(containing: day, scope: .day, calendar: model.calendar).title
        if isToday { text += ", 오늘" }
        if count > 0 { text += ", 일정 \(count)개" }
        if hasMemo { text += ", 메모 있음" }
        if todoCount > 0 { text += ", 남은 할 일 \(todoCount)개" }
        return text
    }
}

/// All-day and multi-day events as bands across the days they cover, each on its row for the
/// week. Past four rows, the fourth says how many more each day has.
private struct BandStrip: View {
    let days: [Date]
    let lanes: BandLanes?
    let model: AppModel
    let calendars: CalendarController

    var body: some View {
        let placements = lanes?.placements ?? []
        let rowCount = max(1, lanes?.count ?? 0)
        let overflows = rowCount > WeekGrid.maxLanes
        let shownRows = min(rowCount, WeekGrid.maxLanes)
        let bandRows = overflows ? WeekGrid.maxLanes - 1 : shownRows
        HStack(spacing: 0) {
            Text("종일")
                .textStyle(.meta)
                .foregroundStyle(.inkSoft)
                .frame(width: WeekGrid.gutter - Metrics.spaceM, height: WeekGrid.laneHeight, alignment: .trailing)
                .padding(.trailing, Metrics.spaceM)
                .frame(maxHeight: .infinity, alignment: .top)
            GeometryReader { geo in
                let width = geo.size.width / CGFloat(days.count)
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            Rectangle().fill(WeekGrid.isWeekend(day, calendar: model.calendar) ? Color.raised : Color.clear)
                                .overlay(alignment: .leading) { Rectangle().fill(.shade).frame(width: Metrics.line) }
                        }
                    }
                    ForEach(placements.filter { $0.lane < bandRows }, id: \.occurrence.id) { placement in
                        let continues = (placement.occurrence.start < days[placement.firstDay],
                                         placement.occurrence.end > model.calendar.date(byAdding: .day, value: 1, to: days[placement.lastDay])!)
                        let leading = CGFloat(placement.firstDay) * width + (continues.0 ? 0 : 3)
                        let trailing = CGFloat(placement.lastDay + 1) * width - (continues.1 ? 0 : 3)
                        let occurrence = placement.occurrence
                        let covered = Array(days[placement.firstDay...placement.lastDay])
                        WeekBand(occurrence: occurrence, source: calendars.sources[occurrence.sourceID], continues: continues,
                                 isSelected: model.selectedEventID == occurrence.id)
                            .unsentOutline(calendars.isUnsent(occurrence))
                            // Keys name the day too (Return on the chosen day), so the band answers to each day it covers.
                            .transformAnchorPreference(key: EventAnchorKey.self, value: .bounds) { anchors, bounds in
                                for covered in covered { anchors[EventAnchor.row(occurrence.id, day: covered, in: .weekGrid)] = bounds }
                            }
                            // One click target per day, so a click picks the day under it, as in the month.
                            .overlay {
                                HStack(spacing: 0) {
                                    ForEach(covered, id: \.self) { day in
                                        Color.clear.opensEvent(occurrence, day: day, anchor: EventAnchor.row(occurrence.id, day: day, in: .weekGrid),
                                                               model: model, calendars: calendars)
                                    }
                                }
                                .accessibilityHidden(true)
                            }
                            // VoiceOver opens the band once, on the chosen day when it covers it.
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction {
                                let day = covered.contains(model.selectedDay) ? model.selectedDay : covered[0]
                                model.openEvent(occurrence, day: day, anchor: EventAnchor.row(occurrence.id, day: day, in: .weekGrid), calendars: calendars)
                            }
                            .frame(width: trailing - leading, height: WeekGrid.laneHeight - 3)
                            .offset(x: leading, y: 4 + CGFloat(placement.lane) * WeekGrid.laneHeight)
                    }
                    if overflows {
                        ForEach(days.indices, id: \.self) { index in
                            let more = placements.count { $0.lane >= bandRows && $0.firstDay <= index && $0.lastDay >= index }
                            if more > 0 {
                                Text("+\(more)개")
                                    .textStyle(.meta)
                                    .foregroundStyle(.inkSoft)
                                    .frame(height: WeekGrid.laneHeight - 3)
                                    .offset(x: CGFloat(index) * width + Metrics.spaceM, y: 4 + CGFloat(bandRows) * WeekGrid.laneHeight)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: CGFloat(shownRows) * WeekGrid.laneHeight + 8)
    }
}

/// One band in the strip, drawn like the month's bands: tinted, with a coloured cap where it starts.
/// Holidays are red words and reminders a ring and a title, as in the month.
private struct WeekBand: View {
    let occurrence: EventOccurrence
    let source: CalendarController.Source?
    let continues: (Bool, Bool)
    /// Picked with a click or Tab: drawn in ink, as in the month.
    let isSelected: Bool
    @Environment(\.showsPalettePatterns) private var showsPatterns

    var body: some View {
        let look = source?.look ?? CalendarLook(.grey)
        let color = isSelected ? Color.onInk : EventTime.titleColor(occurrence, source: source)
        let title = Text(occurrence.title)
            .textStyle(.small)
            .foregroundStyle(color)
            .lineLimit(1)
            .ledgerStrikethrough(occurrence.isCompleted, color: color)
        Group {
            if source?.isHoliday == true {
                title.padding(.horizontal, Metrics.spaceS).background { if isSelected { Rectangle().fill(Tokens.selection) } }
            } else if source?.isReminderList == true {
                HStack(spacing: Metrics.spaceXs) {
                    EventMark(occurrence: occurrence, source: source, size: 9)
                    title
                }
                .padding(.horizontal, Metrics.spaceS)
                .background { if isSelected { Rectangle().fill(Tokens.selection) } }
            } else {
                // With patterns on, the band starts with its calendar's shape in place of the colour cap.
                let capped = !continues.0 && !showsPatterns
                HStack(spacing: Metrics.spaceXs) {
                    if showsPatterns, !continues.0 { Mark(isSelected ? .onInk : look.ink, size: 9, shape: look.shape) }
                    title
                }
                .padding(.leading, capped ? Metrics.spaceL : Metrics.spaceS)
                .padding(.trailing, Metrics.spaceXs)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(isSelected ? Tokens.selection : look.tint)
                .overlay(alignment: .leading) {
                    if capped {
                        Rectangle().fill(look.ink).frame(width: 6)
                            .overlay(alignment: .trailing) { Rectangle().fill(.ink).frame(width: Metrics.line) }
                    }
                }
                .overlay { BandOutline(open: continues).stroke(.ink, lineWidth: Metrics.line) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Hour labels and the seven day columns. When the grid first opens it is scrolled so now sits a
/// quarter of the way down if the week holds today, and to 8 AM otherwise; turning weeks keeps the scroll.
private struct HourGrid: View {
    let days: [Date]
    let model: AppModel
    let calendars: CalendarController
    let onSelect: (Date) -> Void
    @State private var position = ScrollPosition(y: 0)
    @State private var didScroll = false
    /// The part of the day on screen, to bring an event picked with Tab or the keys into view.
    @State private var visible: ClosedRange<CGFloat> = 0...0
    @Environment(\.isRenderingSnapshot) private var isRenderingSnapshot

    var body: some View {
        GeometryReader { geo in
            let start = startOffset(viewHeight: geo.size.height)
            if isRenderingSnapshot {
                // ImageRenderer cannot draw scroll views; show the same part of the day without one.
                content.offset(y: -start).frame(height: geo.size.height, alignment: .top).clipped()
            } else {
                ScrollView { content }
                    .scrollPosition($position)
                    .onAppear {
                        guard !didScroll else { return }
                        didScroll = true
                        position.scrollTo(y: start)
                    }
                    .onScrollGeometryChange(for: ClosedRange<CGFloat>.self) { scroll in
                        scroll.contentOffset.y...(scroll.contentOffset.y + scroll.containerSize.height)
                    } action: { _, range in visible = range }
                    // The event popover points at the picked event, so it has to be on screen.
                    .onChange(of: model.selectedEventID) { _, id in
                        guard let id, let span = pickedSpan(id) else { return }
                        if span.lowerBound < visible.lowerBound || span.upperBound > visible.upperBound {
                            position.scrollTo(y: max(0, min(span.lowerBound - geo.size.height / 4, WeekGrid.hourHeight * 24 - geo.size.height)))
                        }
                    }
            }
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            HourLabels(calendar: model.calendar)
            ForEach(days, id: \.self) { day in
                DayColumn(day: day, model: model, calendars: calendars)
                    .contentShape(Rectangle())
                    // A double-click on the empty part of a day starts a new event there, as in the month.
                    .onTapGesture(count: 2) { model.newEvent(on: day, calendars: calendars) }
                    .simultaneousGesture(TapGesture().onEnded { onSelect(day) })
            }
        }
        .frame(height: WeekGrid.hourHeight * 24)
    }

    /// Where the picked timed event sits on the chosen day's grid; nil for bands and other days.
    private func pickedSpan(_ id: String) -> ClosedRange<CGFloat>? {
        let day = model.selectedDay
        guard let block = TimedLayout.blocks(calendars.occurrences, on: day, calendar: model.calendar).first(where: { $0.occurrence.id == id })
        else { return nil }
        let top = WeekGrid.y(of: block.start, on: day, calendar: model.calendar)
        return top...max(top + WeekGrid.minBlockHeight, WeekGrid.y(of: block.end, on: day, calendar: model.calendar))
    }

    private func startOffset(viewHeight: CGFloat) -> CGFloat {
        let now = Date.now
        let today = model.calendar.startOfDay(for: now)
        let y = days.contains(today)
            ? WeekGrid.y(of: now, on: today, calendar: model.calendar) - viewHeight / 4
            : 8 * WeekGrid.hourHeight
        return max(0, min(y, WeekGrid.hourHeight * 24 - viewHeight))
    }
}

private struct HourLabels: View {
    let calendar: Calendar

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            ForEach(1..<24, id: \.self) { hour in
                Text(hour < 12 ? "오전 \(hour)시" : hour == 12 ? "오후 12시" : "오후 \(hour - 12)시")
                    .textStyle(.meta)
                    .foregroundStyle(.inkSoft)
                    .padding(.trailing, Metrics.spaceM)
                    .frame(height: TextStyle.meta.lineHeight)
                    .offset(y: CGFloat(hour) * WeekGrid.hourHeight - TextStyle.meta.lineHeight / 2)
            }
        }
        .frame(width: WeekGrid.gutter)
        .accessibilityHidden(true)
    }
}

/// A day's hours: a hairline every hour, the day's timed events as blocks, and the current time.
/// Weekends sit on the raised tone; the pointer over a column gives it the hover tone.
private struct DayColumn: View {
    let day: Date
    let model: AppModel
    let calendars: CalendarController
    @State private var hovering = false

    var body: some View {
        let isToday = model.isToday(day)
        let weekend = WeekGrid.isWeekend(day, calendar: model.calendar)
        let ground: Color = hovering ? .hover : weekend ? .raised : .paper
        let hour = WeekGrid.hourHeight
        let blocks = TimedLayout.blocks(calendars.occurrences, on: day, calendar: model.calendar,
                                        minimumDuration: Double(WeekGrid.minBlockHeight / hour) * 3600)
        GeometryReader { geo in
            let width = geo.size.width - 4
            ZStack(alignment: .topLeading) {
                Rectangle().fill(ground)
                Path { path in
                    for h in 1..<24 {
                        path.move(to: CGPoint(x: 0, y: CGFloat(h) * hour))
                        path.addLine(to: CGPoint(x: geo.size.width, y: CGFloat(h) * hour))
                    }
                }
                .stroke(.shade, lineWidth: Metrics.line)
                // Only today's line runs over the blocks; the other days' faint line stays under them.
                TimelineView(.everyMinute) { context in
                    if !isToday {
                        NowLine(y: WeekGrid.y(of: context.date, on: model.calendar.startOfDay(for: context.date), calendar: model.calendar), width: geo.size.width, isToday: false)
                    }
                }
                ForEach(blocks, id: \.occurrence.id) { block in
                    let top = WeekGrid.y(of: block.start, on: day, calendar: model.calendar)
                    let height = max(WeekGrid.minBlockHeight, WeekGrid.y(of: block.end, on: day, calendar: model.calendar) - top - 2)
                    let columnWidth = width / CGFloat(block.columns)
                    let gap: CGFloat = block.column < block.columns - 1 ? 2 : 0
                    let anchor = EventAnchor.row(block.occurrence.id, day: day, in: .weekGrid)
                    TimeBlock(block: block, source: calendars.sources[block.occurrence.sourceID], ground: ground,
                              isSelected: model.selectedEventID == block.occurrence.id,
                              width: columnWidth - gap, height: height, calendar: model.calendar)
                        .frame(width: columnWidth - gap, height: height)
                        .unsentOutline(calendars.isUnsent(block.occurrence))
                        .eventAnchor(anchor)
                        .opensEvent(block.occurrence, day: day, anchor: anchor, model: model, calendars: calendars)
                        // A short block late in the day stays above midnight.
                        .offset(x: 2 + CGFloat(block.column) * columnWidth, y: min(top, hour * 24 - height))
                }
                TimelineView(.everyMinute) { context in
                    if isToday {
                        NowLine(y: WeekGrid.y(of: context.date, on: day, calendar: model.calendar), width: geo.size.width, isToday: true)
                    }
                }
            }
        }
        .overlay(alignment: .leading) { Rectangle().fill(.shade).frame(width: Metrics.line) }
        .onHover { hovering = $0 }
    }
}

/// The current time across a day: a solid ink line with a dot in today's column, a faint dashed hairline in the others.
private struct NowLine: View {
    let y: CGFloat
    let width: CGFloat
    let isToday: Bool

    var body: some View {
        let line = Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
        Group {
            if isToday {
                line.stroke(Tokens.now, lineWidth: Metrics.lineBox)
                    .overlay { Circle().fill(Tokens.now).frame(width: 7, height: 7).position(x: 0, y: y) }
            } else {
                line.stroke(.inkFaint, style: StrokeStyle(lineWidth: Metrics.line, dash: [3, 3]))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A timed event on the grid: tinted with a coloured edge and an ink outline, its title and, when
/// there is room, its start time. A reminder is a ring and its title at its time.
private struct TimeBlock: View {
    let block: TimedLayout.Block
    let source: CalendarController.Source?
    /// The column's own tone under a reminder, so its title covers the hour rule cleanly.
    let ground: Color
    /// Picked with a click or Tab: drawn in ink, as in the month.
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    let calendar: Calendar
    @State private var hovering = false
    @Environment(\.showsPalettePatterns) private var showsPatterns

    var body: some View {
        let occurrence = block.occurrence
        let look = source?.look ?? CalendarLook(.grey)
        let color = isSelected ? Color.onInk : EventTime.titleColor(occurrence, source: source)
        let title = Text(occurrence.title)
            .foregroundStyle(color)
            .ledgerStrikethrough(occurrence.isCompleted, color: color)
        let time = DateText.clock(occurrence.start, calendar: calendar)
        Group {
            if source?.isReminderList == true {
                HStack(spacing: Metrics.spaceXs) {
                    EventMark(occurrence: occurrence, source: source, size: 9)
                    title.textStyle(.small).lineLimit(1)
                }
                .padding(.horizontal, Metrics.spaceXs)
                .frame(maxWidth: .infinity, maxHeight: WeekGrid.minBlockHeight - 2, alignment: .leading)
                // Covers the hour rule under the title, in the column's own colour.
                .background(isSelected ? Tokens.selection : hovering ? Color.hover : ground)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                // Side by side in a narrow column, a block tall enough gets a second title line in place of the time.
                let narrow = width < 70
                VStack(alignment: .leading, spacing: 0) {
                    // With patterns on, the title starts with its calendar's shape; the bar keeps the colour.
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceXs) {
                        if showsPatterns {
                            Mark(isSelected ? .onInk : look.ink, size: 8, shape: look.shape)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        }
                        title.textStyle(narrow ? .cell : .small).fontWeight(.semibold).lineLimit(narrow && height >= 32 ? 2 : 1)
                    }
                    if height >= 32, !narrow {
                        Text(time).textStyle(.meta).foregroundStyle(isSelected ? Color.onInk : Color.inkSoft).lineLimit(1)
                    }
                }
                .padding(.leading, Metrics.spaceM)
                .padding(.trailing, Metrics.spaceXs)
                .padding(.vertical, Metrics.spaceXxs)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(isSelected ? Tokens.selection : look.tint)
                .overlay(alignment: .leading) {
                    Rectangle().fill(look.ink).frame(width: 4)
                        .overlay(alignment: .trailing) { Rectangle().fill(.ink).frame(width: Metrics.line) }
                }
                // The block keeps its calendar's tint under the pointer; a heavier edge answers instead.
                .overlay { Rectangle().strokeBorder(.ink, lineWidth: hovering && !isSelected ? Metrics.lineBox : Metrics.line) }
                .clipped()
            }
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(time), \(occurrence.title)" + (source.map { ", \($0.name)" } ?? ""))
    }
}
