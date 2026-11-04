import Foundation
import Testing
@testable import SimplifyKit

/// Tables as tab-split lines: reading cells, moving between them, and changing rows and columns.
struct MemoTablesTests {
    /// The letters after making `change`'s edits one by one.
    private func applied(_ change: MemoLists.Change?, to text: String) -> String? {
        guard let change else { return nil }
        let string = NSMutableString(string: text)
        for edit in change.edits { string.replaceCharacters(in: edit.range, with: edit.text) }
        return string as String
    }

    /// Every line of `text` from line `first` to `last` as rows, without their breaks.
    private func rows(_ text: String, _ lines: ClosedRange<Int>) -> [NSRange] {
        let string = text as NSString
        var found: [NSRange] = []
        var location = 0
        var index = 0
        while location <= string.length {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            if lines.contains(index) { found.append(MemoLists.lineContent(of: line, in: string)) }
            index += 1
            if NSMaxRange(line) == location || NSMaxRange(line) >= string.length { break }
            location = NSMaxRange(line)
        }
        return found
    }

    private func offset(of letters: String, in text: String) -> Int {
        (text as NSString).range(of: letters).location
    }

    private let cost = "비용\n항목\t금액\t메모\n디자인\t1,200,000\t시안 2종\n개발\t3,400,000\t4주\n끝"

