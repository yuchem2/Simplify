import Foundation

/// A memo as the Mac's 메모 app takes it: the note's name and its body as HTML, for the copy the
/// app keeps in the 메모 app's "Simplify" folder.
///
/// The 메모 app names a note after its first line, so the body starts with the name as a heading
/// and the memo's lines follow, one `<div>` each. Formatting maps to the tags the 메모 app keeps;
/// colours take the palette's light values, since a note has one look in both themes.
public enum NotesHTML {
    /// `2026년 11월 3일 (화)`, `2026년 11월 1주차 (11.1 – 11.7)`, `2026년 11월`. Every name holds
    /// its year, so notes are matched by name across years too.
    public static func noteName(for period: Period) -> String {
        let c = period.calendar.dateComponents([.year, .month, .day, .weekday], from: period.start)
        switch period.scope {
        case .day:
            return "\(c.year!)년 \(c.month!)월 \(c.day!)일 (\(Calendar.weekdayName(c.weekday!)))"
        case .week:
            // The year of the month the week is named after.
            return "\(c.year!)년 \(period.title) (\(period.rangeText))"
        case .month:
            return period.title
        }
    }

    /// One memo's note: the period's name, ` - ` and the memo's name, as `2026년 11월 4일 (수) - 회의록`.
    /// `name` is nil for a memo from before a period could have several, which keeps the period's
    /// name alone.
    public static func noteName(for period: Period, memo name: String?) -> String {
        guard let name, !name.isEmpty else { return noteName(for: period) }
        return "\(noteName(for: period)) - \(name)"
    }

