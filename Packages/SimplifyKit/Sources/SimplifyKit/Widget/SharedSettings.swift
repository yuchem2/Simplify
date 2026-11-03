import Foundation

/// Settings the app and its widgets both read, kept in the App Group's defaults.
///
/// Before stage 7 these lived in the app's own defaults; `migrate` carries them over once.
public enum SharedSettings {
    /// Ticked-off reminders stay on the calendar, struck through. Off unless turned on.
    public static let showsCompletedReminders = "showsCompletedReminders"
    /// Timed events in the app's day cells start with their time. On unless turned off. Shared since
    /// stage 7; the widgets' cells are too narrow for times and leave it aside.
    public static let showsCellTimes = "showsCellTimes"
    /// When a widget last changed the diary store, so the app knows to read it again.
    static let diaryChangedAt = "diaryChangedAt"

    static let movedKeys = [showsCompletedReminders, showsCellTimes]

    /// The App Group's defaults, or the app's own when the build has no group (unsigned builds).
    /// Made once; UserDefaults is thread-safe though not marked Sendable.
    nonisolated(unsafe) public static let defaults: UserDefaults = AppGroup.identifier().flatMap(UserDefaults.init(suiteName:)) ?? .standard

    /// Copies the settings the person already chose from `old` into `shared`, where `shared` has
    /// none yet, and removes them from `old` so a later change has one home.
    public static func migrate(from old: UserDefaults, to shared: UserDefaults) {
        guard old !== shared else { return }
        for key in movedKeys {
            guard let value = old.object(forKey: key) else { continue }
            if shared.object(forKey: key) == nil { shared.set(value, forKey: key) }
            old.removeObject(forKey: key)
        }
    }

    public static func showsCellTimes(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: showsCellTimes) as? Bool ?? true
    }

    // MARK: Diary changes from widgets

    /// A widget changed the diary store (a ToDo ticked).
    public static func markDiaryChanged(in defaults: UserDefaults, at date: Date = .now) {
        defaults.set(date.timeIntervalSinceReferenceDate, forKey: diaryChangedAt)
    }

    /// The last widget change, or nil when there was none.
    public static func diaryChangedAt(in defaults: UserDefaults) -> Date? {
        (defaults.object(forKey: diaryChangedAt) as? Double).map(Date.init(timeIntervalSinceReferenceDate:))
    }

    /// Tells a running app at once, even one already in front (where no activation follows).
    /// Under the group's name, the one prefix the sandbox lets both processes use.
    static let diaryChangedNotification = (AppGroup.identifier() ?? "dev.yoom.simplify") + ".diaryChanged"

    public static func postDiaryChanged() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(diaryChangedNotification as CFString), nil, nil, true)
    }

    /// Calls `handler` on the main queue whenever a widget posts a diary change.
    @MainActor public static func observeDiaryChanges(_ handler: @escaping @MainActor () -> Void) {
        diaryHandler = handler
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { SharedSettings.diaryHandler?() } }
        }, diaryChangedNotification as CFString, nil, .deliverImmediately)
    }

    @MainActor private static var diaryHandler: (@MainActor () -> Void)?
}
