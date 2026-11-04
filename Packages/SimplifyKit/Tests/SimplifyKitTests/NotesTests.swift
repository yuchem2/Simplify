import Foundation
import Testing
@testable import SimplifyKit

/// Copies of memos in the 메모 app: names, the HTML body, and what this Mac remembers about them.
struct NotesTests {
    private let calendar = Calendar.simplify(firstWeekday: 1)

    private func styled(_ string: String, _ build: (inout AttributeContainer) -> Void = { _ in }) -> AttributedString {
        var container = AttributeContainer()
        build(&container)
        return AttributedString(string, attributes: container)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// The body's lines after the name.
    private func lines(_ text: AttributedString) throws -> [String] {
        Array(try #require(NotesHTML.body(name: "이름", text: text)).components(separatedBy: "\n").dropFirst())
    }

    @Test func notesAreNamedAfterTheirPeriod() {
        let day = date(2026, 11, 3)
        #expect(NotesHTML.noteName(for: Period(containing: day, scope: .day, calendar: calendar)) == "2026년 11월 3일 (화)")
        #expect(NotesHTML.noteName(for: Period(containing: day, scope: .week, calendar: calendar)) == "2026년 11월 1주차 (11.1 – 11.7)")
        #expect(NotesHTML.noteName(for: Period(containing: day, scope: .month, calendar: calendar)) == "2026년 11월")
        // Monday weeks: the week holding 3 November starts on the 2nd.
        let monday = Calendar.simplify(firstWeekday: 2)
        #expect(NotesHTML.noteName(for: Period(containing: day, scope: .week, calendar: monday)) == "2026년 11월 1주차 (11.2 – 11.8)")
        // A week across the year end takes the year of the month it is named after.
        #expect(NotesHTML.noteName(for: Period(containing: date(2027, 1, 1), scope: .week, calendar: calendar)) == "2026년 12월 4주차 (12.27 – 1.2)")
    }

    @Test func theNameIsTheFirstLineAndEachLineItsOwnDiv() throws {
        let html = try #require(NotesHTML.body(name: "2026년 11월", text: styled("장보기\n\n우유")))
        #expect(html == "<div><h1>2026년 11월</h1></div>\n<div>장보기</div>\n<div><br></div>\n<div>우유</div>")
    }

    @Test func formulasAreTheirLaTeXInDollars() throws {
        var text = styled("근의 공식 ")
        text += styled("x = \\frac{-b}{2a}") { $0[MemoAttributes.Math.self] = true }
        text += styled(" 로 풀기\n$$ \\sum_{i=1}^{n} p_i < 1\n")
        text += styled("$$ 코드는 그대로") { $0[MemoAttributes.Code.self] = true }
        #expect(try lines(text) == [
            "<div>근의 공식 $x = \\frac{-b}{2a}$ 로 풀기</div>",
            "<div>$$\\sum_{i=1}^{n} p_i &lt; 1$$</div>",
            "<div><tt>$$ 코드는 그대로</tt></div>",
        ])
    }

    @Test func aColouredFormulaIsOneFormula() throws {
        var text = styled("a + ") { $0[MemoAttributes.Math.self] = true }
        text += styled("b") { $0[MemoAttributes.Math.self] = true; $0[MemoAttributes.Ink.self] = .red }
        #expect(try lines(text) == ["<div>$a + <span style=\"color: #b3332a\">b</span>$</div>"])
    }

    @Test func oldFormulasMirrorTheirScriptsAsLaTeX() throws {
        var text = styled("w = 0.9w") { $0[MemoAttributes.Math.self] = true }
        text += styled("0") { $0[MemoAttributes.Math.self] = true; $0[MemoAttributes.Script.self] = .lowered }
        #expect(try lines(text) == ["<div>$w = 0.9w_{0}$</div>"])
    }

    @Test func blankMemosHaveNoBody() {
        #expect(NotesHTML.body(name: "이름", text: AttributedString()) == nil)
        #expect(NotesHTML.body(name: "이름", text: styled(" \n\n  ")) == nil)
    }

    @Test func blankLinesAroundTheMemoAreDropped() throws {
        #expect(try lines(styled("\n\n할 일\n\n")) == ["<div>할 일</div>"])
    }

