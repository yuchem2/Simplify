import Foundation

/// Writes iCalendar text (RFC 5545), the counterpart of `ICalendar`'s reader. Properties read from
/// a resource are written back as they came; only new or changed ones are spelled out here.
enum ICalendarWriter {
    typealias Property = ICalendar.Property
    typealias Component = ICalendar.Component

    /// Components as text: CRLF line ends, long lines folded.
    static func text(_ components: [Component]) -> String {
        var lines: [String] = []
        func write(_ component: Component) {
            lines.append("BEGIN:" + component.name)
            lines += component.properties.map(line)
            component.children.forEach(write)
            lines.append("END:" + component.name)
        }
        components.forEach(write)
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// One property, unfolded.
    static func line(_ property: Property) -> String {
        if let raw = property.raw { return raw }
        let params = property.params.sorted { $0.key < $1.key }.map { key, value in
            ";" + key + "=" + (value.contains(where: { ":;,".contains($0) }) ? "\"" + value + "\"" : value)
        }
        return property.name + params.joined() + ":" + property.value
    }

    /// Splits a line into pieces of at most 75 octets, each continuation starting with a space;
    /// never inside a UTF-8 character.
    static func fold(_ line: String) -> String {
        guard line.utf8.count > 75 else { return line }
        var pieces: [String] = []
        var current = ""
        var size = 0
        for scalar in line.unicodeScalars {
            let width = String(scalar).utf8.count
            // The first piece holds 75 octets; later ones 74 after their leading space.
            if size + width > (pieces.isEmpty ? 75 : 74) {
                pieces.append(current)
                current = ""
                size = 0
            }
            current.unicodeScalars.append(scalar)
            size += width
        }
        pieces.append(current)
        return pieces.joined(separator: "\r\n ")
    }

    /// TEXT values: `\`, `;`, `,` and line breaks escaped.
    static func escape(_ text: String) -> String {
        var result = ""
        for char in text {
            switch char {
            case "\\": result += "\\\\"
            case ";": result += "\\;"
            case ",": result += "\\,"
            case "\n", "\r\n": result += "\\n"
            case "\r": continue
            default: result.append(char)
            }
        }
        return result
    }

    static func textProperty(_ name: String, _ value: String) -> Property {
        Property(name: name, params: [:], value: escape(value))
    }

    // MARK: - Times

    /// `20261105T010000Z`.
    static func utcStamp(_ date: Date) -> String {
        stamp(date, zone: TimeZone(identifier: "UTC")!) + "Z"
    }

    /// `20261105T100000` on the wall clock of `zone`.
    static func stamp(_ date: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    /// `20261105` for the day `date` falls on in `calendar`.
    static func dayStamp(_ date: Date, calendar: Calendar) -> String {
        DayKey.key(date, calendar: calendar).replacingOccurrences(of: "-", with: "")
    }

    /// `DTSTART;VALUE=DATE:20261105`, `DTSTART;TZID=Asia/Seoul:20261105T100000` or
    /// `DTSTART:20261105T010000Z` for zone UTC. All-day dates are read in `calendar`.
    static func time(_ name: String, _ date: Date, isAllDay: Bool, zone: String, calendar: Calendar) -> Property {
        if isAllDay { return Property(name: name, params: ["VALUE": "DATE"], value: dayStamp(date, calendar: calendar)) }
        if zone == "UTC" || zone == "GMT" { return Property(name: name, params: [:], value: utcStamp(date)) }
        let tz = TimeZone(identifier: zone) ?? calendar.timeZone
        return Property(name: name, params: ["TZID": tz.identifier], value: stamp(date, zone: tz))
    }

    /// A VTIMEZONE for an IANA zone, so a TZID written into a resource is defined in it. Zones
    /// with daylight time get yearly rules from this year's two changes; zones whose changes do
    /// not follow a weekday rule (Iran, Israel) come out right for this year only.
    static func timeZone(_ id: String, around date: Date = .now) -> Component? {
        guard let zone = TimeZone(identifier: id), id != "UTC" else { return nil }
        var component = Component(name: "VTIMEZONE", properties: [Property(name: "TZID", params: [:], value: id)])
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let year = utc.date(from: DateComponents(year: utc.component(.year, from: date), month: 1, day: 1))!
        guard let first = zone.nextDaylightSavingTimeTransition(after: year),
              let second = zone.nextDaylightSavingTimeTransition(after: first) else {
            let offset = zone.secondsFromGMT(for: date)
            component.children = [observance("STANDARD", at: year, from: offset, to: offset, zone: zone, yearly: false)]
            return component
        }
        component.children = [first, second].map { transition in
            let from = zone.secondsFromGMT(for: transition.addingTimeInterval(-1))
            let to = zone.secondsFromGMT(for: transition)
            return observance(zone.isDaylightSavingTime(for: transition) ? "DAYLIGHT" : "STANDARD",
                              at: transition, from: from, to: to, zone: zone, yearly: true)
        }
        return component
    }

    /// One observance, starting in 1970 so every event falls after its start. Daylight zones
    /// repeat this year's change yearly, as "the nth (or last) weekday of the month".
    private static func observance(_ name: String, at transition: Date, from: Int, to: Int, zone: TimeZone, yearly: Bool) -> Component {
        var start = "19700101T000000"
        var rule: Property?
        if yearly {
            // The wall-clock time the change happens at, before it happens.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: from)!
            let c = calendar.dateComponents([.month, .day, .weekday, .hour, .minute, .second], from: transition)
            let days = calendar.range(of: .day, in: .month, for: transition)!.count
            let ordinal = c.day! + 7 > days ? -1 : (c.day! - 1) / 7 + 1
            let code = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][c.weekday! - 1]
            rule = Property(name: "RRULE", params: [:], value: "FREQ=YEARLY;BYMONTH=\(c.month!);BYDAY=\(ordinal)\(code)")

            let first = calendar.date(from: DateComponents(year: 1970, month: c.month, day: 1))!
            let firstWeekday = calendar.component(.weekday, from: first)
            var day = 1 + (c.weekday! - firstWeekday + 7) % 7
            if ordinal > 0 {
                day += (ordinal - 1) * 7
            } else {
                let length = calendar.range(of: .day, in: .month, for: first)!.count
                while day + 7 <= length { day += 7 }
            }
            start = String(format: "1970%02d%02dT%02d%02d%02d", c.month!, day, c.hour!, c.minute!, c.second!)
        }
        var properties = [
            Property(name: "DTSTART", params: [:], value: start),
            Property(name: "TZOFFSETFROM", params: [:], value: offset(from)),
            Property(name: "TZOFFSETTO", params: [:], value: offset(to)),
        ]
        if let rule { properties.append(rule) }
        if let abbreviation = zone.abbreviation(for: transition) {
            properties.append(Property(name: "TZNAME", params: [:], value: abbreviation))
        }
        return Component(name: name, properties: properties)
    }

    /// `+0900`, `-0430`.
    private static func offset(_ seconds: Int) -> String {
        String(format: "%@%02d%02d", seconds < 0 ? "-" : "+", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
    }
}

extension ICalendar.Component {
    /// Puts `property` where the first one of its name was (or at the end), dropping the others;
    /// nil removes them all.
    mutating func set(_ name: String, _ property: ICalendar.Property?) {
        let index = properties.firstIndex { $0.name == name }
        properties.removeAll { $0.name == name }
        guard let property else { return }
        properties.insert(property, at: min(index ?? properties.count, properties.count))
    }

    mutating func remove(_ name: String) {
        properties.removeAll { $0.name == name }
    }
}
