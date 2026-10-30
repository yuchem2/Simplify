import CryptoKit
import Foundation

/// The repeat choices the editor offers. Richer rules made elsewhere ("격주 월·수") show as their
/// frequency, and are kept as they are unless the person picks another preset.
public enum RepeatPreset: String, Sendable, CaseIterable, Codable {
    case none, daily, weekly, monthly, yearly

    /// The preset a stored rule shows as; rules the engine cannot read show as `.none`.
    public init(_ recurrence: Recurrence?) {
        switch recurrence?.frequency {
        case .daily: self = .daily
        case .weekly: self = .weekly
        case .monthly: self = .monthly
        case .yearly: self = .yearly
        case nil: self = .none
        }
    }

    /// `RRULE:FREQ=WEEKLY`, or nil for `.none`.
    var rrule: String? {
        self == .none ? nil : "RRULE:FREQ=" + rawValue.uppercased()
    }
}

/// What the editor sends: a new event, or the new values for one being changed.
public struct EventDraft: Sendable, Equatable, Codable {
    public var title: String
    public var isAllDay: Bool
    /// All-day: the first day's midnight in the person's calendar.
    public var start: Date
    /// Exclusive. All-day: midnight of the day after the last day.
    public var end: Date
    /// Timed events: the IANA zone; nil means the person's own.
    public var timeZone: String?
    public var location: String?
    public var notes: String?
    public var repeatRule: RepeatPreset
    /// Where the occurrence the editor was opened on started, as it was shown. Changing every
    /// occurrence moves the series by the difference (in days, plus the new time of day) rather
    /// than to this occurrence's date. Nil for a new event.
    public var occurrenceStart: Date?

    public init(title: String, isAllDay: Bool, start: Date, end: Date, timeZone: String? = nil, location: String? = nil,
                notes: String? = nil, repeatRule: RepeatPreset = .none, occurrenceStart: Date? = nil) {
        self.title = title
        self.isAllDay = isAllDay
        self.start = start
        self.end = end
        self.timeZone = timeZone
        self.location = location
        self.notes = notes
        self.repeatRule = repeatRule
        self.occurrenceStart = occurrenceStart
    }

    /// The values to fill the editor with: `event` as stored (a series, a single event, or one
    /// changed occurrence) and the start of the occurrence picked.
    public init(editing event: EventSnapshot, occurrenceStart: Date, calendar: Calendar) {
        title = event.title == "(제목 없음)" ? "" : event.title
        isAllDay = event.isAllDay
        location = event.location
        notes = event.notes
        // A changed occurrence cannot carry a rule of its own.
        repeatRule = event.recurringEventID == nil ? RepeatPreset(event.recurrence) : .none
        if event.isAllDay {
            start = calendar.startOfDay(for: occurrenceStart)
            let first = event.startDay.flatMap { DayKey.date($0, calendar: DayKey.utc) }
            let last = event.endDay.flatMap { DayKey.date($0, calendar: DayKey.utc) }
            let days = first.flatMap { first in last.flatMap { DayKey.utc.dateComponents([.day], from: first, to: $0).day } } ?? 1
            end = calendar.date(byAdding: .day, value: max(1, days), to: start)!
        } else {
            timeZone = event.timeZone
            start = occurrenceStart
            let duration = max(0, (event.end ?? occurrenceStart).timeIntervalSince(event.start ?? occurrenceStart))
            end = occurrenceStart.addingTimeInterval(duration)
        }
        self.occurrenceStart = occurrenceStart
    }

