import SwiftUI
import SimplifyKit

/// The panel beside the grid, on the same paper past the ink spine: the chosen day, its week, or its month.
/// Events come from the calendar cache, memos and ToDos from the diary store.
struct DayPanel: View {
    @Bindable var model: AppModel
    let calendars: CalendarController
    let memos: MemoBook
    /// The scroll view's height, and the memo's top inside its content: the memo takes what is left.
    @State private var viewport: CGFloat = 0
    @State private var memoTop: CGFloat = 0
    /// The panel's scroll, moved only to bring the memo's caret line into view.
    @State private var scroll = ScrollPosition()
    @State private var scrolledTo: CGFloat = 0
    /// 모아 보기's memos scroll on their own, under the events and ToDos: where they are scrolled,
    /// and the memo being written's top among them.
    @State private var memosScroll = ScrollPosition()
    @State private var memosScrolledTo: CGFloat = 0
    @State private var editorTop: CGFloat = 0
    /// A memo header being dragged in 모아 보기.
    @State private var headerReorder = MemoReorder(axis: .vertical, gap: Metrics.spaceXl)

    /// Beside the small month, whose list already shows the day's events.
    private var isWide: Bool { model.isPanelWide && !model.isPanelHidden }

    /// The memo runs to the panel's foot, and never shorter than it used to be: when events and
    /// ToDos leave less, the whole panel scrolls instead.
    private var memoHeight: CGFloat {
        max(MemoStyle.minHeight, viewport - memoTop - Metrics.spaceXxl)
    }

    var body: some View {
        let period = model.panelPeriod
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Metrics.spaceL) {
                if !memos.isSaved {
                    NoticeBar("이번 실행에서 쓴 메모는 남지 않아요.", title: "메모를 저장할 수 없어요.")
                }
                SegmentedTabs(PeriodScope.allCases.map { ($0, scopeName($0)) }, selection: $model.panelScope,
                              marked: Set(PeriodScope.allCases.filter { memos.has(Period(containing: model.selectedDay, scope: $0, calendar: model.calendar)) }),
                              fillsWidth: true)
                HStack(alignment: .firstTextBaseline) {
                    Text(period.title)
                        .textStyle(.heading)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if period.scope == .week {
                        Text(period.rangeText).textStyle(.meta).foregroundStyle(.inkSoft)
                    } else if period.scope == .month {
                        Text(monthMeta(period)).textStyle(.meta).foregroundStyle(.inkSoft)
                    } else if period.scope == .day && period.contains(model.today) {
                        Tag("오늘")
                    }
                }
                if period.scope == .day {
                    DayStripView(day: period.start, isToday: period.contains(model.today), calendars: calendars, calendar: model.calendar)
                }
            }
            .padding(.horizontal, Metrics.spaceXxl)
            .padding(.top, Metrics.spaceXxl)
            .padding(.bottom, Metrics.spaceM)

