import Foundation

/// `simplify://day/2026-11-02`: opens the app on that day. Widgets link to it.
public enum DayLink {
    public static let scheme = "simplify"

    public static func url(for day: Date, calendar: Calendar) -> URL {
        URL(string: "\(scheme)://day/\(DayKey.key(day, calendar: calendar))")!
    }

    /// The start of the linked day, or nil for any other URL.
    public static func day(from url: URL, calendar: Calendar) -> Date? {
        guard url.scheme == scheme, url.host() == "day" else { return nil }
        let key = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // DayKey.date rolls 2026-02-31 over into March; only a key that comes back unchanged is a day.
        guard let day = DayKey.date(key, calendar: calendar), DayKey.key(day, calendar: calendar) == key else { return nil }
        return day
    }
}
