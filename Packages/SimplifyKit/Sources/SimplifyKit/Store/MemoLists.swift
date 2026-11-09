import Foundation

/// Lists and quotes in a memo: letters at the front of a line that the memo draws its own way. A
/// list item is any number of tabs (its level) and a marker: `• ` (bullet), `- ` (dash), or a
/// number (`1. `, `a. ` one level in, `i. ` two levels in, then figures, letters and roman figures
/// again every three levels); a quote is `> `, and a list item can sit in a
/// quote (`> • `, `> \t1. `). The letters are what is stored, synced and mirrored to Notes; the
/// editor only draws them with a hanging indent.
///
/// The editing rules (Return, Tab, Delete, the 서식 menu) work on the memo's plain letters and
/// give back the edits to make, so the editor can make them as typing would. Offsets and ranges
/// are in UTF-16 units, as the text view counts them.
public enum MemoLists {
    public enum Kind: Hashable, Sendable {
        case bullet, dash, number, quote
    }

    /// The front of a list or quote line.
    public struct Marker: Equatable, Sendable {
        /// `.quote` for a quote line with no list item in it.
        public var kind: Kind
        /// How many tabs come before the marker, from 0; there is no deepest level.
        public var level: Int
        /// The marker's letters (`•`, `-`, `12.`, `b.`, `>`), without the tabs or the space after.
        public var label: String
        /// Quote, tabs, label and the space after it, in UTF-16 units: where the item's words start.
        public var length: Int
        /// A number item's place (`b.` is 2, `iv.` is 4).
        public var number: Int?
        /// A list item inside a quote: the line starts with `> `.
        public var quoted = false
        /// Tabs that belong to a timeline line above, not to the list: 1 for a list in a timeline
        /// line's child (`MemoTimeline.isChild`), whose levels count from there.
        public var offset = 0

        public init(kind: Kind, level: Int, label: String, length: Int, number: Int?, quoted: Bool = false, offset: Int = 0) {
            self.kind = kind
            self.level = level
            self.label = label
            self.length = length
            self.number = number
            self.quoted = quoted
            self.offset = offset
        }

        /// The level the list's labels and bullets go by: its tabs past the timeline line's.
        public var labelLevel: Int { level - offset }

        /// The line is in a quote, with or without a list item.
        public var isQuoted: Bool { kind == .quote || quoted }
        /// Where the label starts in the line: after the quote and the tabs.
        public var labelOffset: Int { (quoted ? 2 : 0) + level }
    }

    /// One change to the letters: `range` (in the text as it is when this edit is made) becomes `text`.
    public struct Edit: Equatable, Sendable {
        public var range: NSRange
        public var text: String

        public init(range: NSRange, text: String) {
            self.range = range
            self.text = text
        }
    }

    /// Edits to make one after another, and the selection after the last.
    public struct Change: Equatable, Sendable {
        public var edits: [Edit]
        public var selection: NSRange

        public init(edits: [Edit], selection: NSRange) {
            self.edits = edits
            self.selection = selection
        }
    }

    /// An invisible letter (U+2060, word joiner) at the front of a line (after its leading tabs),
    /// or just after a quote's `> `: what was typed there stays plain words. A list or quote made as a space is typed
    /// (`autoFormat`) is first put in with it, and taken out as an undo step of its own, so ⌘Z
    /// right after leaves the letters and takes the formatting away. A build or app that does not
    /// know it sees a line that does not start with a marker either. Left out of copies.
    public static let plainMark = "\u{2060}"

    /// Levels look alike every three (bullets `●○■`, numbers `1. a. i.`), however deep a list goes.
    public static let levelCycle = 3
    /// Each level's indent, in points.
    public static let levelIndent: CGFloat = 22

    // MARK: Reading lines