            ScrollArea(position: $scroll) {
                VStack(alignment: .leading, spacing: Metrics.spaceXxl) {
                    ForEach(sections(for: period.scope), id: \.kind) { section in
                        VStack(alignment: .leading, spacing: Metrics.spaceM) {
                            // The memo being written thickens its rule to the spine's weight: with
                            // no box around it, that and the caret are its keyboard focus.
                            SectionRule(section.title, lineWidth: section.kind == .memo && memos.draft.hasFocus ? Metrics.lineSpine : Metrics.line) {
                                if section.kind == .todos, let action = section.action {
                                    Button(action) {
                                        // Lines typed a moment ago are in the store before the list is read.
                                        memos.draft.flush()
                                        memos.todos.pop = .importer(period)
                                    }
                                        .buttonStyle(DrawnButtonStyle(.text))
                                        .help("다른 날의 할 일과 메모 속 할 일 줄을 가져와요")
                                } else if section.kind == .memo {
                                    MemoLayoutSwitch(layout: $model.memoLayout, draft: memos.draft)
                                    if model.memoLayout == .all { MemoAddButton(draft: memos.draft) }
                                    MemoParagraphButton(draft: memos.draft)
                                } else if let action = section.action {
                                    Button(action) { model.newEvent(on: period.start, calendars: calendars) }
                                        .buttonStyle(DrawnButtonStyle(.text))
                                        .disabled(calendars.writableSources.isEmpty)
                                        .help(calendars.writableSources.isEmpty ? "설정에서 Google이나 iCloud를 연결해 주세요" : "이날에 새 일정 (⌘N)")
                                }
                            }
                            if section.kind == .events {
                                if period.scope == .week {
                                    WeekEvents(period: period, model: model, calendars: calendars)
                                } else {
                                    DayEvents(slots: calendars.slots[period.start] ?? [], day: period.start, model: model, calendars: calendars, calendar: model.calendar, empty: section.empty)
                                }
                            } else if section.kind == .memo {
                                // Pinned: the Aa bar as one line of tools under the rule, for whichever memo is written.
                                if MemoBarPin.shared.isPinned { MemoFormatStrip(draft: memos.draft) }
                                memoSection(section, period: period)
                            } else {
                                TodoList(period: period, model: model, memos: memos)
                            }
                        }
                        // The Aa bar and its shortcut card hang under the button, over the tabs and memos.
                        .overlayPreferenceValue(MemoAaAnchor.self) { anchor in
                            if section.kind == .memo { MemoAaLayer(draft: memos.draft, anchor: anchor) }
                        }
                    }
                }
                .padding(.horizontal, Metrics.spaceXxl)
                .padding(.bottom, Metrics.spaceXxl)
                .coordinateSpace(.named(Self.content))
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in scrolledTo = offset }
        }
        .background(.paper)
        .overlay { PanelPopLayer(model: model, calendars: calendars, memos: memos) }
        // Pinned or not, the floating bar closes: the toolbar takes its place, or comes back with Aa.
        .onChange(of: MemoBarPin.shared.isPinned) { memos.draft.showsParagraphBar = false }
        // A ToDo ticked or renamed anywhere redraws its chips in the open memo.
        .onChange(of: memos.todos.revision) { memos.draft.refreshChips() }
        // Every pop is about the period on screen (the memo's lines, a place in its letters).
        .onChange(of: period) { memos.todos.pop = nil }
        // Here as well as in the editor: 모아 보기 draws the editor only for the open memo, which a
        // new period's memos do not hold until the period is opened. The same calendar check as
        // the editor's, so a week's new first day opens it again.
        .onChange(of: [period.key, "\(period.start.timeIntervalSinceReferenceDate)", "\(period.calendar.firstWeekday)"], initial: true) {
            memos.draft.open(period)
        }
    }

    /// The period's memos: under their tabs one at a time, the open one to the panel's foot
    /// (하나씩), or all of them one under another, each as tall as its text (모아 보기).
    @ViewBuilder
    private func memoSection(_ section: Section, period: Period) -> some View {
        let draft = memos.draft
        let tabs = memos.tabs(for: period)
        if let id = draft.confirmingDelete, let tab = tabs.first(where: { $0.id == id }) {
            MemoDeleteQuestion(draft: draft, id: id, name: tab.name)
        }
        if model.memoLayout == .one {
            MemoTabsRow(draft: draft, tabs: tabs)
            editor(section, period: period, height: memoHeight)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.content)).minY } action: { memoTop = $0 }
        } else {
            // To the panel's foot, as 하나씩's memo is, and scrolled inside: the events and ToDos stay put.
            ScrollArea(position: $memosScroll) {
                allMemos(section, period: period, tabs: tabs)
                    .coordinateSpace(.named(Self.memos))
            }
            .frame(height: memoHeight)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.content)).minY } action: { memoTop = $0 }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in memosScrolledTo = offset }
        }
    }

    /// 모아 보기: every memo of the period one under another, each as tall as its text.
    private func allMemos(_ section: Section, period: Period, tabs: [MemoBook.Tab]) -> some View {
        let draft = memos.draft
        let ids = tabs.compactMap(\.id)
        return VStack(alignment: .leading, spacing: Metrics.spaceXl) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                VStack(alignment: .leading, spacing: Metrics.spaceXs) {
                    MemoTabLabel(draft: draft, tab: tab, isOn: tab.id == draft.noteID, font: .display(17), nsFont: Self.headerFont, isHeader: true,
                                 place: MemoTabLabel.Place(index: index, ids: ids, reorder: headerReorder))
                    if tab.id == draft.noteID {
                        // A line to spare under the last, so a new line does not scroll inside the memo first.
                        editor(section, period: period, height: max(draft.contentHeight, MemoStyle.lineHeight) + MemoStyle.lineHeight)
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.memos)).minY } action: { editorTop = $0 }
                    } else {
                        // Not while the open memo's bars may hang over this one.
                        MemoReadOnly(text: memos.shownText(note: tab.id) ?? AttributedString(), label: tab.name,
                                     canPick: { memos.todos.pop == nil && !model.isModalOpen && !draft.showsParagraphBar && !draft.hasSelectedText }) {
                            // The editor leaves its memo for this one's place.
                            guard tab.id != draft.noteID else { return }
                            draft.resignEditor?()
                            draft.focusOnAppear = true
                            draft.select(tab.id)
                            // Not opened (no period): no editor is coming to take the focus.
                            if draft.noteID != tab.id { draft.focusOnAppear = false }
                        }
                    }
                }
                // A header is dragged up or down by its whole memo's place; the letters stay open.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.memos)) } action: { frame in
                    if let id = tab.id { headerReorder.frames[id] = frame }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            MemoReorderMarks(reorder: headerReorder, name: tabs.first { $0.id == headerReorder.dragging }?.name,
                             font: .display(17), isHeader: true)
        }
        // Under the last memo, room for the caret line's spare line when scrolled to the end.
        .padding(.bottom, Metrics.spaceXs)
    }

    private static var headerFont: NSFont { NSFont(name: "GowunBatang-Bold", size: 17) ?? .boldSystemFont(ofSize: 17) }

    private func editor(_ section: Section, period: Period, height: CGFloat) -> some View {
        MemoEditor(draft: memos.draft, period: period, chosenDay: model.selectedDay, height: height,
                   title: section.title, placeholder: section.empty, onCaretLine: reveal)
    }

    /// Scrolls just enough that the memo's caret line, `line` in the memo's own place, shows with
    /// a line to spare above or under it; a line already in view stays put. In 모아 보기 the memos'
    /// own scroll moves first, then the panel, if the memos are partly under its foot.
    private func reveal(_ line: CGRect) {
        guard model.memoLayout == .all else { return revealInPanel(line) }
        let room = MemoStyle.lineHeight
        let top = editorTop + line.minY, bottom = editorTop + line.maxY
        var offset = memosScrolledTo
        if top - room < offset {
            offset = max(0, top - room)
        } else if bottom + room > offset + memoHeight {
            offset = bottom + room - memoHeight
        }
        if offset != memosScrolledTo { memosScroll.scrollTo(y: offset) }
        revealInPanel(line.offsetBy(dx: 0, dy: editorTop - offset))
    }

    /// The panel's own scroll: `line` is in the memo area's place (하나씩's memo, 모아 보기's memos).
    private func revealInPanel(_ line: CGRect) {
        let room = MemoStyle.lineHeight
        let top = memoTop + line.minY, bottom = memoTop + line.maxY
        if top - room < scrolledTo {
            scroll.scrollTo(y: max(0, top - room))
        } else if bottom + room > scrolledTo + viewport {
            scroll.scrollTo(y: bottom + room - viewport)
        }
    }

    /// `오늘`, `이번 주`, `이번 달` while the chosen day's day, week or month holds today; `일`,
    /// `주`, `월` otherwise. Each button on its own: a day last week reads `일 · 주 · 이번 달`.
    private func scopeName(_ scope: PeriodScope) -> String {
        Self.scopeName(scope, chosen: model.selectedDay, today: model.today, calendar: model.calendar)
    }

    static func scopeName(_ scope: PeriodScope, chosen: Date, today: Date, calendar: Calendar) -> String {
        let holdsToday = Period(containing: chosen, scope: scope, calendar: calendar).contains(today)
        return switch scope {
        case .day: holdsToday ? "오늘" : "일"
        case .week: holdsToday ? "이번 주" : "주"
        case .month: holdsToday ? "이번 달" : "월"
        }
    }

    /// `일정 16 · 할 일 4/9`: the month's events, and its ToDos finished out of all.
    private func monthMeta(_ month: Period) -> String {
        var ids = Set<String>()
        for day in month.days { (calendars.slots[day] ?? []).forEach { ids.insert($0.occurrence.eventID) } }
        let tally = memos.todos.tally(for: month)
        return "일정 \(ids.count) · 할 일 \(tally.done)/\(tally.total)"
    }

    private struct Section {
        enum Kind { case events, todos, memo }
        var title: String
        var action: String?
        var empty: String
        var kind: Kind
    }

    private nonisolated static let content = "panelContent"
    private nonisolated static let memos = MemoReorder.memosSpace

    /// A wide panel leaves the events to the small month's list.
    private func sections(for scope: PeriodScope) -> [Section] {
        isWide ? allSections(for: scope).filter { $0.kind != .events } : allSections(for: scope)
    }

    private func allSections(for scope: PeriodScope) -> [Section] {
        switch scope {
        case .day:
            [Section(title: "일정", action: "추가", empty: "이날은 일정이 없어요.", kind: .events),
             Section(title: "할 일", action: "가져오기", empty: "할 일이 없어요.", kind: .todos),
             Section(title: "메모", empty: "이날의 메모를 적어 보세요.", kind: .memo)]
        case .week:
            [Section(title: "이번 주 일정", empty: "이번 주는 일정이 없어요.", kind: .events),
             Section(title: "이번 주 할 일", action: "가져오기", empty: "할 일이 없어요.", kind: .todos),
             Section(title: "주간 메모", empty: "이번 주 메모를 적어 보세요.", kind: .memo)]
        case .month:
            [Section(title: "이번 달 할 일", action: "가져오기", empty: "할 일이 없어요.", kind: .todos),
             Section(title: "월간 메모", empty: "이번 달 메모를 적어 보세요.", kind: .memo)]
        }
    }
}