    /// The note's body, or nil for a blank memo, whose note is deleted instead.
    ///
    /// The memo's 제목, 머리말 and 부머리말 sit under the note's name: `<h2>`, `<h3>` and bold
    /// letters, since the name already takes the 메모 app's title (`<h1>`). List lines become
    /// `<ul>` (`class="Apple-dash-list"` for dashes) or `<ol>` items, a level in nested inside
    /// the list above; quote lines are a `<blockquote>`, with any list items in them inside it.
    /// Formulas are their LaTeX in `$…$`, and a formula line's in `$$…$$`. A table's rows are one
    /// `<table>`, a row's tab-split cells each a `<td>`. An attached file is `📎` and its name.
    public static func body(name: String, text: AttributedString) -> String? {
        guard !MemoText.isBlank(text) else { return nil }
        let text = MemoMath.upgradingScripts(text)
        var lines: [Line] = MemoTodoLines.lines(in: text).map { range in
            let letters = String(text[range].characters)
            // A code block keeps its `- ` and `> ` as typed, as the editor shows them.
            let isCode = !range.isEmpty && text.runs[range.lowerBound][MemoAttributes.Code.self] == true
            let table = range.isEmpty ? nil : text.runs[range.lowerBound][MemoAttributes.Table.self]
            if let table {
                // Cell by cell: the runs' letters split at the tabs, formulas in `$…$` within their cell.
                var cells = [""]
                var afterSpace = true
                var inFormula = false
                for run in text[range].runs {
                    let isFormula = !isCode && run[MemoAttributes.Math.self] == true
                    let pieces = String(text[run.range].characters).components(separatedBy: MemoTables.separator)
                    for (index, piece) in pieces.enumerated() {
                        if index > 0 {
                            if inFormula { cells[cells.count - 1] += "$" }
                            inFormula = false
                            cells.append("")
                            afterSpace = true
                        }
                        guard !piece.isEmpty else { continue }
                        if isFormula != inFormula { cells[cells.count - 1] += "$" }
                        inFormula = isFormula
                        cells[cells.count - 1] += segment(piece, run: run, afterSpace: afterSpace && !isFormula)
                        afterSpace = piece.last == " "
                    }
                }
                if inFormula { cells[cells.count - 1] += "$" }
                return Line(html: "", marker: nil, paragraph: nil, isBlank: false, table: table, cells: cells)
            }
            let marker = isCode ? nil : MemoLists.marker(letters)
            let start = text.characters.index(range.lowerBound, offsetBy: marker.map { String(letters.utf16.prefix($0.length))!.count } ?? 0)
            var html = ""
            // Whether the letters so far on this line end in a space (or there are none yet).
            var afterSpace = true
            if !isCode, marker == nil, let latex = MemoMath.displayLaTeX(letters) {
                html = "$$\(escape(latex))$$"
            } else {
                var inFormula = false
                for run in text[start..<range.upperBound].runs {
                    let piece = String(text[run.range].characters)
                    let isFormula = !isCode && run[MemoAttributes.Math.self] == true
                    if isFormula != inFormula { html += "$" }
                    inFormula = isFormula
                    html += segment(piece, run: run, afterSpace: afterSpace && !isFormula)
                    afterSpace = piece.last == " "
                }
                if inFormula { html += "$" }
            }
            let paragraph = text[range].runs.first { $0[MemoAttributes.Paragraph.self] != nil }?[MemoAttributes.Paragraph.self]
            return Line(html: html, marker: marker, paragraph: paragraph, isBlank: letters.isEmpty)
        }
        while lines.last?.isBlank == true { lines.removeLast() }
        while lines.first?.isBlank == true { lines.removeFirst() }
        var out = ["<div><h1>\(escape(name))</h1></div>"]
        // The lists open around the line being written, outermost first.
        var open: [(tag: String, close: String)] = []
        var inQuote = false
        var table: String?
        for line in lines {
            if let id = line.table {
                while let list = open.popLast() { out.append(list.close) }
                if inQuote {
                    out.append("</blockquote>")
                    inQuote = false
                }
                if table != id {
                    if table != nil { out.append("</table>") }
                    out.append("<table>")
                    table = id
                }
                out.append("<tr>" + line.cells.map { "<td>\($0.isEmpty ? "<br>" : $0)</td>" }.joined() + "</tr>")
                continue
            }
            if table != nil {
                out.append("</table>")
                table = nil
            }
            // Into or out of a quote: the lists around end there.
            let quoted = line.marker?.isQuoted == true
            if quoted != inQuote {
                while let list = open.popLast() { out.append(list.close) }
                out.append(quoted ? "<blockquote>" : "</blockquote>")
                inQuote = quoted
            }
            guard let marker = line.marker, marker.kind != .quote else {
                while let list = open.popLast() { out.append(list.close) }
                out.append("<div>\(paragraphed(line))</div>")
                continue
            }
            let tag = switch marker.kind {
            case .number: "<ol>"
            case .dash: "<ul class=\"Apple-dash-list\">"
            default: "<ul>"
            }
            while open.count > marker.level + 1 { out.append(open.removeLast().close) }
            if open.count == marker.level + 1, open.last?.tag != tag { out.append(open.removeLast().close) }
            while open.count < marker.level + 1 {
                // A numbered list typed from `3. ` starts at 3 in the note too.
                let start = marker.number ?? 1
                out.append(open.count == marker.level && start > 1 ? "<ol start=\"\(start)\">" : tag)
                open.append((tag, marker.kind == .number ? "</ol>" : "</ul>"))
            }
            out.append("<li>\(paragraphed(line))</li>")
        }
        while let list = open.popLast() { out.append(list.close) }
        if inQuote { out.append("</blockquote>") }
        if table != nil { out.append("</table>") }
        return out.joined(separator: "\n")
    }

    private struct Line {
        var html: String
        var marker: MemoLists.Marker?
        var paragraph: MemoParagraph?
        var isBlank: Bool
        /// A table row's table id and its cells' HTML.
        var table: String? = nil
        var cells: [String] = []
    }

