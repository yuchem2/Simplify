import AppKit
import SwiftUI
import SimplifyKit

/// Tables through the clipboard. Copying letters with a table row in them writes them three ways:
/// tab-split words (spreadsheets take them as cells), HTML with a `<table>` (the 메모 app, Pages
/// and the web take a table), and the memo's own letters (`MemoTablePaste.pasteboardType`), which
/// paste back here whole. Pasting reads, first that fits: the memo's own letters; a table in HTML
/// or RTF (the 메모 app, Excel, Numbers, Google Sheets, Word, web pages); a Markdown table; lines
/// split by tabs that form a grid. Anything else pastes as the text view always has.
@MainActor
enum MemoTableClipboard {
    static let memoType = NSPasteboard.PasteboardType(MemoTablePaste.pasteboardType)
    private static let tableKey = MemoLineStyler.tableKey

    // MARK: Copying

    /// True when the letters hold a table's rows (not words inside one cell), so `write` has a
    /// table to carry.
    static func hasTable(_ piece: AttributedString) -> Bool {
        MemoTablePaste.holdsTable(piece)
    }

    /// The clipboard's contents become `piece` as words, HTML and the memo's own letters.
    static func write(_ piece: AttributedString) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(MemoAttachments.plainText(piece), forType: .string)
        // Marked UTF-8: an HTML reader that is not told reads Latin-1, and Korean breaks.
        if let html = NotesHTML.fragment(piece) { board.setString("<meta charset=\"utf-8\">" + html, forType: .html) }
        if let data = MemoTablePaste.clip(piece) { board.setData(data, forType: memoType) }
        noteOwnCopy()
    }

    /// The clipboard as a memo's own copy last left it: its words paste back as words, never
    /// read again as a grid (a memo's tab-aligned lines are not a table).
    private static var ownCopy: Int?

    /// A copy or cut in the memo just filled the clipboard.
    static func noteOwnCopy() {
        ownCopy = NSPasteboard.general.changeCount
    }

    // MARK: Pasting

    /// What the clipboard holds when it is a table paste: the memo's own letters, or pieces read
    /// from elsewhere. Nil when it is not one.
    enum Paste {
        case memo(AttributedString)
        case pieces([MemoTablePaste.Piece])
    }

    static func read(_ board: NSPasteboard = .general) -> Paste? {
        if let data = board.data(forType: memoType), let text = MemoTablePaste.unclip(data), hasTable(text) {
            return .memo(text)
        }
        // A memo's own copy without a table: its words as they were.
        if board.changeCount == ownCopy { return nil }
        // Read only with a table in it: reading HTML or RTF is slow, on every paste.
        if let html = board.data(forType: .html), contains(html, "<table"), let rich = rich(withoutLoads(html), type: .html),
           let pieces = pieces(in: rich) {
            return .pieces(pieces)
        }
        if let rtf = board.data(forType: .rtf), contains(rtf, "\\trowd"), let rich = rich(rtf, type: .rtf), let pieces = pieces(in: rich) {
            return .pieces(pieces)
        }
        guard let words = board.string(forType: .string) else { return nil }
        if let pieces = MemoTablePaste.markdownPieces(words) { return .pieces(pieces) }
        if let rows = MemoTablePaste.tabGrid(words) { return .pieces([.table(rows)]) }
        return nil
    }

    /// The data holds these letters, any case.
    private static func contains(_ data: Data, _ letters: String) -> Bool {
        String(decoding: data, as: UTF8.self).range(of: letters, options: .caseInsensitive) != nil
    }

    /// HTML without pictures, style sheets and scripts, which its reading would fetch and run.
    private static func withoutLoads(_ html: Data) -> Data {
        var text = String(decoding: html, as: UTF8.self)
        for pattern in ["<(script|iframe|style|object|video|audio)[^>]*/>", "<(script|iframe|style|object|video|audio)[\\s\\S]*?</\\1\\s*>",
                        "<(img|link|embed|source|base|input)\\b[^>]*>", "url\\([^)]*\\)"] {
            text = text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return Data(text.utf8)
    }

    private static func rich(_ data: Data, type: NSAttributedString.DocumentType) -> NSAttributedString? {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
        if type == .html { options[.characterEncoding] = String.Encoding.utf8.rawValue }
        return try? NSAttributedString(data: data, options: options, documentAttributes: nil)
    }

    /// The rich text's tables (its paragraphs in table blocks, by row and column) and the lines
    /// between them; nil when it has no table of two columns or more.
    static func pieces(in rich: NSAttributedString) -> [MemoTablePaste.Piece]? {
        var pieces: [MemoTablePaste.Piece] = []
        var words: [String] = []
        var table: NSTextTable?
        var cells: [Grid: MemoTablePaste.Cell] = [:]
        var found = false
        func endTable() {
            guard table != nil else { return }
            table = nil
            let rows = (cells.keys.map { $0.row + $0.rows }.max() ?? 0), columns = (cells.keys.map { $0.column + $0.columns }.max() ?? 0)
            var grid = Array(repeating: Array(repeating: MemoTablePaste.Cell(""), count: columns), count: rows)
            // A merged cell's letters go in its first cell; the rest stay empty.
            for (place, cell) in cells { grid[place.row][place.column] = cell }
            cells = [:]
            if let tidy = MemoTablePaste.tidy(grid) {
                pieces.append(.table(tidy))
                found = true
            } else {
                words += grid.map { $0.map(\.text).filter { !$0.isEmpty }.joined(separator: " ") }.filter { !$0.isEmpty }
            }
        }
        func endWords() {
            if !words.isEmpty { pieces.append(.lines(words.joined(separator: "\n"))) }
            words = []
        }
        let string = rich.string as NSString
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs]) { substring, range, _, _ in
            let letters = (substring ?? "").replacingOccurrences(of: "\u{2028}", with: "\n")
            let style = range.length > 0 || range.location < rich.length
                ? rich.attribute(.paragraphStyle, at: min(range.location, max(0, rich.length - 1)), effectiveRange: nil) as? NSParagraphStyle : nil
            guard let block = style?.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first else {
                endTable()
                words.append(Self.listLine(letters))
                return
            }
            if table !== block.table {
                endTable()
                endWords()
                table = block.table
            }
            let place = Grid(row: block.startingRow, column: block.startingColumn, rows: max(1, block.rowSpan), columns: max(1, block.columnSpan))
            let formatted = Self.cell(rich, range)
            // A cell of several paragraphs: their letters one after another, formatting all share
            // (an empty paragraph has none to share, so it does not count).
            if var cell = cells[place] {
                let blank = letters.allSatisfy(\.isWhitespace), wasBlank = cell.text.allSatisfy(\.isWhitespace)
                cell.text += "\n" + letters
                if wasBlank {
                    (cell.bold, cell.italic, cell.underline, cell.strike) = (formatted.bold, formatted.italic, formatted.underline, formatted.strike)
                } else if !blank {
                    cell.bold = cell.bold && formatted.bold
                    cell.italic = cell.italic && formatted.italic
                    cell.underline = cell.underline && formatted.underline
                    cell.strike = cell.strike && formatted.strike
                }
                cells[place] = cell
            } else {
                var cell = formatted
                cell.text = letters
                cells[place] = cell
            }
        }
        endTable()
        endWords()
        // Blank lines a web page puts around its table.
        while case .lines(let words)? = pieces.first, words.allSatisfy(\.isWhitespace) { pieces.removeFirst() }
        while case .lines(let words)? = pieces.last, words.allSatisfy(\.isWhitespace) { pieces.removeLast() }
        return found ? pieces : nil
    }

    private struct Grid: Hashable {
        var row: Int
        var column: Int
        var rows: Int
        var columns: Int
    }

    /// The formatting a cell keeps from elsewhere: bold, italic, underline and strikethrough that
    /// all its letters share; never its font, colour or link (nor a link's underline).
    private static func cell(_ rich: NSAttributedString, _ range: NSRange) -> MemoTablePaste.Cell {
        guard range.length > 0 else { return MemoTablePaste.Cell("") }
        var cell = MemoTablePaste.Cell("", bold: true, italic: true, underline: true, strike: true)
        let letters = rich.string as NSString
        rich.enumerateAttributes(in: range) { attributes, part, _ in
            guard !letters.substring(with: part).allSatisfy(\.isWhitespace) else { return }
            let traits = (attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            cell.bold = cell.bold && traits.contains(.boldFontMask)
            cell.italic = cell.italic && traits.contains(.italicFontMask)
            cell.underline = cell.underline && attributes[.link] == nil && ((attributes[.underlineStyle] as? Int) ?? 0) != 0
            cell.strike = cell.strike && ((attributes[.strikethroughStyle] as? Int) ?? 0) != 0
        }
        if letters.substring(with: range).allSatisfy(\.isWhitespace) {
            cell = MemoTablePaste.Cell("")
        }
        return cell
    }

    /// A list line as rich text reads it (`\t•\titem`, `\t\t1.\titem`) as a memo list line, a
    /// tab a level past the first.
    private static func listLine(_ letters: String) -> String {
        guard let match = letters.firstMatch(of: /^(\t*)([•◦▪‣⁃–-]|\d+\.)\t/) else { return letters }
        let rest = letters[match.range.upperBound...]
        let level = String(repeating: "\t", count: max(0, match.1.count - 1))
        let mark = match.2
        return level + (mark.last == "." ? "\(mark) " : "• ") + rest
    }

    /// ⌘V and the right-click menu's 붙여넣기 with a table on the clipboard: in place of the
    /// selection, or filling the caret's table from its cell. False when the clipboard holds no
    /// table, so the paste goes on as usual. A very large table asks first.
    static func paste(into textView: NSTextView, draft: MemoDraft) -> Bool {
        guard !draft.isUnreadable, let paste = read() else { return false }
        let pieces: [MemoTablePaste.Piece]
        let letters: AttributedString
        switch paste {
        case .memo(let text):
            letters = text
            pieces = []
        case .pieces(let found):
            pieces = found
            letters = MemoTablePaste.memoText(found)
        }
        let go = { insert(letters, pieces: pieces, into: textView, draft: draft) }
        guard MemoTablePaste.isLarge(pieces), let window = textView.window else {
            go()
            return true
        }
        // Asked at the caret, in an ink menu as the memo's other choices are.
        let tables: [[[MemoTablePaste.Cell]]] = pieces.compactMap { piece in
            guard case .table(let rows) = piece else { return nil }
            return rows
        }
        let rows = tables.map(\.count).max() ?? 0, columns = tables.map { $0.first?.count ?? 0 }.max() ?? 0
        let caret = textView.firstRect(forCharacterRange: NSRange(location: textView.selectedRange().location, length: 0), actualRange: nil)
        InkMenuPresenter.popUp([.section("큰 표예요 (\(rows)행 × \(columns)열)"),
                                .item("그대로 붙여넣기") { go() },
                                .item("취소") {}],
                               at: CGPoint(x: caret.minX, y: caret.minY), in: window)
        return true
    }

    /// The letters in place of the selection, as the text view's own edit (one undo step). In a
    /// table cell a single table fills the table from that cell instead.
    private static func insert(_ letters: AttributedString, pieces: [MemoTablePaste.Piece], into textView: NSTextView, draft: MemoDraft) {
        guard let storage = textView.textStorage else { return }
        var selected = textView.selectedRange()
        var movedUnder = false
        if let table = MemoLineStyler.table(in: storage, at: selected.location) {
            if let rows = onlyTable(letters) {
                fill(table, from: selected.location, with: rows, in: textView)
                return
            }
            // Words around the table on the clipboard: under the caret's table, never splitting it.
            selected = NSRange(location: NSMaxRange(MemoTables.span(of: table.rows)), length: 0)
            movedUnder = true
        }
        let string = storage.string as NSString
        let content = MemoLists.lineContent(of: string.lineRange(for: NSRange(location: selected.location, length: 0)), in: string)
        let startsTable = letters.runs.first?[MemoAttributes.Table.self] != nil
        let endsTable = letters.runs.last?[MemoAttributes.Table.self] != nil
        let added = rendered(letters)
        // A table starts on a line of its own, and what follows it on the caret's line goes under it.
        if startsTable || movedUnder, selected.location > content.location {
            added.insert(NSAttributedString(string: "\n", attributes: plainAttributes(textView)), at: 0)
        }
        let breaksAfter = endsTable && NSMaxRange(selected) < NSMaxRange(content)
        if breaksAfter { added.append(NSAttributedString(string: "\n", attributes: plainAttributes(textView))) }
        replace(selected, with: added, in: textView)
        // The caret after what went in, before the line break added after a table.
        let caret = selected.location + added.length - (breaksAfter ? 1 : 0)
        textView.setSelectedRange(NSRange(location: min(caret, (textView.string as NSString).length), length: 0))
        draft.focusRequest += 1
    }

    /// The letters' cells when they are one table and nothing else.
    private static func onlyTable(_ letters: AttributedString) -> [[NSAttributedString]]? {
        let ids = Set(letters.runs.compactMap { $0[MemoAttributes.Table.self] })
        guard ids.count == 1 else { return nil }
        // Empty lines at its ends (a row copied with its line break) do not count.
        var lines = MemoTodoLines.lines(in: letters)
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty, lines.allSatisfy({ line in !line.isEmpty && letters[line].runs.allSatisfy { run in
            run[MemoAttributes.Table.self] != nil || String(letters[run.range].characters).allSatisfy { $0 == "\t" } } }) else { return nil }
        return lines.map { line in
            let row = rendered(AttributedString(letters[line]))
            let string = row.string as NSString
            var cells: [NSAttributedString] = []
            var start = 0
            for index in 0...string.length where index == string.length || string.character(at: index) == 0x09 {
                cells.append(row.attributedSubstring(from: NSRange(location: start, length: index - start)))
                start = index + 1
            }
            return cells
        }
    }

    /// Fills the caret's table from its cell: the pasted rows over the cells right of and under
    /// it, rows and columns added where it runs past; one edit.
    private static func fill(_ table: (id: String, rows: [NSRange]), from location: Int, with pasted: [[NSAttributedString]], in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let string = storage.string as NSString
        guard let at = MemoTables.cell(at: location, rows: table.rows, in: string) else { return }
        var grid: [[NSAttributedString]] = table.rows.map { row in
            MemoTables.cellRanges(of: row, in: string).map { storage.copiedPart($0) }
        }
        let width = max(grid.map(\.count).max() ?? 0, at.column + (pasted.map(\.count).max() ?? 0))
        let height = max(grid.count, at.row + pasted.count)
        let empty = NSAttributedString(string: "", attributes: plainAttributes(textView))
        grid = (0..<height).map { index in
            let row = index < grid.count ? grid[index] : []
            return row + Array(repeating: empty, count: width - row.count)
        }
        for (r, row) in pasted.enumerated() {
            for (c, cell) in row.enumerated() { grid[at.row + r][at.column + c] = cell }
        }
        let rebuilt = NSMutableAttributedString()
        let tab = NSAttributedString(string: MemoTables.separator, attributes: plainAttributes(textView))
        for (index, row) in grid.enumerated() {
            if index > 0 { rebuilt.append(NSAttributedString(string: "\n", attributes: plainAttributes(textView))) }
            for (column, cell) in row.enumerated() {
                if column > 0 { rebuilt.append(tab) }
                rebuilt.append(cell)
            }
        }
        // Every letter but the line breaks is a row's of this table: each row's span at once.
        let letters = rebuilt.string as NSString
        var start = 0
        for index in 0...letters.length where index == letters.length || letters.character(at: index) == 0x0A {
            if index > start { rebuilt.addAttribute(tableKey, value: table.id, range: NSRange(location: start, length: index - start)) }
            start = index + 1
        }
        let span = MemoTables.span(of: table.rows)
        replace(span, with: rebuilt, in: textView)
        // The caret at the end of the last cell filled.
        let lastRow = at.row + pasted.count - 1, lastColumn = at.column + (pasted.last?.count ?? 1) - 1
        var offset = span.location
        for (index, row) in grid.enumerated() {
            if index == lastRow {
                offset += row.prefix(lastColumn + 1).reduce(0) { $0 + $1.length } + lastColumn
                break
            }
            offset += row.reduce(0) { $0 + $1.length } + row.count - 1 + 1
        }
        textView.setSelectedRange(NSRange(location: min(offset, (textView.string as NSString).length), length: 0))
    }

    /// The memo's letters as the text view keeps them: the memo's own keys, and the memo's face,
    /// bold and italic where they are; the editor draws the rest from the keys.
    private static func rendered(_ letters: AttributedString) -> NSMutableAttributedString {
        let converted = (try? NSAttributedString(letters, including: \.memo)) ?? NSAttributedString(string: String(letters.characters))
        let made = NSMutableAttributedString(attributedString: converted)
        let whole = NSRange(location: 0, length: made.length)
        made.addAttributes([.font: NSFont.systemFont(ofSize: MemoStyle.size), .foregroundColor: NSColor(Color.ink)], range: whole)
        for run in letters.runs {
            let bold = run[MemoAttributes.Bold.self] == true, italic = run[MemoAttributes.Italic.self] == true
            guard bold || italic else { continue }
            let range = NSRange(run.range, in: letters)
            var font = NSFont.systemFont(ofSize: MemoStyle.size, weight: bold ? .bold : .regular)
            if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            made.addAttribute(.font, value: font, range: range)
        }
        return made
    }

    /// Plain memo letters: the memo's face and ink, no keys.
    private static func plainAttributes(_ textView: NSTextView) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: MemoStyle.size), .foregroundColor: NSColor(Color.ink)]
    }

    /// One edit, as the text view's own: undoable, and passed on to SwiftUI's copy of the memo.
    private static func replace(_ range: NSRange, with letters: NSAttributedString, in textView: NSTextView) {
        guard let storage = textView.textStorage, NSMaxRange(range) <= storage.length,
              textView.shouldChangeText(in: range, replacementString: letters.string) else { return }
        textView.breakUndoCoalescing()
        storage.replaceCharacters(in: range, with: letters)
        textView.didChangeText()
    }
}
