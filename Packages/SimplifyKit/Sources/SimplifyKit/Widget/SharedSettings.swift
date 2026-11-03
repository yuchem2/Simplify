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
    /// Event marks take their calendar's shape besides its colour (stage 8). Off unless turned on.
    public static let showsPatterns = "showsPalettePatterns"
    /// The weekday weeks start on, as `Calendar.firstWeekday`: 1 Sunday (the default) or 2 Monday (stage 8).
    public static let firstWeekday = "firstWeekday"
    /// Memos are copied into the 메모 app's "Simplify" folder as they are saved. Off unless turned on.
    /// This Mac's own choice, like the two below: another Mac keeps its own.
    public static let mirrorsToNotes = "mirrorsToNotes"
    /// Each period key's note id in this Mac's 메모 app, so its copy is found again even renamed.
    static let notesNoteIDs = "notesNoteIDs"
    /// Period keys whose copy has not reached the 메모 app yet.
    static let notesPending = "notesPending"
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

    public static func showsPatterns(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: showsPatterns)
    }

    /// Sunday unless Monday was chosen; anything else stored there reads as Sunday.
    public static func firstWeekday(in defaults: UserDefaults) -> Int {
        defaults.integer(forKey: firstWeekday) == 2 ? 2 : 1
    }

    // MARK: Copies in the 메모 app

    public static func notesNoteIDs(in defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: notesNoteIDs) as? [String: String] ?? [:]
    }

    public static func setNotesNoteIDs(_ ids: [String: String], in defaults: UserDefaults) {
        defaults.set(ids, forKey: notesNoteIDs)
    }

    public static func notesPending(in defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: notesPending) ?? [])
    }

    public static func setNotesPending(_ keys: Set<String>, in defaults: UserDefaults) {
        defaults.set(keys.sorted(), forKey: notesPending)
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
