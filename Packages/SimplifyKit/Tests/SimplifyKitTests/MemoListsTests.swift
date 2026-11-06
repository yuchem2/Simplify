import Foundation
import Testing
@testable import SimplifyKit

/// Lists and quotes as letters: reading their markers, and what Return, Tab, Delete and the 서식
/// menu do to them.
struct MemoListsTests {
    /// The letters after making `change`'s edits one by one.
    private func applied(_ change: MemoLists.Change?, to text: String) -> String? {
        guard let change else { return nil }
        let string = NSMutableString(string: text)
        for edit in change.edits { string.replaceCharacters(in: edit.range, with: edit.text) }
        return string as String
    }

    private func utf16(_ string: String) -> Int { (string as NSString).length }

    @Test func markersAreRead() {
        #expect(MemoLists.marker("• 하나")?.kind == .bullet)
        #expect(MemoLists.marker("- 하나")?.kind == .dash)
        #expect(MemoLists.marker("> 인용")?.kind == .quote)
        #expect(MemoLists.marker("12. 열두째") == MemoLists.Marker(kind: .number, level: 0, label: "12.", length: 4, number: 12))
        #expect(MemoLists.marker("\tb. 둘째") == MemoLists.Marker(kind: .number, level: 1, label: "b.", length: 4, number: 2))
        #expect(MemoLists.marker("\t\tiv. 넷째")?.number == 4)
        #expect(MemoLists.marker("\t\t• 셋째 단계")?.level == 2)
        // As deep as the tabs go.
        #expect(MemoLists.marker("\t\t\t• 넷째 단계")?.level == 3)
        // Not lists: no space, letters at the outer level, a rule, words.
        #expect(MemoLists.marker("-하나") == nil)
        #expect(MemoLists.marker("a. 아니요") == nil)
        #expect(MemoLists.marker("\t\tiiii. 아니요") == nil)
        #expect(MemoLists.marker("----") == nil)
        #expect(MemoLists.marker("\t> 인용") == nil)
        #expect(MemoLists.marker("1.5배") == nil)
        // Dates are words: a year is too long for a number, and `11. 4.` runs on into its day.
        #expect(MemoLists.marker("2026. 11. 4 회의") == nil)
        #expect(MemoLists.marker("11. 4. 회의") == nil)
        #expect(MemoLists.marker("11. 4명") != nil)
        #expect(MemoLists.marker("1. 3.5% 상승") != nil)
    }

    @Test func labelsByLevel() {
        #expect(MemoLists.label(3, level: 0) == "3.")
        #expect(MemoLists.label(1, level: 1) == "a.")
        #expect(MemoLists.label(27, level: 1) == "aa.")
        #expect(MemoLists.label(4, level: 2) == "iv.")
        #expect(MemoLists.shownLabel(MemoLists.marker("• x")!) == "●")
        #expect(MemoLists.shownLabel(MemoLists.marker("\t• x")!) == "○")
        #expect(MemoLists.shownLabel(MemoLists.marker("\t\t• x")!) == "■")
        #expect(MemoLists.shownLabel(MemoLists.marker("- x")!) == "–")
    }

    @Test func aStarAndASpaceMakeABullet() {
        let text = "할 일\n* "
        let change = MemoLists.autoBullet(in: text, caret: utf16(text))
        #expect(applied(change, to: text) == "할 일\n• ")
        #expect(applied(MemoLists.autoBullet(in: "\t* ", caret: 3), to: "\t* ") == "\t• ")
        // Only at the front of a line.
        #expect(MemoLists.autoBullet(in: "a * ", caret: 4) == nil)
        #expect(MemoLists.autoBullet(in: "** ", caret: 3) == nil)
    }

    @Test func returnMakesTheNextItem() {
        let text = "1. 견적서\n2. 리뷰"
        let caret = utf16("1. 견적서")
        let change = MemoLists.returnKey(in: text, caret: caret)
        // The item below is numbered again.
        #expect(applied(change, to: text) == "1. 견적서\n2. \n3. 리뷰")
        #expect(change?.selection == NSRange(location: utf16("1. 견적서\n2. "), length: 0))
        #expect(applied(MemoLists.returnKey(in: "• 하나", caret: 4), to: "• 하나") == "• 하나\n• ")
        #expect(applied(MemoLists.returnKey(in: "\t- 하나", caret: 5), to: "\t- 하나") == "\t- 하나\n\t- ")
        #expect(applied(MemoLists.returnKey(in: "> 말", caret: 3), to: "> 말") == "> 말\n> ")
    }