    /// `offset`: tabs at the line's front that belong to a timeline line above (`Marker.offset`).
    /// A line starting with `plainMark` has none; after a quote's `> ` it leaves the quote alone.
    public static func marker<S: StringProtocol>(_ line: S, offset: Int = 0) -> Marker? {
        let line = String(line)
        guard !line.hasPrefix(plainMark) else { return nil }
        guard line.hasPrefix("> ") else { return listMarker(line, offset: offset) }
        let rest = String(line.dropFirst(2))
        guard !rest.hasPrefix(plainMark), var item = listMarker(rest, offset: 0) else { return Marker(kind: .quote, level: 0, label: ">", length: 2, number: nil) }
        item.quoted = true
        item.length += 2
        return item
    }

    /// The marker of `line` (its letters without the line break) in `string`, a timeline line's
    /// child counting its levels from the timeline line.
    public static func marker(in string: NSString, line: NSRange) -> Marker? {
        marker(string.substring(with: line), offset: MemoTimeline.isChild(line, in: string) ? 1 : 0)
    }

    /// A list item's marker at the front of `line`, no quote.
    private static func listMarker(_ line: String, offset: Int) -> Marker? {
        let letters = Array(line.utf16)
        var level = 0
        while level < letters.count, letters[level] == 0x09 { level += 1 }
        let offset = min(offset, level)
        let rest = String(utf16CodeUnits: Array(letters[level...]), count: letters.count - level)
        // Left plain with ⌘Z (`plainMark` after the tabs).
        if rest.hasPrefix(plainMark) { return nil }
        if rest.hasPrefix("• ") { return Marker(kind: .bullet, level: level, label: "•", length: level + 2, number: nil, offset: offset) }
        if rest.hasPrefix("- ") { return Marker(kind: .dash, level: level, label: "-", length: level + 2, number: nil, offset: offset) }
        // `12. `, `b. `, `iv. `: letters up to a full stop and a space.
        guard let stop = rest.firstIndex(of: "."), rest[rest.index(after: stop)...].hasPrefix(" ") else { return nil }
        let label = String(rest[..<stop])
        guard !label.isEmpty, label.count <= ((level - offset) % levelCycle == 0 ? 3 : 4), let number = number(of: label, level: level - offset) else { return nil }
        // `11. 4. 회의` is a date, not item 11; `1. 3.5%` is an item.
        let words = rest[rest.index(stop, offsetBy: 2)...]
        let figures = words.prefix { $0.isASCII && $0.isNumber }
        if !figures.isEmpty, words.dropFirst(figures.count).hasPrefix(".") {
            let after = words.dropFirst(figures.count + 1)
            if after.isEmpty || after.hasPrefix(" ") { return nil }
        }
        return Marker(kind: .number, level: level, label: label + ".", length: level + label.utf16.count + 2, number: number, offset: offset)
    }

    /// A number label's place. Figures count at every level; letters only one level in (four,
    /// seven …) and roman figures only two (five, eight …), so `a. ` at the front of a plain line stays words.
    static func number(of label: String, level: Int) -> Int? {
        if label.allSatisfy({ $0.isASCII && $0.isNumber }) { return Int(label) }
        switch level % levelCycle {
        case 1: return alphabetic(label)
        case 2: return roman(label)
        default: return nil
        }
    }

    /// `1.`, `a.`, `i.` for the item's level, again from `1.` every three levels.
    public static func label(_ number: Int, level: Int) -> String {
        switch level % levelCycle {
        case 1: alphabetic(number) + "."
        case 2: roman(number) + "."
        default: "\(number)."
        }
    }

    /// What a marker looks like on screen: bullets `●` `○` `■` by level, again every three levels
    /// (drawn small, but larger than a `•` would be), a dash `–`; numbers and quotes as stored.
    /// Always as many UTF-16 units as the stored letter.
    public static func shownLabel(_ marker: Marker) -> String {
        switch marker.kind {
        case .bullet: ["●", "○", "■"][marker.labelLevel % levelCycle]
        case .dash: "–"
        case .number, .quote: marker.label
        }
    }

