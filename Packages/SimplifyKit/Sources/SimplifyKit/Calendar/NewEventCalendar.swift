import Foundation

/// Which calendar a new event starts in (설정 › 일반 › 새 일정).
public enum NewEventCalendar {
    /// Where the choice is kept, in the shared defaults: a calendar id, or nothing for the last one used.
    public static let preferredKey = "newEventSourceID"
    /// The calendar saved to last.
    public static let lastKey = "lastEventSourceID"

    /// The chosen calendar while it can still be written to; otherwise the one saved to last, while
    /// that can; otherwise the first writable one. Nil when there is nothing to write to.
    public static func pick(preferred: String?, last: String?, writable: [String]) -> String? {
        if let preferred, writable.contains(preferred) { return preferred }
        if let last, writable.contains(last) { return last }
        return writable.first
    }
}
