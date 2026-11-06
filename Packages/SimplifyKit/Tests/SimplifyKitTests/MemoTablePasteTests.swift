import Foundation
import Testing
@testable import SimplifyKit

/// Tables pasted from elsewhere (Markdown, tab-split lines) and a memo's own pieces through the
/// clipboard.
struct MemoTablePasteTests {
    private func texts(_ rows: [[MemoTablePaste.Cell]]) -> [[String]] { rows.map { $0.map(\.text) } }

    @Test func aMarkdownTableBecomesATable() throws {
        let pieces = try #require(MemoTablePaste.markdownPieces("""
        위 글
        | 항목 | 값 |
        |:---|---:|
        | 사과 | 1,200 |
        | 배 \\| 감 | 800 |
        아래 글
        """))
        #expect(pieces.count == 3)
        #expect(pieces[0] == .lines("위 글"))
        guard case .table(let rows) = pieces[1] else { Issue.record("no table"); return }
        #expect(texts(rows) == [["항목", "값"], ["사과", "1,200"], ["배 | 감", "800"]])
        #expect(pieces[2] == .lines("아래 글"))
    }

    @Test func markdownWithoutOuterPipesAndRaggedRows() throws {
        let pieces = try #require(MemoTablePaste.markdownPieces("a | b | c\n--- | --- | ---\n1 | 2\n**굵게** | *기울임* | ~~줄~~"))
        guard case .table(let rows) = pieces.first else { Issue.record("no table"); return }
        #expect(texts(rows) == [["a", "b", "c"], ["1", "2", ""], ["굵게", "기울임", "줄"]])
        #expect(rows[2][0].bold && rows[2][1].italic && rows[2][2].strike)
    }

    @Test func pipesWithoutADividerAreWords() {
        #expect(MemoTablePaste.markdownPieces("a | b\nc | d") == nil)
        #expect(MemoTablePaste.markdownPieces("그냥 글") == nil)
    }

    @Test func notesTableTextIsAGrid() throws {
        // A table copied from the 메모 app, as its plain text comes.
        let copied = """
        측정\t결과
        단일 케이스 12개 × 3회 (14:1x)\t화면 요청은 모두 1번이었습니다. 하지만 50초를 넘은 실행이 4/36회였고, "나이키 에어포스1"은 판매 페이지를 3회 모두 못 찾았습니다.
        상품명 10개 × 3회 × 3구조\t평균 S4 14.9초, S2 17.0초, S1 21.5초. 50초 초과는 S1 1회입니다.
        URL·요청서 4개 × 3회 × 3구조\t이번에는 50초 초과가 없었고 평균은 23~27초입니다.
        지금 코드와 main 시간 분석\t시간의 80~95%가 XGEN입니다.
        """
        let rows = try #require(MemoTablePaste.tabGrid(copied))
        #expect(rows.count == 5 && rows.allSatisfy { $0.count == 2 })
        #expect(rows[0].map(\.text) == ["측정", "결과"])
        #expect(rows[1][1].text.contains("\"나이키 에어포스1\""))
    }

    @Test func memoLinesWithTabsAreNotAGrid() {
        // List items, a timeline line's children, indented lines, ragged lines, one line.
        #expect(MemoTablePaste.tabGrid("• 하나\t둘\n• 셋\t넷") == nil)
        #expect(MemoTablePaste.tabGrid("11.02 08:30 회의\t메모\n11.02 09:00 점심\t식당") == nil)
        #expect(MemoTablePaste.tabGrid("\t안건\t하나\n\t결론\t둘") == nil)
        #expect(MemoTablePaste.tabGrid("a\tb\nc\td\te") == nil)
        #expect(MemoTablePaste.tabGrid("a\tb") == nil)
        #expect(MemoTablePaste.tabGrid("a\nb") == nil)
    }

    @Test func tidyingDropsEmptyEdgesAndJoinsLines() throws {
        let cell = { MemoTablePaste.Cell($0) }
        let rows = try #require(MemoTablePaste.tidy([
            [cell(""), cell(""), cell(""), cell("")],
            [cell(""), cell("이름"), cell(""), cell("")],
            [cell(""), cell("둘째\n줄"), cell(""), cell("값")],
            [cell(""), cell(""), cell(""), cell("")],
        ]))
        // The empty first column and edge rows go; the empty middle column stays.
        #expect(texts(rows) == [["이름", "", ""], ["둘째 줄", "", "값"]])
        #expect(MemoTablePaste.tidy([[cell("하나")], [cell("둘")]]) == nil)
    }

    @Test func memoTextMarksEachTableUnderItsOwnID() {
        var ids = ["t1", "t2"].makeIterator()
        let cell = { MemoTablePaste.Cell($0) }
        let text = MemoTablePaste.memoText([.lines("위"), .table([[cell("a"), cell("b")], [cell("c"), MemoTablePaste.Cell("d", bold: true)]]),
                                            .table([[cell("x"), cell("y")]])], newID: { ids.next()! })
        #expect(String(text.characters) == "위\na\tb\nc\td\nx\ty")
        let marks = text.runs.map { (String(text[$0.range].characters), $0[MemoAttributes.Table.self]) }
        #expect(marks.contains { $0.0 == "\n" && $0.1 == nil })
        #expect(text.runs.contains { $0[MemoAttributes.Bold.self] == true && String(text[$0.range].characters) == "d" })
        #expect(Set(text.runs.compactMap { $0[MemoAttributes.Table.self] }) == ["t1", "t2"])
    }

    @Test func aMemoPieceComesBackUnderNewTableIDs() throws {
        var original = MemoTablePaste.table([[MemoTablePaste.Cell("a"), MemoTablePaste.Cell("b", bold: true)]], id: "old")
        original += AttributedString("\n뒤")
        let data = try #require(MemoTablePaste.clip(original))
        let back = try #require(MemoTablePaste.unclip(data, newID: { "new" }))
        #expect(String(back.characters) == "a\tb\n뒤")
        #expect(Set(back.runs.compactMap { $0[MemoAttributes.Table.self] }) == ["new"])
        #expect(back.runs.contains { $0[MemoAttributes.Bold.self] == true })
    }

    @Test func onlyRowsAreATableNotWordsInACell() {
        let row = MemoTablePaste.table([[MemoTablePaste.Cell("사과"), MemoTablePaste.Cell("3")]], id: "t")
        #expect(MemoTablePaste.holdsTable(row))
        // "사과" picked inside its cell.
        let word = AttributedString(row[row.startIndex..<row.characters.index(row.startIndex, offsetBy: 2)])
        #expect(!MemoTablePaste.holdsTable(word))
        #expect(!MemoTablePaste.holdsTable(AttributedString("a\tb")))
    }

    @Test func marksInsideACellStayLetters() throws {
        let pieces = try #require(MemoTablePaste.markdownPieces("| a | b |\n|---|---|\n| **x** 와 **y** | `c` |"))
        guard case .table(let rows) = pieces.first else { Issue.record("no table"); return }
        #expect(rows[1][0].text == "**x** 와 **y**" && !rows[1][0].bold)
    }

    @Test func renewingGivesEachTableItsOwnNewID() {
        var text = MemoTablePaste.table([[MemoTablePaste.Cell("a"), MemoTablePaste.Cell("b")]], id: "one")
        text += AttributedString("\n")
        text += MemoTablePaste.table([[MemoTablePaste.Cell("c"), MemoTablePaste.Cell("d")]], id: "two")
        var made = ["n1", "n2"].makeIterator()
        let renewed = MemoTablePaste.renewingTables(text, newID: { made.next()! })
        #expect(Set(renewed.runs.compactMap { $0[MemoAttributes.Table.self] }) == ["n1", "n2"])
        #expect(String(renewed.characters) == String(text.characters))
    }

    @Test func largeTablesAreNoticed() {
        let row = (0..<21).map { MemoTablePaste.Cell("\($0)") }
        #expect(MemoTablePaste.isLarge([.table([row])]))
        #expect(!MemoTablePaste.isLarge([.table([Array(row.prefix(3))])]))
    }

    @Test func theClipboardHTMLHasTheTableAndNoName() throws {
        let text = MemoTablePaste.table([[MemoTablePaste.Cell("a"), MemoTablePaste.Cell("b")]], id: "t")
        let html = try #require(NotesHTML.fragment(text))
        #expect(html == "<table>\n<tr><td>a</td><td>b</td></tr>\n</table>")
    }
}
