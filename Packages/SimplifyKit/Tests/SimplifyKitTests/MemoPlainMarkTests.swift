import Foundation
import Testing
@testable import SimplifyKit

/// A list or quote made as a space is typed, undone with ⌘Z: the invisible mark that keeps the
/// line plain, how the list rules pass it by, and copies without it.
struct MemoPlainMarkTests {
    let mark = MemoLists.plainMark

    /// Applies a change's edits one after another.
    private func applied(_ change: MemoLists.Change?, to text: String) -> String {
        guard let change else { return text }
        let string = NSMutableString(string: text)
        for edit in change.edits { string.replaceCharacters(in: edit.range, with: edit.text) }
        return string as String
    }

    @Test func aMarkedLineIsNoListNorQuote() {
        #expect(MemoLists.marker("\(mark)1. 회의 준비") == nil)
        #expect(MemoLists.marker("\(mark)- 장보기") == nil)
        #expect(MemoLists.marker("\(mark)> 인용") == nil)
        #expect(MemoLists.marker("\(mark)\t1. 깊은 줄") == nil)
        // A list left plain in a quote: still a quote.
        #expect(MemoLists.marker("> \(mark)1. 회의")?.kind == .quote)
        #expect(MemoLists.marker("> \(mark)1. 회의")?.length == 2)
    }

    @Test func aSpaceThatMakesAListIsFound() {
        #expect(MemoLists.autoFormat(in: "1.", caret: 2) == 0)
        #expect(MemoLists.autoFormat(in: "가\n-", caret: 3) == 2)
        #expect(MemoLists.autoFormat(in: ">", caret: 1) == 0)
        // After leading tabs, so a timeline line's child stays one.
        #expect(MemoLists.autoFormat(in: "\t1.", caret: 3) == 1)
        #expect(MemoLists.autoFormat(in: "11.03 14:25 회의\n\t-", caret: 17) == 16)
        #expect(MemoLists.marker("\t\(mark)- 하위") == nil)
        #expect(MemoLists.plainMarkRange(of: NSRange(location: 0, length: 5), in: "\t\(mark)- 하" as NSString) == NSRange(location: 1, length: 1))
        #expect(MemoLists.autoFormat(in: "1.회의", caret: 2) == 0)
        // In a quote, the mark goes after its `> `.
        #expect(MemoLists.autoFormat(in: "> 1.", caret: 4) == 2)
        // Nothing new: a space in words, after a list's marker, or a date.
        #expect(MemoLists.autoFormat(in: "a -", caret: 3) == nil)
        #expect(MemoLists.autoFormat(in: "1. 회의", caret: 5) == nil)
        #expect(MemoLists.autoFormat(in: "- -", caret: 3) == nil)
        #expect(MemoLists.autoFormat(in: "11.4.", caret: 5) == nil)
        #expect(MemoLists.autoFormat(in: "", caret: 0) == nil)
        // A line left plain stays plain.
        #expect(MemoLists.autoFormat(in: "\(mark)1.", caret: 3) == nil)
    }

    @Test func returnAndNumberingPassAMarkedLineBy() {
        // Return on it is a plain line break, not "2.".
        #expect(MemoLists.returnKey(in: "\(mark)1. 회의 준비", caret: 9) == nil)
        // It splits a list in two for numbering, as a plain line does.
        let text = "1. 가\n\(mark)7. 나\n5. 다"
        let edits = MemoLists.renumber(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        #expect(edits.isEmpty)
        #expect(MemoLists.deleteBackward(in: "\(mark)1. 가", caret: 4) == nil)
    }

    @Test func makingItAListByTheMenuTakesTheMarkOut() {
        let plain = "\(mark)1. 회의 준비"
        // 번호 목록 on a line that shows as plain `1. 회의 준비`: a list, not toggled off.
        #expect(applied(MemoLists.setKind(.number, in: plain, selection: NSRange(location: 4, length: 0)), to: plain) == "1. 회의 준비")
        #expect(applied(MemoLists.setKind(.bullet, in: plain, selection: NSRange(location: 4, length: 0)), to: plain) == "• 회의 준비")
        // A list left plain in a quote takes the list; 인용 there takes the quote off and leaves the line plain.
        let quoted = "> \(mark)1. 회의"
        #expect(applied(MemoLists.setKind(.number, in: quoted, selection: NSRange(location: 5, length: 0)), to: quoted) == "> 1. 회의")
        #expect(applied(MemoLists.setKind(.quote, in: quoted, selection: NSRange(location: 5, length: 0)), to: quoted) == "\(mark)1. 회의")
        // A quote left plain (`> ` with the mark before it) becomes a quote again.
        let nested = "\t\(mark)- 하위"
        #expect(applied(MemoLists.setKind(.dash, in: nested, selection: NSRange(location: 3, length: 0)), to: nested) == "\t- 하위")
        let unquoted = "\(mark)> 인용"
        #expect(applied(MemoLists.setKind(.quote, in: unquoted, selection: NSRange(location: 3, length: 0)), to: unquoted) == "> 인용")
    }

    @Test func copiesAndTheNotesCopyLeaveTheMarkOut() throws {
        let text = AttributedString("\(mark)1. 회의 준비\n\(mark)- 장보기")
        #expect(MemoAttachments.plainText(text) == "1. 회의 준비\n- 장보기")
        let html = try #require(NotesHTML.body(name: "11월 9일", text: text))
        #expect(!html.contains(mark))
        // Plain lines in the note, not an <ol> or <ul>.
        #expect(html.contains("<div>1. 회의 준비</div>") && !html.contains("<ol>") && !html.contains("<ul"))
        // And it is stored as typed, so the memo opens the same way.
        #expect(MemoText.decode(MemoText.encode(text)) == text)
        // A ToDo made from such a line has no mark in its name, and loses its dash as usual.
        #expect(MemoTodoLines.title(of: "\(mark)- 회의") == "회의")
    }
}