    @Test func returnInTheMiddleSplitsTheItem() {
        let change = MemoLists.returnKey(in: "• 견적서보내기", caret: 5)
        #expect(applied(change, to: "• 견적서보내기") == "• 견적서\n• 보내기")
        #expect(change?.selection.location == 8)
    }

    @Test func returnOnAnEmptyItemStepsOut() {
        #expect(applied(MemoLists.returnKey(in: "• 하나\n• ", caret: 7), to: "• 하나\n• ") == "• 하나\n")
        #expect(applied(MemoLists.returnKey(in: "1. 하나\n\ta. ", caret: 10), to: "1. 하나\n\ta. ") == "1. 하나\n2. ")
        #expect(applied(MemoLists.returnKey(in: "> ", caret: 2), to: "> ") == "")
    }

    @Test func returnElsewhereIsALineBreak() {
        #expect(MemoLists.returnKey(in: "그냥 줄", caret: 2) == nil)
        // Before or inside the marker.
        #expect(MemoLists.returnKey(in: "• 하나", caret: 0) == nil)
        #expect(MemoLists.returnKey(in: "12. 하나", caret: 2) == nil)
    }

    @Test func deleteAtTheItemsStartTakesTheMarker() {
        let text = "1. 하나\n2. 둘\n3. 셋"
        let change = MemoLists.deleteBackward(in: text, caret: utf16("1. 하나\n2. "))
        // The list after the line keeps its place, as a typed `3. ` would.
        #expect(applied(change, to: text) == "1. 하나\n둘\n3. 셋")
        #expect(change?.selection.location == utf16("1. 하나\n"))
        #expect(applied(MemoLists.deleteBackward(in: "\t• 둘", caret: 3), to: "\t• 둘") == "둘")
        #expect(MemoLists.deleteBackward(in: "• 하나", caret: 3) == nil)
    }

    @Test func tabMovesItemsAndNumbersFollow() {
        let text = "1. 하나\n2. 둘\n3. 셋"
        let caret = utf16("1. 하나\n2. 둘")
        let change = MemoLists.indent(in: text, selection: NSRange(location: caret, length: 0), by: 1)
        #expect(applied(change, to: text) == "1. 하나\n\ta. 둘\n2. 셋")
        #expect(change?.selection.location == caret + 1)
        let back = applied(change, to: text)!
        #expect(applied(MemoLists.indent(in: back, selection: NSRange(location: utf16("1. 하나\n\ta"), length: 0), by: -1), to: back) == text)
        // Past the third level too; Tab on a plain line is a tab.
        #expect(applied(MemoLists.indent(in: "\t\t• 셋", selection: NSRange(location: 5, length: 0), by: 1), to: "\t\t• 셋") == "\t\t\t• 셋")
        #expect(MemoLists.indent(in: "그냥", selection: NSRange(location: 1, length: 0), by: 1) == nil)
        #expect(MemoLists.indent(in: "• 하나", selection: NSRange(location: 3, length: 0), by: -1) == nil)
    }

    @Test func bracketKeysMovePlainLinesToo() {
        #expect(applied(MemoLists.indent(in: "그냥", selection: NSRange(location: 1, length: 0), by: 1, listsOnly: false), to: "그냥") == "\t그냥")
        #expect(applied(MemoLists.indent(in: "\t그냥", selection: NSRange(location: 2, length: 0), by: -1, listsOnly: false), to: "\t그냥") == "그냥")
    }

    @Test func tabOnSeveralLines() {
        let text = "• 하나\n• 둘\n• 셋"
        let selection = NSRange(location: utf16("• 하나\n"), length: utf16("• 둘\n• 셋"))
        #expect(applied(MemoLists.indent(in: text, selection: selection, by: 1), to: text) == "• 하나\n\t• 둘\n\t• 셋")
    }

    @Test func menuItemsSetAndClearKinds() {
        let text = "견적서\n리뷰"
        let all = NSRange(location: 0, length: utf16(text))
        let numbered = applied(MemoLists.setKind(.number, in: text, selection: all), to: text)!
        #expect(numbered == "1. 견적서\n2. 리뷰")
        #expect(applied(MemoLists.setKind(.number, in: numbered, selection: NSRange(location: 0, length: utf16(numbered))), to: numbered) == text)
        #expect(applied(MemoLists.setKind(.dash, in: numbered, selection: NSRange(location: 0, length: utf16(numbered))), to: numbered) == "- 견적서\n- 리뷰")
        // A quote goes around the item.
        #expect(applied(MemoLists.setKind(.quote, in: "\t• 말", selection: NSRange(location: 4, length: 0)), to: "\t• 말") == "> \t• 말")
        // A caret on an empty line starts an item there; the caret goes after the marker.
        let empty = MemoLists.setKind(.bullet, in: "", selection: NSRange(location: 0, length: 0))
        #expect(applied(empty, to: "") == "• ")
        #expect(empty.selection.location == 2)
        // Blank lines inside a longer selection stay blank.
        #expect(applied(MemoLists.setKind(.bullet, in: "가\n\n나", selection: NSRange(location: 0, length: 4)), to: "가\n\n나") == "• 가\n\n• 나")
    }

