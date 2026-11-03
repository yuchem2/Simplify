import Foundation
import SwiftData

/// How records are matched across devices: memos by period, ToDos and links by id.
public enum SyncKey {
    /// `day|2026-11-03`: a memo's place, the same on every device.
    public static func note(scope: PeriodScope, periodKey: String) -> String {
        "\(scope.rawValue)|\(periodKey)"
    }
}

/// The times and tombstones the store's changing functions leave for syncing (stage 9).
enum SyncStamp {
    /// Now, or just after `previous` when this device's clock is behind it, so a change always
    /// reads as newer than what it changed.
    static func after(_ previous: Date, now: Date = .now) -> Date {
        max(now, previous.addingTimeInterval(0.001))
    }

    /// Notes that `key` was deleted, so another device's copy goes too.
    static func bury(_ kind: SyncKind, _ key: String, at date: Date = .now, in context: ModelContext) {
        context.insert(SyncTombstone(kind: kind, key: key, deletedAt: date))
    }
}
