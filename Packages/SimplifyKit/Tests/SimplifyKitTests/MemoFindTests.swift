import Foundation
import Testing
@testable import SimplifyKit

/// ⌘F in one memo: where words are found, which letters are passed over, and replacing them.
struct MemoFindTests {
    private func string(_ text: AttributedString, _ ranges: [NSRange]) -> [String] {
        let letters = String(text.characters) as NSString
        return ranges.map { letters.substring(with: $0) }
    }

    @Test func findsEveryPlaceIgnoringCase() {
        let text = AttributedString("Swift 회의, swift 회의실\nSWIFT")
        let swift = MemoFind.matches(of: "swift", in: text)
        #expect(string(text, swift) == ["Swift", "swift", "SWIFT"])
        // Korean letter for letter: 회 finds both.
        #expect(MemoFind.matches(of: "회", in: text).count == 2)
        #expect(MemoFind.matches(of: "회의", in: text).map(\.location) == [6, 16])
        #expect(MemoFind.matches(of: "", in: text).isEmpty)
        #expect(MemoFind.matches(of: "없는 말", in: text).isEmpty)
        #expect(MemoFind.matches(of: "a", in: AttributedString()).isEmpty)
    }

    @Test func placesDoNotOverlap() {
        let text = AttributedString("aaaa")
        #expect(MemoFind.matches(of: "aa", in: text) == [NSRange(location: 0, length: 2), NSRange(location: 2, length: 2)])
    }

    @Test func chipsAndAttachmentsArePassedOver() {
        var text = AttributedString("주간 회의 ")
        text += MemoChips.chip(id: UUID(), title: "회의 자료 보내기", isDone: false)
        text += AttributedString(" 오후 회의")
        var card = AttributedString(String(MemoAttachments.placeholder))
        card[MemoAttributes.Attachment.self] = "id/회의.pdf"
        text += card
        let found = MemoFind.matches(of: "회의", in: text)
        #expect(found.count == 2)
        let skipped = MemoFind.skippedRanges(in: text)
        #expect(!found.contains { range in skipped.contains { NSIntersectionRange($0, range).length > 0 } })
        // Finding the chip's own words finds nothing.
        #expect(MemoFind.matches(of: "자료 보내기", in: text).isEmpty)
    }

    @Test func tablesCodeAndFormulasAreFound() {
        var row = AttributedString("사과\t1,200")
        row[MemoAttributes.Table.self] = "t1"
        var code = AttributedString("fruit = \"사과\"")
        code[MemoAttributes.Code.self] = true
        let text = row + AttributedString("\n") + code + AttributedString("\n내일 사과")
        #expect(MemoFind.matches(of: "사과", in: text).count == 3)
    }

    @Test func theFirstPlaceIsAfterTheCaretAndStepsGoRound() {
        let ranges = [NSRange(location: 2, length: 2), NSRange(location: 10, length: 2), NSRange(location: 20, length: 2)]
        #expect(MemoFind.firstIndex(from: 0, in: ranges) == 0)
        #expect(MemoFind.firstIndex(from: 5, in: ranges) == 1)
        #expect(MemoFind.firstIndex(from: 30, in: ranges) == 0)
        #expect(MemoFind.firstIndex(from: 0, in: []) == nil)
        #expect(MemoFind.step(2, by: 1, count: 3) == 0)
        #expect(MemoFind.step(0, by: -1, count: 3) == 2)
        #expect(MemoFind.step(nil, by: -1, count: 3) == 2)
        #expect(MemoFind.step(nil, by: 1, count: 3) == 0)
        #expect(MemoFind.step(1, by: 1, count: 0) == nil)
    }

    @Test func aReplacementKeepsTableCellsAndLines() {
        #expect(MemoFind.replacement("a\tb\nc", inTable: true) == "abc")
        #expect(MemoFind.replacement("a\tb\nc", inTable: false) == "a\tbc")
        #expect(MemoFind.replacement("미팅", inTable: true) == "미팅")
    }

    @Test func replacingAllGoesBackToFront() {
        var row = AttributedString("회의\t시간")
        row[MemoAttributes.Table.self] = "t1"
        let text = AttributedString("주간 회의 준비\n") + row + AttributedString("\n오후 회의")
        let found = MemoFind.matches(of: "회의", in: text)
        #expect(found.count == 3)
        #expect(MemoFind.replaceAllOrder(found).map(\.location) == found.map(\.location).reversed())
    }
}
