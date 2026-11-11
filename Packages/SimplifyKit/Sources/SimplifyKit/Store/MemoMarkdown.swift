import Foundation

/// Markdown pasted into a memo, as the memo's own formatting rather than its marks: `#` lines
/// become a title, heading or subheading; `**` `*` `~~` bold, italic and strikethrough; code
/// spans and blocks inline code and code blocks; lists and quotes the memo's own list letters
/// (`• `, `- `, `1. `, `> `, a tab a level); links whose address `MemoLinks` takes links; `---`
/// a rule; tables a memo table; `$…$` and `$$…$$` formulas. A ToDo line (`- [ ] 글`) becomes a
/// dash item, struck through when done, never a ToDo chip. HTML tags and footnotes stay letters.
///
/// `looks` decides whether pasted words are Markdown at all, by one sure sign; lists, quotes and
/// rules alone are not one, as the memo already reads those letters as they are.
public enum MemoMarkdown {
    /// The letters a rule becomes (`MemoTimeline.isRule`).
    public static let rule = "────"

    // MARK: Telling Markdown

    /// Signs only Markdown gives: a `#` heading, a code fence, `**bold**` `__bold__` `~~struck~~`,
    /// `*italic*` `_italic_` on word edges, a code span, a link or picture, a ToDo line, `$$`.
    /// `a*b*c`, `snake_case_name`, file paths, dates and sums of money are not.
    private static let signs: [NSRegularExpression] = [
        #"^ {0,3}#{1,6}[ \t]+\S"#,
        #"^ {0,3}(```|~~~)"#,
        #"(?<![\w*])\*\*(?![\s*])[^\n]*?(?<![\s*])\*\*(?!\*)"#,
        // Not a Python name (`__init__`, `__name__`).
        #"(?<![\w_])__(?![\s_])(?![A-Za-z0-9_]+__)[^\n]*?(?<![\s_])__(?![\w_]|\.\w)"#,
        #"(?<![\w~])~~(?![\s~])[^\n]*?(?<![\s~])~~(?!~)"#,
        #"(?<![\w*])\*(?![\s*])[^*\n]+?(?<![\s*])\*(?!\*)"#,
        #"(?<![\w_])_(?![\s_])[^_\n]+?(?<![\s_])_(?![\w_]|\.\w)"#,
        #"`[^`\n]+`"#,
        #"!?\[[^\]\n]*\]\([^)\s]+(?:\s+"[^"\n]*")?\)"#,
        #"^[ \t]*(?:>[ \t]*)?[-*+][ \t]+\[[ xX]\][ \t]"#,
        #"\$\$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }

    /// The words carry at least one sure sign of Markdown.
    public static func looks(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return signs.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    // MARK: Converting

    /// The Markdown as memo letters. Tables get new ids from `newID`.
    public static func memoText(_ markdown: String, newID: @escaping () -> String = MemoTablePaste.newID) -> AttributedString {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let (source, formulas) = takingFormulas(normalized)
        let options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: false, interpretedSyntax: .full,
                                                              failurePolicy: .returnPartiallyParsedIfPossible,
                                                              appliesSourcePositionAttributes: true)
        guard let parsed = try? AttributedString(markdown: source, options: options) else { return AttributedString(markdown) }
        var builder = Builder(parsed: parsed, sourceLines: source.components(separatedBy: "\n"), formulas: formulas, newID: newID)
        return builder.build()
    }

    // MARK: Formulas

    /// A formula taken out before parsing (so `_` and `*` in it are not read as emphasis) and the
    /// letters it was written with, which code and tables keep as they were.
    struct Formula {
        var latex: String
        var original: String
        var isDisplay: Bool
    }

    static let openMark: Character = "\u{E000}"
    static let closeMark: Character = "\u{E001}"
    private static let placeholder = try! NSRegularExpression(pattern: "\u{E000}(\\d+)\u{E001}")

    static func placeholder(_ index: Int) -> String { "\(openMark)\(index)\(closeMark)" }

    /// The Markdown with every `$…$` and `$$…$$` outside code put aside as a placeholder. `$$`
    /// lines on their own (one line or several) are a display formula; within a line, `$` opens
    /// only before a letter that is not a space or a figure and closes only after one that is not
    /// a space, and never before a figure, so sums of money stay as written.
    static func takingFormulas(_ text: String) -> (String, [Formula]) {
        var formulas: [Formula] = []
        var lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var fence: String?
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.drop { $0 == " " }
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                out.append(line)
                index += 1
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                out.append(line)
                index += 1
                continue
            }
            // A quote's marks and spaces in front stay; the rest is looked at.
            let lead = String(line.prefix { $0 == " " || $0 == ">" || $0 == "\t" })
            let rest = line.dropFirst(lead.count).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("$$") {
                if rest.count > 4, rest.hasSuffix("$$") {
                    let latex = rest.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespaces)
                    if !latex.isEmpty {
                        formulas.append(Formula(latex: latex, original: rest, isDisplay: true))
                        out.append(lead + placeholder(formulas.count - 1))
                        index += 1
                        continue
                    }
                }
                // `$$` and more lines up to one ending in `$$`.
                // Not past a blank line or a code fence: an unclosed `$$` takes nothing more in.
                let stop = lines[(index + 1)...].firstIndex { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return trimmed.isEmpty || trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
                } ?? lines.count
                if let end = lines[(index + 1)..<stop].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasSuffix("$$") }) {
                    var parts = [String(rest.dropFirst(2))]
                    for inner in lines[(index + 1)...end] {
                        var piece = inner.drop { $0 == " " || $0 == ">" || $0 == "\t" }.trimmingCharacters(in: .whitespaces)
                        if inner == lines[end] { piece = String(piece.dropLast(2)) }
                        parts.append(piece)
                    }
                    let latex = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
                    if !latex.isEmpty {
                        let original = ([rest] + lines[(index + 1)...end].map { $0.trimmingCharacters(in: .whitespaces) }).joined(separator: "\n")
                        formulas.append(Formula(latex: latex, original: original, isDisplay: true))
                        out.append(lead + placeholder(formulas.count - 1))
                        index = end + 1
                        continue
                    }
                }
            }
            out.append(inlineFormulas(line, into: &formulas))
            index += 1
        }
        lines = out
        return (lines.joined(separator: "\n"), formulas)
    }

    /// The line with its `$…$` and `$$…$$` as placeholders, code spans and `\$` left alone.
    private static func inlineFormulas(_ line: String, into formulas: inout [Formula]) -> String {
        guard line.contains("$") else { return line }
        let letters = Array(line)
        var result = ""
        var at = 0
        func isSpace(_ i: Int) -> Bool { i < 0 || i >= letters.count || letters[i].isWhitespace }
        func isFigure(_ i: Int) -> Bool { i >= 0 && i < letters.count && letters[i].isASCII && letters[i].isNumber }
        while at < letters.count {
            let letter = letters[at]
            if letter == "\\", at + 1 < letters.count {
                result.append(letter)
                result.append(letters[at + 1])
                at += 2
                continue
            }
            // A code span: as many backticks closing it as opened it.
            if letter == "`" {
                var ticks = 0
                while at + ticks < letters.count, letters[at + ticks] == "`" { ticks += 1 }
                var close = at + ticks
                var found: Int?
                while close < letters.count {
                    if letters[close] == "`" {
                        var run = 0
                        while close + run < letters.count, letters[close + run] == "`" { run += 1 }
                        if run == ticks { found = close; break }
                        close += run
                    } else {
                        close += 1
                    }
                }
                let end = found.map { $0 + ticks } ?? at + ticks
                result += String(letters[at..<end])
                at = end
                continue
            }
            if letter == "$" {
                let double = at + 1 < letters.count && letters[at + 1] == "$"
                let width = double ? 2 : 1
                let start = at + width
                if !isSpace(start), double || !isFigure(start) {
                    var close = start
                    var found: Int?
                    while close < letters.count {
                        if letters[close] == "\\" { close += 2; continue }
                        if letters[close] == "$" {
                            let closes = double ? close + 1 < letters.count && letters[close + 1] == "$" : true
                            if closes, !isSpace(close - 1), close > start, double || !isFigure(close + 1) {
                                found = close
                            }
                            break
                        }
                        close += 1
                    }
                    if let close = found {
                        let latex = String(letters[start..<close])
                        formulas.append(Formula(latex: latex, original: String(letters[at..<(close + width)]), isDisplay: false))
                        result += placeholder(formulas.count - 1)
                        at = close + width
                        continue
                    }
                }
                result += String(letters[at..<start])
                at = start
                continue
            }
            result.append(letter)
            at += 1
        }
        return result
    }

    // MARK: Building

    private struct Builder {
        let parsed: AttributedString
        let sourceLines: [String]
        let formulas: [Formula]
        let newID: () -> String

        /// Pieces of the memo in order, each one or more lines; `nil` is a blank line.
        private var pieces: [AttributedString?] = []
        /// List items whose first line has been written (later blocks of the item follow it).
        private var startedItems: Set<Int> = []
        private var lastLine: Int?

        init(parsed: AttributedString, sourceLines: [String], formulas: [Formula], newID: @escaping () -> String) {
            self.parsed = parsed
            self.sourceLines = sourceLines
            self.formulas = formulas
            self.newID = newID
        }

        /// A leaf block: a paragraph, heading, code block, rule or table, or HTML outside any.
        private struct Block {
            var intent: PresentationIntent?
            var runs: [AttributedString.Runs.Run] = []
        }

        mutating func build() -> AttributedString {
            var blocks: [Block] = []
            var key: Int?
            for run in parsed.runs {
                let intent = run.presentationIntent
                let id = intent.map(Self.blockID) ?? -1
                if id != key || blocks.isEmpty {
                    blocks.append(Block(intent: intent))
                    key = id
                }
                blocks[blocks.count - 1].runs.append(run)
            }
            for block in blocks { add(block) }
            // No blank lines at the ends.
            while let first = pieces.first, first == nil { pieces.removeFirst() }
            while let last = pieces.last, last == nil { pieces.removeLast() }
            var text = AttributedString()
            for (index, piece) in pieces.enumerated() {
                if index > 0 { text += AttributedString("\n") }
                if let piece { text += piece }
            }
            return text
        }

        /// The block a run belongs to: its table, or its innermost block.
        private static func blockID(_ intent: PresentationIntent) -> Int {
            if let table = intent.components.first(where: { if case .table = $0.kind { true } else { false } }) { return table.identity }
            return intent.components.first?.identity ?? -1
        }

        // MARK: Blank lines

        /// The block's first and last lines in the Markdown (from 1); nil when it has none.
        private func lines(of block: Block) -> ClosedRange<Int>? {
            let positions = block.runs.compactMap(\.markdownSourcePosition)
            guard let start = positions.map(\.startLine).min(), let end = positions.map(\.endLine).max() else { return nil }
            return start...max(start, end)
        }

        /// One blank line where the Markdown had blank lines before the block (several are one).
        private mutating func spaceBefore(_ block: Block) {
            var span = lines(of: block)
            if span == nil {
                // A rule has no place given: the first written line after the last block.
                if let next = ((lastLine ?? 0)..<sourceLines.count).first(where: { !sourceLines[$0].trimmingCharacters(in: .whitespaces).isEmpty }) {
                    span = (next + 1)...(next + 1)
                }
            }
            guard let span else { return }
            if let last = lastLine, span.lowerBound > last + 1 {
                let between = sourceLines[last..<min(span.lowerBound - 1, sourceLines.count)]
                if between.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }), let last = pieces.last, last != nil {
                    pieces.append(nil)
                }
            }
            lastLine = max(lastLine ?? 0, span.upperBound)
        }

        // MARK: Blocks

        private mutating func add(_ block: Block) {
            spaceBefore(block)
            guard let intent = block.intent, let kind = intent.components.first?.kind else {
                // HTML on lines of its own: its letters.
                let letters = block.runs.map { String(parsed[$0.range].characters) }.joined()
                pieces.append(AttributedString(trimmingBreak(literal(letters))))
                return
            }
            if intent.components.contains(where: { if case .table = $0.kind { true } else { false } }) {
                pieces.append(table(block))
                return
            }
            switch kind {
            case .codeBlock:
                let letters = block.runs.map { literal(String(parsed[$0.range].characters)) }.joined()
                var code = AttributedString(trimmingBreak(letters))
                code[MemoAttributes.Code.self] = true
                pieces.append(code)
            case .thematicBreak:
                pieces.append(AttributedString(rule))
            case .header(let level):
                var line = prefix(of: intent, block: block).letters
                line += withFormulas(inline(block.runs))
                line[MemoAttributes.Paragraph.self] = level == 1 ? .title : level == 2 ? .heading : .sub
                pieces.append(line)
            default:
                pieces.append(paragraph(block, intent: intent))
            }
        }

        /// A paragraph's lines, each after the quote, tabs and list marker it sits in.
        private mutating func paragraph(_ block: Block, intent: PresentationIntent) -> AttributedString {
            let front = prefix(of: intent, block: block)
            var words = inline(block.runs)
            // A ToDo line: a list item, no chip; done ones struck through.
            if front.isItem {
                let letters = String(words.characters.prefix(4))
                if letters == "[ ] " || letters.lowercased() == "[x] " {
                    words.removeSubrange(words.startIndex..<words.characters.index(words.startIndex, offsetBy: 4))
                    if letters != "[ ] " { words.mergeAttributes(Self.struck) }
                }
            }
            var text = AttributedString()
            for (index, line) in split(words).enumerated() {
                if index > 0 { text += AttributedString("\n") }
                let before = index == 0 ? front.letters : front.following
                // A formula alone on its line (written between lines with no blank line around
                // it, it is still in their paragraph): a `$$ ` line.
                if before.characters.isEmpty, let formula = formulaIndex(String(line.characters)), formulas[formula].isDisplay {
                    text += AttributedString(MemoMath.displayMark + formulas[formula].latex)
                    continue
                }
                text += before
                text += withFormulas(line)
            }
            return text
        }

        private static let struck: AttributeContainer = {
            var container = AttributeContainer()
            container[MemoAttributes.Strike.self] = true
            return container
        }()

        /// The letters in front of a block's first line (quote, tabs, list marker) and of its
        /// later lines (quote and tabs under the item's words), and whether it starts an item.
        private struct Front {
            var letters: AttributedString
            var following: AttributedString
            var isItem: Bool
        }

        private mutating func prefix(of intent: PresentationIntent, block: Block) -> Front {
            let components = intent.components
            let quote = components.contains { if case .blockQuote = $0.kind { true } else { false } } ? "> " : ""
            let lists = components.filter {
                switch $0.kind {
                case .orderedList, .unorderedList: true
                default: false
                }
            }
            guard let itemIndex = components.firstIndex(where: { if case .listItem = $0.kind { true } else { false } }),
                  case .listItem(let ordinal) = components[itemIndex].kind else {
                return Front(letters: AttributedString(quote), following: AttributedString(quote), isItem: false)
            }
            let level = max(0, lists.count - 1)
            let tabs = String(repeating: "\t", count: level)
            let under = AttributedString(quote + String(repeating: "\t", count: level + 1))
            let item = components[itemIndex].identity
            guard !startedItems.contains(item) else { return Front(letters: under, following: under, isItem: false) }
            startedItems.insert(item)
            var marker = "• "
            if itemIndex + 1 < components.count, case .orderedList = components[itemIndex + 1].kind {
                marker = MemoLists.label(ordinal, level: level) + " "
            } else if bulletLetter(of: block) == "-" {
                marker = "- "
            }
            return Front(letters: AttributedString(quote + tabs + marker), following: under, isItem: true)
        }

        /// The letter an unordered item was written with: the last one before its words.
        private func bulletLetter(of block: Block) -> Character? {
            guard let position = block.runs.lazy.compactMap(\.markdownSourcePosition).first,
                  position.startLine - 1 < sourceLines.count else { return nil }
            let line = Array(sourceLines[position.startLine - 1].utf8)
            let before = line.prefix(max(0, position.startColumn - 1))
            // The last `-` `*` `+` followed by a space: not the `**` of bold words after it.
            let letters = Array(String(decoding: before, as: UTF8.self))
            return letters.indices.last { index in
                index + 1 < letters.count && "-*+".contains(letters[index]) && letters[index + 1].isWhitespace
            }.map { letters[$0] }
        }

        /// A table's rows as a memo table (cells keeping bold, italic, strikethrough all through
        /// and their links), or lines when it has one column.
        private func table(_ block: Block) -> AttributedString {
            var rows: [[MemoTablePaste.Cell]] = []
            var rowIDs: [Int] = []
            var parts: [[Int: [AttributedString.Runs.Run]]] = []
            for run in block.runs {
                guard let components = run.presentationIntent?.components,
                      let cell = components.first(where: { if case .tableCell = $0.kind { true } else { false } }),
                      case .tableCell(let column) = cell.kind,
                      let row = components.first(where: {
                          switch $0.kind {
                          case .tableHeaderRow, .tableRow: true
                          default: false
                          }
                      }) else { continue }
                if rowIDs.last != row.identity {
                    rowIDs.append(row.identity)
                    parts.append([:])
                }
                parts[parts.count - 1][column, default: []].append(run)
            }
            let width = parts.map { ($0.keys.max() ?? -1) + 1 }.max() ?? 0
            for row in parts {
                rows.append((0..<width).map { column in cell(row[column] ?? []) })
            }
            if let tidy = MemoTablePaste.tidy(rows) {
                return MemoTablePaste.table(tidy, id: newID())
            }
            return AttributedString(rows.map { $0.map(\.text).filter { !$0.isEmpty }.joined(separator: " ") }.joined(separator: "\n"))
        }

        private func cell(_ runs: [AttributedString.Runs.Run]) -> MemoTablePaste.Cell {
            var cell = MemoTablePaste.Cell("", bold: true, italic: true, strike: true)
            var text = ""
            for run in runs {
                let letters = literal(visibleLetters(run))
                text += letters
                if let address = address(of: run) {
                    cell.links.append(MemoTablePaste.Cell.Link(letters: letters, address: address))
                }
                guard !letters.allSatisfy(\.isWhitespace) else { continue }
                let inline = run.inlinePresentationIntent ?? []
                cell.bold = cell.bold && inline.contains(.stronglyEmphasized)
                cell.italic = cell.italic && inline.contains(.emphasized)
                cell.strike = cell.strike && inline.contains(.strikethrough)
            }
            if text.allSatisfy(\.isWhitespace) { return MemoTablePaste.Cell("") }
            cell.text = text
            return cell
        }

        // MARK: Letters

        /// The runs' letters with the memo's formatting; soft and hard breaks are line breaks.
        private func inline(_ runs: [AttributedString.Runs.Run]) -> AttributedString {
            var text = AttributedString()
            for run in runs {
                let inline = run.inlinePresentationIntent ?? []
                if inline.contains(.softBreak) || inline.contains(.lineBreak) {
                    text += AttributedString("\n")
                    continue
                }
                var container = AttributeContainer()
                if inline.contains(.stronglyEmphasized) { container[MemoAttributes.Bold.self] = true }
                if inline.contains(.emphasized) { container[MemoAttributes.Italic.self] = true }
                if inline.contains(.strikethrough) { container[MemoAttributes.Strike.self] = true }
                var letters = visibleLetters(run)
                if inline.contains(.code) {
                    container[MemoAttributes.InlineCode.self] = true
                    letters = literal(letters)
                }
                if let address = address(of: run) { container[MemoAttributes.Link.self] = address }
                text += AttributedString(letters, attributes: container)
            }
            return text
        }

        /// A run's letters; a picture is its description, or its address when it has none.
        private func visibleLetters(_ run: AttributedString.Runs.Run) -> String {
            let letters = String(parsed[run.range].characters)
            if let picture = run.imageURL, letters == "\u{FFFC}" || letters.isEmpty { return picture.absoluteString }
            return letters
        }

        private func address(of run: AttributedString.Runs.Run) -> String? {
            guard let url = run.link ?? run.imageURL else { return nil }
            return MemoLinks.address(url.absoluteString)
        }

        /// Placeholders back to the formulas as they were written (in code and tables).
        private func literal(_ letters: String) -> String {
            guard letters.contains(openMark) else { return letters }
            var result = letters
            let range = NSRange(letters.startIndex..., in: letters)
            for match in placeholder.matches(in: letters, range: range).reversed() {
                guard let whole = Range(match.range, in: letters), let number = Range(match.range(at: 1), in: letters),
                      let index = Int(letters[number]), index < formulas.count else { continue }
                result.replaceSubrange(whole, with: formulas[index].original)
            }
            return result
        }

        /// Placeholders in words as formula letters (`Math`), LaTeX without the `$`.
        private func withFormulas(_ words: AttributedString) -> AttributedString {
            var text = words
            while let found = text.characters.firstIndex(of: openMark) {
                guard let close = text.characters[found...].firstIndex(of: closeMark),
                      let index = Int(String(text.characters[text.characters.index(after: found)..<close])), index < formulas.count else { break }
                let after = text.characters.index(after: close)
                var container = text[found..<after].runs.first?.attributes ?? AttributeContainer()
                container[MemoAttributes.InlineCode.self] = nil
                container[MemoAttributes.Link.self] = nil
                container[MemoAttributes.Math.self] = true
                text.replaceSubrange(found..<after, with: AttributedString(formulas[index].latex, attributes: container))
            }
            return text
        }

        /// The formula a placeholder alone stands for.
        private func formulaIndex(_ letters: String) -> Int? {
            guard letters.first == openMark, letters.last == closeMark, let index = Int(letters.dropFirst().dropLast()),
                  index < formulas.count else { return nil }
            return index
        }

        /// The words split at their line breaks.
        private func split(_ words: AttributedString) -> [AttributedString] {
            var lines: [AttributedString] = []
            var start = words.startIndex
            for index in words.characters.indices where words.characters[index] == "\n" {
                lines.append(AttributedString(words[start..<index]))
                start = words.characters.index(after: index)
            }
            lines.append(AttributedString(words[start...]))
            return lines
        }

        private func trimmingBreak(_ letters: String) -> String {
            letters.hasSuffix("\n") ? String(letters.dropLast()) : letters
        }
    }
}

