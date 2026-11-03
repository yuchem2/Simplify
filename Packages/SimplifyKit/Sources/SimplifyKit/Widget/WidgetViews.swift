import AppIntents
import SwiftUI
import WidgetKit

// The desktop widgets (C · lights off): a rounded surface without an outline, today's number in a
// nest-tone oval, square marks for events and rings for reminders. The extra-large widget's month
// follows the main window's ledger rules. Kept in the kit so the app's snapshot run can draw them too.

/// Colours for the way the system draws the widget. In full colour they are the tokens; in the
/// one-tone modes (accented, vibrant) the system keeps only brightness, so they become primary
/// shades and colour marks fall back on their shape.
public struct WidgetInk: Sendable {
    public let isFullColor: Bool

    public init(_ mode: WidgetRenderingMode) {
        isFullColor = mode == .fullColor
    }

    var ink: Color { isFullColor ? .ink : .primary }
    var soft: Color { isFullColor ? .inkSoft : .secondary }
    var faint: Color { isFullColor ? .inkFaint : .primary.opacity(0.45) }
    var nest: Color { isFullColor ? .widgetNest : .primary.opacity(0.14) }
    var hair: Color { isFullColor ? .shadeSoft : .primary.opacity(0.18) }
    var holiday: Color { isFullColor ? .holiday : .primary }
    func mark(_ palette: Palette) -> Color { isFullColor ? palette.ink : .primary }
    func tint(_ palette: Palette) -> Color { isFullColor ? palette.tint : .primary.opacity(0.1) }
}

/// What a widget needs at one moment: the stores' contents and the entry's time.
public struct WidgetMoment: Sendable {
    public var data: WidgetData
    public var date: Date
    public var calendar: Calendar

    /// Worked out once: every part of a widget reads it.
    let today: [WidgetEvent]

    public init(data: WidgetData, date: Date, calendar: Calendar = .simplify) {
        self.data = data
        self.date = date
        self.calendar = calendar
        today = WidgetContent.day(date, events: data.events, calendar: calendar)
    }

    /// Today's events not over yet and not ticked off, as the medium widget's blocks show them.
    var comingCount: Int { today.count { !$0.isOver(at: date) && !$0.isCompleted } }

