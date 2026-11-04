import Foundation

/// Tables in a memo: one line a row, its cells split by tab letters, every row of one table
/// marked with the table's id (`MemoAttributes.Table`). The letters are what is stored, synced
/// and copied; the editor draws the rows on a grid.
///
/// The editing rules (Tab, Return, Delete, the right-click menu) work on the memo's plain letters
/// and the table's rows, and give back the edits to make, as `MemoLists` does. Offsets and ranges
/// are in UTF-16 units, as the text view counts them.
public enum MemoTables {
    /// What splits a row into cells.
    public static let separator = "\t"
    /// A table has at least two columns, so every row keeps a letter (a tab) to carry its mark.
    public static let leastColumns = 2

    // MARK: Reading rows

    /// The cells of a row's letters (no line break), left to right; a row with no tab is one cell.
    public static func cells(_ line: String) -> [String] {
        line.components(separatedBy: separator)
    }

    /// Each cell's letters in the text: `row` is the row's line without its break.
    public static func cellRanges(of row: NSRange, in string: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var start = row.location
        var at = row.location
        while at < NSMaxRange(row) {
            if string.character(at: at) == 0x09 {
                ranges.append(NSRange(location: start, length: at - start))
                start = at + 1
            }
            at += 1
        }
        ranges.append(NSRange(location: start, length: NSMaxRange(row) - start))
        return ranges
    }

    /// A cell that holds a number only (`1,200,000`, `-3.5`, `12%`, `₩4,600`): drawn against its right edge.
    public static func isNumber(_ cell: String) -> Bool {
        var letters = Substring(cell.trimmingCharacters(in: .whitespaces))
        guard !letters.isEmpty else { return false }
        if let first = letters.first, "+-−₩$€¥£".contains(first) { letters = letters.dropFirst() }
        if letters.last == "%" { letters = letters.dropLast() }
        guard let first = letters.first, first.isASCII, first.isNumber, let last = letters.last, last.isASCII, last.isNumber else { return false }
        return letters.allSatisfy { ($0.isASCII && $0.isNumber) || $0 == "," || $0 == "." }
    }

