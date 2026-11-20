import AppKit
import SwiftUI
import SimplifyKit

/// What the editor holds while an event is being made or changed.
@MainActor
@Observable
final class EventEditorModel {
    enum RepeatChoice: Hashable, CaseIterable {
        case none, daily, weekly, monthly, yearly
        /// A rule the presets do not cover (every other week, on two weekdays …); kept as it is unless changed.
        case custom

        /// The preset `recurrence` matches when it repeats every period on `start`'s own day. How it
        /// ends (a count, a date) is the 반복 종료 row's, not the preset's.
        init(_ recurrence: Recurrence, start: Date, calendar: Calendar) {
            switch RepeatPreset.matching(recurrence, start: start, calendar: calendar) {
            case .daily?: self = .daily
            case .weekly?: self = .weekly
            case .monthly?: self = .monthly
            case .yearly?: self = .yearly
            case .none?, nil: self = .custom
            }
        }

        /// `매주 (수요일)`, `매월 (28일)` …, named after the day the event starts.
        func label(start: Date, calendar: Calendar) -> String {
            let day = { (format: String) in DateText.string(start, format, timeZone: calendar.timeZone) }
            switch self {
            case .none: return "안 함"
            case .daily: return "매일"
            case .weekly: return "매주 (\(day("EEEE")))"
            case .monthly: return "매월 (\(day("d일")))"
            case .yearly: return "매년 (\(day("M월 d일")))"
            case .custom: return "사용자 지정"
            }
        }

        static let presets: [RepeatChoice] = [.none, .daily, .weekly, .monthly, .yearly]

        /// The engine's preset; nil for "사용자 지정", which keeps the stored rule.
        var preset: RepeatPreset? {
            switch self {
            case .none: RepeatPreset.none
            case .daily: .daily
            case .weekly: .weekly
            case .monthly: .monthly
            case .yearly: .yearly
            case .custom: nil
            }
        }
    }

    enum Phase: Equatable {
        case editing
        case saving
        /// Written; waiting for the account's sync to bring it onto the calendar. Esc may close.
        case refreshing
        case failed(String)
        /// The event changed somewhere else first.
        case conflict
    }

    /// How the 반복 종료 row reads: 안 함, 날짜, 횟수.
    enum EndKind: Hashable, CaseIterable {
        case never, date, count

        var label: String {
            switch self {
            case .never: "안 함"
            case .date: "날짜"
            case .count: "횟수"
            }
        }
    }

    struct Fields: Equatable {
        var title = ""
        var isAllDay = false
        var start: Date
        /// Exclusive: an all-day event ends at midnight after its last day.
        var end: Date
        var repeatChoice = RepeatChoice.none
        var endKind = EndKind.never
        /// The last day it may repeat on (midnight); used when `endKind` is `.date`.
        var endDay: Date
        /// What the count box holds, as typed; used when `endKind` is `.count`.
        var endCount = "10"
        var sourceID: String
        var location = ""
        var notes = ""

        /// The fields with the end values the row does not show set aside, so picking 날짜 and
        /// going back to 안 함 is no change.
        var compared: Fields {
            var fields = self
            let shows = repeatChoice.preset.map { $0 != .none } ?? false
            if !shows { fields.endKind = .never }
            if fields.endKind != .date { fields.endDay = .distantPast }
            // As a number: "010" is the 10 it was.
            fields.endCount = fields.endKind == .count ? Int(fields.endCount.trimmingCharacters(in: .whitespaces)).map(String.init) ?? fields.endCount : ""
            return fields
        }
    }

    /// The occurrence being edited; nil for a new event.
    let occurrence: EventOccurrence?
    let event: EventSnapshot?
    let calendar: Calendar
    private(set) var initial: Fields
    var fields: Fields
    var phase = Phase.editing
    /// The event was deleted elsewhere; there is nothing left to save to.
    var isGone = false

    init(editing occurrence: EventOccurrence, event: EventSnapshot, calendar: Calendar) {
        self.occurrence = occurrence
        self.event = event
        self.calendar = calendar
        // Providers show an untitled event as "(제목 없음)"; it must not be saved back as its title.
        var fields = Fields(title: occurrence.title == "(제목 없음)" ? "" : occurrence.title, isAllDay: occurrence.isAllDay, start: occurrence.start, end: occurrence.end,
                            endDay: Self.monthLater(occurrence.start, calendar: calendar),
                            sourceID: occurrence.sourceID, location: occurrence.location ?? "", notes: event.notes ?? "")
        if event.recurrenceUnsupported {
            fields.repeatChoice = .custom
        } else if let recurrence = event.recurrence {
            fields.repeatChoice = RepeatChoice(recurrence, start: occurrence.start, calendar: calendar)
            switch RepeatEnd(of: event, calendar: calendar) {
            case .never: break
            case .until(let day):
                fields.endKind = .date
                fields.endDay = day
            case .count(let count):
                fields.endKind = .count
                fields.endCount = String(count)
            }
        }
        initial = fields
        self.fields = fields
    }

