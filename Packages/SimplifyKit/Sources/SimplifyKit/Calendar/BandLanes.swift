import Foundation

/// Rows for the bands of one week, so a band keeps the same row on every day it covers.
///
/// Bands are placed open first, then by start, longer first on the same start; each takes the
/// lowest row free on all its days, so a row a band leaves is picked up by the next one to start.
public struct BandLanes: Sendable {
    /// One band in the week: its row and the first and last day it covers (0 = the week's first day).
    public struct Placement: Hashable, Sendable {
        public let occurrence: EventOccurrence
        public let lane: Int
        public let firstDay: Int
        public let lastDay: Int
    }

    /// In placing order.
    public let placements: [Placement]
    /// How many rows the week uses.
    public let count: Int
    private let lanes: [String: Int]

    /// `days` are the week's days in order; occurrences that are not bands are ignored.
    public init(_ occurrences: [EventOccurrence], days: [Date], calendar: Calendar) {
        let bands = occurrences.filter(\.isBand).sorted {
            ($0.isCompleted ? 1 : 0, $0.start, -$0.end.timeIntervalSince1970, $0.title, $0.id)
                < ($1.isCompleted ? 1 : 0, $1.start, -$1.end.timeIntervalSince1970, $1.title, $1.id)
        }
        let dayEnds = days.map { calendar.date(byAdding: .day, value: 1, to: $0)! }
        var taken: [[Bool]] = []
        var placements: [Placement] = []
        for band in bands {
            let covered = days.indices.filter { band.start < dayEnds[$0] && band.end > days[$0] }
            guard let first = covered.first, let last = covered.last else { continue }
            var lane = 0
            while lane < taken.count, taken[lane][first...last].contains(true) { lane += 1 }
            if lane == taken.count { taken.append(Array(repeating: false, count: days.count)) }
            for day in first...last { taken[lane][day] = true }
            placements.append(Placement(occurrence: band, lane: lane, firstDay: first, lastDay: last))
        }
        self.placements = placements
        count = taken.count
        lanes = Dictionary(placements.map { ($0.occurrence.id, $0.lane) }, uniquingKeysWith: { first, _ in first })
    }

    public func lane(of occurrence: EventOccurrence) -> Int? { lanes[occurrence.id] }

    /// A day's slots with its bands at their rows, `nil` where a row is free that day, then the
    /// rest in their given order.
    public func rows(_ slots: [OccurrenceBuilder.Slot]) -> [OccurrenceBuilder.Slot?] {
        var placed: [OccurrenceBuilder.Slot?] = []
        var rest: [OccurrenceBuilder.Slot] = []
        for slot in slots {
            guard slot.occurrence.isBand, let lane = lanes[slot.occurrence.id] else {
                rest.append(slot)
                continue
            }
            if placed.count <= lane { placed += Array(repeating: nil, count: lane + 1 - placed.count) }
            placed[lane] = slot
        }
        return placed + rest.map(Optional.some)
    }
}