/// The day strip under the heading: the day's timed events and reminders from 9 to 24 o'clock, and
/// the current time on today.
private struct DayStripView: View {
    let day: Date
    let isToday: Bool
    let calendars: CalendarController
    let calendar: Calendar

    var body: some View {
        if isToday {
            TimelineView(.everyMinute) { context in
                DayStrip(items: items, now: minutes(context.date))
            }
        } else {
            DayStrip(items: items, now: nil)
        }
    }

    private var items: [DayStrip.Item] {
        (calendars.slots[day] ?? []).compactMap { slot in
            let occurrence = slot.occurrence
            guard !occurrence.isBand else { return nil }
            let source = calendars.sources[occurrence.sourceID]
            guard source?.isHoliday != true else { return nil }
            let start = minutes(occurrence.start)
            // An event that runs past midnight fills the strip to its end.
            let end = calendar.isDate(occurrence.end, inSameDayAs: day) ? minutes(occurrence.end) : 24 * 60
            return DayStrip.Item(id: occurrence.id, start: start, end: max(end, start + 15),
                                 look: source?.look ?? CalendarLook(.grey), isReminder: source?.isReminderList == true)
        }
    }

    private func minutes(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// The chosen day's events: all-day first, then by time, each with its calendar. On today an ink
/// line with the time sits between what is over and what is still to come.
struct DayEvents: View {
    let slots: [OccurrenceBuilder.Slot]
    let day: Date
    let model: AppModel
    let calendars: CalendarController
    let calendar: Calendar
    let empty: String

    var body: some View {
        if slots.isEmpty {
            Text(empty).textStyle(.item).foregroundStyle(.inkSoft)
        } else {
            if model.isToday(day) {
                TimelineView(.everyMinute) { context in list(now: context.date) }
            } else {
                list(now: nil)
            }
        }
    }

    private func list(now: Date?) -> some View {
        // Completed reminders trail the list out of time order, so the line goes before the first
        // event still to come, or before them when nothing is left.
        let nowIndex = now.map { now in
            slots.firstIndex { !$0.occurrence.isBand && !$0.occurrence.isCompleted && $0.occurrence.start >= now }
                ?? slots.firstIndex { $0.occurrence.isCompleted } ?? slots.count
        }
        return VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
            ForEach(Array(slots.enumerated()), id: \.element.occurrence.id) { index, slot in
                if let now, index == nowIndex { NowLine(time: DateText.clock(now, calendar: calendar)) }
                row(slot, isPast: now.map { !slot.occurrence.isBand && slot.occurrence.end <= $0 } ?? false)
            }
            if let now, nowIndex == slots.count { NowLine(time: DateText.clock(now, calendar: calendar)) }
        }
    }

    private func row(_ slot: OccurrenceBuilder.Slot, isPast: Bool) -> some View {
        let source = calendars.sources[slot.occurrence.sourceID]
        let chosen = model.selectedEventID == slot.occurrence.id
        return HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceM) {
            Text(EventTime.label(slot, on: day, calendar: calendar))
                .textStyle(.meta)
                .foregroundStyle(chosen ? Color.onInk : Color.inkSoft)
                .frame(width: 58, alignment: .leading)
            // The mark stays on the first line when a long title wraps.
            HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceM) {
                EventMark(occurrence: slot.occurrence, source: source, size: 10)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                let color = chosen ? Color.onInk : isPast ? Color.inkSoft : EventTime.titleColor(slot.occurrence, source: source)
                let title = Text(slot.occurrence.title)
                    .textStyle(.item)
                    .foregroundStyle(color)
                    .ledgerStrikethrough(slot.occurrence.isCompleted, color: color)
                let name = source.map { source in
                    Text(source.name)
                        .textStyle(.meta)
                        .foregroundStyle(chosen ? Color.onInk : Color.inkSoft)
                        .lineLimit(1)
                }
                // A title that fits on one line keeps the calendar at the row's end; a longer one takes
                // the whole width and the calendar goes under it, so it never wraps in a narrow strip.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceXs) {
                        title.lineLimit(1).fixedSize()
                        Spacer(minLength: Metrics.spaceM)
                        name?.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
                        title.fixedSize(horizontal: false, vertical: true)
                        name
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, Metrics.spaceXs)
        .pickedEvent(slot.occurrence, day: day, place: .panel, model: model, calendars: calendars)
        .accessibilityElement(children: .combine)
    }
}