    /// A new event on `day`, from the next full hour for an hour.
    init(newOn day: Date, sourceID: String, calendar: Calendar, now: Date = .now) {
        occurrence = nil
        event = nil
        self.calendar = calendar
        let hour = min(calendar.component(.hour, from: now) + 1, 23)
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        let fields = Fields(start: start, end: start.addingTimeInterval(3600), endDay: Self.monthLater(start, calendar: calendar), sourceID: sourceID)
        initial = fields
        self.fields = fields
    }

    var isNew: Bool { occurrence == nil }
    var isDirty: Bool { fields.compared != initial.compared }

    /// Part of a series, so a change asks how far it reaches.
    var isRepeating: Bool { event.map(Self.isRepeating) ?? false }
    /// A changed occurrence of a series has no rule of its own, so its repeat row is hidden.
    var showsRepeat: Bool { event?.recurringEventID == nil }
    /// 반복 종료 shows under a preset; a custom rule is kept as it is, end and all.
    var showsEnd: Bool { showsRepeat && fields.repeatChoice.preset.map { $0 != .none } == true }
    var repeatChanged: Bool { fields.repeatChoice != initial.repeatChoice || endChanged }
    private var endChanged: Bool {
        let now = fields.compared, before = initial.compared
        return (now.endKind, now.endDay, now.endCount) != (before.endKind, before.endDay, before.endCount)
    }

    /// Only where the series stops changed: that goes to the whole series without asking how far.
    var changesOnlyEnd: Bool {
        guard !isNew, endChanged, fields.repeatChoice == initial.repeatChoice else { return false }
        var rest = fields
        rest.endKind = initial.endKind
        rest.endDay = initial.endDay
        rest.endCount = initial.endCount
        return rest.compared == initial.compared
    }

    /// The end the row says, or nil while the count box holds something other than 1–999.
    var repeatEnd: RepeatEnd? {
        switch fields.endKind {
        case .never: return .never
        case .date: return .until(calendar.startOfDay(for: fields.endDay))
        case .count:
            guard let count = Int(fields.endCount.trimmingCharacters(in: .whitespaces)), RepeatEnd.counts.contains(count) else { return nil }
            return .count(count)
        }
    }

    /// Why the 반복 종료 row stops a save.
    var endProblem: String? {
        guard showsEnd else { return nil }
        switch fields.endKind {
        case .never: return nil
        case .date:
            return calendar.startOfDay(for: fields.endDay) < calendar.startOfDay(for: fields.start) ? "반복 종료일이 시작보다 빨라요." : nil
        case .count:
            return repeatEnd == nil ? "반복 횟수는 1–999회로 적어 주세요." : nil
        }
    }

