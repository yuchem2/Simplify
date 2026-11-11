import Foundation
import Testing
@testable import SimplifyKit

/// Markdown pasted into a memo: told apart from other words, and made into the memo's own
/// formatting and list letters.
struct MemoMarkdownTests {
    private func memo(_ markdown: String) -> AttributedString {
        MemoMarkdown.memoText(markdown, newID: { "t1" })
    }

    private func letters(_ text: AttributedString) -> String { String(text.characters) }

    /// The letters carrying `key` (true or a value), in order, joined by `|`.
    private func marked<K: AttributedStringKey>(_ text: AttributedString, _ key: K.Type) -> String where K.Value: Hashable & Sendable {
        text.runs[key].compactMap { value, range in value == nil ? nil : String(text[range].characters) }.joined(separator: "|")
    }

    // MARK: Telling

    @Test func sureSignsAreMarkdown() {
        for words in ["# 제목", "### 소제목\n글", "```\ncode\n```", "~~~swift\nx\n~~~", "이건 **굵게** 써요", "__굵게__ 글", "~~취소~~",
                      "*기울임* 글", "_기울임_ 글", "`npm i` 실행", "[문서](https://a.com)", "![그림](https://a.com/x.png)",
                      "- [ ] 할 일", "* [x] 끝", "$$\nx^2\n$$", "**강조**는 이렇게"] {
            #expect(MemoMarkdown.looks(words), "\(words)")
        }
    }

    @Test func otherWordsAreNot() {
        for words in ["그냥 글", "a*b*c", "2*3*4 = 24", "snake_case_name", "my_var_name 값", "/usr/local/my_file_name.txt",
                      "C:\\Users\\me\\*.txt", "2026-11-11", "$5와 $10", "$10 and $20", "가격 $3.50", "#해시태그", "#1 이슈",
                      "• 목록\n• 둘", "- 대시\n- 둘", "1. 하나\n2. 둘", "> 인용", "----", "x * y * z", "__init__.py", "__굵게__는", "if __name__ == \"__main__\":", "def __init__(self):", "__note__ 한 단어", "a ~~ b", "[참고]"] {
            #expect(!MemoMarkdown.looks(words), "\(words)")
        }
    }

    // MARK: Paragraph styles and letters

    @Test func headingsBecomeParagraphStyles() {
        let text = memo("# 제목\n## 머리말\n### 부\n#### 더 작은")
        #expect(letters(text) == "제목\n머리말\n부\n더 작은")
        let styles = MemoTodoLines.lines(in: text).map { text.runs[$0.lowerBound][MemoAttributes.Paragraph.self] }
        #expect(styles == [.title, .heading, .sub, .sub])
        // The line breaks are not styled.
        #expect(text.runs.filter { $0[MemoAttributes.Paragraph.self] != nil }.allSatisfy { !text[$0.range].characters.contains("\n") })
    }

    @Test func emphasisCodeAndStrike() {
        let text = memo("글 **굵게** *기울* _또_ __굵__ ~~취소~~ `코드` ***둘 다***")
        #expect(letters(text) == "글 굵게 기울 또 굵 취소 코드 둘 다")
        #expect(marked(text, MemoAttributes.Bold.self) == "굵게|굵|둘 다")
        #expect(marked(text, MemoAttributes.Italic.self) == "기울|또|둘 다")
        #expect(marked(text, MemoAttributes.Strike.self) == "취소")
        #expect(marked(text, MemoAttributes.InlineCode.self) == "코드")
    }

    @Test func codeBlocksAreWholeLinesWithoutTheirLanguage() {
        let text = memo("앞\n\n```swift\nlet a = 1\n\nlet b = *2*\n```\n\n    들여쓴 코드\n")
        #expect(letters(text) == "앞\n\nlet a = 1\n\nlet b = *2*\n\n들여쓴 코드")
        #expect(marked(text, MemoAttributes.Code.self) == "let a = 1\n\nlet b = *2*|들여쓴 코드")
        #expect(text.runs.allSatisfy { $0[MemoAttributes.Italic.self] == nil })
    }

    // MARK: Lists and quotes

