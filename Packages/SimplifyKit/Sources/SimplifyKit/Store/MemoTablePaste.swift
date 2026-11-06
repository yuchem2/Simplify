import Foundation

/// Tables pasted into a memo from elsewhere, and a memo's own pieces carried through the
/// clipboard: a Markdown table, tab-split lines that form a grid, rows read out of HTML or RTF by
/// the app, all tidied into rows of cells and made into memo letters, each table under a new id.
public enum MemoTablePaste {
    /// One cell's letters and the little formatting kept from elsewhere.
    public struct Cell: Equatable, Sendable {
        public var text: String
        public var bold = false
        public var italic = false
        public var underline = false
        public var strike = false

        public init(_ text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false, strike: Bool = false) {
            self.text = text
            self.bold = bold
            self.italic = italic
            self.underline = underline
            self.strike = strike
        }

        var isEmpty: Bool { text.allSatisfy(\.isWhitespace) }
    }

    /// What a paste holds, in order: lines of words, or a table's rows.
    public enum Piece: Equatable, Sendable {
        case lines(String)
        case table([[Cell]])
    }

    /// Past this many rows or columns the app asks before pasting.
    public static let askRows = 200
    public static let askColumns = 20

    /// The clipboard type a memo's copied letters travel under (`MemoText` JSON), so they paste
    /// back whole, tables and formatting and all.
    public static let pasteboardType = "dev.yoom.simplify.memo"

    // MARK: Markdown

    /// The text with its Markdown tables (a header row, then a `|---|` row) as tables; nil when
    /// it has none.
    public static func markdownPieces(_ text: String) -> [Piece]? {
        let lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var pieces: [Piece] = []
        var words: [String] = []
        var index = 0
        var found = false
        func flush() {
            if !words.isEmpty { pieces.append(.lines(words.joined(separator: "\n"))) }
            words = []
        }
        while index < lines.count {
            if index + 1 < lines.count, let header = markdownCells(lines[index]), isDivider(lines[index + 1], columns: header.count) {
                var rows = [header]
                var next = index + 2
                while next < lines.count, let row = markdownCells(lines[next]) {
                    rows.append(row)
                    next += 1
                }
                if let table = tidy(rows.map { $0.map(markdownCell) }) {
                    flush()
                    pieces.append(.table(table))
                    found = true
                    index = next
                    continue
                }
            }
            words.append(lines[index])
            index += 1
        }
        flush()
        return found ? pieces : nil
    }