    /// Why 저장 is off, when it is for a reason the person can fix.
    var problem: String? {
        if fields.end <= fields.start { return "끝이 시작보다 빨라요." }
        if let endProblem { return endProblem }
        if fields.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "제목을 적으면 저장할 수 있어요." }
        return nil
    }

    // MARK: Repeat end

    /// 날짜 starts a month after the start, 횟수 at 10, unless the series already ended that way.
    func setEndKind(_ kind: EndKind) {
        guard kind != fields.endKind else { return }
        if kind == .date, initial.endKind != .date { fields.endDay = Self.monthLater(fields.start, calendar: calendar) }
        if kind == .count, initial.endKind != .count { fields.endCount = "10" }
        if kind == initial.endKind {
            fields.endDay = initial.endDay
            fields.endCount = initial.endCount
        }
        fields.endKind = kind
    }

    /// The day the last occurrence falls on, for the count picked: counted from the series' first
    /// occurrence (moved as far as this one was), as COUNT is.
    var lastCounted: Date? {
        guard fields.endKind == .count, case .count(let count)? = repeatEnd, let preset = fields.repeatChoice.preset,
              let frequency = Self.frequency(preset) else { return nil }
        var first = fields.start
        if let event, let occurrence, event.recurringEventID == nil {
            let seriesStart = event.startDay.flatMap { DayKey.date($0, calendar: calendar) } ?? event.start ?? occurrence.start
            let moved = calendar.dateComponents([.day], from: calendar.startOfDay(for: occurrence.start), to: calendar.startOfDay(for: fields.start)).day ?? 0
            first = calendar.date(byAdding: .day, value: moved, to: seriesStart) ?? fields.start
        }
        var rule = Recurrence(frequency: frequency)
        rule.count = count
        return RecurrenceExpander.occurrences(of: rule, start: first, calendar: calendar, in: DateInterval(start: first, end: .distantFuture)).last
    }

    private static func frequency(_ preset: RepeatPreset) -> Recurrence.Frequency? {
        switch preset {
        case .none: nil
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
    }

    static func monthLater(_ start: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: 1, to: calendar.startOfDay(for: start))!
    }

    var canSave: Bool { problem == nil && phase != .saving && phase != .refreshing && !isGone && (isNew || isDirty) }

    // MARK: Saving

    /// What goes to the write engine. A change starts from the stored event, so what the editor
    /// does not show (its zone, a richer repeat rule) stays as it was.
    func draft() -> EventDraft {
        var draft: EventDraft
        if let event, let occurrence {
            draft = EventDraft(editing: event, occurrenceStart: occurrence.start, calendar: calendar)
        } else {
            draft = EventDraft(title: "", isAllDay: false, start: fields.start, end: fields.end)
        }
        draft.title = fields.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.isAllDay = fields.isAllDay
        draft.start = fields.start
        draft.end = fields.end
        let location = fields.location.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.location = location.isEmpty ? nil : location
        let notes = fields.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.notes = notes.isEmpty ? nil : notes
        // "사용자 지정" leaves the rule alone: the engine keeps a rule whose preset did not change.
        if let preset = fields.repeatChoice.preset, showsRepeat {
            draft.repeatRule = preset
            draft.repeatEnd = showsEnd ? repeatEnd ?? .never : .never
        }
        return draft
    }

    // MARK: Changing times

    /// Moving the start carries the end along, so the event keeps its length.
    func setStart(_ date: Date) {
        let length = fields.end.timeIntervalSince(fields.start)
        fields.start = date
        fields.end = date.addingTimeInterval(max(length, 0))
    }

    /// For an all-day event `day` is the last day; it ends at midnight after it.
    func setEndDay(_ day: Date) {
        if fields.isAllDay {
            fields.end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))!
        } else {
            fields.end = Self.combine(day: day, time: fields.end, calendar: calendar)
        }
    }

    func setStartDay(_ day: Date) {
        setStart(fields.isAllDay ? calendar.startOfDay(for: day) : Self.combine(day: day, time: fields.start, calendar: calendar))
    }

    func setAllDay(_ on: Bool) {
        guard on != fields.isAllDay else { return }
        let firstDay = calendar.startOfDay(for: fields.start)
        if on {
            let lastDay = calendar.startOfDay(for: max(fields.start, fields.end.addingTimeInterval(-1)))
            fields.start = firstDay
            fields.end = calendar.date(byAdding: .day, value: 1, to: lastDay)!
        } else {
            // Back to a time: the original one when there was one, else 9 to 10 on the first day.
            if !initial.isAllDay, calendar.isDate(initial.start, inSameDayAs: firstDay) {
                fields.start = initial.start
                fields.end = initial.end
            } else {
                fields.start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: firstDay)!
                fields.end = fields.start.addingTimeInterval(3600)
            }
        }
        fields.isAllDay = on
    }

    /// The last day an all-day event covers.
    var lastDay: Date {
        calendar.date(byAdding: .day, value: -1, to: fields.end) ?? fields.start
    }

    private static func combine(day: Date, time: Date, calendar: Calendar) -> Date {
        let t = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day)!
    }

    // MARK: Series

    static func isRepeating(_ event: EventSnapshot) -> Bool {
        event.recurrence != nil || event.recurrenceUnsupported || event.recurringEventID != nil
    }

    /// The series' first occurrence: there, "this and following" would be every occurrence.
    static func isFirstOccurrence(_ occurrence: EventOccurrence, of event: EventSnapshot, calendar: Calendar) -> Bool {
        if event.recurringEventID != nil { return false }
        let seriesStart = event.isAllDay ? event.startDay.flatMap { DayKey.date($0, calendar: calendar) } : event.start
        return seriesStart.map { abs($0.timeIntervalSince(occurrence.start)) < 1 } ?? false
    }

}

extension Error {
    /// The reason shown when a save or a delete fails.
    var eventWriteMessage: String {
        (self as? CalendarSyncError)?.message ?? "잠시 뒤 다시 시도해 주세요."
    }
}

// MARK: - The editor