    /// The letters a new item of `kind` starts with at `level`, after `> ` in a quote.
    static func prefix(_ kind: Kind, level: Int, number: Int = 1, quoted: Bool = false, offset: Int = 0) -> String {
        (quoted && kind != .quote ? "> " : "") + listPrefix(kind, level: level, number: number, offset: min(offset, level))
    }

    private static func listPrefix(_ kind: Kind, level: Int, number: Int, offset: Int) -> String {
        switch kind {
        case .bullet: String(repeating: "\t", count: level) + "• "
        case .dash: String(repeating: "\t", count: level) + "- "
        case .number: String(repeating: "\t", count: level) + label(number, level: level - offset) + " "
        case .quote: "> "
        }
    }

    // MARK: Typing

    /// A space about to be typed at `caret` that makes its line a list item or a quote (`1. `,
    /// `- `, `> `, a list item in a quote): where `plainMark` goes in with it, the line's front or
    /// just after the quote's `> `. Nil where the space changes nothing, or the line was a list
    /// item already.
    public static func autoFormat(in text: String, caret: Int) -> Int? {
        let string = text as NSString
        guard caret <= string.length else { return nil }
        let line = lineContent(of: string.lineRange(for: NSRange(location: caret, length: 0)), in: string)
        guard caret > line.location else { return nil }
        let before = marker(in: string, line: line)
        // The line alone with the space in, not the whole memo, on every space typed.
        let letters = string.substring(with: line) as NSString
        let spaced = letters.replacingCharacters(in: NSRange(location: caret - line.location, length: 0), with: " ")
        let offset = MemoTimeline.isChild(line, in: string) ? 1 : 0
        // The space just typed is the marker's last letter.
        guard let after = marker(spaced, offset: offset), after.length == caret - line.location + 1 else { return nil }
        // After a line's leading tabs, which keep a timeline line's child its own.
        let tabs = string.substring(with: line).utf16.prefix { $0 == 0x09 }.count
        if before == nil { return line.location + tabs }
        if before?.kind == .quote, after.quoted, after.kind != .quote { return line.location + 2 }
        return nil
    }

    /// Where a line's `plainMark` is, if it has one: at its front after any leading tabs, or
    /// (`inQuote`) just after a quote's `> `.
    public static func plainMarkRange(of line: NSRange, in string: NSString, inQuote: Bool = true) -> NSRange? {
        let letters = string.substring(with: line)
        let mark = (plainMark as NSString).length
        let tabs = letters.utf16.prefix { $0 == 0x09 }.count
        if String(letters.dropFirst(tabs)).hasPrefix(plainMark) { return NSRange(location: line.location + tabs, length: mark) }
        if inQuote, letters.hasPrefix("> " + plainMark) { return NSRange(location: line.location + 2, length: mark) }
        return nil
    }

    /// The letters without `plainMark`, for copies.
    public static func withoutPlainMarks(_ letters: String) -> String {
        letters.replacingOccurrences(of: plainMark, with: "")
    }

    /// A space just typed after `*` at the front of a line (tabs before it are fine): the star
    /// becomes a stored bullet. `caret` is after the space. Made after the space went in, so ⌘Z
    /// takes the bullet back to the star.
    public static func autoBullet(in text: String, caret: Int) -> Change? {
        let string = text as NSString
        guard caret >= 2, caret <= string.length else { return nil }
        let line = string.lineRange(for: NSRange(location: caret, length: 0))
        var typed = string.substring(with: NSRange(location: line.location, length: caret - line.location))
        // In a quote too.
        if typed.hasPrefix("> ") { typed.removeFirst(2) }
        guard typed.hasSuffix("* "), typed.dropLast(2).allSatisfy({ $0 == "\t" }) else { return nil }
        return Change(edits: [Edit(range: NSRange(location: caret - 2, length: 1), text: "•")], selection: NSRange(location: caret, length: 0))
    }