    @Test func listsBecomeMemoListLetters() {
        let text = memo("- 대시\n* 별\n+ 더하기\n\n1. 하나\n2. 둘\n\n글\n\n5. 다섯\n6. 여섯")
        #expect(letters(text) == "- 대시\n• 별\n• 더하기\n\n1. 하나\n2. 둘\n\n글\n\n5. 다섯\n6. 여섯")
        // A blank line between items keeps one list, numbered on as Markdown shows it.
        #expect(letters(memo("1. 하나\n\n7. 둘")) == "1. 하나\n\n2. 둘")
    }

    @Test func levelsAreTabsWhateverTheIndent() {
        let expected = "- 하나\n\t- 둘\n\t\t- 셋\n- 넷"
        #expect(letters(memo("- 하나\n  - 둘\n    - 셋\n- 넷")) == expected)
        #expect(letters(memo("- 하나\n    - 둘\n        - 셋\n- 넷")) == expected)
        #expect(letters(memo("- 하나\n\t- 둘\n\t\t- 셋\n- 넷")) == expected)
    }

    @Test func numbersByLevel() {
        let text = memo("1. 하나\n   1. 가\n   2. 나\n      1. 첫\n2. 둘")
        #expect(letters(text) == "1. 하나\n\ta. 가\n\tb. 나\n\t\ti. 첫\n2. 둘")
        // As the memo reads them back.
        let markers = MemoTodoLines.lines(in: text).map { MemoLists.marker(String(text[$0].characters))?.number }
        #expect(markers == [1, 1, 2, 1, 2])
    }

    @Test func quotesAndListsInThem() {
        let text = memo("> 인용 글\n> - 안의 목록\n> 1. 번호")
        #expect(letters(text) == "> 인용 글\n> - 안의 목록\n> 1. 번호")
        let kinds = MemoTodoLines.lines(in: text).map { MemoLists.marker(String(text[$0].characters)) }
        #expect(kinds.map { $0?.kind } == [.quote, .dash, .number] && kinds.dropFirst().allSatisfy { $0?.quoted == true })
    }

    @Test func todoLinesAreDashItemsNotChips() {
        let text = memo("- [ ] 할 일\n- [x] 끝난 일\n- [X] 또 끝")
        #expect(letters(text) == "- 할 일\n- 끝난 일\n- 또 끝")
        #expect(marked(text, MemoAttributes.Strike.self) == "끝난 일|또 끝")
        #expect(text.runs.allSatisfy { $0[MemoAttributes.Todo.self] == nil })
    }

    // MARK: Links, rules, tables

    @Test func linksOnlyWithAddressesTheMemoTakes() {
        let text = memo("[문서](https://a.com/x) [나쁜](javascript:alert(1)) [상대](docs/x.md) <https://b.com> [메일](mailto:me@a.com)")
        #expect(letters(text) == "문서 나쁜 상대 https://b.com 메일")
        let links = text.runs[MemoAttributes.Link.self].compactMap { $0.0 }
        #expect(links == ["https://a.com/x", "https://b.com", "mailto:me@a.com"])
    }

    @Test func picturesAreTheirDescriptionLinked() {
        let text = memo("![설명](https://a.com/x.png) ![](https://a.com/y.png) ![로컬](file:///x.png)")
        #expect(letters(text) == "설명 https://a.com/y.png 로컬")
        #expect(text.runs[MemoAttributes.Link.self].compactMap { $0.0 } == ["https://a.com/x.png", "https://a.com/y.png"])
    }

    @Test func rulesBecomeRuleLines() {
        for mark in ["---", "***", "___"] {
            let text = memo("위\n\n\(mark)\n\n아래")
            #expect(letters(text) == "위\n\n────\n\n아래", "\(mark)")
            #expect(MemoTimeline.isRule(MemoMarkdown.rule))
        }
        // First, with no place of its own given by the parser.
        #expect(letters(memo("---\n\n**아래**")) == "────\n\n아래")
    }

    @Test func tablesBecomeMemoTables() {
        let text = memo("# 표\n\n| 항목 | **값** |\n|---|---|\n| [링크](https://a.com) | ~~2~~ |\n| `c` | $x_1$ |\n\n끝")
        #expect(letters(text) == "표\n\n항목\t값\n링크\t2\nc\t$x_1$\n\n끝")
        #expect(text.runs.contains { $0[MemoAttributes.Table.self] == "t1" })
        #expect(marked(text, MemoAttributes.Bold.self) == "값")
        #expect(marked(text, MemoAttributes.Strike.self) == "2")
        #expect(text.runs[MemoAttributes.Link.self].compactMap { $0.0 } == ["https://a.com"])
        #expect(text.runs.allSatisfy { $0[MemoAttributes.Math.self] == nil })
    }