/// The editor in the popover: title, all day, start and end, repeat, calendar, place, memo.
struct EventEditorView: View {
    let model: AppModel
    let calendars: CalendarController
    @Bindable var editor: EventEditorModel
    @FocusState private var focus: Field?
    @State private var isRepeatOpen = false
    @State private var isEndOpen = false
    @State private var isCalendarOpen = false

    private enum Field: Hashable { case title, count, location, notes }

    private var locked: Bool { editor.phase == .saving || editor.phase == .refreshing }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Metrics.spaceL) {
                TextField("제목", text: $editor.fields.title)
                    .focused($focus, equals: .title)
                    .drawnField(.title, focused: focus == .title)
                    .onSubmit { if editor.canSave { save() } }
                row("종일") {
                    Toggle("종일", isOn: Binding(get: { editor.fields.isAllDay }, set: { editor.setAllDay($0) }))
                        .toggleStyle(DrawnCheckboxStyle())
                        .labelsHidden()
                }
                row("시작") {
                    DayField(day: editor.fields.start, calendar: editor.calendar, today: model.today, holidays: calendars.holidayDays) { editor.setStartDay($0) }
                    if !editor.fields.isAllDay {
                        TimeField(time: editor.fields.start, calendar: editor.calendar) { editor.setStart($0) }
                    }
                }
                row("끝") {
                    DayField(day: editor.fields.isAllDay ? editor.lastDay : editor.fields.end, calendar: editor.calendar, today: model.today,
                             holidays: calendars.holidayDays) { editor.setEndDay($0) }
                    if !editor.fields.isAllDay {
                        TimeField(time: editor.fields.end, calendar: editor.calendar) { editor.fields.end = $0 }
                    }
                }
                if editor.showsRepeat {
                    row("반복") { repeatMenu }
                }
                if editor.showsEnd {
                    row("반복 종료") { repeatEndRow }
                    if let problem = editor.endProblem {
                        Text(problem)
                            .textStyle(.small)
                            .padding(.horizontal, Metrics.spaceM)
                            .padding(.vertical, Metrics.spaceXs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.errorTint)
                    }
                }
                row("캘린더") { calendarMenu }
                row("장소") {
                    TextField("장소", text: $editor.fields.location)
                        .focused($focus, equals: .location)
                        .drawnField(.box, focused: focus == .location)
                }
                row("메모", top: true) {
                    TextField("메모", text: $editor.fields.notes, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focus, equals: .notes)
                        .padding(.vertical, Metrics.spaceS)
                        .drawnField(.box, focused: focus == .notes)
                }
                status
            }
            .disabled(locked)
            .padding(.horizontal, Metrics.spaceXl)
            .padding(.top, Metrics.spaceXl)
            .padding(.bottom, Metrics.spaceL)

            Rectangle().fill(.ink).frame(height: Metrics.line)
            footer
                .padding(.horizontal, Metrics.spaceXl)
                .padding(.vertical, Metrics.spaceL)
        }
        .onAppear { if editor.isNew { focus = .title } }
    }

    private func row<Content: View>(_ label: String, top: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: top ? .top : .center, spacing: Metrics.spaceM) {
            Text(label)
                .textStyle(.section)
                .foregroundStyle(.inkSoft)
                .frame(width: 52, alignment: .leading)
                .padding(.top, top ? Metrics.spaceS : 0)
            HStack(spacing: Metrics.spaceS) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Menus

    private var repeatMenu: some View {
        let start = editor.fields.start
        // A custom rule stays unless another frequency is picked (the engine keeps a rule whose preset is
        // unchanged), so the preset of its own frequency would change nothing and is left out.
        let ownPreset = RepeatPreset(editor.event?.recurrence)
        let choices = editor.initial.repeatChoice == .custom
            ? EventEditorModel.RepeatChoice.presets.filter { $0.preset != ownPreset } + [.custom]
            : EventEditorModel.RepeatChoice.presets
        return Button { isRepeatOpen = true } label: {
            MenuLabel(text: editor.fields.repeatChoice.label(start: start, calendar: editor.calendar), isOpen: isRepeatOpen)
        }
        .buttonStyle(FocusOnlyStyle())
        .fixedSize()
        .inkMenu(isPresented: $isRepeatOpen) {
            choices.map { choice in
                .item(choice.label(start: start, calendar: editor.calendar), checked: editor.fields.repeatChoice == choice) {
                    editor.fields.repeatChoice = choice
                }
            }
        }
    }

    /// 안 함 / 날짜 / 횟수, then the day or the count. A count shows the day it reaches.
    @ViewBuilder private var repeatEndRow: some View {
        Button { isEndOpen = true } label: {
            MenuLabel(text: editor.fields.endKind.label, isOpen: isEndOpen)
        }
        .buttonStyle(FocusOnlyStyle())
        .fixedSize()
        .inkMenu(isPresented: $isEndOpen) {
            EventEditorModel.EndKind.allCases.map { kind in
                .item(kind.label, checked: editor.fields.endKind == kind) { editor.setEndKind(kind) }
            }
        }
        switch editor.fields.endKind {
        case .never:
            EmptyView()
        case .date:
            DayField(day: editor.fields.endDay, calendar: editor.calendar, today: model.today, holidays: calendars.holidayDays,
                     error: editor.endProblem != nil) { editor.fields.endDay = $0 }
        case .count:
            // Typed as it is; anything but 1–999 stops the save and says why.
            TextField("", text: $editor.fields.endCount)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focus, equals: .count)
                .drawnField(.box, focused: focus == .count, error: editor.endProblem != nil)
                .frame(width: 52)
                .accessibilityLabel("반복 횟수")
            Text("회").foregroundStyle(.inkSoft)
            if let last = editor.lastCounted {
                Text("· \(EventText.endDay(last, calendar: editor.calendar))까지")
                    .textStyle(.small)
                    .foregroundStyle(.inkSoft)
                    .lineLimit(1)
            }
        }
    }

    private var calendarMenu: some View {
        let source = calendars.sources[editor.fields.sourceID]
        return Button { isCalendarOpen = true } label: {
            MenuLabel(text: source?.name ?? "캘린더", soft: source.flatMap(providerLabel), mark: source?.look, isOpen: isCalendarOpen)
        }
        .buttonStyle(FocusOnlyStyle())
        .inkMenu(isPresented: $isCalendarOpen) {
            calendars.writableSources.enumerated().flatMap { index, group in
                let (account, sources) = group
                return (index > 0 ? [InkMenuEntry.divider] : []) + [.section("\(account.provider.label) · \(account.email)")]
                    + sources.map { source in
                        .item(source.name, swatch: InkMenuSwatch(source.look.ink, shape: source.look.shape), checked: editor.fields.sourceID == source.id) {
                            editor.fields.sourceID = source.id
                        }
                    }
            }
        }
        // A changed event stays in its calendar; moving between calendars is not part of this stage.
        .disabled(!editor.isNew)
        .help(editor.isNew ? "" : "만든 뒤에는 캘린더를 옮길 수 없어요")
    }

    private func providerLabel(_ source: CalendarController.Source) -> String? {
        calendars.accounts.first { $0.id == source.accountID }?.provider.label
    }

    // MARK: Status and buttons

    @ViewBuilder private var status: some View {
        switch editor.phase {
        case .failed(let reason):
            NoticeBar(reason, title: "저장하지 못했어요.", tone: .warning)
        case .conflict:
            NoticeBar("이 일정이 다른 기기에서 먼저 바뀌었어요. 새로 불러온 뒤 다시 고쳐 주세요.", title: "다른 곳에서 바뀌었어요.", tone: .warning)
        case .editing, .saving, .refreshing:
            if calendars.isOffline {
                NoticeBar("지금은 인터넷에 연결되어 있지 않아요. 저장하면 이 Mac에 맡겨 두었다가 연결되면 보내요.", tone: .info, icon: "wifi.slash")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Metrics.spaceM) {
            if !editor.isNew {
                Button("삭제") { model.popover?.question = .delete }
                    .buttonStyle(DrawnButtonStyle(.danger))
                    .disabled(locked)
            }
            Spacer(minLength: Metrics.spaceXs)
            if locked {
                HStack(spacing: Metrics.spaceS) {
                    ProgressView().controlSize(.small)
                    Text(editor.phase == .saving ? "저장하는 중…" : "달력에 반영하는 중…")
                }
                .textStyle(.cell)
                .foregroundStyle(.inkSoft)
            } else if editor.phase != .conflict, let problem = editor.problem, problem != editor.endProblem, editor.isNew || editor.isDirty {
                Text(problem).textStyle(.cell).foregroundStyle(.inkSoft).lineLimit(1)
            }
            if editor.phase == .conflict {
                Button("닫기") { model.popover = nil }.buttonStyle(DrawnButtonStyle())
                Button("새로 불러오기") { reloadAfterConflict() }.buttonStyle(DrawnButtonStyle(.primary))
            } else {
                Button("취소") { model.requestClosePopover() }
                    .buttonStyle(DrawnButtonStyle())
                    .disabled(locked)
                Button(editor.phase == .editing ? "저장" : "다시 저장") { save() }
                    .buttonStyle(DrawnButtonStyle(.primary))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!editor.canSave)
            }
        }
    }

    // MARK: Actions

    private func save() {
        guard editor.canSave else { return }
        // A new end alone is the whole series' (an end on one occurrence means nothing).
        if !editor.isNew, editor.isRepeating, !editor.changesOnlyEnd {
            model.popover?.question = .saveScope
        } else {
            EventActions.save(editor, scope: .allOccurrences, model: model, calendars: calendars)
        }
    }

    /// Syncs the event's account again, then edits the event as it is now; it may have moved or be gone.
    private func reloadAfterConflict() {
        guard let occurrence = editor.occurrence else { return }
        editor.phase = .saving
        Task {
            await calendars.resync(sourceID: occurrence.sourceID)
            let fresh = calendars.slots.values.joined().map(\.occurrence).first { $0.id == occurrence.id }
            if let fresh, model.edit(fresh, calendars: calendars) { return }
            editor.isGone = true
            editor.phase = .failed(calendars.event(id: occurrence.eventID) == nil
                ? "이 일정은 다른 곳에서 지워졌어요."
                : "이 일정은 다른 곳에서 날짜나 시간이 바뀌었어요. 닫은 뒤 달력에서 다시 열어 주세요.")
        }
    }
}