/// The current time between today's events: the time, then an ink line with a dot.
private struct NowLine: View {
    let time: String

    var body: some View {
        HStack(spacing: Metrics.spaceM) {
            Text(time)
                .textStyle(.meta)
                .fontWeight(.semibold)
                .frame(width: 58, alignment: .leading)
            Rectangle().fill(Tokens.now).frame(height: Metrics.lineBox)
                .overlay(alignment: .leading) { Circle().fill(Tokens.now).frame(width: 7, height: 7).offset(x: -3) }
        }
        .frame(height: TextStyle.meta.lineHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("지금 \(time)")
    }
}

/// The week's events grouped by day, from its first day to its last. A month (beside a wide panel)
/// leaves its days without events out, and says so when none has any.
struct WeekEvents: View {
    let period: Period
    let model: AppModel
    let calendars: CalendarController

    private var days: [Date] {
        period.scope == .week ? period.days : period.days.filter { !(calendars.slots[$0] ?? []).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceS) {
            if days.isEmpty {
                Text("\(model.calendar.component(.month, from: period.start))월은 일정이 없어요.").textStyle(.item).foregroundStyle(.inkSoft)
            }
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                let slots = calendars.slots[day] ?? []
                let weekday = model.calendar.component(.weekday, from: day)
                let red = weekday == 1 || calendars.holidayDays.contains(day)
                if index > 0 { Rectangle().fill(.shade).frame(height: Metrics.line) }
                HStack(alignment: .top, spacing: Metrics.spaceM) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(model.calendar.component(.day, from: day))")
                            .textStyle(.date)
                            .fontWeight(model.isToday(day) ? .bold : .semibold)
                            .foregroundStyle(red ? Color.holiday : Color.ink)
                        Text(Calendar.weekdayName(weekday) + (model.isToday(day) ? " · 오늘" : ""))
                            .textStyle(.meta)
                            .foregroundStyle(.inkSoft)
                    }
                    .frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
                        if slots.isEmpty {
                            Text("일정이 없어요.").textStyle(.body).foregroundStyle(.inkSoft)
                        }
                        ForEach(slots, id: \.occurrence.id) { slot in
                            let source = calendars.sources[slot.occurrence.sourceID]
                            let chosen = model.selectedEventID == slot.occurrence.id
                            HStack(spacing: Metrics.spaceM) {
                                EventMark(occurrence: slot.occurrence, source: source, size: 10)
                                let color = chosen ? Color.onInk : EventTime.titleColor(slot.occurrence, source: source)
                                Text(slot.occurrence.title)
                                    .textStyle(.item)
                                    .lineLimit(1)
                                    .foregroundStyle(color)
                                    .ledgerStrikethrough(slot.occurrence.isCompleted, color: color)
                                Spacer(minLength: Metrics.spaceXs)
                                Text(EventTime.label(slot, on: day, calendar: model.calendar))
                                    .textStyle(.meta)
                                    .foregroundStyle(chosen ? Color.onInk : Color.inkSoft)
                            }
                            .padding(.vertical, Metrics.spaceXxs)
                            .pickedEvent(slot.occurrence, day: day, place: .week, model: model, calendars: calendars)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}

enum EventTime {
    /// Red for public holidays, soft for completed reminders.
    static func titleColor(_ occurrence: EventOccurrence, source: CalendarController.Source?) -> Color {
        if occurrence.isCompleted { return .inkSoft }
        return source?.isHoliday == true ? .holiday : .ink
    }

    /// `오전 9:30` or `종일`; a band over several days reads `~ 30일` on its first day and
    /// `2일째`, `3일째` … after that.
    static func label(_ slot: OccurrenceBuilder.Slot, on day: Date, calendar: Calendar) -> String {
        let occurrence = slot.occurrence
        if occurrence.isBand {
            if slot.continuesFromPrevious {
                let index = (calendar.dateComponents([.day], from: calendar.startOfDay(for: occurrence.start), to: day).day ?? 0) + 1
                return "\(index)일째"
            }
            guard slot.continuesToNext else { return "종일" }
            let lastDay = calendar.date(byAdding: .second, value: -1, to: occurrence.end)!
            return "~ \(calendar.component(.day, from: lastDay))일"
        }
        return DateText.clock(occurrence.start, calendar: calendar)
    }
}

private extension View {
    /// A panel row that opens its event; the picked one is filled with ink, as everywhere.
    func pickedEvent(_ occurrence: EventOccurrence, day: Date, place: EventAnchor.Place, model: AppModel, calendars: CalendarController) -> some View {
        let anchor = EventAnchor.row(occurrence.id, day: day, in: place)
        return selectableRow(chosen: model.selectedEventID == occurrence.id)
            .unsentOutline(calendars.isUnsent(occurrence))
            .eventAnchor(anchor)
            .opensEvent(occurrence, day: day, anchor: anchor, model: model, calendars: calendars)
    }
}
