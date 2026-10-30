import Foundation

/// Lays out one day's timed events on an hour grid: events that overlap share the width side by side.
public enum TimedLayout {
    /// An event's piece on the day, with its side-by-side column.
    public struct Block: Hashable, Sendable {
        public let occurrence: EventOccurrence
        /// The part of the event on this day; an event over midnight is cut at the day's edges.
        public let start: Date
        public let end: Date
        public let column: Int
        /// Columns in the group of events this one overlaps, directly or through others.
        public let columns: Int
    }

    /// Timed events (not bands) on `day`. A block is drawn at least `minimumDuration` tall, so
    /// short and zero-length events overlap by that height too.
    public static func blocks(_ occurrences: [EventOccurrence], on day: Date, calendar: Calendar,
                              minimumDuration: TimeInterval = 0) -> [Block] {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
        let pieces = occurrences
            .filter { !$0.isBand && $0.start < dayEnd && ($0.end > day || $0.start >= day) }
            .map { (occurrence: $0, start: max($0.start, day), end: min(max($0.end, $0.start), dayEnd)) }
            .sorted { ($0.start, -$0.end.timeIntervalSince1970, $0.occurrence.title, $0.occurrence.id)
                < ($1.start, -$1.end.timeIntervalSince1970, $1.occurrence.title, $1.occurrence.id) }

        var result: [Block] = []
        var group: [(piece: (occurrence: EventOccurrence, start: Date, end: Date), column: Int)] = []
        var columnEnds: [Date] = []
        var groupEnd = Date.distantPast
        func closeGroup() {
            result += group.map { Block(occurrence: $0.piece.occurrence, start: $0.piece.start, end: $0.piece.end,
                                        column: $0.column, columns: columnEnds.count) }
            group = []
            columnEnds = []
        }
        for piece in pieces {
            let drawnEnd = max(piece.end, piece.start.addingTimeInterval(minimumDuration))
            if !group.isEmpty, piece.start >= groupEnd { closeGroup() }
            let column = columnEnds.firstIndex { $0 <= piece.start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(drawnEnd) } else { columnEnds[column] = drawnEnd }
            group.append((piece, column))
            groupEnd = group.count == 1 ? drawnEnd : max(groupEnd, drawnEnd)
        }
        closeGroup()
        return result
    }
}
