import Foundation

/// Reads iCalendar text (RFC 5545): the VEVENTs of one CalDAV resource.
public enum ICalendar {
    struct Property {
        var name: String
        var params: [String: String]
        var value: String
        /// The line as it was read (unfolded), written back unchanged when the property is kept.
        var raw: String? = nil
    }

    struct Component {
        var name: String
        var properties: [Property] = []
        var children: [Component] = []

        func first(_ name: String) -> Property? { properties.first { $0.name == name } }
        func all(_ name: String) -> [Property] { properties.filter { $0.name == name } }
    }

    /// The events of one resource: a single event, or a series with its changed occurrences.
    ///
    /// - Parameters:
    ///   - href: The resource they came in, so a later change or deletion replaces them all.
    ///   - calendar: The person's calendar, for times that name no zone when the calendar has none.
    ///   - defaultZone: The calendar collection's zone, for floating times.
    public static func events(in text: String, sourceID: String, href: String, calendar: Calendar, defaultZone: String? = nil) -> [EventSnapshot] {
        let floating = floating(calendar: calendar, defaultZone: defaultZone)
        return parse(text)
            .flatMap { $0.name == "VCALENDAR" ? $0.children : [$0] }
            .filter { $0.name == "VEVENT" }
            .compactMap { event(from: $0, sourceID: sourceID, href: href, floating: floating) }
    }

    /// How times without a zone are read: in the calendar collection's zone when it has one
    /// (and then the event repeats in that zone), otherwise in the person's own.
    struct Floating {
        var calendar: Calendar
        var zone: String?
    }

    static func floating(calendar: Calendar, defaultZone: String?) -> Floating {
        var floating = Floating(calendar: calendar, zone: nil)
        if let defaultZone, let zone = TimeZone(identifier: defaultZone) {
            floating.calendar.timeZone = zone
            floating.zone = defaultZone
        }
        return floating
    }