    /// A Markdown row's cells: `|` splits them (`\|` is the letter), the outer pipes optional;
    /// nil for a line with no pipe.
    static func markdownCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        var cells: [String] = []
        var cell = ""
        var escaped = false
        for character in trimmed {
            if escaped {
                cell.append(character == "|" ? "|" : "\\\(character)")
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(cell)
                cell = ""
            } else {
                cell.append(character)
            }
        }
        if escaped { cell.append("\\") }
        cells.append(cell)
        if trimmed.hasPrefix("|") { cells.removeFirst() }
        if trimmed.hasSuffix("|") && !trimmed.hasSuffix("\\|") && !cells.isEmpty { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// `|---|:--:|` under a header of `columns` cells.
    static func isDivider(_ line: String, columns: Int) -> Bool {
        guard let cells = markdownCells(line), cells.count == columns else { return false }
        return cells.allSatisfy { cell in
            var body = Substring(cell)
            if body.hasPrefix(":") { body = body.dropFirst() }
            if body.hasSuffix(":") { body = body.dropLast() }
            return !body.isEmpty && body.allSatisfy { $0 == "-" }
        }
    }

    /// A Markdown cell: `**bold**`, `*italic*`/`_italic_` and `~~struck~~` around the whole cell
    /// become its formatting; any other marks stay as letters.
    static func markdownCell(_ text: String) -> Cell {
        var cell = Cell(text)
        for (mark, set) in [("**", { (c: inout Cell) in c.bold = true }), ("__", { (c: inout Cell) in c.bold = true }),
                            ("~~", { (c: inout Cell) in c.strike = true }), ("*", { (c: inout Cell) in c.italic = true }),
                            ("_", { (c: inout Cell) in c.italic = true })] {
            let text = cell.text
            // Only marks around the whole cell: `**a** 와 **b**` stays as typed.
            if text.count > mark.count * 2, text.hasPrefix(mark), text.hasSuffix(mark),
               !text.dropFirst(mark.count).dropLast(mark.count).contains(mark) {
                cell.text = String(text.dropFirst(mark.count).dropLast(mark.count))
                set(&cell)
            }
        }
        return cell
    }

    // MARK: Tab-split lines

    /// Lines split by tabs that form a grid: two or more lines, each with the same number of
    /// cells (two or more), none starting with a tab, a list marker or a timeline time, which are
    /// a memo's own lines rather than a table. Nil otherwise.
    public static func tabGrid(_ text: String) -> [[Cell]]? {
        var lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        while lines.last?.isEmpty == true { lines.removeLast() }
        guard lines.count >= 2 else { return nil }
        let rows = lines.map { $0.components(separatedBy: "\t") }
        guard let columns = rows.first?.count, columns >= MemoTables.leastColumns, rows.allSatisfy({ $0.count == columns }) else { return nil }
        for line in lines {
            if line.hasPrefix("\t") || MemoLists.marker(line) != nil || MemoTimeline.stampLength(line) != nil { return nil }
        }
        return tidy(rows.map { $0.map { Cell($0) } })
    }

    // MARK: Tidying

    /// Rows as a memo table takes them: line breaks in a cell become a space, every row as long
    /// as the longest, rows and columns empty all through at the edges dropped. Nil for no rows
    /// or fewer than two columns.
    public static func tidy(_ rows: [[Cell]]) -> [[Cell]]? {
        var rows = rows.map { row in
            row.map { cell in
                var cell = cell
                cell.text = cell.text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.joined(separator: " ")
                    .replacingOccurrences(of: "\t", with: " ")
                return cell
            }
        }
        let width = rows.map(\.count).max() ?? 0
        rows = rows.map { $0 + Array(repeating: Cell(""), count: width - $0.count) }
        while let first = rows.first, first.allSatisfy(\.isEmpty) { rows.removeFirst() }
        while let last = rows.last, last.allSatisfy(\.isEmpty) { rows.removeLast() }
        func columnIsEmpty(_ column: Int) -> Bool { rows.allSatisfy { $0[column].isEmpty } }
        while let count = rows.first?.count, count > 0, columnIsEmpty(count - 1) { rows = rows.map { Array($0.dropLast()) } }
        while let count = rows.first?.count, count > 0, columnIsEmpty(0) { rows = rows.map { Array($0.dropFirst()) } }
        guard !rows.isEmpty, (rows.first?.count ?? 0) >= MemoTables.leastColumns else { return nil }
        return rows
    }

    /// The table's size passes `askRows` or `askColumns`.
    public static func isLarge(_ pieces: [Piece]) -> Bool {
        pieces.contains { piece in
            guard case .table(let rows) = piece else { return false }
            return rows.count > askRows || (rows.first?.count ?? 0) > askColumns
        }
    }

    // MARK: Memo letters

    /// The pieces as memo letters: lines plain, each table's rows one a line with tab-split
    /// cells, its letters (not the line breaks) under a new id, cells keeping their formatting.
    public static func memoText(_ pieces: [Piece], newID: () -> String = MemoTablePaste.newID) -> AttributedString {
        var text = AttributedString()
        for (index, piece) in pieces.enumerated() {
            if index > 0 { text += AttributedString("\n") }
            switch piece {
            case .lines(let words):
                text += AttributedString(words)
            case .table(let rows):
                text += table(rows, id: newID())
            }
        }
        return text
    }

    /// One table's rows under `id`.
    public static func table(_ rows: [[Cell]], id: String) -> AttributedString {
        var text = AttributedString()
        for (index, row) in rows.enumerated() {
            if index > 0 { text += AttributedString("\n") }
            for (column, cell) in row.enumerated() {
                if column > 0 { text += marked(MemoTables.separator, id: id) }
                var container = AttributeContainer()
                container[MemoAttributes.Table.self] = id
                if cell.bold { container[MemoAttributes.Bold.self] = true }
                if cell.italic { container[MemoAttributes.Italic.self] = true }
                if cell.underline { container[MemoAttributes.Underline.self] = true }
                if cell.strike { container[MemoAttributes.Strike.self] = true }
                text += AttributedString(cell.text, attributes: container)
            }
        }
        return text
    }

    private static func marked(_ letters: String, id: String) -> AttributedString {
        var container = AttributeContainer()
        container[MemoAttributes.Table.self] = id
        return AttributedString(letters, attributes: container)
    }

    /// A table id like the ones 표 넣기 makes.
    public static func newID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    // MARK: A memo's own pieces

    /// The letters hold a table's rows rather than words inside one cell: a tab that splits a
    /// table's cells is among them.
    public static func holdsTable(_ text: AttributedString) -> Bool {
        text.runs.contains { run in
            run[MemoAttributes.Table.self] != nil && text[run.range].characters.contains("\t")
        }
    }

    /// The letters with every table under a new id, so a pasted table never joins the one it was
    /// copied from.
    public static func renewingTables(_ text: AttributedString, newID: () -> String = MemoTablePaste.newID) -> AttributedString {
        var text = text
        var ids: [String: String] = [:]
        for (id, range) in text.runs[MemoAttributes.Table.self].reversed() {
            guard let id else { continue }
            if ids[id] == nil { ids[id] = newID() }
            text[range][MemoAttributes.Table.self] = ids[id]
        }
        return text
    }

    /// A memo's copied letters for the clipboard.
    public static func clip(_ text: AttributedString) -> Data? {
        MemoText.encode(text)
    }

    /// Copied memo letters back from the clipboard, every table under a new id so it never joins
    /// the table it was copied from. Nil for data that cannot be read.
    public static func unclip(_ data: Data, newID: () -> String = MemoTablePaste.newID) -> AttributedString? {
        MemoText.decodeIfReadable(data).map { renewingTables($0, newID: newID) }
    }
}