    // MARK: Formulas

    @Test func inlineFormulasKeepTheirMarksOut() {
        let text = memo("넓이는 $\\pi r_1^2$ 이고 *기울임*과 $a_b * c_d$")
        #expect(letters(text) == "넓이는 \\pi r_1^2 이고 기울임과 a_b * c_d")
        #expect(marked(text, MemoAttributes.Math.self) == "\\pi r_1^2|a_b * c_d")
        #expect(marked(text, MemoAttributes.Italic.self) == "기울임")
    }

    @Test func displayFormulasBecomeFormulaLines() {
        #expect(letters(memo("위\n\n$$\n\\sum_i p_i\n= 1\n$$\n\n아래")) == "위\n\n$$ \\sum_i p_i = 1\n\n아래")
        #expect(letters(memo("$$x_1 + x_2$$")) == "$$ x_1 + x_2")
    }

    @Test func formulasInHeadingsHtmlAndBetweenLines() {
        let heading = memo("# 에너지 $E=mc^2$")
        #expect(letters(heading) == "에너지 E=mc^2" && marked(heading, MemoAttributes.Math.self) == "E=mc^2")
        #expect(letters(memo("**a**\n\n<div>$x$</div>")) == "a\n\n<div>$x$</div>")
        // `$$` lines with words right above and below are still a formula line.
        #expect(letters(memo("식은\n$$\nE=mc^2\n$$\n입니다")) == "식은\n$$ E=mc^2\n입니다")
        // An unclosed `$$` takes nothing past a blank line.
        #expect(letters(memo("$$ 열림\n\n**아래** 끝$$")) == "$$ 열림\n\n아래 끝$$")
        #expect(!String(memo("# $x$ <b>$y$</b>").characters).contains(where: { $0 == MemoMarkdown.openMark || $0 == MemoMarkdown.closeMark }))
    }

    @Test func moneyIsNotAFormula() {
        let text = memo("**값** $5와 $10, $10 and $20, 가격 $3.50")
        #expect(letters(text) == "값 $5와 $10, $10 and $20, 가격 $3.50")
        #expect(text.runs.allSatisfy { $0[MemoAttributes.Math.self] == nil })
    }

    @Test func formulasInCodeStayAsWritten() {
        let text = memo("`$HOME` 과 $x$\n\n```\necho $a_b$\n```")
        #expect(letters(text) == "$HOME 과 x\n\necho $a_b$")
        #expect(marked(text, MemoAttributes.Math.self) == "x")
    }

    // MARK: Lines

    @Test func blankLinesBetweenBlocksAreOne() {
        #expect(letters(memo("**하나**\n\n\n\n둘\n셋\n\n\n")) == "하나\n\n둘\n셋")
        #expect(letters(memo("\n\n# 제목\n본문\n")) == "제목\n본문")
    }

    @Test func linesInAnItemOrQuoteStayInIt() {
        // A line break in the source stays one; under an item it is indented to its words.
        #expect(letters(memo("**글** 하나\n둘")) == "글 하나\n둘")
        #expect(letters(memo("- **하나**\n  이어서\n\n  다음 문단\n- 둘")) == "- 하나\n\t이어서\n\n\t다음 문단\n- 둘")
        #expect(letters(memo("> **a**\n> b")) == "> a\n> b")
    }

    @Test func htmlAndFootnotesStayLetters() {
        #expect(letters(memo("**a** <b>굵게</b> 각주[^1]\n\n<div>블록</div>")) == "a <b>굵게</b> 각주[^1]\n\n<div>블록</div>")
    }

    @Test func storedAndReadBack() throws {
        // Only keys the memo knows: it encodes and decodes as it is.
        let text = memo("# 제목\n- **굵게** [링크](https://a.com)\n\n```\ncode\n```\n$x$")
        let data = try #require(MemoText.encode(text))
        #expect(MemoText.decode(data) == text)
    }
}