    var todos: [TodoEntry]? { data.todos(on: date, calendar: calendar).map(WidgetContent.todoRows) }
    var dayNumber: Int { calendar.component(.day, from: date) }
    var weekday: String { calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1] }
    var monthName: String { "\(calendar.component(.month, from: date))월" }
    var link: URL { DayLink.url(for: date, calendar: calendar) }

    /// What to say instead of events, or nil when there are events to read.
    var eventProblem: String? {
        switch data.state {
        case .ready: nil
        case .noAccounts: "앱에서 캘린더를 연결하면 일정이 보여요"
        case .unavailable: "앱을 한 번 열면 일정을 다시 읽어요"
        }
    }

    /// The heading of a later day in a list: `내일`, then `11월 4일 수요일`.
    func heading(_ day: WidgetContent.AgendaDay) -> String {
        if day.offset == 1 { return "내일" }
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: day.date) - 1]
        return "\(calendar.component(.month, from: day.date))월 \(calendar.component(.day, from: day.date))일 \(weekday)"
    }

    /// `16:00 – 17:00`, or the one time of a reminder, under a block's title.
    func span(_ event: WidgetEvent) -> String {
        event.isReminder || event.end <= event.start ? time(event) : "\(time(event)) – \(clock(event.end))"
    }

    private func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// `14:00`, or `종일` for an all-day event.
    func time(_ event: WidgetEvent) -> String {
        if event.isBand { return "종일" }
        let parts = calendar.dateComponents([.hour, .minute], from: event.start)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// The intent behind a ToDo's checkbox, made by the widget extension (nil draws a plain box).
public typealias TodoIntentMaker = @Sendable (TodoEntry) -> (any AppIntent)?

// MARK: - Small

/// Today's number and what comes next.
public struct SmallWidgetView: View {
    let moment: WidgetMoment
    let override: WidgetRenderingMode?
    @Environment(\.widgetRenderingMode) private var mode

    /// `renderingMode` stands in for the system's, for snapshots.
    public init(_ moment: WidgetMoment, renderingMode: WidgetRenderingMode? = nil) {
        self.moment = moment
        override = renderingMode
    }

    public var body: some View {
        let ink = WidgetInk(override ?? mode)
        VStack(spacing: Metrics.spaceS) {
            DateOval(day: moment.dayNumber, fill: ink.nest).foregroundStyle(ink.ink).widgetAccentable()
                .accessibilityLabel("\(moment.monthName) \(moment.dayNumber)일 \(moment.weekday)")
            Text("\(moment.monthName) · \(moment.weekday)")
                .textStyle(.meta).fontWeight(.semibold).foregroundStyle(ink.soft)
                .accessibilityHidden(true)
            if let problem = moment.eventProblem {
                EmptyLine(problem, ink: ink).padding(.top, Metrics.spaceXs)
            } else {
                let next = WidgetContent.upNext(moment.today, now: moment.date)
                // Nothing left today: the next day that has events, under its heading.
                let later = next.isEmpty ? WidgetContent.agenda(events: moment.data.events, now: moment.date,
                                                                calendar: moment.calendar, lines: 2).days.filter { $0.offset > 0 } : []
                if next.isEmpty, later.isEmpty {
                    EmptyLine("남은 일정이 없어요", ink: ink).padding(.top, Metrics.spaceM)
                } else {
                    VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
                        ForEach(next) { EventLine(event: $0, time: moment.time($0), isPast: false, ink: ink) }
                        ForEach(later, id: \.date) { day in
                            DayHeading(moment.heading(day), ink: ink)
                            ForEach(day.rows, id: \.event.id) { EventLine(event: $0.event, time: moment.time($0.event), isPast: false, ink: ink) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.spaceXl)
        .padding(.top, Metrics.spaceL)
        .padding(.bottom, Metrics.spaceXl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(moment.link)
    }
}

// MARK: - Medium

/// Like the system Calendar widget (M1): the date and what is left of today on the left, the
/// coming days' events as blocks under their headings on the right. ToDos live on the extra-large one.
public struct MediumWidgetView: View {
    let moment: WidgetMoment
    let override: WidgetRenderingMode?
    @Environment(\.widgetRenderingMode) private var mode

    public init(_ moment: WidgetMoment, renderingMode: WidgetRenderingMode? = nil) {
        self.moment = moment
        override = renderingMode
    }

    public var body: some View {
        let ink = WidgetInk(override ?? mode)
        HStack(alignment: .top, spacing: Metrics.spaceXl) {
            VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
                Text(moment.weekday).textStyle(.meta).fontWeight(.semibold).foregroundStyle(ink.soft)
                Text(verbatim: "\(moment.dayNumber)").textStyle(.bigDate).foregroundStyle(ink.ink).widgetAccentable()
                if moment.data.state == .ready {
                    Text(moment.comingCount > 0 ? "남은 일정 \(moment.comingCount)" : "남은 일정 없음")
                        .textStyle(.small).foregroundStyle(ink.soft).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .frame(width: 96, alignment: .leading)
            if let problem = moment.eventProblem {
                EmptyLine(problem, ink: ink, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScheduleColumn(moment: moment, ink: ink)
            }
        }
        .padding(.horizontal, Metrics.spaceXl)
        .padding(.vertical, Metrics.spaceL)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(moment.link)
    }
}

// MARK: - Extra large

/// The month as a ledger with each day's events by title, filling the widget's height; today's
/// ToDos and the coming events as blocks beside it (X1).
public struct ExtraLargeWidgetView: View {
    let moment: WidgetMoment
    let override: WidgetRenderingMode?
    let todoIntent: TodoIntentMaker
    let linksDays: Bool
    @Environment(\.widgetRenderingMode) private var mode

    /// `linksDays` false draws the days without their links, which only a widget host can draw (snapshots).
    public init(_ moment: WidgetMoment, renderingMode: WidgetRenderingMode? = nil, linksDays: Bool = true,
                todoIntent: @escaping TodoIntentMaker = { _ in nil }) {
        self.moment = moment
        override = renderingMode
        self.linksDays = linksDays
        self.todoIntent = todoIntent
    }

    public var body: some View {
        let ink = WidgetInk(override ?? mode)
        HStack(alignment: .top, spacing: Metrics.spaceXl) {
            VStack(alignment: .leading, spacing: Metrics.spaceM) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceM) {
                    Text(verbatim: "\(moment.dayNumber)").textStyle(.bigDate).foregroundStyle(ink.ink).widgetAccentable()
                    Text(verbatim: "\(moment.calendar.component(.year, from: moment.date))년 \(moment.monthName) · \(moment.weekday)")
                        .textStyle(.meta).fontWeight(.semibold).foregroundStyle(ink.soft)
                }
                .accessibilityElement(children: .combine)
                Ledger(moment: moment, linksDays: linksDays, ink: ink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // ToDos first, so the room the schedule leaves falls at the bottom.
            VStack(alignment: .leading, spacing: Metrics.spaceS) {
                TodoColumn(title: "오늘 할 일", todos: moment.todos, capacity: 3, ink: ink, intent: todoIntent)
                    .fixedSize(horizontal: false, vertical: true)
                ColumnHead("다가오는 일정", count: nil, ink: ink)
                    .padding(.top, Metrics.spaceS)
                if let problem = moment.eventProblem {
                    EmptyLine(problem, ink: ink, alignment: .leading)
                    Spacer(minLength: 0)
                } else {
                    ScheduleColumn(moment: moment, ink: ink)
                }
            }
            .frame(width: 200, alignment: .topLeading)
        }
        .padding(.horizontal, Metrics.spaceXl)
        .padding(.vertical, Metrics.spaceL)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(moment.link)
    }
}

// MARK: - Parts

private struct EmptyLine: View {
    let text: String
    let ink: WidgetInk
    let alignment: TextAlignment

    init(_ text: String, ink: WidgetInk, alignment: TextAlignment = .center) {
        self.text = text
        self.ink = ink
        self.alignment = alignment
    }

    var body: some View {
        Text(text).textStyle(.small).foregroundStyle(ink.soft)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A square for an event, a ring for a reminder; no outline in a widget.
private struct EventMark: View {
    let event: WidgetEvent
    let size: CGFloat
    let ink: WidgetInk

    var body: some View {
        Group {
            if event.isReminder {
                ReminderMark(ink.mark(event.palette), size: size, isCompleted: event.isCompleted)
            } else {
                Mark(ink.mark(event.palette), size: size, outlined: false)
            }
        }
        .widgetAccentable()
    }
}

private struct EventLine: View {
    let event: WidgetEvent
    let time: String
    let isPast: Bool
    let ink: WidgetInk

    var body: some View {
        HStack(spacing: Metrics.spaceXs) {
            EventMark(event: event, size: 9, ink: ink)
            Text(time).textStyle(.meta).foregroundStyle(ink.soft).frame(width: 34, alignment: .leading)
            Text(event.title).textStyle(.small).foregroundStyle(isPast || event.isCompleted ? ink.soft : ink.ink)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DayHeading: View {
    let text: String
    let ink: WidgetInk

    init(_ text: String, ink: WidgetInk) {
        self.text = text
        self.ink = ink
    }

    var body: some View {
        Text(text).textStyle(.meta).fontWeight(.semibold).foregroundStyle(ink.soft)
            .lineLimit(1)
            .padding(.top, Metrics.spaceXxs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The coming days as blocks under their headings, as many as the column's height holds.
private struct ScheduleColumn: View {
    let moment: WidgetMoment
    let ink: WidgetInk
    /// The heights the parts below are drawn at.
    static let costs = WidgetContent.ScheduleCosts(heading: Double(TextStyle.meta.lineHeight + Metrics.spaceXxs),
                                                   allDay: Double(EventBlock.allDayHeight), timed: Double(EventBlock.timedHeight),
                                                   more: Double(TextStyle.meta.lineHeight), gap: Double(Metrics.spaceXs))

    var body: some View {
        GeometryReader { proxy in
            let column = WidgetContent.schedule(events: moment.data.events, now: moment.date, calendar: moment.calendar,
                                                height: proxy.size.height, costs: Self.costs)
            if column.days.isEmpty {
                EmptyLine("다가오는 일정이 없어요", ink: ink, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: Metrics.spaceXs) {
                    ForEach(column.days, id: \.date) { day in
                        if day.offset > 0 { DayHeading(moment.heading(day), ink: ink) }
                        ForEach(day.rows, id: \.event.id) { EventBlock(event: $0.event, span: moment.span($0.event), ink: ink) }
                    }
                    if column.more > 0 {
                        Text("+\(column.more)개 더").textStyle(.meta).foregroundStyle(ink.soft)
                            .padding(.leading, Metrics.spaceM)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// An event as a block, as the week view draws one: the calendar's tint, a 3 pt bar in its ink,
/// the title, and for a timed event its times underneath.
private struct EventBlock: View {
    /// A title line, or a title and a time line, with 2 pt above and below.
    static let allDayHeight = TextStyle.small.lineHeight + 2 * Metrics.spaceXxs
    static let timedHeight = TextStyle.small.lineHeight + TextStyle.meta.lineHeight + 2 * Metrics.spaceXxs

    let event: WidgetEvent
    let span: String
    let ink: WidgetInk

    var body: some View {
        HStack(spacing: Metrics.spaceS) {
            Rectangle().fill(ink.mark(event.palette)).frame(width: 3).widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Metrics.spaceXs) {
                    if event.isReminder { ReminderMark(ink.mark(event.palette), size: 8).widgetAccentable() }
                    Text(event.title).textStyle(.small).fontWeight(.semibold).foregroundStyle(ink.ink).lineLimit(1)
                }
                if !event.isBand {
                    Text(span).textStyle(.meta).foregroundStyle(ink.soft).lineLimit(1)
                }
            }
            .padding(.vertical, Metrics.spaceXxs)
            Spacer(minLength: 0)
        }
        .frame(height: event.isBand ? Self.allDayHeight : Self.timedHeight)
        .background(ink.tint(event.palette))
        .accessibilityElement(children: .combine)
    }
}

private struct ColumnHead: View {
    let title: String
    let count: Int?
    let ink: WidgetInk

    init(_ title: String, count: Int?, ink: WidgetInk) {
        self.title = title
        self.count = count
        self.ink = ink
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: Metrics.spaceXs)
            if let count, count > 0 { Text("\(count)").monospacedDigit() }
        }
        .textStyle(.meta).fontWeight(.semibold).foregroundStyle(ink.soft)
        .accessibilityElement(children: .combine)
    }
}

private struct TodoColumn: View {
    let title: String
    let todos: [TodoEntry]?
    let capacity: Int
    let ink: WidgetInk
    let intent: TodoIntentMaker

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceS) {
            ColumnHead(title, count: todos.flatMap { $0.isEmpty ? nil : $0.count { !$0.isDone } }, ink: ink)
            if let todos {
                if todos.isEmpty {
                    EmptyLine("할 일이 없어요", ink: ink, alignment: .leading)
                } else {
                    // `capacity` lines in all: the "+n개 더" line takes the last one when they overflow.
                    let shown = todos.prefix(todos.count > capacity ? capacity - 1 : capacity)
                    ForEach(shown) { TodoLine(entry: $0, ink: ink, intent: intent($0)) }
                    if todos.count > shown.count {
                        Text("+\(todos.count - shown.count)개 더").textStyle(.meta).foregroundStyle(ink.soft)
                    }
                }
            } else {
                EmptyLine("할 일을 읽지 못했어요", ink: ink, alignment: .leading)
            }
        }
    }
}

/// A ToDo with its box. With an intent the whole line ticks it without opening the app.
private struct TodoLine: View {
    let entry: TodoEntry
    let ink: WidgetInk
    let intent: (any AppIntent)?

    var body: some View {
        if let intent {
            Button(intent: intent) { line }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.title)
                .accessibilityValue(entry.isDone ? "완료" : "안 함")
                .accessibilityHint(entry.isDone ? "완료를 취소해요" : "완료로 표시해요")
        } else {
            line
        }
    }

    private var line: some View {
        HStack(spacing: Metrics.spaceS) {
            box
            if let label = entry.label { Mark(ink.mark(label), size: 7, outlined: false).widgetAccentable() }
            Text(entry.title).textStyle(.small)
                .foregroundStyle(entry.isDone ? ink.soft : ink.ink)
                .ledgerStrikethrough(entry.isDone, color: ink.faint)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    /// One-tone modes keep only brightness, so a filled box would swallow its check; there the
    /// done box stays open with the check drawn in ink.
    @ViewBuilder private var box: some View {
        if ink.isFullColor {
            CheckBox(isOn: entry.isDone, size: 13)
        } else {
            ZStack {
                Rectangle().strokeBorder(ink.ink, lineWidth: Metrics.lineMark)
                if entry.isDone { Glyph(.check, size: 8, weight: Metrics.lineBox).foregroundStyle(ink.ink) }
            }
            .frame(width: 13, height: 13)
            .widgetAccentable()
        }
    }
}

/// The month in the main window's ledger rules: 1.75 ink under the weekdays, 1 pt ink under each
/// week, a 3 pt ink bar over today's number, red numbers only for Sundays and holidays. The weeks
/// share the height left; each day lists its events by title, as many as its row holds, then
/// "+n". A tap opens that day.
private struct Ledger: View {
    let moment: WidgetMoment
    let linksDays: Bool
    let ink: WidgetInk

    var body: some View {
        let weeks = WidgetContent.ledger(month: moment.date, today: moment.date,
                                         events: moment.data.state == .ready ? moment.data.events : [],
                                         calendar: moment.calendar)
        GeometryReader { proxy in
            // Weekday row and its rule above, a 1 pt rule under each week.
            let row = (proxy.size.height - TextStyle.meta.lineHeight - Metrics.spaceXs - Metrics.lineSpine) / CGFloat(weeks.count) - Metrics.line
            grid(weeks, titles: LedgerCell.titles(fitting: row))
        }
    }

    private func grid(_ weeks: [[WidgetContent.LedgerDay]], titles: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(["일", "월", "화", "수", "목", "금", "토"].enumerated()), id: \.offset) { index, name in
                    Text(name).textStyle(.meta).foregroundStyle(index == 0 ? ink.holiday : ink.soft)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, Metrics.spaceXs)
            Rectangle().fill(ink.ink).frame(height: Metrics.lineSpine)
            ForEach(weeks.indices, id: \.self) { index in
                HStack(spacing: 0) {
                    ForEach(weeks[index]) { day in
                        let cell = LedgerCell(day: day, titles: titles, ink: ink)
                        if linksDays {
                            Link(destination: DayLink.url(for: day.date, calendar: moment.calendar)) { cell }
                        } else {
                            cell
                        }
                    }
                }
                .frame(minHeight: 0, maxHeight: .infinity)
                Rectangle().fill(ink.ink).frame(height: Metrics.line)
            }
        }
    }
}

private struct LedgerCell: View {
    let day: WidgetContent.LedgerDay
    /// How many titles the row holds.
    let titles: Int
    let ink: WidgetInk

    /// Title lines a row of `height` holds under the number. A row with none shows the number alone.
    static func titles(fitting height: CGFloat) -> Int {
        let room = height - Metrics.spaceXxs - TextStyle.meta.lineHeight
        return max(0, min(WidgetContent.markLimit, Int(room / TextStyle.cell.lineHeight)))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: "\(day.number)").textStyle(.meta).monospacedDigit()
                .fontWeight(day.isToday ? .bold : nil)
                .foregroundStyle(!day.isInMonth ? ink.faint : day.isRed ? ink.holiday : ink.ink)
            // A title cut gives its line to "+n"; with room for one line only, "+n" follows that title.
            let ownLine = day.count > titles && titles >= 2
            let shown = min(day.count, ownLine ? titles - 1 : titles)
            let rest = day.count - shown
            ForEach(Array(day.marks.prefix(shown).enumerated()), id: \.element.id) { index, event in
                HStack(spacing: Metrics.spaceXxs) {
                    Rectangle().fill(ink.mark(event.palette)).frame(width: 3, height: 10).widgetAccentable()
                    Text(event.title).textStyle(.cell).foregroundStyle(day.isInMonth ? ink.ink : ink.faint).lineLimit(1)
                    if !ownLine, rest > 0, index == shown - 1 {
                        Text("+\(rest)").textStyle(.cell).foregroundStyle(ink.soft).fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if ownLine {
                Text("+\(rest)").textStyle(.cell).foregroundStyle(ink.soft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.spaceXs)
        .padding(.top, Metrics.spaceXxs)
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .clipped()
        .overlay(alignment: .top) {
            if day.isToday { Rectangle().fill(ink.ink).frame(height: 3).padding(.horizontal, Metrics.spaceXs) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(day.number)일" + (day.isToday ? ", 오늘" : "") + (day.first.map { ", \($0.title)" } ?? "")
                            + (day.count > 1 ? ", 외 \(day.count - 1)개" : ""))
    }

}