    /// Return at `caret` on a list or quote line, past its marker: the next item of the same kind
    /// (a number one up) with the words after the caret; on an empty item, one level out, or a
    /// plain line at the outermost level. Nil where Return is an ordinary line break.
    public static func returnKey(in text: String, caret: Int) -> Change? {
        let string = text as NSString
        guard caret <= string.length else { return nil }
        let line = lineContent(of: string.lineRange(for: NSRange(location: caret, length: 0)), in: string)
        guard let marker = marker(in: string, line: line) else { return childReturn(in: string, line: line, caret: caret) }
        guard caret >= line.location + marker.length else { return nil }
        let words = string.substring(with: NSRange(location: line.location + marker.length, length: line.length - marker.length))
        var builder = Builder(string, selection: NSRange(location: caret, length: 0))
        if words.allSatisfy(\.isWhitespace) {
            if marker.offset > 0, marker.level <= marker.offset {
                // The list ends; the timeline line's child goes on.
                builder.replace(NSRange(location: line.location, length: marker.length), with: String(repeating: "\t", count: marker.offset))
            } else if marker.level > 0, marker.kind != .quote {
                builder.replace(NSRange(location: line.location, length: marker.length),
                                with: prefix(marker.kind, level: marker.level - 1, quoted: marker.quoted, offset: marker.offset))
            } else if marker.quoted {
                // The list ends; the quote goes on.
                builder.replace(NSRange(location: line.location, length: marker.length), with: "> ")
            } else {
                builder.replace(NSRange(location: line.location, length: line.length), with: "")
            }
        } else {
            let next = prefix(marker.kind, level: marker.level, number: (marker.number ?? 0) + 1, quoted: marker.quoted, offset: marker.offset)
            builder.replace(NSRange(location: caret, length: 0), with: "\n" + next)
            // The caret after the new marker, not before it.
            builder.selection = NSRange(location: caret + 1 + next.utf16.count, length: 0)
        }
        builder.renumber(around: line.location)
        return builder.change
    }

    /// Return on a timeline line's child with no list in it: the next line is a child too, at the
    /// same tabs; on an empty one, the children end and it becomes a plain empty line.
    private static func childReturn(in string: NSString, line: NSRange, caret: Int) -> Change? {
        guard MemoTimeline.isChild(line, in: string) else { return nil }
        let letters = string.substring(with: line)
        let tabs = String(letters.prefix { $0 == "\t" })
        let tabCount = (tabs as NSString).length
        guard caret >= line.location + tabCount else { return nil }
        var builder = Builder(string, selection: NSRange(location: caret, length: 0))
        if letters.allSatisfy({ $0 == "\t" || $0 == " " }) {
            builder.replace(line, with: "")
            builder.selection = NSRange(location: line.location, length: 0)
        } else {
            builder.replace(NSRange(location: caret, length: 0), with: "\n" + tabs)
            builder.selection = NSRange(location: caret + 1 + tabCount, length: 0)
        }
        return builder.change
    }

    /// Delete with the caret just after an item's marker: the marker goes (tabs too) and the words
    /// stay as a plain line, or a quote line in a quote. Nil anywhere else.
    public static func deleteBackward(in text: String, caret: Int) -> Change? {
        let string = text as NSString
        guard caret <= string.length else { return nil }
        let line = lineContent(of: string.lineRange(for: NSRange(location: caret, length: 0)), in: string)
        guard let marker = marker(in: string, line: line), caret == line.location + marker.length else { return nil }
        var builder = Builder(string, selection: NSRange(location: caret, length: 0))
        // In a timeline line's child, the words stay in it.
        builder.replace(NSRange(location: line.location, length: marker.length),
                        with: marker.quoted ? "> " : String(repeating: "\t", count: marker.offset))
        builder.renumber(around: line.location)
        return builder.change
    }

