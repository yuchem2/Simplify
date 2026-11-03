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

    /// The note's body, or nil for a blank memo, whose note is deleted instead.
    public static func body(name: String, text: AttributedString) -> String? {
        guard !MemoText.isBlank(text) else { return nil }
        var lines = [""]
        // Whether the letters so far on this line end in a space (or there are none yet).
        var afterSpace = true
        for run in text.runs {
            let pieces = String(text[run.range].characters).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            for (number, piece) in pieces.enumerated() {
                if number > 0 {
                    lines.append("")
                    afterSpace = true
                }
                guard !piece.isEmpty else { continue }
                lines[lines.count - 1] += segment(String(piece), run: run, afterSpace: afterSpace)
                afterSpace = piece.last == " "
            }
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        let heading = "<div><h1>\(escape(name))</h1></div>"
        return ([heading] + lines.map { "<div>\($0.isEmpty ? "<br>" : $0)</div>" }).joined(separator: "\n")
    }

    /// One run's letters on one line, wrapped in its formatting's tags.
    private static func segment(_ letters: String, run: AttributedString.Runs.Run, afterSpace: Bool) -> String {
        var letters = letters
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
        if run[MemoAttributes.Italic.self] == true || run[MemoAttributes.Math.self] == true { html = "<i>\(html)</i>" }
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