    private static func event(from component: Component, sourceID: String, href: String, floating: Floating) -> EventSnapshot? {
        guard let uid = component.first("UID")?.value, !uid.isEmpty,
              let startProperty = component.first("DTSTART"), let start = moment(startProperty, floating: floating) else { return nil }
        let summary = component.first("SUMMARY").map { unescape($0.value) } ?? ""
        var event = EventSnapshot(id: sourceID + ":" + uid, sourceID: sourceID, remoteID: uid,
                                  title: summary.isEmpty ? "(제목 없음)" : summary, isAllDay: start.isDay)
        event.resourceHref = href
        event.location = component.first("LOCATION").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 }
        event.notes = component.first("DESCRIPTION").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 }
        event.isCancelled = component.first("STATUS")?.value.uppercased() == "CANCELLED"

        let end = component.first("DTEND").flatMap { moment($0, floating: floating) }
        let duration = component.first("DURATION").flatMap { parseDuration($0.value) }
        switch start {
        case .day(let key, let date):
            event.startDay = key
            if case .day(let endKey, _)? = end {
                event.endDay = endKey
            } else if let duration, duration.days > 0,
                      let last = DayKey.utc.date(byAdding: .day, value: duration.days, to: date) {
                event.endDay = DayKey.key(last, calendar: DayKey.utc)
            }
        case .instant(let date, let zone):
            event.start = date
            event.timeZone = zone
            if case .instant(let endDate, _)? = end {
                event.end = endDate
            } else if let duration {
                var zoned = floating.calendar
                if let zone, let tz = TimeZone(identifier: zone) { zoned.timeZone = tz }
                event.end = zoned.date(byAdding: .day, value: duration.days, to: date)?.addingTimeInterval(duration.seconds)
            } else {
                event.end = date
            }
        }

        if let recurrenceID = component.first("RECURRENCE-ID") {
            // A changed (or cancelled) occurrence of the series with the same UID.
            event.id += "@" + recurrenceID.value
            event.recurringEventID = uid
            switch moment(recurrenceID, floating: floating) {
            case .day(let key, _)?: event.originalStartDay = key
            case .instant(let date, _)?: event.originalStart = date
            case nil: return nil
            }
            return event
        }

        let rules = component.all("RRULE")
        let extraDates = component.all("RDATE")
        guard !rules.isEmpty || !extraDates.isEmpty else { return event }
        // Timed series repeat in their own zone; all-day ones by calendar day, read in UTC.
        var zoned = start.isDay ? DayKey.utc : floating.calendar
        if case .instant(_, let zone?) = start, let tz = TimeZone(identifier: zone) { zoned.timeZone = tz }
        // Several rules, extra dates, or a rule the engine does not cover: the server expands it instead.
        if rules.count == 1, extraDates.isEmpty, let rule = Recurrence(rrule: rules[0].value, calendar: zoned) {
            event.recurrence = rule
        } else {
            event.recurrenceUnsupported = true
        }
        let exdates = component.all("EXDATE").map { property in
            let zone = property.params["TZID"].flatMap(timeZoneID)
            return "EXDATE" + (zone.map { ";TZID=" + $0 } ?? "") + ":" + property.value
        }
        event.exceptionDates = Recurrence.exceptionDates(from: exdates, calendar: zoned)
        return event
    }

    // MARK: - Times

    enum Moment {
        /// A date-only value: `2026-10-26`, and that day's start in UTC.
        case day(String, Date)
        /// A date-time, with the IANA zone it was given in (`UTC` for `Z`; floating times get the
        /// collection's zone, or nil when it has none).
        case instant(Date, zone: String?)

        var isDay: Bool { if case .day = self { true } else { false } }
    }

    static func moment(_ property: Property, floating: Floating) -> Moment? {
        let value = property.value.trimmingCharacters(in: .whitespaces)
        if property.params["VALUE"]?.uppercased() == "DATE" || value.count == 8 {
            guard value.count == 8, let date = Recurrence.parseDateTime(value, calendar: DayKey.utc) else { return nil }
            return .day(DayKey.key(date, calendar: DayKey.utc), date)
        }
        var calendar = floating.calendar
        var zone = floating.zone
        if value.hasSuffix("Z") {
            zone = "UTC"
        } else if let tzid = property.params["TZID"], let id = timeZoneID(tzid), let tz = TimeZone(identifier: id) {
            calendar.timeZone = tz
            zone = id
        }
        guard let date = Recurrence.parseDateTime(value, calendar: calendar) else { return nil }
        return .instant(date, zone: zone)
    }

    /// An IANA zone id for a TZID: IANA ids as they are, Outlook's Windows names
    /// (`Korea Standard Time`), and prefixed ids (`/mozilla.org/20050126_1/Asia/Seoul`).
    static func timeZoneID(_ tzid: String) -> String? {
        let tzid = tzid.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        if TimeZone(identifier: tzid) != nil { return tzid }
        if let mapped = windowsZones[tzid] { return mapped }
        let parts = tzid.split(separator: "/")
        for count in [3, 2] where parts.count > count {
            let tail = parts.suffix(count).joined(separator: "/")
            if TimeZone(identifier: tail) != nil { return tail }
        }
        return nil
    }

    private static let windowsZones = [
        "Korea Standard Time": "Asia/Seoul", "Tokyo Standard Time": "Asia/Tokyo",
        "China Standard Time": "Asia/Shanghai", "Taipei Standard Time": "Asia/Taipei",
        "Singapore Standard Time": "Asia/Singapore", "India Standard Time": "Asia/Kolkata",
        "AUS Eastern Standard Time": "Australia/Sydney", "Hawaiian Standard Time": "Pacific/Honolulu",
        "Alaskan Standard Time": "America/Anchorage", "Pacific Standard Time": "America/Los_Angeles",
        "Mountain Standard Time": "America/Denver", "Central Standard Time": "America/Chicago",
        "Eastern Standard Time": "America/New_York", "GMT Standard Time": "Europe/London",
        "W. Europe Standard Time": "Europe/Berlin", "Romance Standard Time": "Europe/Paris",
        "Central European Standard Time": "Europe/Warsaw", "UTC": "UTC",
    ]

    /// `P1D`, `PT1H30M`, `P2W`: whole days apart from the rest, so a day stays a calendar day across DST.
    static func parseDuration(_ text: String) -> (days: Int, seconds: TimeInterval)? {
        var rest = Substring(text.uppercased())
        let sign = rest.hasPrefix("-") ? -1 : 1
        if rest.first == "-" || rest.first == "+" { rest = rest.dropFirst() }
        guard rest.hasPrefix("P") else { return nil }
        rest = rest.dropFirst()
        var days = 0
        var seconds: TimeInterval = 0
        var number = ""
        var inTime = false
        for char in rest {
            switch char {
            case "0"..."9": number.append(char)
            case "T": inTime = true
            case "W", "D", "H", "M", "S":
                guard let n = Int(number) else { return nil }
                number = ""
                switch (char, inTime) {
                case ("W", _): days += n * 7
                case ("D", _): days += n
                case ("H", true): seconds += Double(n) * 3600
                case ("M", true): seconds += Double(n) * 60
                case ("S", true): seconds += Double(n)
                default: return nil
                }
            default: return nil
            }
        }
        return (days * sign, seconds * Double(sign))
    }

    // MARK: - Text

    /// Components nested as they appear (`VCALENDAR` › `VEVENT` › `VALARM`).
    static func parse(_ text: String) -> [Component] {
        var stack: [Component] = []
        var top: [Component] = []
        for line in unfold(text) {
            guard let property = parseLine(line) else { continue }
            switch property.name {
            case "BEGIN":
                stack.append(Component(name: property.value.uppercased()))
            case "END":
                guard let done = stack.popLast() else { continue }
                if stack.isEmpty { top.append(done) } else { stack[stack.count - 1].children.append(done) }
            default:
                if !stack.isEmpty { stack[stack.count - 1].properties.append(property) }
            }
        }
        return top
    }

    /// Joins continuation lines (a line starting with a space or tab continues the one before).
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(String(raw))
            }
        }
        return lines
    }

    /// `DTSTART;TZID=Asia/Seoul:20261026T090000` → name, params, value. Quoted parameter values
    /// may hold `;` and `:`.
    static func parseLine(_ line: String) -> Property? {
        var inQuotes = false
        var segments: [String] = []
        var current = ""
        var value: String?
        for (offset, char) in line.enumerated() {
            if char == "\"" { inQuotes.toggle() }
            if !inQuotes, char == ":" {
                segments.append(current)
                value = String(line.dropFirst(offset + 1))
                break
            }
            if !inQuotes, char == ";" {
                segments.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        guard let value, let name = segments.first, !name.isEmpty else { return nil }
        var params: [String: String] = [:]
        for segment in segments.dropFirst() {
            let kv = segment.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        return Property(name: name.uppercased(), params: params, value: value, raw: line)
    }

    /// `\n`, `\,`, `\;`, `\\` in TEXT values.
    static func unescape(_ text: String) -> String {
        var result = ""
        var escaping = false
        for char in text {
            if escaping {
                result.append(char == "n" || char == "N" ? "\n" : char)
                escaping = false
            } else if char == "\\" {
                escaping = true
            } else {
                result.append(char)
            }
        }
        return result
    }
}