    /// Tab and ⇧Tab (`by` 1 or -1) on list items: every item the selection touches moves a level
    /// in or out, numbers following. `listsOnly` false (⌘] and ⌘[) moves plain lines too, by a
    /// leading tab. Nil when no line the selection touches can move, so Tab types a tab there.
    public static func indent(in text: String, selection: NSRange, by step: Int, listsOnly: Bool = true) -> Change? {
        let string = text as NSString
        var builder = Builder(string, selection: selection)
        var moved = false
        // Bottom to top, so the lines above keep their offsets.
        for line in lines(touching: selection, in: string).reversed() {
            let letters = string.substring(with: line)
            if let marker = marker(in: string, line: line) {
                guard marker.kind != .quote else { continue }
                let level = marker.level + step
                // Not out of a timeline line's child: its first tab is the child's.
                guard level >= marker.offset else { continue }
                // Numbers take the new level's letters; renumbering below sets their place.
                builder.replace(NSRange(location: line.location, length: marker.length),
                                with: prefix(marker.kind, level: level, number: marker.number ?? 1, quoted: marker.quoted, offset: marker.offset))
                moved = true
            } else if !listsOnly {
                let tabs = letters.prefix { $0 == "\t" }.count
                if step > 0 {
                    builder.replace(NSRange(location: line.location, length: 0), with: "\t")
                    moved = true
                } else if step < 0, tabs > 0 {
                    builder.replace(NSRange(location: line.location, length: 1), with: "")
                    moved = true
                }
            }
        }
        guard moved else { return nil }
        builder.renumber(touching: builder.selection)
        return builder.change
    }

    /// The 서식 menu's list and quote items: every line the selection touches becomes `kind`
    /// (keeping its level), or, when they all are already, plain lines again. A quote goes on or
    /// off around a line's list item, and a list item on or off inside a quote. Blank lines in a
    /// longer selection are left alone.
    /// A line a ⌘Z left plain (`plainMark`) is made `kind` too: the mark goes first (for a quote,
    /// only one at the line's front, so a list left plain in a quote stays plain).
    public static func setKind(_ kind: Kind, in text: String, selection: NSRange) -> Change {
        let original = text as NSString
        func targets(in string: NSString, _ selection: NSRange) -> [NSRange] {
            var targets = lines(touching: selection, in: string)
            if targets.count > 1 {
                // A line holding only a plain mark is blank too, before and after the mark goes.
                let filled = targets.filter { !withoutPlainMarks(string.substring(with: $0)).allSatisfy(\.isWhitespace) }
                if !filled.isEmpty { targets = filled }
            }
            return targets
        }
        // Whether it goes on or off is judged by the lines as they show, marks and all.
        let shown = targets(in: original, selection).map { marker(in: original, line: $0) }
        var builder = Builder(original, selection: selection)
        for line in targets(in: original, selection).reversed() {
            if let mark = plainMarkRange(of: line, in: original, inQuote: kind != .quote) { builder.replace(mark, with: "") }
        }
        let string = NSString(string: builder.string)
        let targets = targets(in: string, builder.selection)
        let markers = targets.map { marker(in: string, line: $0) }
        if kind == .quote {
            let isOff = shown.allSatisfy { $0?.isQuoted == true }
            for (line, marker) in zip(targets, markers).reversed() where (marker?.isQuoted == true) == isOff {
                builder.replace(NSRange(location: line.location, length: isOff ? 2 : 0), with: isOff ? "" : "> ")
            }
        } else {
            let isOff = shown.allSatisfy { $0?.kind == kind }
            for (line, marker) in zip(targets, markers).reversed() {
                let quote = marker?.isQuoted == true ? 2 : 0
                let isItem = marker.map { $0.kind != .quote } ?? false
                if isOff {
                    // A timeline line's child stays one.
                    builder.replace(NSRange(location: line.location + quote, length: marker!.length - quote),
                                    with: String(repeating: "\t", count: marker!.offset))
                } else {
                    // A plain line's own leading tabs become its level.
                    let rest = string.substring(with: NSRange(location: line.location + quote, length: line.length - quote))
                    let tabs = isItem ? marker!.level : rest.prefix { $0 == "\t" }.count
                    let old = NSRange(location: line.location + quote, length: isItem ? marker!.length - quote : tabs)
                    let offset = quote == 0 && MemoTimeline.isChild(line, in: string) ? 1 : 0
                    builder.replace(old, with: prefix(kind, level: tabs, number: 1, offset: offset))
                }
            }
        }
        builder.renumber(touching: builder.selection)
        return builder.change
    }