/// Saving and deleting, shared by the editor and the questions over it.
@MainActor
enum EventActions {
    /// `failureAnchor`: a save with no popover of its own (an event dragged to another day) opens
    /// the editor there when it fails, so the failure shows and the save can be tried again.
    static func save(_ editor: EventEditorModel, scope: CalendarController.WriteScope, model: AppModel, calendars: CalendarController,
                     failureAnchor: String? = nil) {
        model.popover?.question = nil
        editor.phase = .saving
        Task {
            do {
                let outcome = try await calendars.save(editor, scope: scope)
                calendars.rememberSource(editor.fields.sourceID)
                // A written change is not in the queue, so it shows once the account syncs; a queued one shows at once.
                if outcome == .saved {
                    editor.phase = .refreshing
                    await calendars.resync(sourceID: editor.fields.sourceID)
                }
                // Only this editor's popover: Esc may have closed it while it refreshed.
                if case .editor(let shown)? = model.popover?.content, shown === editor { model.popover = nil }
            } catch CalendarSyncError.conflict {
                editor.phase = .conflict
                showFailure(of: editor, at: failureAnchor, model: model)
            } catch {
                editor.phase = .failed(error.eventWriteMessage)
                showFailure(of: editor, at: failureAnchor, model: model)
            }
        }
    }

