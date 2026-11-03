import Foundation

/// One event as a widget draws it: the occurrence with its calendar's colour and kind.
public struct WidgetEvent: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    /// Exclusive.
    public let end: Date
    public let isAllDay: Bool
    public let isBand: Bool
    /// Its calendar's colour and shape, as picked in 설정 or following the provider.
    public let look: CalendarLook
    /// From the Mac's reminders: a round mark, and it is due at `start`.
    public let isReminder: Bool
    /// From a holiday calendar: it reddens the date and stays out of the marks.
    public let isHoliday: Bool
    public let isCompleted: Bool

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, isBand: Bool, look: CalendarLook,
                isReminder: Bool = false, isHoliday: Bool = false, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isBand = isBand
        self.look = look
        self.isReminder = isReminder
        self.isHoliday = isHoliday
        self.isCompleted = isCompleted
    }

    /// In a palette colour with that colour's shape.
    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, isBand: Bool, palette: Palette,
                isReminder: Bool = false, isHoliday: Bool = false, isCompleted: Bool = false) {
        self.init(id: id, title: title, start: start, end: end, isAllDay: isAllDay, isBand: isBand, look: CalendarLook(palette),
                  isReminder: isReminder, isHoliday: isHoliday, isCompleted: isCompleted)
    }

    /// Over by `now`: a timed event once it ends, a reminder once its time comes. Bands last the day.
    func isOver(at now: Date) -> Bool {
        if isBand { return end <= now }
        return isReminder ? start <= now : end <= now
    }
}

/// What a calendar contributes to a widget besides its events.
public struct WidgetCalendar: Hashable, Sendable {
    public var look: CalendarLook
    public var isReminderList: Bool
    public var isHoliday: Bool

    public init(look: CalendarLook, isReminderList: Bool = false, isHoliday: Bool = false) {
        self.look = look
        self.isReminderList = isReminderList
        self.isHoliday = isHoliday
    }
}

/// Everything a widget shows at one moment, worked out from the stores' contents.
///
/// Pure functions, so the timeline can compute each entry ahead of time and tests can pin them down.
public enum WidgetContent {
    /// One line of an agenda or schedule.
    public struct Row: Hashable, Sendable {
        public let event: WidgetEvent
        /// Over already; drawn faint.
        public let isPast: Bool
    }

    /// One day of the month ledger.
    public struct LedgerDay: Hashable, Sendable, Identifiable {
        public let date: Date
        public let number: Int
        public let isInMonth: Bool
        public let isToday: Bool
        /// Sunday or a public holiday.
        public let isRed: Bool
        /// The first `markLimit` of the day's events (holidays aside), in the order the day lists them.
        public let marks: [WidgetEvent]
        /// All the day's events, holidays aside.
        public let count: Int
        /// The day's first event (holidays aside), for the day's spoken label.
        public let first: WidgetEvent?
        public var id: Date { date }
    }

    public static let markLimit = 3

    public static func events(_ occurrences: [EventOccurrence], calendars: [String: WidgetCalendar]) -> [WidgetEvent] {
        occurrences.map { occurrence in
            let info = calendars[occurrence.sourceID] ?? WidgetCalendar(look: CalendarLook(.blue))
            return WidgetEvent(id: occurrence.id, title: occurrence.title, start: occurrence.start, end: occurrence.end,
                               isAllDay: occurrence.isAllDay, isBand: occurrence.isBand, look: info.look,
                               isReminder: info.isReminderList, isHoliday: info.isHoliday, isCompleted: occurrence.isCompleted)
        }
    }