    /// The marker of the line `location` is on, for the 문단 bar and the menus.
    public static func marker(in text: String, at location: Int) -> Marker? {
        let string = text as NSString
        guard location <= string.length else { return nil }
        let line = lineContent(of: string.lineRange(for: NSRange(location: location, length: 0)), in: string)
        return marker(in: string, line: line)
    }

    // MARK: Numbering

    /// Edits that number every list the lines in `range` belong to: each run of number items at
    /// one level counts up from its first item's place, starting again under a new parent item.
    public static func renumber(in text: String, range: NSRange) -> [Edit] {
        let string = text as NSString
        var builder = Builder(string, selection: NSRange(location: 0, length: 0))
        builder.renumber(touching: range)
        return builder.change.edits
    }

    // MARK: Helpers

    /// A line's range without its line break.
    public static func lineContent(of line: NSRange, in string: NSString) -> NSRange {
        var length = line.length
        while length > 0, [0x0A, 0x0D, 0x2028, 0x2029].contains(string.character(at: line.location + length - 1)) { length -= 1 }
        return NSRange(location: line.location, length: length)
    }

    /// Every line `selection` touches, without line breaks. A selection ending just after a line
    /// break stays off the next line.
    static func lines(touching selection: NSRange, in string: NSString) -> [NSRange] {
        var result: [NSRange] = []
        var location = selection.location
        let end = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
        repeat {
            let line = string.lineRange(for: NSRange(location: min(location, string.length), length: 0))
            result.append(lineContent(of: line, in: string))
            location = NSMaxRange(line)
        } while location <= end && location < string.length
        return result
    }

    /// Makes edits on a copy of the letters, keeping the selection where the words are.
    struct Builder {
        var string: NSMutableString
        var selection: NSRange
        var edits: [Edit] = []

        init(_ string: NSString, selection: NSRange) {
            self.string = NSMutableString(string: string)
            self.selection = selection
        }

        var change: Change { Change(edits: edits, selection: selection) }

        mutating func replace(_ range: NSRange, with text: String) {
            guard string.substring(with: range) != text else { return }
            edits.append(Edit(range: range, text: text))
            string.replaceCharacters(in: range, with: text)
            let delta = (text as NSString).length - range.length
            func moved(_ location: Int) -> Int {
                if location >= NSMaxRange(range) { return location + delta }
                if location > range.location { return min(location, range.location + (text as NSString).length) }
                return location
            }
            let start = moved(selection.location)
            selection = NSRange(location: start, length: max(0, moved(NSMaxRange(selection)) - start))
        }

        mutating func renumber(around location: Int) {
            renumber(touching: NSRange(location: min(location, string.length), length: 0))
        }