    @Test func eachFormattingHasItsTag() throws {
        #expect(try lines(styled("굵게") { $0[MemoAttributes.Bold.self] = true }) == ["<div><b>굵게</b></div>"])
        #expect(try lines(styled("기울임") { $0[MemoAttributes.Italic.self] = true }) == ["<div><i>기울임</i></div>"])
        #expect(try lines(styled("2") { $0[MemoAttributes.Script.self] = .raised }) == ["<div><sup>2</sup></div>"])
        #expect(try lines(styled("0") { $0[MemoAttributes.Script.self] = .lowered }) == ["<div><sub>0</sub></div>"])
        #expect(try lines(styled("let x = 1") { $0[MemoAttributes.Code.self] = true }) == ["<div><tt>let x = 1</tt></div>"])
        #expect(try lines(styled("E=mc^2") { $0[MemoAttributes.Math.self] = true }) == ["<div>$E=mc^2$</div>"])
        #expect(try lines(styled("빨강") { $0[MemoAttributes.Ink.self] = .red }) == ["<div><span style=\"color: #b3332a\">빨강</span></div>"])
        #expect(try lines(styled("노랑") { $0[MemoAttributes.Highlight.self] = .yellow })
            == ["<div><span style=\"background-color: #faf0c4\">노랑</span></div>"])
    }

    @Test func underlineAndStrike() throws {
        #expect(try lines(styled("밑줄") { $0[MemoAttributes.Underline.self] = true }) == ["<div><u>밑줄</u></div>"])
        #expect(try lines(styled("취소") { $0[MemoAttributes.Strike.self] = true }) == ["<div><strike>취소</strike></div>"])
    }

    /// The note's name is its `<h1>`; the memo's own title and headings come under it.
    @Test func paragraphStylesSitUnderTheName() throws {
        var text = styled("11월 정리") { $0[MemoAttributes.Paragraph.self] = .title }
        text += styled("\n")
        text += styled("회의") { $0[MemoAttributes.Paragraph.self] = .heading }
        text += styled("\n")
        text += styled("결정") { $0[MemoAttributes.Paragraph.self] = .sub }
        text += styled("\n본문")
        #expect(try lines(text) == ["<div><h2>11월 정리</h2></div>", "<div><h3>회의</h3></div>", "<div><b>결정</b></div>", "<div>본문</div>"])
    }

    @Test func listsBecomeNestedListTags() throws {
        let text = styled("1. 견적서\n2. 리뷰\n\ta. 시안\n\tb. 색상\n3. 치과\n• 배포\n\t• QA\n- 회의록\n끝")
        #expect(try lines(text) == [
            "<ol>", "<li>견적서</li>", "<li>리뷰</li>", "<ol>", "<li>시안</li>", "<li>색상</li>", "</ol>", "<li>치과</li>", "</ol>",
            "<ul>", "<li>배포</li>", "<ul>", "<li>QA</li>", "</ul>", "</ul>",
            "<ul class=\"Apple-dash-list\">", "<li>회의록</li>", "</ul>",
            "<div>끝</div>",
        ])
    }

    @Test func codeLinesAreNotListsAndNumbersKeepTheirStart() throws {
        let code = styled("- name: x\n> out.txt") { $0[MemoAttributes.Code.self] = true }
        #expect(try lines(code) == ["<div><tt>- name: x</tt></div>", "<div><tt>&gt; out.txt</tt></div>"])
        #expect(try lines(styled("3. 셋\n4. 넷")) == ["<ol start=\"3\">", "<li>셋</li>", "<li>넷</li>", "</ol>"])
    }

    @Test func listsInsideAQuoteStayInIt() throws {
        #expect(try lines(styled("> 말\n> • 하나\n> \t• 둘\n끝")) == [
            "<blockquote>", "<div>말</div>", "<ul>", "<li>하나</li>", "<ul>", "<li>둘</li>", "</ul>", "</ul>", "</blockquote>", "<div>끝</div>",
        ])
    }

    @Test func listItemsKeepTheirFormatting() throws {
        var text = styled("• ")
        text += styled("굵게") { $0[MemoAttributes.Bold.self] = true }
        #expect(try lines(text) == ["<ul>", "<li><b>굵게</b></li>", "</ul>"])
    }

    @Test func quoteLinesShareABlockquote() throws {
        #expect(try lines(styled("> 범위를 줄이고\n> 마감을 지키자\n다음")) == [
            "<blockquote>", "<div>범위를 줄이고</div>", "<div>마감을 지키자</div>", "</blockquote>", "<div>다음</div>",
        ])
    }

    @Test func formattingStacksAndMixesWithinALine() throws {
        var text = styled("견적서") { $0[MemoAttributes.Bold.self] = true; $0[MemoAttributes.Italic.self] = true; $0[MemoAttributes.Ink.self] = .blue; $0[MemoAttributes.Highlight.self] = .pink }
        text += styled(" 보내기")
        #expect(try lines(text) == ["<div><span style=\"color: #2a5fc4; background-color: #f9e0e9\"><b><i>견적서</i></b></span> 보내기</div>"])
    }

    @Test func formattingCarriesAcrossLineBreaks() throws {
        let text = styled("첫 줄\n둘째 줄") { $0[MemoAttributes.Bold.self] = true }
        #expect(try lines(text) == ["<div><b>첫 줄</b></div>", "<div><b>둘째 줄</b></div>"])
    }

    @Test func codeBlocksTakeNoHighlighter() throws {
        let text = styled("x") { $0[MemoAttributes.Code.self] = true; $0[MemoAttributes.Highlight.self] = .green }
        #expect(try lines(text) == ["<div><tt>x</tt></div>"])
    }

    @Test func todoChipsBecomeBoxLetters() throws {
        let id = UUID()
        var text = styled("오늘 ")
        text += MemoChips.chip(id: id, title: "견적서 보내기", isDone: false)
        text += styled("\n")
        text += MemoChips.chip(id: UUID(), title: "장보기", isDone: true)
        #expect(try lines(text) == ["<div>오늘 ☐ 견적서 보내기</div>", "<div>☑ 장보기</div>"])
    }

    @Test func lettersAreEscaped() throws {
        let text = styled("<script>alert(\"x\" & 'y')</script>")
        #expect(try lines(text) == ["<div>&lt;script&gt;alert(&quot;x&quot; &amp; &#39;y&#39;)&lt;/script&gt;</div>"])
        let named = try #require(NotesHTML.body(name: "<b>&", text: styled("a")))
        #expect(named.hasPrefix("<div><h1>&lt;b&gt;&amp;</h1></div>"))
    }

    @Test func indentsAndRunsOfSpacesSurvive() throws {
        #expect(try lines(styled("  a  b")) == ["<div>&nbsp;&nbsp;a &nbsp;b</div>"])
        // A space ending one run and starting the next still counts as a run of spaces.
        var text = styled("a ") { $0[MemoAttributes.Bold.self] = true }
        text += styled(" b")
        #expect(try lines(text) == ["<div><b>a </b>&nbsp;b</div>"])
    }

    /// The colours written into notes are the palette's light values in `design/tokens.json`.
    @Test func coloursMatchTheDesignTokens() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../../design/tokens.json").standardized
        // Aliases (`"value": "ink"`) have no light value of their own and are skipped.
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let tokens = try #require((json["color"] as? [String: Any])?["tokens"] as? [[String: Any]])
        var light: [String: String] = [:]
        for token in tokens {
            if let name = token["name"] as? String, let value = (token["value"] as? [String: Any])?["light"] as? String {
                light[name] = value.lowercased()
            }
        }
        for palette in Palette.allCases {
            #expect(NotesHTML.lightInk(palette) == light["\(palette.rawValue)-ink"], "\(palette)")
            #expect(NotesHTML.lightTint(palette) == light["\(palette.rawValue)-tint"], "\(palette)")
        }
    }

    @Test func idsAndPendingKeysAreKeptPerMac() throws {
        let defaults = try #require(UserDefaults(suiteName: "NotesTests-\(UUID())"))
        #expect(SharedSettings.notesNoteIDs(in: defaults).isEmpty)
        #expect(SharedSettings.notesPending(in: defaults).isEmpty)
        SharedSettings.setNotesNoteIDs(["2026-11-03": "x-coredata://note/p1"], in: defaults)
        SharedSettings.setNotesPending(["2026-11", "2026-W45"], in: defaults)
        #expect(SharedSettings.notesNoteIDs(in: defaults) == ["2026-11-03": "x-coredata://note/p1"])
        #expect(SharedSettings.notesPending(in: defaults) == ["2026-11", "2026-W45"])
        #expect(defaults.bool(forKey: SharedSettings.mirrorsToNotes) == false)
    }
}
