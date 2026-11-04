import Foundation
import Testing
@testable import SimplifyKit

/// Formulas: where they are, old formulas read as LaTeX, and the clipboard's plain text.
struct MemoMathTests {
    private func styled(_ string: String, _ build: (inout AttributeContainer) -> Void = { _ in }) -> AttributedString {
        var container = AttributeContainer()
        build(&container)
        return AttributedString(string, attributes: container)
    }

    private let math: (inout AttributeContainer) -> Void = { $0[MemoAttributes.Math.self] = true }

    @Test func oldScriptsInAFormulaBecomeLaTeX() {
        var text = styled("w = 0.9w", math)
        text += styled("0") { $0[MemoAttributes.Math.self] = true; $0[MemoAttributes.Script.self] = .lowered }
        text += styled(" 그리고 ")
        text += styled("x", math)
        text += styled("10") { $0[MemoAttributes.Math.self] = true; $0[MemoAttributes.Script.self] = .raised }
        let upgraded = MemoMath.upgradingScripts(text)
        #expect(String(upgraded.characters) == "w = 0.9w_{0} 그리고 x^{10}")
        #expect(!upgraded.runs.contains { $0[MemoAttributes.Script.self] != nil })
        #expect(MemoMath.formulas(in: upgraded).map(\.latex) == ["w = 0.9w_{0}", "x^{10}"])
    }

    @Test func scriptsOutsideFormulasStay() {
        var text = styled("H")
        text += styled("2") { $0[MemoAttributes.Script.self] = .lowered }
        text += styled("O")
        #expect(MemoMath.upgradingScripts(text) == text)
    }

    @Test func otherFormattingOfAScriptIsKept() {
        let text = styled("2") { $0[MemoAttributes.Math.self] = true; $0[MemoAttributes.Script.self] = .raised; $0[MemoAttributes.Ink.self] = .blue }
        let upgraded = MemoMath.upgradingScripts(text)
        #expect(String(upgraded.characters) == "^{2}")
        #expect(upgraded.runs.allSatisfy { $0[MemoAttributes.Ink.self] == .blue && $0[MemoAttributes.Math.self] == true })
    }

    @Test func aScriptAcrossLinesWrapsEachLine() {
        let text = styled("a\nb") { $0[MemoAttributes.Math.self] = true; $0[MemoAttributes.Script.self] = .lowered }
        #expect(String(MemoMath.upgradingScripts(text).characters) == "_{a}\n_{b}")
    }

    @Test func formulasStopAtLineBreaksAndPlainLetters() {
        var text = styled("a", math)
        text += styled("b") { $0[MemoAttributes.Math.self] = true; $0[MemoAttributes.Bold.self] = true }
        text += styled(" 와 ")
        text += styled("c\nd", math)
        #expect(MemoMath.formulas(in: text).map(\.latex) == ["ab", "c", "d"])
        #expect(MemoMath.formulas(in: text).allSatisfy { !$0.isDisplay })
    }

    @Test func aDollarLineIsAFormulaOfItsOwn() {
        var text = styled("위\n$$ \\sum_i p_i\n아래 ")
        text += styled("$$ 코드", { $0[MemoAttributes.Code.self] = true })
        let formulas = MemoMath.formulas(in: text)
        #expect(formulas.count == 1)
        #expect(formulas.first?.latex == "\\sum_i p_i")
        #expect(formulas.first?.isDisplay == true)
        #expect(formulas.first.map { String(text[$0.range].characters) } == "\\sum_i p_i")
        #expect(MemoMath.displayLaTeX("$$x") == nil)
    }

    @Test func plainTextMarksFormulas() {
        var text = styled("값: ")
        text += styled("x^2", math)
        text += styled(" 끝\n$$ \\frac{a}{b}")
        #expect(MemoMath.plainText(text) == "값: $x^2$ 끝\n$$\\frac{a}{b}$$")
        #expect(MemoMath.plainText(styled("수식 없음")) == "수식 없음")
    }

    @Test func formulasSurviveTheRoundTripUnchanged() throws {
        var text = styled("근의 공식: ")
        text += styled("x = \\frac{-b}{2a}", math)
        let decoded = MemoText.decode(try #require(MemoText.encode(text)))
        #expect(decoded == text)
        #expect(String(decoding: try #require(MemoText.encode(text)), as: UTF8.self).contains(#""v":1"#))
    }
}