        /// Numbers the lists the lines in `range` belong to, line by line from each list's top.
        mutating func renumber(touching range: NSRange) {
            let range = NSRange(location: min(range.location, string.length), length: min(range.length, string.length - min(range.location, string.length)))
            var lines = MemoLists.lines(touching: range, in: string)
            // Out to the whole run of list lines around them.
            while let first = lines.first, first.location > 0 {
                let above = MemoLists.lineContent(of: string.lineRange(for: NSRange(location: first.location - 1, length: 0)), in: string)
                guard MemoLists.marker(in: string, line: above).map({ $0.kind != .quote }) == true else { break }
                lines.insert(above, at: 0)
            }
            var next = lines.last.map { NSMaxRange(string.lineRange(for: $0)) } ?? string.length
            while next < string.length {
                let below = MemoLists.lineContent(of: string.lineRange(for: NSRange(location: next, length: 0)), in: string)
                guard MemoLists.marker(in: string, line: below).map({ $0.kind != .quote }) == true else { break }
                lines.append(below)
                next = NSMaxRange(string.lineRange(for: below))
            }
            // Top to bottom, finding each line again after the edits above it.
            var location = lines.first?.location ?? 0
            // Each level's count so far; grown as deeper levels come.
            var counts: [Int?] = []
            // A quote above starts a list as a plain line does.
            var startsBlock = location == 0 || MemoLists.marker(string.substring(with: MemoLists.lineContent(
                of: string.lineRange(for: NSRange(location: location - 1, length: 0)), in: string))).map { $0.kind == .quote } ?? true
            var quoted: Bool?
            for _ in lines {
                let line = MemoLists.lineContent(of: string.lineRange(for: NSRange(location: location, length: 0)), in: string)
                if let marker = MemoLists.marker(in: string, line: line), marker.kind != .quote {
                    // Items in a quote and items out of it are two lists.
                    if let quoted, quoted != marker.quoted {
                        counts = counts.map { _ in nil }
                        startsBlock = true
                    }
                    quoted = marker.quoted
                    if counts.count <= marker.level { counts += Array(repeating: nil, count: marker.level + 1 - counts.count) }
                    for deeper in (marker.level + 1)..<counts.count { counts[deeper] = nil }
                    if marker.kind == .number {
                        // A list's first item keeps the place it was typed with (`3. `), as in
                        // Markdown; a list under an item, or after a bullet, counts from one.
                        let number = counts[marker.level].map { $0 + 1 } ?? (startsBlock && marker.labelLevel == 0 ? marker.number ?? 1 : 1)
                        counts[marker.level] = number
                        replace(NSRange(location: line.location + marker.labelOffset, length: (marker.label as NSString).length),
                                with: MemoLists.label(number, level: marker.labelLevel))
                    } else {
                        // A bullet between numbers starts the count again.
                        counts[marker.level] = nil
                    }
                    startsBlock = false
                } else {
                    counts = counts.map { _ in nil }
                    startsBlock = true
                    quoted = nil
                }
                location = NSMaxRange(string.lineRange(for: NSRange(location: location, length: 0)))
                guard location < string.length else { break }
            }
        }
    }

    // MARK: Letters and roman figures

    static func alphabetic(_ number: Int) -> String {
        var number = max(1, number)
        var letters = ""
        while number > 0 {
            number -= 1
            letters = String(UnicodeScalar(UInt8(97 + number % 26))) + letters
            number /= 26
        }
        return letters
    }

    static func alphabetic(_ label: String) -> Int? {
        guard label.allSatisfy({ ("a"..."z").contains($0) }) else { return nil }
        return label.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 96 }
    }

    private static let romans: [(Int, String)] = [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
                                                  (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]

    static func roman(_ number: Int) -> String {
        var number = max(1, number)
        var letters = ""
        for (value, figure) in romans {
            while number >= value {
                letters += figure
                number -= value
            }
        }
        return letters
    }

    static func roman(_ label: String) -> Int? {
        var rest = Substring(label)
        var total = 0
        for (value, figure) in romans {
            while rest.hasPrefix(figure) {
                total += value
                rest = rest.dropFirst(figure.count)
            }
        }
        // Only the usual way of writing it: `iiii` and `vx` are words.
        return rest.isEmpty && total > 0 && roman(total) == label ? total : nil
    }
}
