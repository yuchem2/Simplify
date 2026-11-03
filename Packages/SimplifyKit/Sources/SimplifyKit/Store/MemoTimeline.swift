import Foundation

/// Lines the memo draws its own way without changing a letter: a rule (`────────`) drawn as an
/// ink line across the memo, and a timeline line (`11.02 08:30 …`) whose time is set in figures
/// with the lines it wraps onto starting under its words. The stored text, the synced copy and
/// the Notes mirror keep the letters as typed.
public enum MemoTimeline {
    /// Letters a rule is typed with. One of them, more than three times in a row, alone on its line.
    public static let ruleLetters: Set<Character> = ["─", "━", "═", "-", "=", "_", "~", "―", "—", "–"]

    /// The line is a rule: one rule letter repeated more than three times, and nothing else on it
    /// but spaces.
    public static func isRule<S: StringProtocol>(_ line: S) -> Bool {
        let letters = line.filter { !$0.isWhitespace }
        guard letters.count > 3, let first = letters.first, ruleLetters.contains(first) else { return false }
        guard letters.allSatisfy({ $0 == first }) else { return false }
        // One unbroken run: `── ──` is two short dashes, not a rule.
        let trimmed = line.drop { $0.isWhitespace }.reversed().drop { $0.isWhitespace }
        return trimmed.count == letters.count
    }

    /// How many letters at the start of the line are its time: `11.02 08:30` (11) or
    /// `11.02 08:30-09:15` (17), followed by a space or the line's end. Nil for any other line.
    public static func stampLength<S: StringProtocol>(_ line: S) -> Int? {
        let letters = Array(line.prefix(18))
        func digits(_ at: Int, max: Int) -> Bool {
            guard at + 1 < letters.count, let tens = letters[at].wholeNumberValue, let ones = letters[at + 1].wholeNumberValue,
                  letters[at].isASCII, letters[at + 1].isASCII else { return false }
            return tens * 10 + ones <= max
        }
        func clock(_ at: Int) -> Bool {
            digits(at, max: 23) && at + 2 < letters.count && letters[at + 2] == ":" && digits(at + 3, max: 59)
        }
        guard digits(0, max: 12), letters.count > 2, letters[2] == ".", digits(3, max: 31), letters.count > 5, letters[5] == " ",
              clock(6) else { return nil }
        var length = 11
        if letters.count > 11, letters[11] == "-", clock(12) { length = 17 }
        guard length == letters.count || letters[length].isWhitespace else { return nil }
        return length
    }

    /// `11.03 14:25`: the month and day of `day` and the hour and minute of `now`, in figures.
    public static func stamp(day: Date, now: Date, calendar: Calendar) -> String {
        let date = calendar.dateComponents([.month, .day], from: day)
        let time = calendar.dateComponents([.hour, .minute], from: now)
        return String(format: "%02d.%02d %02d:%02d", date.month ?? 0, date.day ?? 0, time.hour ?? 0, time.minute ?? 0)
    }

    /// The day a new timeline line names: a day memo's own day; for a week or month memo today,
    /// or the chosen day when today is outside that week or month.
    public static func stampDay(for memo: Period, today: Date, chosen: Date) -> Date {
        switch memo.scope {
        case .day: memo.start
        case .week, .month: memo.contains(today) ? today : chosen
        }
    }

    /// Where the time goes for a caret at `caret` (in letters): at the front of its line when the
    /// line is empty, otherwise on a new line opened under it. `text` is what to insert at
    /// `offset`, and the caret goes to `caretAfter`.
    public static func insertion(in memo: String, caret: Int, stamp: String) -> (offset: Int, text: String, caretAfter: Int) {
        let letters = Array(memo)
        let caret = min(max(caret, 0), letters.count)
        var start = caret
        while start > 0, !letters[start - 1].isNewline { start -= 1 }
        var end = caret
        while end < letters.count, !letters[end].isNewline { end += 1 }
        let piece = stamp + " "
        if letters[start..<end].allSatisfy(\.isWhitespace) {
            return (start, piece, start + piece.count)
        }
        return (end, "\n" + piece, end + 1 + piece.count)
    }
}