    /// Opens the failed editor at `anchor` when nothing else is open; otherwise the event just
    /// stays on its own day.
    private static func showFailure(of editor: EventEditorModel, at anchor: String?, model: AppModel) {
        guard let anchor, !model.isModalOpen else { return }
        model.popover = EventPopoverState(content: .editor(editor), anchor: anchor)
    }
}

// MARK: - Questions

/// Takes over the popover to ask one thing: discard changes, delete, or how far a change reaches.
struct EventQuestionView: View {
    let model: AppModel
    let calendars: CalendarController
    let state: EventPopoverState
    let question: EventPopoverState.Question
    @State private var scope: CalendarController.WriteScope?
    @State private var isDeleting = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceL) {
            Text(title).textStyle(.subheading).accessibilityAddTraits(.isHeader)
            Text(message)
                .textStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
            if asksScope {
                VStack(spacing: Metrics.spaceS) {
                    ForEach(scopes, id: \.scope) { option in
                        ScopeOption(title: option.title, detail: option.detail, isOn: chosenScope == option.scope, isEnabled: option.enabled) {
                            scope = option.scope
                        }
                    }
                }
            }
            if let failure {
                NoticeBar(failure, title: "지우지 못했어요.", tone: .warning)
            }
            HStack(spacing: Metrics.spaceM) {
                Spacer()
                // A dragged event's question: cancelling leaves the event on its own day.
                Button(cancelTitle) { if state.cancelClosesPopover { model.popover = nil } else { model.popover?.question = nil } }
                    .buttonStyle(DrawnButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .disabled(isDeleting)
                confirmButton
            }
        }
        .padding(Metrics.spaceXl)
    }

    @ViewBuilder private var confirmButton: some View {
        switch question {
        case .discard:
            // Dropped edits cannot come back, so this is red like delete.
            Button("버리기") { model.popover = nil }
                .buttonStyle(DrawnButtonStyle(.danger))
                .keyboardShortcut(.defaultAction)
        case .delete:
            Button(isDeleting ? "지우는 중…" : "삭제") { delete() }
                .buttonStyle(DrawnButtonStyle(.danger))
                .keyboardShortcut(.defaultAction)
                .disabled(isDeleting)
        case .saveScope:
            Button("저장") {
                guard let editor else { return }
                EventActions.save(editor, scope: chosenScope, model: model, calendars: calendars)
            }
            .buttonStyle(DrawnButtonStyle(.primary))
            .keyboardShortcut(.defaultAction)
        }
    }

    private var editor: EventEditorModel? {
        if case .editor(let editor) = state.content { return editor }
        return nil
    }

    private var event: EventSnapshot? {
        state.occurrence.flatMap { calendars.event(id: $0.eventID) }
    }

    private var isRepeating: Bool { event.map(EventEditorModel.isRepeating) ?? false }
    private var asksScope: Bool { question != .discard && isRepeating }

    private var title: String {
        switch question {
        case .discard: "고친 내용을 버릴까요?"
        case .delete: isRepeating ? "반복 일정을 지울까요?" : "일정을 지울까요?"
        case .saveScope: "반복 일정을 바꿀까요?"
        }
    }

    private var message: String {
        let name = "“\(state.occurrence?.title ?? editor?.fields.title ?? "")”"
        switch question {
        case .discard:
            return "저장하지 않은 내용이 사라져요."
        case .delete where !isRepeating:
            guard let occurrence = state.occurrence else { return "" }
            let calendarName = calendars.sources[occurrence.sourceID]?.name ?? "캘린더"
            return "\(name) · \(EventText.when(occurrence, isReminder: false, calendar: model.calendar))\n“\(calendarName)” 캘린더에서 지워지고, 되돌릴 수 없어요."
        case .delete, .saveScope:
            return "\(name)은 반복 일정이에요. 어디까지 \(question == .delete ? "지울지" : "바꿀지") 골라 주세요."
        }
    }

    private var cancelTitle: String { question == .discard ? "계속 고치기" : "취소" }

    private struct Scope {
        var scope: CalendarController.WriteScope
        var title: String
        var detail: String
        var enabled = true
    }

    private var scopes: [Scope] {
        guard let occurrence = state.occurrence else { return [] }
        let day = EventText.day(occurrence.start, calendar: model.calendar)
        let deleting = question == .delete
        // A new repeat rule cannot go on one occurrence alone; a delete ignores the rule.
        let ruleChanged = !deleting && editor?.repeatChanged == true
        var list = [Scope(scope: .thisOccurrence, title: "이 일정만",
                          detail: "\(day) 하나만 \(deleting ? "지워져요" : "바뀌어요")", enabled: !ruleChanged)]
        if let event, !EventEditorModel.isFirstOccurrence(occurrence, of: event, calendar: model.calendar) {
            list.append(Scope(scope: .thisAndFollowing, title: "이후 모든 일정",
                              detail: "\(day)부터 앞으로의 반복이 \(deleting ? "지워져요. 지난 일정은 남아요" : "바뀌어요. 지난 일정은 그대로예요")"))
        }
        list.append(Scope(scope: .allOccurrences, title: "모든 일정",
                          detail: deleting ? "반복 전체가 지워져요" : "지난 일정을 포함해 반복 전체가 바뀌어요"))
        return list
    }

    /// "이 일정만" unless the rule changed; then the narrowest choice left.
    private var chosenScope: CalendarController.WriteScope {
        if let scope, scopes.contains(where: { $0.scope == scope && $0.enabled }) { return scope }
        return scopes.first { $0.enabled }?.scope ?? .allOccurrences
    }

    private func delete() {
        guard let occurrence = state.occurrence else { return }
        isDeleting = true
        model.popover?.isBusy = true
        failure = nil
        let scope = isRepeating ? chosenScope : .allOccurrences
        Task {
            do {
                let outcome = try await calendars.delete(occurrence, scope: scope)
                // Written: Esc may close now, and the event leaves the calendar with the account's sync.
                model.popover?.isBusy = false
                if outcome == .saved { await calendars.resync(sourceID: occurrence.sourceID) }
                if model.popover?.occurrence?.id == occurrence.id {
                    model.selectedEventID = nil
                    model.popover = nil
                }
            } catch {
                failure = error.eventWriteMessage
                isDeleting = false
                model.popover?.isBusy = false
            }
        }
    }
}