    @Test func listsInsideQuotes() {
        #expect(MemoLists.marker("> • 하나") == MemoLists.Marker(kind: .bullet, level: 0, label: "•", length: 4, number: nil, quoted: true))
        #expect(MemoLists.marker("> \tb. 둘")?.labelOffset == 3)
        #expect(MemoLists.marker("> \tb. 둘")?.number == 2)
        #expect(MemoLists.marker("> 그냥 인용")?.kind == .quote)
        #expect(MemoLists.marker("> 그냥 인용")?.isQuoted == true)
        // Return keeps the quote; an empty item ends the list but not the quote.
        #expect(applied(MemoLists.returnKey(in: "> 1. 하나", caret: 7), to: "> 1. 하나") == "> 1. 하나\n> 2. ")
        #expect(applied(MemoLists.returnKey(in: "> - 하나\n> - ", caret: utf16("> - 하나\n> - ")), to: "> - 하나\n> - ") == "> - 하나\n> ")
        #expect(applied(MemoLists.returnKey(in: "> \t• 둘\n> \t• ", caret: utf16("> \t• 둘\n> \t• ")), to: "> \t• 둘\n> \t• ") == "> \t• 둘\n> • ")
        // Tab and Delete inside the quote.
        #expect(applied(MemoLists.indent(in: "> • 하나\n> • 둘", selection: NSRange(location: 11, length: 0), by: 1), to: "> • 하나\n> • 둘")
                == "> • 하나\n> \t• 둘")
        #expect(applied(MemoLists.deleteBackward(in: "> • 하나", caret: 4), to: "> • 하나") == "> 하나")
        // * and a space after the quote's mark.
        #expect(applied(MemoLists.autoBullet(in: "> * ", caret: 4), to: "> * ") == "> • ")
    }

    @Test func quoteAndListMenuItemsWorkTogether() {
        let all = { (text: String) in NSRange(location: 0, length: (text as NSString).length) }
        // A list item put in a quote keeps its marker, and comes out of it again.
        let quoted = applied(MemoLists.setKind(.quote, in: "1. 하나\n2. 둘", selection: all("1. 하나\n2. 둘")), to: "1. 하나\n2. 둘")!
        #expect(quoted == "> 1. 하나\n> 2. 둘")
        #expect(applied(MemoLists.setKind(.quote, in: quoted, selection: all(quoted)), to: quoted) == "1. 하나\n2. 둘")
        // A list made inside a quote, and taken off again.
        let listed = applied(MemoLists.setKind(.bullet, in: "> 말\n> 글", selection: all("> 말\n> 글")), to: "> 말\n> 글")!
        #expect(listed == "> • 말\n> • 글")
        #expect(applied(MemoLists.setKind(.bullet, in: listed, selection: all(listed)), to: listed) == "> 말\n> 글")
        #expect(applied(MemoLists.setKind(.number, in: listed, selection: all(listed)), to: listed) == "> 1. 말\n> 2. 글")
        #expect(MemoLists.marker(in: "가\n> • 나", at: 3)?.isQuoted == true)
    }

    @Test func listsInAndOutOfAQuoteCountApart() {
        let text = "1. 가\n> 1. 나\n> 5. 다\n2. 라"
        let string = NSMutableString(string: text)
        for edit in MemoLists.renumber(in: text, range: NSRange(location: 0, length: 0)) { string.replaceCharacters(in: edit.range, with: edit.text) }
        #expect(string as String == "1. 가\n> 1. 나\n> 2. 다\n2. 라")
    }

    @Test func numberingRestartsUnderEachParentAndAfterBreaks() {
        let text = "1. 가\n\tc. 나\n\tf. 다\n9. 라\n\ta. 마\n• 바\n7. 사"
        let string = NSMutableString(string: text)
        for edit in MemoLists.renumber(in: text, range: NSRange(location: 0, length: 0)) { string.replaceCharacters(in: edit.range, with: edit.text) }
        #expect(string as String == "1. 가\n\ta. 나\n\tb. 다\n2. 라\n\ta. 마\n• 바\n1. 사")
    }

    @Test func numberingKeepsTheFirstItemsPlace() {
        let text = "3. 셋\n3. 넷"
        let string = NSMutableString(string: text)
        for edit in MemoLists.renumber(in: text, range: NSRange(location: 0, length: 0)) { string.replaceCharacters(in: edit.range, with: edit.text) }
        #expect(string as String == "3. 셋\n4. 넷")
    }

    @Test func aListUnderAQuoteKeepsItsFirstPlace() {
        let text = "> 말\n3. 셋\n3. 넷"
        let string = NSMutableString(string: text)
        for edit in MemoLists.renumber(in: text, range: NSRange(location: 5, length: 0)) { string.replaceCharacters(in: edit.range, with: edit.text) }
        #expect(string as String == "> 말\n3. 셋\n4. 넷")
        // The same when the quote is in the lines being numbered.
        let whole = NSMutableString(string: text)
        for edit in MemoLists.renumber(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { whole.replaceCharacters(in: edit.range, with: edit.text) }
        #expect(whole as String == "> 말\n3. 셋\n4. 넷")
    }

    @Test func tenthItemWidensItsLabel() {
        let text = (1...9).map { "\($0). 줄" }.joined(separator: "\n")
        let change = MemoLists.returnKey(in: text, caret: utf16(text))
        #expect(applied(change, to: text)?.hasSuffix("9. 줄\n10. ") == true)
        #expect(change?.selection.location == utf16(text) + utf16("\n10. "))
    }

    @Test func listsGoAsDeepAsTheTabs() {
        // Every three levels the labels and bullets start over: 1. a. i. 1. a. i. …
        #expect((0..<7).map { MemoLists.label(2, level: $0) } == ["2.", "b.", "ii.", "2.", "b.", "ii.", "2."])
        let bullets = (0..<7).map { level in MemoLists.shownLabel(MemoLists.Marker(kind: .bullet, level: level, label: "•", length: level + 2, number: nil)) }
        #expect(bullets == ["●", "○", "■", "●", "○", "■", "●"])
        // Read at any level: letters one past a figures level, roman figures two past.
        #expect(MemoLists.marker("\t\t\t\tb. 다섯째")?.number == 2)
        #expect(MemoLists.marker("\t\t\t\t\tiii. 여섯째")?.number == 3)
        #expect(MemoLists.marker("\t\t\t\t\t\t\t\t\t• 열째")?.level == 9)
        #expect(MemoLists.marker("\t\t\ta. 아니요") == nil)
        // Tab takes an item a level in however deep, numbers following with that level's letters.
        let text = "1. 하나\n\ta. 둘\n\t\ti. 셋\n\t\tii. 넷"
        let caret = utf16("1. 하나\n\ta. 둘\n\t\ti. 셋\n\t\ti")
        #expect(applied(MemoLists.indent(in: text, selection: NSRange(location: caret, length: 0), by: 1), to: text)
                == "1. 하나\n\ta. 둘\n\t\ti. 셋\n\t\t\t1. 넷")
        // Return on a deep item goes on at its level; on an empty one, a level out.
        let deep = "\t\t\t\t• 다섯"
        #expect(applied(MemoLists.returnKey(in: deep, caret: utf16(deep)), to: deep) == deep + "\n\t\t\t\t• ")
        let empty = "\t\t\t\t• "
        #expect(applied(MemoLists.returnKey(in: empty, caret: utf16(empty)), to: empty) == "\t\t\t• ")
        // `* ` after any number of tabs becomes a bullet.
        #expect(MemoLists.autoBullet(in: "\t\t\t\t* ", caret: 6) != nil)
        // Numbers count at each deep level, starting again under a new parent.
        let counted = "1. 가\n\ta. 나\n\t\ti. 다\n\t\t\t1. 라\n\t\t\t1. 마\n\t\t\t\t1. 바\n\t\t\t1. 사"
        var fixed = counted as NSString
        for edit in MemoLists.renumber(in: counted, range: NSRange(location: 0, length: utf16(counted))) {
            fixed = fixed.replacingCharacters(in: edit.range, with: edit.text) as NSString
        }
        #expect(fixed as String == "1. 가\n\ta. 나\n\t\ti. 다\n\t\t\t1. 라\n\t\t\t2. 마\n\t\t\t\ta. 바\n\t\t\t3. 사")
    }
}