    @Test func cellsAreSplitByTabs() {
        #expect(MemoTables.cells("항목\t금액\t메모") == ["항목", "금액", "메모"])
        #expect(MemoTables.cells("\t") == ["", ""])
        let string = "가\t\t나" as NSString
        #expect(MemoTables.cellRanges(of: NSRange(location: 0, length: string.length), in: string)
                == [NSRange(location: 0, length: 1), NSRange(location: 2, length: 0), NSRange(location: 3, length: 1)])
    }

    @Test func numbersStandRight() {
        for cell in ["1,200,000", "3.5", "-12", "12%", "₩4,600", " 7 "] { #expect(MemoTables.isNumber(cell), "\(cell)") }
        for cell in ["", "4주", "시안 2종", "1.2.", "v2", "--"] { #expect(!MemoTables.isNumber(cell), "\(cell)") }
    }

    @Test func caretCell() {
        let table = rows(cost, 1...3)
        let string = cost as NSString
        #expect(MemoTables.columnCount(of: table, in: string) == 3)
        #expect(MemoTables.cell(at: offset(of: "1,200", in: cost) + 2, rows: table, in: string)! == (1, 1))
        #expect(MemoTables.cell(at: offset(of: "항목", in: cost), rows: table, in: string)! == (0, 0))
        #expect(MemoTables.cell(at: offset(of: "끝", in: cost), rows: table, in: string) == nil)
    }

    @Test func tabGoesToTheNextCellAndMakesARowAtTheEnd() throws {
        let table = rows(cost, 1...3)
        let next = try #require(MemoTables.tab(in: cost, rows: table, caret: offset(of: "디자인", in: cost), backward: false))
        #expect(next.edits.isEmpty)
        #expect(next.selection.location == offset(of: "\t시안", in: cost))
        // The end of a row goes on to the next row's first cell.
        let wrap = try #require(MemoTables.tab(in: cost, rows: table, caret: offset(of: "\n디자인", in: cost), backward: false))
        #expect(wrap.selection.location == offset(of: "\t1,200", in: cost))
        // The last cell makes a new empty row and puts the caret in it.
        let last = try #require(MemoTables.tab(in: cost, rows: table, caret: offset(of: "\n끝", in: cost), backward: false))
        let made = try #require(applied(last, to: cost))
        #expect(made == "비용\n항목\t금액\t메모\n디자인\t1,200,000\t시안 2종\n개발\t3,400,000\t4주\n\t\t\n끝")
        #expect(last.selection.location == offset(of: "\t\t\n끝", in: made))
    }

    @Test func shiftTabGoesBackAndStaysAtTheFirstCell() throws {
        let table = rows(cost, 1...3)
        let back = try #require(MemoTables.tab(in: cost, rows: table, caret: offset(of: "디자인", in: cost), backward: true))
        #expect(back.selection.location == offset(of: "\n디자인", in: cost))
        let first = try #require(MemoTables.tab(in: cost, rows: table, caret: offset(of: "항목", in: cost) + 1, backward: true))
        #expect(first.edits.isEmpty && first.selection.location == offset(of: "항목", in: cost) + 1)
    }

    @Test func shortRowsAreFilledOut() throws {
        let text = "가\t나\t다\n라"
        let table = rows(text, 0...1)
        let change = try #require(MemoTables.tab(in: text, rows: table, caret: (text as NSString).length, backward: false))
        #expect(applied(change, to: text) == "가\t나\t다\n라\t")
        #expect(change.selection.location == (text as NSString).length + 1)
    }

    @Test func returnGoesDownAndLeavesAtTheLastRow() throws {
        let table = rows(cost, 1...3)
        let down = try #require(MemoTables.returnKey(in: cost, rows: table, caret: offset(of: "\t금액", in: cost) + 3))
        #expect(down.edits.isEmpty && down.selection.location == offset(of: "\t시안", in: cost))
        // Out of the last row: a new line under the table.
        let out = try #require(MemoTables.returnKey(in: cost, rows: table, caret: offset(of: "4주", in: cost)))
        let made = try #require(applied(out, to: cost))
        #expect(made.hasSuffix("4주\n\n끝"))
        #expect(out.selection.location == offset(of: "\n\n끝", in: made) + 1)
        // An empty line under it is used as it is.
        let spaced = "가\t나\n\n끝"
        let onto = try #require(MemoTables.returnKey(in: spaced, rows: rows(spaced, 0...0), caret: 1))
        #expect(onto.edits.isEmpty && onto.selection.location == 4)
    }

    @Test func deleteNeverTakesTheTableApart() throws {
        let table = rows(cost, 1...3)
        // The front of a cell and of a row stay.
        let cellFront = offset(of: "금액", in: cost)
        let stay = try #require(MemoTables.deleteBackward(in: cost, rows: table, above: nil, caret: cellFront))
        #expect(stay.edits.isEmpty && stay.selection.location == cellFront)
        #expect(MemoTables.deleteBackward(in: cost, rows: table, above: nil, caret: offset(of: "디자인", in: cost))?.edits.isEmpty == true)
        // Inside a cell's words Delete deletes.
        #expect(MemoTables.deleteBackward(in: cost, rows: table, above: nil, caret: cellFront + 1) == nil)
        // Words under the table stay on their line; the caret goes up into the last cell.
        let under = try #require(MemoTables.deleteBackward(in: cost, rows: nil, above: table, caret: offset(of: "끝", in: cost)))
        #expect(under.edits.isEmpty && under.selection.location == offset(of: "\n끝", in: cost))
        // An empty line under it goes as usual.
        let spaced = "가\t나\n\n끝"
        #expect(MemoTables.deleteBackward(in: spaced, rows: nil, above: rows(spaced, 0...0), caret: 4) == nil)
    }

    @Test func forwardDeleteNeverJoinsCells() {
        let table = rows(cost, 1...3)
        #expect(MemoTables.deleteForward(in: cost, rows: table, caret: offset(of: "\t금액", in: cost))?.edits.isEmpty == true)
        #expect(MemoTables.deleteForward(in: cost, rows: table, caret: offset(of: "\n디자인", in: cost))?.edits.isEmpty == true)
        #expect(MemoTables.deleteForward(in: cost, rows: table, caret: offset(of: "금액", in: cost)) == nil)
    }

    @Test func rowsGoInAboveAndBelow() throws {
        let table = rows(cost, 1...3)
        let below = try #require(MemoTables.insertRow(rows: table, at: 1, below: true, in: cost))
        let madeBelow = try #require(applied(below, to: cost))
        #expect(madeBelow == "비용\n항목\t금액\t메모\n디자인\t1,200,000\t시안 2종\n\t\t\n개발\t3,400,000\t4주\n끝")
        #expect(below.selection.location == offset(of: "\t\t\n개발", in: madeBelow))
        let above = try #require(MemoTables.insertRow(rows: table, at: 0, below: false, in: cost))
        let madeAbove = try #require(applied(above, to: cost))
        #expect(madeAbove == "비용\n\t\t\n항목\t금액\t메모\n디자인\t1,200,000\t시안 2종\n개발\t3,400,000\t4주\n끝")
        #expect(above.selection.location == 3)
    }

    @Test func columnsGoInLeftAndRight() throws {
        let table = rows(cost, 1...3)
        let right = try #require(MemoTables.insertColumn(rows: table, at: 1, right: true, caretRow: 2, in: cost))
        let madeRight = try #require(applied(right, to: cost))
        #expect(madeRight == "비용\n항목\t금액\t\t메모\n디자인\t1,200,000\t\t시안 2종\n개발\t3,400,000\t\t4주\n끝")
        #expect(right.selection.location == offset(of: "3,400,000\t", in: madeRight) + 10)
        let left = try #require(MemoTables.insertColumn(rows: table, at: 0, right: false, caretRow: 1, in: cost))
        let madeLeft = try #require(applied(left, to: cost))
        #expect(madeLeft == "비용\n\t항목\t금액\t메모\n\t디자인\t1,200,000\t시안 2종\n\t개발\t3,400,000\t4주\n끝")
        #expect(left.selection.location == offset(of: "\t디자인", in: madeLeft))
        // A short row is filled out so the column lands in its place.
        let short = "가\t나\t다\n라"
        let filled = try #require(MemoTables.insertColumn(rows: rows(short, 0...1), at: 2, right: false, caretRow: 1, in: short))
        #expect(applied(filled, to: short) == "가\t나\t\t다\n라\t\t\t")
    }

    @Test func rowsAndColumnsComeOut() throws {
        let table = rows(cost, 1...3)
        #expect(applied(MemoTables.deleteRow(rows: table, at: 1, in: cost), to: cost) == "비용\n항목\t금액\t메모\n개발\t3,400,000\t4주\n끝")
        #expect(applied(MemoTables.deleteRow(rows: table, at: 2, in: cost), to: cost) == "비용\n항목\t금액\t메모\n디자인\t1,200,000\t시안 2종\n끝")
        let column = try #require(MemoTables.deleteColumn(rows: table, at: 1, caretRow: 2, in: cost))
        let made = try #require(applied(column, to: cost))
        #expect(made == "비용\n항목\t메모\n디자인\t시안 2종\n개발\t4주\n끝")
        #expect(column.selection.location == offset(of: "\t4주", in: made))
        #expect(applied(MemoTables.deleteColumn(rows: table, at: 0, caretRow: 0, in: cost), to: cost) == "비용\n금액\t메모\n1,200,000\t시안 2종\n3,400,000\t4주\n끝")
        // A row of tabs alone keeps one, so it stays a row.
        let thin = "가\t나\t다\n\t"
        #expect(applied(MemoTables.deleteColumn(rows: rows(thin, 0...1), at: 0, caretRow: 1, in: thin), to: thin) == "나\t다\n\t")
        // Two columns are the least.
        let two = "가\t나\n다\t라"
        #expect(MemoTables.deleteColumn(rows: rows(two, 0...1), at: 0, caretRow: 0, in: two) == nil)
        // The last row takes the table with it.
        let one = "위\n가\t나\n아래"
        #expect(applied(MemoTables.deleteRow(rows: rows(one, 1...1), at: 0, in: one), to: one) == "위\n아래")
    }

    @Test func wholeTablesComeOut() {
        let table = rows(cost, 1...3)
        #expect(applied(MemoTables.deleteTable(rows: table, in: cost), to: cost) == "비용\n끝")
        let atEnd = "위\n가\t나\n다\t라"
        #expect(applied(MemoTables.deleteTable(rows: rows(atEnd, 1...2), in: atEnd), to: atEnd) == "위")
    }

    @Test func newTablesAreTwoByTwo() {
        let empty = MemoTables.newTable(in: "위\n\n아래", caret: 2)
        #expect(applied(empty, to: "위\n\n아래") == "위\n\t\n\t\n아래")
        #expect(empty.selection.location == 2)
        let after = MemoTables.newTable(in: "위에 글", caret: 2)
        #expect(applied(after, to: "위에 글") == "위에 글\n\t\n\t")
        #expect(after.selection.location == 5)
    }

    // MARK: Stored

    @Test func tableRowsAreStoredUnderTl() throws {
        var row = AttributeContainer()
        row[MemoAttributes.Table.self] = "a1b2"
        let text = AttributedString("비용\n") + AttributedString("항목\t금액", attributes: row) + AttributedString("\n")
            + AttributedString("개발\t3,400,000", attributes: row) + AttributedString("\n끝")
        let data = try #require(MemoText.encode(text))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""tl":"a1b2""#))
        #expect(json.contains(#""v":2"#))
        // The ToDo box key is left alone.
        #expect(!json.contains(#""tb""#))
        let read = MemoText.decode(data)
        #expect(read == text)
        #expect(MemoText.decodeIfReadable(data) == text)
    }

    @Test func aTableMarkStaysOffLineBreaks() throws {
        let json = #"{"v":2,"runs":[{"t":"가\t나\n다\t라","tl":"t"},{"t":"\n끝"}]}"#
        let text = MemoText.decode(Data(json.utf8))
        let breaks = text.characters.indices.filter { text.characters[$0].isNewline }
        #expect(breaks.count == 2)
        for index in breaks { #expect(text[index...index].runs.first?[MemoAttributes.Table.self] == nil) }
        #expect(text.runs.first?[MemoAttributes.Table.self] == "t")
        // A bad value under the key is dropped, not the memo.
        let bad = MemoText.decode(Data(#"{"v":2,"runs":[{"t":"가\t나","tl":3}]}"#.utf8))
        #expect(String(bad.characters) == "가\t나" && bad.runs.first?[MemoAttributes.Table.self] == nil)
    }
}
