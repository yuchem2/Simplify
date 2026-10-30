import SwiftUI
import SimplifyKit

/// An event's details in the popover: when, how it repeats, its calendar, where. Events in
/// calendars Simplify can write get 편집 and 삭제; holidays, read-only calendars and reminders say why not.
struct EventDetailView: View {
    let model: AppModel
    let calendars: CalendarController
    let occurrence: EventOccurrence

    var body: some View {
        let source = calendars.sources[occurrence.sourceID]
        let event = calendars.event(id: occurrence.eventID)
        let writable = calendars.isWritable(occurrence.sourceID)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if source?.isHoliday != true {
                    EventMark(occurrence: occurrence, source: source, size: 11)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                }
                Text(occurrence.title)
                    .font(.display(19))
                    .foregroundStyle(EventTime.titleColor(occurrence, source: source))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 5) {
                fact("clock", EventText.when(occurrence, isReminder: source?.isReminderList == true, calendar: model.calendar))
                if let repeats = event.flatMap({ EventText.repeats($0, start: occurrence.start, calendar: model.calendar) }) {
                    fact("repeat", repeats)
                }
                if let source {
                    fact("calendar", source.name, soft: providerLabel(source))
                }
                if let location = occurrence.location, !location.isEmpty {
                    fact("mappin.and.ellipse", location)
                }
            }
            if let notes = event?.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                Rectangle().fill(.ink).frame(height: Metrics.line)
                Text(notes)
                    .font(.system(size: 13))
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let write = calendars.unsentWrite(for: occurrence) {
                if case .failed(let error) = write.status {
                    Notice(icon: "exclamationmark.triangle", bold: "보내지 못했어요.", text: error.message, isError: true)
                } else {
                    Notice(icon: "arrow.triangle.2.circlepath", text: "이 변경은 아직 캘린더에 보내지 않았어요. 연결되면 보내요.")
                }
            }
            VStack(spacing: 10) {
                Rectangle().fill(.ink).frame(height: Metrics.line)
                HStack(spacing: 8) {
                    if writable {
                        Spacer()
                        Button("삭제") { ask(.delete) }
                            .buttonStyle(DangerButtonStyle())
                        Button("편집") { model.edit(occurrence, calendars: calendars) }
                            .buttonStyle(DrawnButtonStyle(.primary))
                    } else {
                        Label(readOnlyReason(source), systemImage: "lock")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.inkSoft)
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .onKeyPress(.delete) {
            guard writable else { return .ignored }
            ask(.delete)
            return .handled
        }
        .onKeyPress(.return) {
            guard writable else { return .ignored }
            model.edit(occurrence, calendars: calendars)
            return .handled
        }
    }

    private func fact(_ icon: String, _ text: String, soft: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.inkSoft)
                .frame(width: 14)
            Text("\(text)\(Text(soft.map { " · " + $0 } ?? "").foregroundStyle(.inkSoft))")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ask(_ question: EventPopoverState.Question) {
        model.popover?.question = question
    }

    private func providerLabel(_ source: CalendarController.Source) -> String? {
        guard let account = calendars.accounts.first(where: { $0.id == source.accountID }) else { return nil }
        return account.provider == .reminders ? "이 Mac 미리알림" : account.provider.label
    }

    private func readOnlyReason(_ source: CalendarController.Source?) -> String {
        if source?.isReminderList == true { return "미리알림 앱에서 고쳐 주세요" }
        if source?.isHoliday == true { return "읽기 전용 캘린더예요" }
        if let source, calendars.accounts.first(where: { $0.id == source.accountID })?.status == .needsReauth {
            return "계정을 다시 연결하면 고칠 수 있어요"
        }
        return "보기만 할 수 있는 캘린더예요"
    }
}

/// How an event's time and repeat read in the popover.
enum EventText {
    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }

    /// `10월 28일 (수)`, with the year when it is not this year.
    static func day(_ date: Date, calendar: Calendar) -> String {
        let thisYear = calendar.component(.year, from: .now) == calendar.component(.year, from: date)
        return formatter(thisYear ? "M월 d일 (E)" : "yyyy년 M월 d일 (E)", calendar).string(from: date)
    }

    /// `오후 7:00`
    static func time(_ date: Date, calendar: Calendar) -> String {
        formatter("a h:mm", calendar).string(from: date)
    }

    /// `10월 28일 (수) 오후 7:00 – 8:00`, `10월 22일 (목) – 23일 (금) 종일`; a reminder shows its time alone.
    static func when(_ occurrence: EventOccurrence, isReminder: Bool, calendar: Calendar) -> String {
        let start = occurrence.start
        if occurrence.isAllDay {
            let last = calendar.date(byAdding: .day, value: -1, to: occurrence.end) ?? start
            guard !calendar.isDate(last, inSameDayAs: start), last > start else { return day(start, calendar: calendar) + " 종일" }
            return "\(day(start, calendar: calendar)) – \(day(last, calendar: calendar)) 종일"
        }
        if isReminder || occurrence.end <= start {
            return "\(day(start, calendar: calendar)) \(time(start, calendar: calendar))"
        }
        // An event ending at midnight ends on the day it started.
        let endDay = calendar.date(byAdding: .second, value: -1, to: occurrence.end)!
        if calendar.isDate(endDay, inSameDayAs: start) {
            return "\(day(start, calendar: calendar)) \(time(start, calendar: calendar)) – \(time(occurrence.end, calendar: calendar))"
        }
        return "\(day(start, calendar: calendar)) \(time(start, calendar: calendar)) – \(day(occurrence.end, calendar: calendar)) \(time(occurrence.end, calendar: calendar))"
    }

    /// `매주 수요일`, `반복 (사용자 지정)`, or nil for an event that does not repeat.
    static func repeats(_ event: EventSnapshot, start: Date, calendar: Calendar) -> String? {
        if event.recurringEventID != nil { return "반복 일정 중 이 날만 바뀐 일정" }
        if event.recurrenceUnsupported { return "반복 (사용자 지정)" }
        guard let recurrence = event.recurrence else { return nil }
        let choice = EventEditorModel.RepeatChoice(recurrence, start: start, calendar: calendar)
        return choice == .custom ? "반복 (사용자 지정)" : choice.label(start: start, calendar: calendar)
    }
}