    /// A fresh event id that both Google (base32hex, 5–1024 characters) and CalDAV (UID) accept.
    public static func newID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// The id of the series that splitting `series` at `key` starts. The same split always gets
    /// the same id, so a retry finds the part it already wrote instead of writing a second one.
    static func splitID(series: String, at key: OccurrenceKey) -> String {
        let point = key.day ?? ICalendarWriter.utcStamp(key.date)
        let digest = SHA256.hash(data: Data((series + "|" + point).utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// The person's calendar in the draft's zone: where a timed draft's days and times are read.
    func zoned(_ calendar: Calendar) -> Calendar {
        var zoned = calendar
        if !isAllDay, let id = timeZone, let zone = TimeZone(identifier: id) { zoned.timeZone = zone }
        return zoned
    }

    /// The zone a timed draft is written in.
    func zoneID(_ calendar: Calendar) -> String {
        timeZone ?? calendar.timeZone.identifier
    }

    /// Start and end for the first occurrence of a series being changed as a whole, whose first
    /// occurrence falls on `masterDay`: moved by as many days as the draft moved its occurrence,
    /// at the draft's time of day.
    func seriesSpan(masterDay: DateComponents, calendar: Calendar) -> (start: Date, end: Date) {
        guard let occurrenceStart else { return (start, end) }
        let cal = zoned(calendar)
        let moved = cal.dateComponents([.day], from: cal.startOfDay(for: occurrenceStart), to: cal.startOfDay(for: start)).day ?? 0
        let day = cal.date(byAdding: .day, value: moved, to: cal.date(from: masterDay)!)!
        if isAllDay {
            let days = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
            let first = calendar.startOfDay(for: day)
            return (first, calendar.date(byAdding: .day, value: days, to: first)!)
        }
        let time = cal.dateComponents([.hour, .minute, .second], from: start)
        let first = cal.date(bySettingHour: time.hour!, minute: time.minute!, second: time.second!, of: day)!
        return (first, first.addingTimeInterval(end.timeIntervalSince(start)))
    }

    /// Whether saving `self` over `event` should replace the series' rule: only when the person
    /// picked another preset, so a rule richer than the presets survives an unrelated change.
    func changesRule(of event: EventSnapshot) -> Bool {
        event.recurringEventID == nil && repeatRule != RepeatPreset(event.recurrence)
    }
}

/// Which occurrences of a repeating event a change covers. Single events take `.allOccurrences`.
public enum EditScope: Sendable, Equatable, Codable {
    /// Just the occurrence that was meant to start at `originalStart` (for all-day events, that
    /// day's midnight in the person's calendar).
    case thisOccurrence(originalStart: Date)
    /// That occurrence and every later one: the series is split there.
    case thisAndFollowing(originalStart: Date)
    case allOccurrences
}

/// The one occurrence of a series a scoped change is about, keyed as the provider keys it.
struct OccurrenceKey: Equatable {
    /// Timed: the original start. All-day: that day's midnight in the person's calendar.
    var date: Date
    /// All-day: `2026-11-05`.
    var day: String?

    init(date: Date, day: String?) {
        self.date = date
        self.day = day
    }

    /// A changed occurrence knows its own original start; otherwise the scope says.
    init(event: EventSnapshot, originalStart: Date, calendar: Calendar) {
        if event.recurringEventID != nil, let day = event.originalStartDay, let date = DayKey.date(day, calendar: calendar) {
            self.date = date
            self.day = day
        } else if event.recurringEventID != nil, let original = event.originalStart {
            date = original
        } else {
            date = originalStart
            if event.isAllDay { day = DayKey.key(originalStart, calendar: calendar) }
        }
    }
}

extension EventSnapshot {
    /// A repeating series, or one occurrence of one.
    var isSeriesMember: Bool { recurringEventID != nil || recurrence != nil || recurrenceUnsupported }

    /// The series' id: its own, or the one a changed occurrence belongs to.
    var seriesRemoteID: String { recurringEventID ?? remoteID }
}

enum RuleText {
    /// An `RRULE:` line without its COUNT and UNTIL, and with the given ones.
    static func rrule(_ line: String, until: String? = nil, count: Int? = nil) -> String {
        let body = line.uppercased().hasPrefix("RRULE:") ? String(line.dropFirst(6)) : line
        var parts = body.split(separator: ";").map(String.init).filter {
            let key = $0.split(separator: "=").first?.uppercased()
            return key != "UNTIL" && key != "COUNT"
        }
        if let until { parts.append("UNTIL=" + until) }
        if let count { parts.append("COUNT=\(count)") }
        return "RRULE:" + parts.joined(separator: ";")
    }

    static func count(in line: String) -> Int? {
        line.split(separator: ";").first { $0.uppercased().hasPrefix("COUNT=") }.flatMap { Int($0.dropFirst(6)) }
    }

    /// How many occurrences a rule makes before `split`, for carrying COUNT over to the part
    /// after a split. `calendar` is in the series' zone (UTC for all-day series).
    static func occurrences(of line: String, start: Date, before split: Date, calendar: Calendar) -> Int? {
        guard let rule = Recurrence(rrule: line, calendar: calendar), split > start else { return nil }
        return RecurrenceExpander.occurrences(of: rule, start: start, calendar: calendar, in: DateInterval(start: start, end: split))
            .filter { $0 < split }.count
    }

    /// `20261104T235959Z`, or `20261104` for all-day series: the last moment before `split`.
    static func until(before split: OccurrenceKey, calendar: Calendar) -> String {
        if split.day != nil {
            let previous = calendar.date(byAdding: .day, value: -1, to: split.date)!
            return DayKey.key(previous, calendar: calendar).replacingOccurrences(of: "-", with: "")
        }
        return ICalendarWriter.utcStamp(split.date.addingTimeInterval(-1))
    }
}
