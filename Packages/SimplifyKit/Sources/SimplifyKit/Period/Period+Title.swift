import Foundation

public extension Period {
    /// Heading for the period: `10월 26일 월요일`, `10월 4주차`, `2026년 10월`.
    var title: String {
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: start)
        switch scope {
        case .day:
            return "\(c.month!)월 \(c.day!)일 \(Calendar.weekdayName(c.weekday!))요일"
        case .week:
            return "\(c.month!)월 \(weekOfMonth)주차"
        case .month:
            return "\(c.year!)년 \(c.month!)월"
        }
    }

    /// For a week: its days as `10.26 – 11.1`. Empty for other scopes.
    var rangeText: String {
        guard scope == .week else { return "" }
        let first = calendar.dateComponents([.month, .day], from: start)
        let last = calendar.dateComponents([.month, .day], from: calendar.date(byAdding: .day, value: -1, to: end)!)
        return "\(first.month!).\(first.day!) – \(last.month!).\(last.day!)"
    }

    /// A week is named after the month its first day falls in, and numbered by how many of that
    /// weekday the month has up to it: 2026.10.25–10.31 is 10월 4주차, and in Monday weeks
    /// 2026.11.2–11.8 is 11월 1주차.
    var weekOfMonth: Int {
        (calendar.component(.day, from: start) - 1) / 7 + 1
    }
}