    /// A line's letters in its paragraph style's tag; an empty line is a `<br>`.
    private static func paragraphed(_ line: Line) -> String {
        guard !line.html.isEmpty else { return "<br>" }
        switch line.paragraph {
        case .title: return "<h2>\(line.html)</h2>"
        case .heading: return "<h3>\(line.html)</h3>"
        case .sub: return "<b>\(line.html)</b>"
        case nil: return line.html
        }
    }

    /// One run's letters on one line, wrapped in its formatting's tags.
    private static func segment(_ letters: String, run: AttributedString.Runs.Run, afterSpace: Bool) -> String {
        var letters = letters
        // An attached file: its name after a clip, one per placeholder letter.
        if let ref = run[MemoAttributes.Attachment.self].flatMap(MemoAttachments.Ref.init(value:)) {
            letters = letters.map { $0 == MemoAttachments.placeholder ? MemoAttachments.label(ref) : String($0) }.joined()
        }
        // A chip's box: one box pair that every font has, ticked once the ToDo is done.
        if let todo = run[MemoAttributes.Todo.self], run[MemoAttributes.TodoBox.self] == true {
            letters = todo.isDone ? "☑" : "☐"
        }
        var html = escape(letters, afterSpace: afterSpace)
        if run[MemoAttributes.Code.self] == true { html = "<tt>\(html)</tt>" }
        switch run[MemoAttributes.Script.self] {
        case .raised: html = "<sup>\(html)</sup>"
        case .lowered: html = "<sub>\(html)</sub>"
        case nil: break
        }
        if run[MemoAttributes.Strike.self] == true { html = "<strike>\(html)</strike>" }
        if run[MemoAttributes.Underline.self] == true { html = "<u>\(html)</u>" }
        if run[MemoAttributes.Italic.self] == true { html = "<i>\(html)</i>" }
        if run[MemoAttributes.Bold.self] == true { html = "<b>\(html)</b>" }
        var style: [String] = []
        if let ink = run[MemoAttributes.Ink.self] { style.append("color: \(lightInk(ink))") }
        if run[MemoAttributes.Code.self] != true, let highlight = run[MemoAttributes.Highlight.self] {
            style.append("background-color: \(lightTint(highlight))")
        }
        if !style.isEmpty { html = "<span style=\"\(style.joined(separator: "; "))\">\(html)</span>" }
        return html
    }

    /// Letters safe inside HTML text or a quoted attribute. Spaces that HTML would fold together
    /// (a run of them, or one starting a line) become no-break spaces, so indents survive.
    static func escape(_ letters: String, afterSpace: Bool = false) -> String {
        var html = ""
        var afterSpace = afterSpace
        for character in letters {
            switch character {
            case "&": html += "&amp;"
            case "<": html += "&lt;"
            case ">": html += "&gt;"
            case "\"": html += "&quot;"
            case "'": html += "&#39;"
            case " ": html += afterSpace ? "&nbsp;" : " "
            default: html.append(character)
            }
            afterSpace = character == " "
        }
        return html
    }

    /// The palette's light text colours (`design/tokens.json`, `*-ink`).
    static func lightInk(_ palette: Palette) -> String {
        switch palette {
        case .red: "#b3332a"
        case .orange: "#9a4c00"
        case .yellow: "#7a6000"
        case .green: "#28702c"
        case .teal: "#00776a"
        case .blue: "#2a5fc4"
        case .purple: "#7a44bf"
        case .pink: "#b5325f"
        case .grey: "#5e5e5b"
        }
    }

    /// The palette's light highlighter grounds (`design/tokens.json`, `*-tint`).
    static func lightTint(_ palette: Palette) -> String {
        switch palette {
        case .red: "#fbe3df"
        case .orange: "#fce9d6"
        case .yellow: "#faf0c4"
        case .green: "#e1f1e0"
        case .teal: "#dcf0ed"
        case .blue: "#e1e9fb"
        case .purple: "#ece2f8"
        case .pink: "#f9e0e9"
        case .grey: "#e9e9e6"
        }
    }
}
