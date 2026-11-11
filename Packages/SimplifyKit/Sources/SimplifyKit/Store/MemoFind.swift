import Foundation

/// Finding words in one memo (⌘F): where they are, which letters are left out, and what a
/// replacement may put in. Places are UTF-16 ranges, as the memo's text view counts.
public enum MemoFind {
    /// Every place `query` stands in `text`, front to back, without overlaps. Upper and lower case
    /// are one; Korean is matched letter for letter, so `회` finds `회의`. A ToDo chip's letters
    /// (its words belong to the ToDo list and are drawn again from it) and an attachment's
    /// placeholder are left out: a place that touches one does not count.
    public static func matches(of query: String, in text: AttributedString) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let string = String(text.characters) as NSString
        guard string.length > 0 else { return [] }
        let skipped = skippedRanges(in: text)
        var found: [NSRange] = []
        var start = 0
        while start < string.length {
            let hit = string.range(of: query, options: [.caseInsensitive], range: NSRange(location: start, length: string.length - start))
            guard hit.location != NSNotFound, hit.length > 0 else { break }
            if !skipped.contains(where: { NSIntersectionRange($0, hit).length > 0 }) { found.append(hit) }
            start = NSMaxRange(hit)
        }
        return found
    }

    /// The letters finding passes over: ToDo chips and attachments, as UTF-16 ranges.
    public static func skippedRanges(in text: AttributedString) -> [NSRange] {
        var ranges: [NSRange] = []
        var offset = 0
        for run in text.runs {
            let length = text[run.range].characters.reduce(0) { $0 + $1.utf16.count }
            if run[MemoAttributes.Todo.self] != nil || run[MemoAttributes.Attachment.self] != nil {
                if let last = ranges.last, NSMaxRange(last) == offset {
                    ranges[ranges.count - 1].length += length
                } else {
                    ranges.append(NSRange(location: offset, length: length))
                }
            }
            offset += length
        }
        return ranges
    }

    /// The place to show first: the first that starts at or after `caret`, else the first of all.
    public static func firstIndex(from caret: Int, in matches: [NSRange]) -> Int? {
        guard !matches.isEmpty else { return nil }
        return matches.firstIndex { $0.location >= caret } ?? 0
    }

    /// The next (`step` 1) or previous (-1) place from `index`, going round at either end.
    public static func step(_ index: Int?, by step: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let index else { return step < 0 ? count - 1 : 0 }
        return ((index + step) % count + count) % count
    }

    /// What a replacement puts in: in a table row, without the tabs that split its cells and
    /// without line breaks, so the row keeps its cells; elsewhere without line breaks too, since
    /// one place is within one line.
    public static func replacement(_ letters: String, inTable: Bool) -> String {
        String(letters.unicodeScalars.filter { scalar in
            !(scalar == "\n" || scalar == "\r" || scalar == "\u{2028}" || scalar == "\u{2029}" || (inTable && scalar == "\t"))
        }.map(Character.init))
    }

    /// The places that change when every one is replaced, back to front so each range is still
    /// where it was found when its turn comes.
    public static func replaceAllOrder(_ matches: [NSRange]) -> [NSRange] {
        matches.sorted { $0.location > $1.location }
    }
}