    /// `day`'s events: bands covering it first (earlier, then longer), then the timed ones starting
    /// on it by time, unfinished before finished, as the app's day list orders them.
    public static func day(_ day: Date, events: [WidgetEvent], calendar: Calendar) -> [WidgetEvent] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let bands = events.filter { $0.isBand && $0.start < end && $0.end > start }
            .sorted { ($0.start, -$0.end.timeIntervalSince1970, $0.title) < ($1.start, -$1.end.timeIntervalSince1970, $1.title) }
        let timed = events.filter { !$0.isBand && $0.start >= start && $0.start < end }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        let all = bands + timed
        return all.filter { !$0.isCompleted } + all.filter(\.isCompleted)
    }

    /// The small widget's list: what is still to come today, timed events first (one under way
    /// stays until it ends). All-day events show only when no timed one is left.
    public static func upNext(_ today: [WidgetEvent], now: Date, limit: Int = 2) -> [WidgetEvent] {
        let open = today.filter { !$0.isCompleted && !$0.isOver(at: now) }
        let timed = open.filter { !$0.isBand }
        return Array((timed.isEmpty ? open : timed).prefix(limit))
    }

    /// A day's part of the agenda; today's has no heading of its own (the widget's date says it).
    public struct AgendaDay: Hashable, Sendable {
        public let date: Date
        /// 0 for today, 1 for tomorrow, and so on.
        public let offset: Int
        public let rows: [Row]
    }

    /// The small and large widgets' list, as many `lines` as fit: what is left of today, then the
    /// next days that have events, each under its own heading line, the way a desk diary runs on.
    /// A later day shows only with room for its heading and one event. When nothing comes within
    /// `days`, spare lines go to today's latest events that are over. `more` counts today's events
    /// still to come that did not fit; a later day is shown only in part without a count.
    public static func agenda(events: [WidgetEvent], now: Date, calendar: Calendar, lines: Int, days: Int = WidgetStore.comingDays) -> (days: [AgendaDay], more: Int) {
        guard lines > 0 else { return ([], 0) }
        let today = calendar.startOfDay(for: now)
        let todays = timeOrdered(day(today, events: events, calendar: calendar))
        let coming = todays.filter { !$0.isOver(at: now) }
        if coming.count >= lines {
            let shown = coming.count > lines ? lines - 1 : lines
            return ([AgendaDay(date: today, offset: 0, rows: coming.prefix(shown).map { Row(event: $0, isPast: false) })], coming.count - shown)
        }
        var room = lines - coming.count
        var later: [AgendaDay] = []
        for offset in 1...max(1, days) where room >= 2 {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let list = timeOrdered(day(date, events: events, calendar: calendar).filter { !$0.isCompleted })
            guard !list.isEmpty else { continue }
            let rows = list.prefix(room - 1).map { Row(event: $0, isPast: false) }
            later.append(AgendaDay(date: date, offset: offset, rows: rows))
            room -= 1 + rows.count
        }
        let context = later.isEmpty && room > 0 ? todays.filter { $0.isOver(at: now) }.suffix(room) : []
        let first = context.map { Row(event: $0, isPast: true) } + coming.map { Row(event: $0, isPast: false) }
        return ((first.isEmpty ? [] : [AgendaDay(date: today, offset: 0, rows: first)]) + later, 0)
    }

    /// How tall each part of a schedule column is, in points, gaps included where they follow something.
    public struct ScheduleCosts: Sendable {
        public var heading: Double
        public var allDay: Double
        public var timed: Double
        public var more: Double
        public var gap: Double

        public init(heading: Double, allDay: Double, timed: Double, more: Double, gap: Double) {
            self.heading = heading
            self.allDay = allDay
            self.timed = timed
            self.more = more
            self.gap = gap
        }
    }

    /// The medium widget's schedule column, like the system Calendar widget's: what is left of today
    /// (no heading; the widget's date says it), then the next days within `days` that have events,
    /// each under a heading, as many blocks as fit
    /// in `height`. An all-day block is one line and a timed one two, so the room is counted in
    /// points rather than rows. A day is cut off where the room ends and no later day follows it;
    /// `more` counts the events left out, and the room for its line is kept free.
    public static func schedule(events: [WidgetEvent], now: Date, calendar: Calendar, height: Double,
                                costs: ScheduleCosts, days: Int = WidgetStore.comingDays) -> (days: [AgendaDay], more: Int) {
        let today = calendar.startOfDay(for: now)
        var lists: [(offset: Int, date: Date, events: [WidgetEvent])] = []
        for offset in 0...max(0, days) {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let list = timeOrdered(day(date, events: events, calendar: calendar))
                .filter { !$0.isCompleted && (offset > 0 || !$0.isOver(at: now)) }
            if !list.isEmpty { lists.append((offset, date, list)) }
        }
        let total = lists.reduce(0) { $0 + $1.events.count }
        func cost(_ event: WidgetEvent) -> Double { costs.gap + (event.isBand ? costs.allDay : costs.timed) }

        // Each shown day with the room it takes: its heading and its blocks.
        var shown: [(offset: Int, date: Date, events: [WidgetEvent])] = []
        var used = 0.0
        fill: for list in lists {
            let heading = list.offset == 0 ? 0 : (shown.isEmpty ? 0 : costs.gap) + costs.heading
            var taken: [WidgetEvent] = []
            var room = used + heading
            for event in list.events {
                guard room + cost(event) <= height else { break }
                taken.append(event)
                room += cost(event)
            }
            guard !taken.isEmpty else { break fill }
            shown.append((list.offset, list.date, taken))
            used = room
            if taken.count < list.events.count { break fill }
        }
        // Make room for the "그 밖에" line by giving back the last blocks.
        var count = shown.reduce(0) { $0 + $1.events.count }
        while count < total, used + costs.gap + costs.more > height, var last = shown.popLast(), !last.events.isEmpty {
            let event = last.events.removeLast()
            used -= cost(event)
            count -= 1
            if last.events.isEmpty {
                // A day without blocks goes, heading and all.
                if last.offset > 0 { used -= (shown.isEmpty ? 0 : costs.gap) + costs.heading }
            } else {
                shown.append(last)
            }
        }
        let result = shown.map { AgendaDay(date: $0.date, offset: $0.offset, rows: $0.events.map { Row(event: $0, isPast: false) }) }
        return (result, total - count)
    }

    /// Bands first, then by start: the order a list reads in, finished or not.
    static func timeOrdered(_ list: [WidgetEvent]) -> [WidgetEvent] {
        list.filter(\.isBand) + list.filter { !$0.isBand }.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// The month ledger around `today`: whole weeks from the calendar's first weekday.
    public static func ledger(month: Date, today: Date, events: [WidgetEvent], calendar: Calendar) -> [[LedgerDay]] {
        let grid = MonthGrid(month: month, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        // Only the events touching the grid, so each day sorts a handful rather than the whole range.
        let gridStart = grid.weeks.first!.first!
        let gridEnd = calendar.date(byAdding: .day, value: 1, to: grid.weeks.last!.last!)!
        let shown = events.filter { $0.start < gridEnd && max($0.end, $0.start.addingTimeInterval(1)) > gridStart }
        return grid.weeks.map { week in
            week.map { date in
                let list = day(date, events: shown, calendar: calendar)
                let own = list.filter { !$0.isHoliday }
                let isSunday = calendar.component(.weekday, from: date) == 1
                return LedgerDay(date: date, number: calendar.component(.day, from: date), isInMonth: grid.isInMonth(date),
                                 isToday: date == todayStart, isRed: isSunday || list.contains(where: \.isHoliday),
                                 marks: Array(own.prefix(markLimit)), count: own.count, first: own.first)
            }
        }
    }

    /// When a widget's content changes on its own: now, each start and end of the events of today
    /// and tomorrow still ahead, and the next midnight. Sorted, without repeats. Entries stop with
    /// tomorrow, so the timeline should be renewed by `renewal(now:calendar:)`.
    public static func timeline(now: Date, events: [WidgetEvent], calendar: Calendar, limit: Int = 60) -> [Date] {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let horizon = renewal(now: now, calendar: calendar)
        var dates: Set<Date> = [now, midnight]
        for event in events where !event.isBand {
            for date in [event.start, event.end] where date > now && date < horizon { dates.insert(date) }
        }
        return Array(dates.sorted().prefix(limit))
    }

    /// The end of tomorrow: past it the data read at `now` has nothing to say.
    public static func renewal(now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now))!
    }

    /// A day's ToDos for a widget: unfinished in their order, finished below.
    public static func todoRows(_ entries: [TodoEntry]) -> [TodoEntry] {
        entries.filter { !$0.isDone } + entries.filter(\.isDone)
    }
}
