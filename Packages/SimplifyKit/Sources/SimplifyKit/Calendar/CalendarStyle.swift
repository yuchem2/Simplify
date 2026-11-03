import Foundation
import SwiftUI

/// A calendar's colour: one of the palette's, or any colour picked on the colour wheel (`#RRGGBB`).
public enum CalendarColor: Hashable, Sendable {
    case palette(Palette)
    case custom(hex: String)
}

/// How a calendar is drawn: its colour and the shape its marks take when patterns are on.
public struct CalendarLook: Hashable, Sendable {
    public var color: CalendarColor
    public var shape: MarkShape

    public init(color: CalendarColor, shape: MarkShape) {
        self.color = color
        self.shape = shape
    }

    /// A palette colour with its own shape.
    public init(_ palette: Palette) {
        self.init(color: .palette(palette), shape: palette.markShape)
    }

    /// For marks, bars and text.
    public var ink: Color {
        switch color {
        case .palette(let palette): palette.ink
        case .custom(let hex): Color(hex: hex) ?? Palette.nearest(toHex: hex).ink
        }
    }

    /// For band and block backgrounds: the colour faded into the paper, so it works in both themes.
    public var tint: Color {
        switch color {
        case .palette(let palette): palette.tint
        case .custom: Color.paper.mix(with: ink, by: 0.2)
        }
    }

    /// `파랑`, or `직접 고른 색`.
    public var name: String {
        switch color {
        case .palette(let palette): palette.name
        case .custom: "직접 고른 색"
        }
    }

    /// The palette colour nearest, for places that only take palette colours.
    public var nearestPalette: Palette {
        switch color {
        case .palette(let palette): palette
        case .custom(let hex): Palette.nearest(toHex: hex)
        }
    }
}

/// What the person picked for one calendar on this Mac (설정 › 캘린더); nil fields follow the provider.
/// Nothing here is written back to Google or iCloud.
public struct CalendarStyle: Codable, Hashable, Sendable {
    public var palette: Palette?
    /// `#RRGGBB` from the colour wheel; wins over `palette`.
    public var hex: String?
    public var shape: MarkShape?

    public init(palette: Palette? = nil, hex: String? = nil, shape: MarkShape? = nil) {
        self.palette = palette
        self.hex = hex
        self.shape = shape
    }

    public var isEmpty: Bool { palette == nil && hex == nil && shape == nil }
    public var hasColor: Bool { palette != nil || hex != nil }

    /// The look of a calendar whose provider colour is nearest `auto`. A shape left on 자동 follows
    /// the colour; a holiday calendar keeps its provider's colour, whatever was picked. A stored hex
    /// that does not read as `#RRGGBB` counts as none.
    public func look(auto: Palette, isHoliday: Bool = false) -> CalendarLook {
        if isHoliday { return CalendarLook(auto) }
        let wheel = hex.flatMap { Color.rgb(hex: $0) != nil ? $0 : nil }
        let color: CalendarColor = if let wheel { .custom(hex: wheel) } else if let palette { .palette(palette) } else { .palette(auto) }
        var look = CalendarLook(color: color, shape: .square)
        look.shape = shape ?? look.nearestPalette.markShape
        return look
    }
}

/// The picked styles of every calendar, in the App Group's defaults so the widgets draw the same.
/// Kept apart from the calendar cache, whose file every build of the app and widgets opens.
public enum CalendarStyles {
    static let key = "calendarStyles"

    /// By calendar id (`<account id>|<provider calendar id>`).
    public static func all(in defaults: UserDefaults) -> [String: CalendarStyle] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: CalendarStyle].self, from: data)) ?? [:]
    }

    /// Stores `style` for a calendar; an empty one removes it. The other devices follow (stage 9).
    public static func set(_ style: CalendarStyle, for sourceID: String, in defaults: UserDefaults) {
        var styles = all(in: defaults)
        let kept = style.isEmpty ? nil : style
        guard styles[sourceID] != kept else { return }
        styles[sourceID] = kept
        save(styles, in: defaults)
        SyncedSettings.stamp(SyncedSettings.stylePrefix + sourceID, in: defaults)
    }

    /// Forgets the styles of an account's calendars, when it is disconnected. Only on this device:
    /// accounts are each device's own, so another device that still has the account keeps them,
    /// and they come back here with the next sync, ready for when it is connected again.
    public static func remove(account accountID: String, in defaults: UserDefaults) {
        let styles = all(in: defaults)
        let gone = styles.keys.filter { $0.hasPrefix(accountID + "|") }
        save(styles.filter { !gone.contains($0.key) }, in: defaults)
        SyncedSettings.forgetStamps(gone.map { SyncedSettings.stylePrefix + $0 }, in: defaults)
    }

    static func save(_ styles: [String: CalendarStyle], in defaults: UserDefaults) {
        if styles.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(try? JSONEncoder().encode(styles), forKey: key) }
    }
}

public extension Color {
    /// `#RRGGBB` (or `RRGGBB`) in sRGB; nil for anything else.
    init?(hex: String) {
        guard let rgb = Self.rgb(hex: hex) else { return nil }
        self.init(.sRGB, red: Double((rgb >> 16) & 0xff) / 255, green: Double((rgb >> 8) & 0xff) / 255, blue: Double(rgb & 0xff) / 255)
    }

    /// Exactly six hex digits after an optional `#`.
    static func rgb(hex: String) -> UInt32? {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(digits, radix: 16)
    }
}
