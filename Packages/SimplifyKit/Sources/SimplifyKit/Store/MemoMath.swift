import Foundation

/// A memo's formulas: LaTeX letters, drawn as formulas by the app. Letters marked `m` on one line
/// are a formula in the text; a line typed with `$$ ` in front is a formula of its own, and its
/// letters after the mark are the LaTeX whether marked or not. Nothing new is stored for either.
public enum MemoMath {
    /// The letters a formula line starts with.
    public static let displayMark = "$$ "

    /// The LaTeX of a formula line (`$$ \sum_i p_i`), or nil for any other line.
    public static func displayLaTeX(_ line: some StringProtocol) -> String? {
        line.hasPrefix(displayMark) ? String(line.dropFirst(displayMark.count)) : nil
    }

    /// A formula as it sits in the memo.
    public struct Formula: Equatable {
        /// Its LaTeX letters (after the mark, for a formula line).
        public var range: Range<AttributedString.Index>
        public var latex: String
        /// A `$$ ` line rather than letters in the text.
        public var isDisplay: Bool
    }

    /// Every formula in reading order. A code block keeps `$$ ` and marked letters as typed.
    public static func formulas(in text: AttributedString) -> [Formula] {
        var found: [Formula] = []
        for line in MemoTodoLines.lines(in: text) where !line.isEmpty {
            if text.runs[line.lowerBound][MemoAttributes.Code.self] == true { continue }
            let letters = String(text[line].characters)
            if let latex = displayLaTeX(letters) {
                let start = text.characters.index(line.lowerBound, offsetBy: displayMark.count)
                found.append(Formula(range: start..<line.upperBound, latex: latex, isDisplay: true))
                continue
            }
            var open: AttributedString.Index?
            for run in text[line].runs {
                let math = run[MemoAttributes.Math.self] == true
                if math, open == nil { open = run.range.lowerBound }
                if !math, let start = open {
                    found.append(Formula(range: start..<run.range.lowerBound, latex: String(text[start..<run.range.lowerBound].characters), isDisplay: false))
                    open = nil
                }
            }
            if let start = open {
                found.append(Formula(range: start..<line.upperBound, latex: String(text[start..<line.upperBound].characters), isDisplay: false))
            }
        }
        return found
    }

    /// A memo written before formulas were LaTeX: raised and lowered letters inside a formula
    /// become `^{…}` and `_{…}` (`w = 0.9w` with a lowered `0` reads `w = 0.9w_{0}`), so the
    /// formula draws as it looked. Letters outside formulas keep their script.
    public static func upgradingScripts(_ text: AttributedString) -> AttributedString {
        guard text.runs.contains(where: { $0[MemoAttributes.Math.self] == true && $0[MemoAttributes.Script.self] != nil }) else { return text }
        var result = AttributedString()
        for run in text.runs {
            var piece = AttributedString(text[run.range])
            if run[MemoAttributes.Math.self] == true, let script = run[MemoAttributes.Script.self] {
                // Each line on its own: a formula never takes in a line break.
                let lines = String(piece.characters).split(separator: "\n", omittingEmptySubsequences: false)
                var attributes = run.attributes
                attributes[MemoAttributes.Script.self] = nil
                let mark = script == .raised ? "^" : "_"
                piece = AttributedString(lines.map { $0.isEmpty ? "" : "\(mark){\($0)}" }.joined(separator: "\n"), attributes: attributes)
            }
            result.append(piece)
        }
        return result
    }

    /// The letters as plain text for the clipboard and other apps: each formula in `$…$`, and a
    /// formula line's in `$$…$$`.
    public static func plainText(_ text: AttributedString) -> String {
        let text = upgradingScripts(text)
        var out = ""
        var at = text.startIndex
        for formula in formulas(in: text) {
            let start = formula.isDisplay ? text.characters.index(formula.range.lowerBound, offsetBy: -displayMark.count) : formula.range.lowerBound
            out += String(text[at..<start].characters)
            out += formula.isDisplay ? "$$\(formula.latex)$$" : "$\(formula.latex)$"
            at = formula.range.upperBound
        }
        return out + String(text[at...].characters)
    }
}