    /// Every row's letters from the first row's start to the last row's end, line breaks between included.
    public static func span(of rows: [NSRange]) -> NSRange {
        guard let first = rows.first, let last = rows.last else { return NSRange(location: 0, length: 0) }
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    /// The table's columns: its widest row's cells, at least `leastColumns`.
    public static func columnCount(of rows: [NSRange], in string: NSString) -> Int {
        max(leastColumns, rows.map { cellRanges(of: $0, in: string).count }.max() ?? 0)
    }

    /// The row and column the caret is in; nil outside the table's rows.
    public static func cell(at caret: Int, rows: [NSRange], in string: NSString) -> (row: Int, column: Int)? {
        guard let row = rows.firstIndex(where: { caret >= $0.location && caret <= NSMaxRange($0) }) else { return nil }
        let cells = cellRanges(of: rows[row], in: string)
        guard let column = cells.firstIndex(where: { caret <= NSMaxRange($0) }) else { return nil }
        return (row, column)
    }

    // MARK: Moving between cells

    /// Tab (⇧Tab with `backward`) in a cell: the caret to the end of the next (previous) cell's
    /// letters. Tab in the last cell makes a new row under it; ⇧Tab in the first cell stays.
    public static func tab(in text: String, rows: [NSRange], caret: Int, backward: Bool) -> MemoLists.Change? {
        let string = text as NSString
        guard let here = cell(at: caret, rows: rows, in: string) else { return nil }
        let columns = columnCount(of: rows, in: string)
        if backward {
            if here.column > 0 { return go(to: (here.row, here.column - 1), rows: rows, in: string) }
            guard here.row > 0 else { return MemoLists.Change(edits: [], selection: NSRange(location: caret, length: 0)) }
            return go(to: (here.row - 1, columns - 1), rows: rows, in: string)
        }
        if here.column + 1 < columns { return go(to: (here.row, here.column + 1), rows: rows, in: string) }
        if here.row + 1 < rows.count { return go(to: (here.row + 1, 0), rows: rows, in: string) }
        return insertRow(rows: rows, at: here.row, below: true, in: text)
    }

    /// Return in a cell: the caret to the same column of the next row. In the last row it leaves the
    /// table for the line under it: an empty one there, or a new one.
    public static func returnKey(in text: String, rows: [NSRange], caret: Int) -> MemoLists.Change? {
        let string = text as NSString
        guard let here = cell(at: caret, rows: rows, in: string), let last = rows.last else { return nil }
        if here.row + 1 < rows.count { return go(to: (here.row + 1, here.column), rows: rows, in: string) }
        let end = NSMaxRange(last)
        if end < string.length {
            let below = lineContent(at: end + 1, in: string)
            if below.length == 0 { return MemoLists.Change(edits: [], selection: NSRange(location: end + 1, length: 0)) }
        }
        return MemoLists.Change(edits: [MemoLists.Edit(range: NSRange(location: end, length: 0), text: "\n")],
                                selection: NSRange(location: end + 1, length: 0))
    }

    /// Delete with a caret, where it would take a table apart: at the front of a cell or row it does
    /// nothing, and at the front of the line under a table (with words on it) the caret goes to
    /// the table's last cell instead. `rows` is the caret's table, `above` the table ending on the
    /// line before the caret's. Nil where Delete deletes as usual.
    public static func deleteBackward(in text: String, rows: [NSRange]?, above: [NSRange]?, caret: Int) -> MemoLists.Change? {
        let string = text as NSString
        let stay = MemoLists.Change(edits: [], selection: NSRange(location: caret, length: 0))
        if let rows, let here = cell(at: caret, rows: rows, in: string) {
            let start = cellRanges(of: rows[here.row], in: string)[here.column].location
            // The front of a cell (its tab before) or of a row (the line break before).
            return caret == start && caret > 0 ? stay : nil
        }
        if let above, let last = above.last, caret == NSMaxRange(last) + 1 {
            // An empty line goes as usual; words stay on their own line.
            guard lineContent(at: caret, in: string).length > 0 else { return nil }
            return MemoLists.Change(edits: [], selection: NSRange(location: NSMaxRange(last), length: 0))
        }
        return nil
    }

    /// Forward delete at a cell's end, where it would join the next cell or row: it does nothing.
    /// Nil where it deletes as usual.
    public static func deleteForward(in text: String, rows: [NSRange], caret: Int) -> MemoLists.Change? {
        let string = text as NSString
        guard let here = cell(at: caret, rows: rows, in: string), caret < string.length else { return nil }
        let cell = cellRanges(of: rows[here.row], in: string)[here.column]
        return caret == NSMaxRange(cell) ? MemoLists.Change(edits: [], selection: NSRange(location: caret, length: 0)) : nil
    }

    /// The caret at the end of a cell's letters; a row short of cells gets tabs up to it.
    private static func go(to target: (row: Int, column: Int), rows: [NSRange], in string: NSString) -> MemoLists.Change {
        let row = rows[target.row]
        let cells = cellRanges(of: row, in: string)
        if target.column < cells.count {
            return MemoLists.Change(edits: [], selection: NSRange(location: NSMaxRange(cells[target.column]), length: 0))
        }
        let pad = String(repeating: separator, count: target.column - cells.count + 1)
        return MemoLists.Change(edits: [MemoLists.Edit(range: NSRange(location: NSMaxRange(row), length: 0), text: pad)],
                                selection: NSRange(location: NSMaxRange(row) + pad.utf16.count, length: 0))
    }

    // MARK: Changing the table

    /// A new row of empty cells above or below row `index`; the caret in its first cell.
    public static func insertRow(rows: [NSRange], at index: Int, below: Bool, in text: String) -> MemoLists.Change? {
        let string = text as NSString
        guard rows.indices.contains(index) else { return nil }
        let empty = String(repeating: separator, count: columnCount(of: rows, in: string) - 1)
        let row = rows[index]
        if below {
            return MemoLists.Change(edits: [MemoLists.Edit(range: NSRange(location: NSMaxRange(row), length: 0), text: "\n" + empty)],
                                    selection: NSRange(location: NSMaxRange(row) + 1, length: 0))
        }
        return MemoLists.Change(edits: [MemoLists.Edit(range: NSRange(location: row.location, length: 0), text: empty + "\n")],
                                selection: NSRange(location: row.location, length: 0))
    }

    /// A new column of empty cells left or right of `column`; the caret in the caret row's new cell.
    public static func insertColumn(rows: [NSRange], at column: Int, right: Bool, caretRow: Int, in text: String) -> MemoLists.Change? {
        let string = text as NSString
        guard rows.indices.contains(caretRow) else { return nil }
        var edits: [MemoLists.Edit] = []
        var caret = 0
        var shift = 0
        for (index, row) in rows.enumerated() {
            var cells = cellRanges(of: row, in: string)
            // A short row is filled out first, so the new column lands in its place.
            var pad = ""
            if cells.count <= column {
                pad = String(repeating: separator, count: column + 1 - cells.count)
                cells.append(contentsOf: Array(repeating: NSRange(location: NSMaxRange(row), length: 0), count: column + 1 - cells.count))
            }
            let at = right ? NSMaxRange(cells[column]) : cells[column].location
            let letters = right || !pad.isEmpty ? pad + separator : separator
            let place = pad.isEmpty ? at : NSMaxRange(row)
            edits.append(MemoLists.Edit(range: NSRange(location: place, length: 0), text: letters))
            if index == caretRow { caret = shift + (right || !pad.isEmpty ? place + letters.utf16.count : at) }
            if index < caretRow { shift += letters.utf16.count }
        }
        return change(edits, caret: caret)
    }

    /// Row `index` taken out; the last row takes the table with it.
    public static func deleteRow(rows: [NSRange], at index: Int, in text: String) -> MemoLists.Change? {
        guard rows.indices.contains(index) else { return nil }
        guard rows.count > 1 else { return deleteTable(rows: rows, in: text) }
        let row = rows[index]
        if index + 1 < rows.count {
            return MemoLists.Change(edits: [MemoLists.Edit(range: NSRange(location: row.location, length: row.length + 1), text: "")],
                                    selection: NSRange(location: row.location, length: 0))
        }
        let above = rows[index - 1]
        return MemoLists.Change(edits: [MemoLists.Edit(range: NSRange(location: NSMaxRange(above), length: NSMaxRange(row) - NSMaxRange(above)), text: "")],
                                selection: NSRange(location: NSMaxRange(above), length: 0))
    }

    /// Column `column` taken out of every row; nil for a table of `leastColumns`.
    public static func deleteColumn(rows: [NSRange], at column: Int, caretRow: Int, in text: String) -> MemoLists.Change? {
        let string = text as NSString
        guard columnCount(of: rows, in: string) > leastColumns, rows.indices.contains(caretRow) else { return nil }
        var edits: [MemoLists.Edit] = []
        var caret = 0
        var shift = 0
        for (index, row) in rows.enumerated() {
            let cells = cellRanges(of: row, in: string)
            var cut: NSRange?
            if column < cells.count, cells.count > 1 {
                // With the tab before it, or the first cell with the tab after it.
                cut = column == 0 ? NSRange(location: cells[0].location, length: cells[0].length + 1)
                    : NSRange(location: NSMaxRange(cells[column - 1]), length: NSMaxRange(cells[column]) - NSMaxRange(cells[column - 1]))
            }
            var edit = cut.map { MemoLists.Edit(range: $0, text: "") }
            // A row of nothing but tabs keeps enough of them to stay a row: an empty line has no letter to carry its mark.
            if let cut, cut.length == row.length {
                edit = MemoLists.Edit(range: row, text: String(repeating: separator, count: leastColumns - 1))
            }
            if let edit { edits.append(edit) }
            if index == caretRow { caret = shift + (edit?.range.location ?? NSMaxRange(row)) }
            if index < caretRow { shift += (edit.map { $0.text.utf16.count - $0.range.length } ?? 0) }
        }
        return change(edits, caret: caret)
    }

    /// The whole table taken out, with the line break after it (or before it, at the memo's end).
    public static func deleteTable(rows: [NSRange], in text: String) -> MemoLists.Change? {
        let string = text as NSString
        guard !rows.isEmpty else { return nil }
        var cut = span(of: rows)
        if NSMaxRange(cut) < string.length {
            cut.length += 1
        } else if cut.location > 0 {
            cut.location -= 1
            cut.length += 1
        }
        return MemoLists.Change(edits: [MemoLists.Edit(range: cut, text: "")], selection: NSRange(location: cut.location, length: 0))
    }

    /// 표 넣기: a two-by-two table on the caret's line when it is empty, or on new lines under it;
    /// the caret in its first cell. Every letter it adds but the line breaks is a row's.
    public static func newTable(in text: String, caret: Int) -> MemoLists.Change {
        let string = text as NSString
        let line = lineContent(at: min(caret, string.length), in: string)
        let rows = String(repeating: separator, count: leastColumns - 1) + "\n" + String(repeating: separator, count: leastColumns - 1)
        if line.length == 0 {
            return MemoLists.Change(edits: [MemoLists.Edit(range: NSRange(location: line.location, length: 0), text: rows)],
                                    selection: NSRange(location: line.location, length: 0))
        }
        return MemoLists.Change(edits: [MemoLists.Edit(range: NSRange(location: NSMaxRange(line), length: 0), text: "\n" + rows)],
                                selection: NSRange(location: NSMaxRange(line) + 1, length: 0))
    }

    /// The line holding `location`, without its break.
    private static func lineContent(at location: Int, in string: NSString) -> NSRange {
        MemoLists.lineContent(of: string.lineRange(for: NSRange(location: location, length: 0)), in: string)
    }

    /// Edits given in the text as it is before any of them, made from the last back to the first so
    /// each one's range still holds; `caret` is in the text after them all.
    private static func change(_ edits: [MemoLists.Edit], caret: Int) -> MemoLists.Change {
        MemoLists.Change(edits: edits.sorted { $0.range.location > $1.range.location }, selection: NSRange(location: caret, length: 0))
    }
}
