import Foundation

/// Korean date and time strings from cached formatters. A formatter is costly to make and views
/// redraw often, so each pattern and time zone gets one, made on first use.
enum DateText {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]

    /// `date` in `format` (a DateFormatter pattern such as `a h:mm`), in Korean, in `timeZone`.
    static func string(_ date: Date, _ format: String, timeZone: TimeZone) -> String {
        lock.lock()
        defer { lock.unlock() }
        let key = format + "|" + timeZone.identifier
        if let formatter = formatters[key] { return formatter.string(from: date) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        formatters[key] = formatter
        return formatter.string(from: date)
    }

    /// `오후 7:00`
    static func clock(_ date: Date, calendar: Calendar) -> String {
        string(date, "a h:mm", timeZone: calendar.timeZone)
    }

    /// `19:00`, for tight places such as day cells.
    static func shortClock(_ date: Date, calendar: Calendar) -> String {
        string(date, "HH:mm", timeZone: calendar.timeZone)
    }
}
