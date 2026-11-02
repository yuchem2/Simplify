import SwiftUI
import SimplifyKit

/// The moulded panel beside the month: the chosen day, its week, or its month.
/// Events come from the calendar cache, memos and ToDos from the diary store.
struct DayPanel: View {
    @Bindable var model: AppModel
    let calendars: CalendarController
    let memos: MemoBook

    var body: some View {
        let period = model.panelPeriod
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                if !memos.isSaved { UnsavedMemosNotice() }
                SegmentedTabs([(PeriodScope.day, "하루"), (.week, "한 주"), (.month, "한 달")], selection: $model.panelScope,
                              marked: Set(PeriodScope.allCases.filter { memos.has(Period(containing: model.selectedDay, scope: $0, calendar: model.calendar)) }),
                              fillsWidth: true)
                HStack(alignment: .firstTextBaseline) {
                    Text(period.title)
                        .font(.display(22))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if period.scope == .week {
                        Text(period.rangeText).font(.system(size: 11, weight: .medium)).foregroundStyle(.inkSoft)
                    } else if period.scope == .month {
                        Text(monthMeta(period)).font(.system(size: 11, weight: .medium)).foregroundStyle(.inkSoft)
                    } else if period.scope == .day && period.contains(model.today) {
                        Text("오늘")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.7)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, memos.isSaved ? 20 : 16)
            .padding(.bottom, 10)

            ScrollArea {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(sections(for: period.scope), id: \.title) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionRule(section.title) {
                                if section.kind == .todos, let action = section.action {
                                    Button(action) {
                                        // Lines typed a moment ago are in the store before the list is read.
                                        memos.draft.flush()
                                        memos.todos.pop = .importer(period)
                                    }
                                        .buttonStyle(DrawnButtonStyle(.text))
                                        .help("다른 날의 할 일과 메모 속 할 일 줄을 가져와요")
                                } else if let action = section.action {
                                    Button(action) {}.buttonStyle(DrawnButtonStyle(.text)).disabled(true).help("준비 중이에요")
                                }
                            }
                            if section.kind == .events {
                                if period.scope == .week {
                                    WeekEvents(period: period, model: model, calendars: calendars)
                                } else {
                                    DayEvents(slots: calendars.slots[period.start] ?? [], day: period.start, model: model, calendars: calendars, calendar: model.calendar, empty: section.empty)
                                }
                            } else if section.kind == .memo {
                                MemoEditor(draft: memos.draft, period: period, title: section.title, placeholder: section.empty)
                            } else {
                                TodoList(period: period, model: model, memos: memos)
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
        .mouldedFrame()
        .overlay { PanelPopLayer(model: model, memos: memos) }
        // A ToDo ticked or renamed anywhere redraws its chips in the open memo.
        .onChange(of: memos.todos.revision) { memos.draft.refreshChips() }
        // Every pop is about the period on screen (the memo's lines, a place in its letters).
        .onChange(of: period) { memos.todos.pop = nil }
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

    private func sections(for scope: PeriodScope) -> [Section] {
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

/// Shown over the tabs when the diary store would not open and memos only live in memory.
private struct UnsavedMemosNotice: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .accessibilityHidden(true)
            Text("\(Text("메모를 저장할 수 없어요.").fontWeight(.semibold)) 이번 실행에서 쓴 메모는 남지 않아요.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.shadeSoft)
        .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
        .accessibilityElement(children: .combine)
    }
}

/// The chosen day's events: all-day first, then by time, each with its calendar.
private struct DayEvents: View {
    let slots: [OccurrenceBuilder.Slot]
    let day: Date
    let model: AppModel
    let calendars: CalendarController
    let calendar: Calendar
    let empty: String

    var body: some View {
        if slots.isEmpty {
            Text(empty).font(.system(size: 14)).foregroundStyle(.inkSoft)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(slots, id: \.occurrence.id) { slot in
                    let source = calendars.sources[slot.occurrence.sourceID]
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(EventTime.label(slot, on: day, calendar: calendar))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.inkSoft)
                            .frame(width: 58, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 8) {
                                EventMark(occurrence: slot.occurrence, source: source, size: 10)
                                Text(slot.occurrence.title)
                                    .font(.system(size: 14))
                                    .strikethrough(slot.occurrence.isCompleted)
                                    .foregroundStyle(EventTime.titleColor(slot.occurrence, source: source))
                            }
                            if let source {
                                Text(source.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.inkSoft)
                                    .padding(.leading, 18)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                    .pickedEvent(slot.occurrence, day: day, place: .panel, model: model, calendars: calendars)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// The week's events grouped by day, Sunday to Saturday.
private struct WeekEvents: View {
    let period: Period
    let model: AppModel
    let calendars: CalendarController

    private static let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(period.days.enumerated()), id: \.element) { index, day in
                let slots = calendars.slots[day] ?? []
                let weekday = model.calendar.component(.weekday, from: day)
                let red = weekday == 1 || calendars.holidayDays.contains(day)
                if index > 0 { Rectangle().fill(.shade).frame(height: Metrics.line) }
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(model.calendar.component(.day, from: day))")
                            .font(.display(15))
                            .foregroundStyle(red ? Color.holiday : Color.ink)
                        Text(Self.weekdays[weekday - 1] + (model.isToday(day) ? " · 오늘" : ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.inkSoft)
                    }
                    .frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        if slots.isEmpty {
                            Text("일정 없음").font(.system(size: 13)).foregroundStyle(.inkSoft)
                        }
                        ForEach(slots, id: \.occurrence.id) { slot in
                            let source = calendars.sources[slot.occurrence.sourceID]
                            HStack(spacing: 8) {
                                EventMark(occurrence: slot.occurrence, source: source, size: 10)
                                Text(slot.occurrence.title)
                                    .font(.system(size: 14))
                                    .strikethrough(slot.occurrence.isCompleted)
                                    .lineLimit(1)
                                    .foregroundStyle(EventTime.titleColor(slot.occurrence, source: source))
                                Spacer(minLength: 4)
                                Text(EventTime.label(slot, on: day, calendar: model.calendar))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.inkSoft)
                            }
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
        let format = DateFormatter()
        format.locale = Locale(identifier: "ko_KR")
        format.timeZone = calendar.timeZone
        format.dateFormat = "a h:mm" // 오전 9:30
        return format.string(from: occurrence.start)
    }
}

private extension View {
    /// A panel row that opens its event; the picked one gets an ink outline.
    func pickedEvent(_ occurrence: EventOccurrence, day: Date, place: EventAnchor.Place, model: AppModel, calendars: CalendarController) -> some View {
        let anchor = EventAnchor.row(occurrence.id, day: day, in: place)
        return padding(.horizontal, 4)
            .overlay { if model.selectedEventID == occurrence.id { Rectangle().strokeBorder(.ink, lineWidth: Metrics.line) } }
            .unsentOutline(calendars.isUnsent(occurrence))
            .padding(.horizontal, -4)
            .eventAnchor(anchor)
            .opensEvent(occurrence, day: day, anchor: anchor, model: model, calendars: calendars)
    }
}
