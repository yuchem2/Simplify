import Foundation

/// A setting's value as it travels between devices.
public enum SettingValue: Codable, Hashable, Sendable {
    case bool(Bool)
    case int(Int)
    case string(String)
    case style(CalendarStyle)
}

/// One setting on one device: its value (nil for none, or back to 자동) and when it was chosen.
public struct SyncSetting: Codable, Hashable, Sendable {
    public var value: SettingValue?
    public var changedAt: Date

    public init(value: SettingValue?, changedAt: Date) {
        self.value = value
        self.changedAt = changedAt
    }
}

/// The settings every device shares (stage 9), and when each was last chosen on this device.
///
/// They stay where they always lived, in the shared defaults; the times sit beside them under
/// `syncSettingsChangedAt`. Calendar styles go one calendar at a time (`calendarStyles|<id>`).
/// Everything else in the defaults (the folder, the 메모 app copies, login, the screen) stays on
/// this device.
public enum SyncedSettings {
    enum Kind { case bool, int, string }

    static let plain: [String: Kind] = [
        SharedSettings.showsPatterns: .bool,
        SharedSettings.firstWeekday: .int,
        SharedSettings.showsCellTimes: .bool,
        SharedSettings.showsCompletedReminders: .bool,
        NewEventCalendar.preferredKey: .string,
    ]
    static let stylePrefix = "calendarStyles|"
    static let stampsKey = "syncSettingsChangedAt"

    /// Posted after a synced setting is changed on this device, so the next sync writes it out.
    public static let didChange = Notification.Name("dev.yoom.simplify.syncedSettingsChanged")

    /// A setting never chosen on this device: it loses to any choice made anywhere.
    static let neverChosen = Date.distantPast
    /// A setting chosen before stage 9 kept no time: it beats one never chosen, and loses to any
    /// choice that has a time.
    static let chosenLongAgo = Date.distantPast.addingTimeInterval(1)

    /// Writes a shared setting and notes when, if it changed. Nil removes it.
    public static func set(_ value: SettingValue?, forKey key: String, in defaults: UserDefaults, now: Date = .now) {
        guard plain[key] != nil, self.value(forKey: key, in: defaults) != value else { return }
        write(value, forKey: key, in: defaults)
        stamp(key, in: defaults, now: now)
    }

    /// Notes that `key` was just chosen on this device.
    static func stamp(_ key: String, in defaults: UserDefaults, now: Date = .now) {
        var stamps = self.stamps(in: defaults)
        stamps[key] = now.timeIntervalSinceReferenceDate
        defaults.set(stamps, forKey: stampsKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Forgets when calendars' styles were chosen, alongside `CalendarStyles.remove(account:)`.
    static func forgetStamps(_ keys: [String], in defaults: UserDefaults) {
        var stamps = self.stamps(in: defaults)
        keys.forEach { stamps[$0] = nil }
        defaults.set(stamps, forKey: stampsKey)
    }

    /// Every shared setting on this device with its time.
    public static func snapshot(in defaults: UserDefaults) -> [String: SyncSetting] {
        let stamps = self.stamps(in: defaults)
        func time(_ key: String, present: Bool) -> Date {
            stamps[key].map(Date.init(timeIntervalSinceReferenceDate:)) ?? (present ? chosenLongAgo : neverChosen)
        }
        var result: [String: SyncSetting] = [:]
        for key in plain.keys {
            let value = value(forKey: key, in: defaults)
            result[key] = SyncSetting(value: value, changedAt: time(key, present: value != nil))
        }
        let styles = CalendarStyles.all(in: defaults)
        let styleKeys = Set(styles.keys.map { stylePrefix + $0 }).union(stamps.keys.filter { $0.hasPrefix(stylePrefix) })
        for key in styleKeys {
            let style = styles[String(key.dropFirst(stylePrefix.count))]
            result[key] = SyncSetting(value: style.map(SettingValue.style), changedAt: time(key, present: style != nil))
        }
        return result
    }

    /// Takes the merged settings in, quietly: nothing is posted. Returns the keys whose value changed.
    @discardableResult
    public static func apply(_ settings: [String: SyncSetting], in defaults: UserDefaults) -> Set<String> {
        let current = snapshot(in: defaults)
        var stamps = self.stamps(in: defaults)
        var styles = CalendarStyles.all(in: defaults)
        var changed: Set<String> = []
        for (key, setting) in settings where plain[key] != nil || key.hasPrefix(stylePrefix) {
            if current[key]?.value != setting.value {
                changed.insert(key)
                if key.hasPrefix(stylePrefix) {
                    let id = String(key.dropFirst(stylePrefix.count))
                    if case .style(let style)? = setting.value, !style.isEmpty { styles[id] = style } else { styles[id] = nil }
                } else {
                    write(setting.value, forKey: key, in: defaults)
                }
            }
            if setting.changedAt > neverChosen { stamps[key] = setting.changedAt.timeIntervalSinceReferenceDate }
        }
        if changed.contains(where: { $0.hasPrefix(stylePrefix) }) { CalendarStyles.save(styles, in: defaults) }
        defaults.set(stamps, forKey: stampsKey)
        return changed
    }

    static func value(forKey key: String, in defaults: UserDefaults) -> SettingValue? {
        switch plain[key] {
        case .bool: (defaults.object(forKey: key) as? Bool).map(SettingValue.bool)
        case .int: (defaults.object(forKey: key) as? Int).map(SettingValue.int)
        case .string: defaults.string(forKey: key).map(SettingValue.string)
        case nil: nil
        }
    }

    private static func write(_ value: SettingValue?, forKey key: String, in defaults: UserDefaults) {
        switch value {
        case .bool(let flag)?: defaults.set(flag, forKey: key)
        case .int(let number)?: defaults.set(number, forKey: key)
        case .string(let text)?: defaults.set(text, forKey: key)
        case .style?, nil: defaults.removeObject(forKey: key)
        }
    }

    private static func stamps(in defaults: UserDefaults) -> [String: Double] {
        defaults.dictionary(forKey: stampsKey) as? [String: Double] ?? [:]
    }
}