/// One choice of how far a change reaches. The chosen one is filled with ink, like any choice from many.
private struct ScopeOption: View {
    let title: String
    let detail: String
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let text = isOn ? Color.onInk : isEnabled ? Color.ink : Color.inkFaint
        Button(action: action) {
            HStack(alignment: .top, spacing: Metrics.spaceL) {
                ZStack {
                    Circle().strokeBorder(text, lineWidth: Metrics.lineBox)
                    if isOn { Circle().fill(.onInk).padding(Metrics.spaceXs) }
                }
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
                    Text(title).textStyle(.body).fontWeight(.semibold)
                    Text(isEnabled ? detail : "반복을 바꾸면 고를 수 없어요")
                        .textStyle(.small)
                        .foregroundStyle(isOn ? Color.onInk : Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.spaceL)
            .padding(.vertical, Metrics.spaceM)
            .background(isOn ? Tokens.selection : hovering && isEnabled ? Color.hover : Color.paper)
            .overlay(Rectangle().strokeBorder(isEnabled ? Color.ink : Color.inkFaint, lineWidth: Metrics.line))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
        .buttonStyle(FocusOnlyStyle())
        .disabled(!isEnabled)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Pieces

/// A date in a drawn box; a click opens a small ledger month under it.
private struct DayField: View {
    let day: Date
    let calendar: Calendar
    let today: Date
    let holidays: Set<Date>
    var error = false
    let onPick: (Date) -> Void
    @State private var isPicking = false

    var body: some View {
        Button { isPicking = true } label: {
            Text(EventText.day(day, calendar: calendar))
                .monospacedDigit()
                .drawnField(.box, focused: false, error: error, active: isPicking)
                .contentShape(Rectangle())
        }
        // The box draws itself; the button adds the focus ring.
        .buttonStyle(FocusOnlyStyle())
        .fixedSize()
        .anchoredPop(isPresented: $isPicking) {
            DayPick(day: day, calendar: calendar, today: today, holidays: holidays) { picked in
                onPick(picked)
                isPicking = false
            }
        }
    }
}

/// The month in DayField's box: the arrows move the day, Return or a click takes it.
private struct DayPick: View {
    let calendar: Calendar
    let today: Date
    let holidays: Set<Date>
    let onPick: (Date) -> Void
    @State private var day: Date

    init(day: Date, calendar: Calendar, today: Date, holidays: Set<Date>, onPick: @escaping (Date) -> Void) {
        self.calendar = calendar
        self.today = today
        self.holidays = holidays
        self.onPick = onPick
        _day = State(initialValue: day)
    }

    var body: some View {
        InkDatePicker(selection: $day, calendar: calendar, today: today, isHoliday: { holidays.contains($0) }) { onPick(day) }
            .padding(.horizontal, Metrics.spaceL)
            .padding(.top, Metrics.spaceM)
            .padding(.bottom, Metrics.spaceL)
    }
}

/// A time in a drawn box; a click lists the day in quarter hours, nine at a time with the chosen
/// one in the middle. Typing a time (`14`, `230`) moves the cursor to the nearest.
private struct TimeField: View {
    let time: Date
    let calendar: Calendar
    let onPick: (Date) -> Void
    @State private var isOpen = false

    var body: some View {
        let day = calendar.startOfDay(for: time)
        // By clock time, once each: on a daylight-saving day the skipped quarter hours map onto one moment.
        let options = (0..<96).compactMap { calendar.date(bySettingHour: $0 / 4, minute: $0 % 4 * 15, second: 0, of: day) }
            .reduce(into: [Date]()) { if $0.last != $1 { $0.append($1) } }
        let minutes = options.map(minutesOfDay)
        Button { isOpen = true } label: {
            Text(EventText.time(time, calendar: calendar))
                .monospacedDigit()
                .drawnField(.box, focused: false, active: isOpen)
                .contentShape(Rectangle())
        }
        .buttonStyle(FocusOnlyStyle())
        .fixedSize()
        .inkMenu(isPresented: $isOpen, maxItems: 9, typeahead: { TimeTypeahead.nearest($0, in: minutes, near: minutesOfDay(time)) }) {
            options.map { option in
                .item(EventText.time(option, calendar: calendar), checked: option == time) { onPick(option) }
            }
        }
    }

    private func minutesOfDay(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return c.hour! * 60 + c.minute!
    }
}

/// What a menu shows when closed: a drawn box with a chevron, grey while its menu is open. The
/// button around it adds the focus ring.
struct MenuLabel: View {
    let text: String
    var soft: String?
    var mark: CalendarLook?
    var isOpen = false

    var body: some View {
        HStack(spacing: Metrics.spaceS) {
            if let mark { Mark(mark.ink, size: 10, shape: mark.shape) }
            Text("\(text)\(Text(soft.map { " · " + $0 } ?? "").foregroundStyle(.inkSoft))")
            Spacer(minLength: Metrics.spaceXs)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }
        .lineLimit(1)
        .drawnField(.box, focused: false, active: isOpen)
        .contentShape(Rectangle())
    }
}

