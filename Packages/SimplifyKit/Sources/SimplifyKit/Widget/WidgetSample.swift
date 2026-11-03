import Foundation

public extension WidgetData {
    /// Example contents around `now`, for the widget gallery's preview and snapshots. Never stored.
    static func sample(now: Date = .now, calendar: Calendar = .simplify) -> WidgetData {
        let today = calendar.startOfDay(for: now)
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: today)!
        }
        func timed(_ title: String, _ day: Int, _ hour: Int, _ minute: Int = 0, minutes: Double = 60, in palette: Palette,
                   reminder: Bool = false) -> WidgetEvent {
            let start = at(day, hour, minute)
            return WidgetEvent(id: "\(title)@\(day)", title: title, start: start, end: reminder ? start : start.addingTimeInterval(minutes * 60),
                               isAllDay: false, isBand: false, palette: palette, isReminder: reminder)
        }
        func band(_ title: String, _ day: Int, days: Int, _ palette: Palette) -> WidgetEvent {
            WidgetEvent(id: "\(title)@\(day)", title: title, start: at(day, 0), end: at(day + days, 0),
                        isAllDay: true, isBand: true, palette: palette)
        }
        var events = [
            timed("주간 스탠드업", 0, 9, 30, minutes: 30, in: .blue), timed("점심 미팅", 0, 12, in: .orange),
            timed("디자인 시스템 정리 회의", 0, 14, minutes: 90, in: .blue), timed("영양제 주문", 0, 17, in: .yellow, reminder: true),
            timed("필라테스", 0, 19, 30, in: .green), timed("독서 모임", 0, 21, in: .orange),
            timed("건강검진", 3, 8, in: .orange), timed("연말정산 서류", 4, 10, in: .yellow, reminder: true),
            band("UX 컨퍼런스", 9, days: 3, .purple), timed("사촌 결혼식", 12, 12, 30, in: .teal),
            timed("분기 회고", 17, 15, in: .blue), timed("대학 동기 저녁", 19, 18, 30, in: .orange), timed("부모님 점심", 24, 11, in: .teal),
        ]
        // A weekly standup and pilates, so the ledger has some rhythm.
        for week in [-21, -14, -7, 7, 14, 21] {
            events.append(timed("주간 스탠드업", week, 9, 30, minutes: 30, in: .blue))
            events.append(timed("필라테스", week + 1, 19, 30, in: .green))
        }
        let key = DayKey.key(today, calendar: calendar)
        func todo(_ title: String, done: Bool = false, _ label: Palette? = nil) -> TodoEntry {
            TodoEntry(todoID: UUID(), linkID: nil, title: title, isDone: done, label: label, order: 0,
                      home: PeriodRef(scope: .day, key: key), elsewhere: [], sourceNoteID: nil)
        }
        let todos = [todo("분기 리포트 초안 보내기", .pink), todo("연휴 전 경비 정산"),
                     todo("제주 숙소 체크인 확인", .teal), todo("회의록 정리", done: true)]
        return WidgetData(state: .ready, events: events, todos: [key: todos])
    }
}
