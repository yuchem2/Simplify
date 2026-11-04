import AppKit
import SwiftUI
import SimplifyKit

// Editing tables: Tab, ⇧Tab, Return and Delete in and under a table, 표 넣기 and the right-click
// menu's row and column items. The rules are `MemoTables`'; the edits are made in the text view as
// typing would, so each is one undo step, and every letter they add but a line break is marked as
// a row of the table.

/// What the 서식 menu, the Aa bar and the right-click menu do to tables.
enum MemoTableAction {
    case insert
    case rowAbove, rowBelow, columnLeft, columnRight
    case deleteRow, deleteColumn
    case toText, deleteTable
}

extension MemoDraft {
    /// The caret's line, or the selection's first, is a table row.
    var isInTable: Bool {
        guard let start = selectedRanges.first?.lowerBound else { return false }
        let characters = text.characters
        var line = start
        while line > characters.startIndex, !characters[characters.index(before: line)].isNewline {
            line = characters.index(before: line)
        }
        guard line < characters.endIndex, !characters[line].isNewline else { return false }
        return text.runs[line][MemoAttributes.Table.self] != nil
    }

    /// Some line the selection touches is a table row.
    var touchesTable: Bool {
        let characters = text.characters
        return selectedRanges.contains { range in
            var start = range.lowerBound
            while start > characters.startIndex, !characters[characters.index(before: start)].isNewline { start = characters.index(before: start) }
            var end = range.upperBound
            while end < characters.endIndex, !characters[end].isNewline { end = characters.index(after: end) }
            return text[start..<end].runs[MemoAttributes.Table.self].contains { $0.0 != nil }
        }
    }

    /// 표 넣기 and the table items: made in the text view; a beep where there is nothing to do.
    func tableAction(_ action: MemoTableAction) {
        if action == .toText {
            guard !isUnreadable, unmarkTable() else { return NSSound.beep() }
            focusRequest += 1
            return
        }
        guard !isUnreadable, editTable?(action) == true else {
            NSSound.beep()
            return
        }
        focusRequest += 1
    }

    /// 표를 글로 바꾸기: the caret's table's rows lose their mark; the letters stay, lines of
    /// tab-split words. In the memo's own text, as a paragraph style is set.
    private func unmarkTable() -> Bool {
        guard let start = selectedRanges.first?.lowerBound else { return false }
        // The caret's line and the lines above and below it in the same table, one under another.
        let lines = MemoTodoLines.lines(in: text)
        func id(_ line: Range<AttributedString.Index>) -> String? { line.isEmpty ? nil : text.runs[line.lowerBound][MemoAttributes.Table.self] }
        guard let here = lines.firstIndex(where: { $0.lowerBound <= start && start <= $0.upperBound }), let table = id(lines[here]) else { return false }
        var first = here, last = here
        while first > 0, id(lines[first - 1]) == table { first -= 1 }
        while last + 1 < lines.count, id(lines[last + 1]) == table { last += 1 }
        let rows = RangeSet(lines[first...last])
        text.transform(updating: &selection) { text in
            text[rows][MemoAttributes.Table.self] = nil
        }
        return true
    }

    /// A line partly in a table (letters typed at a row's front, or a line joined to a row) is a
    /// row throughout, of the first table in it.
    func keepTablesWhole() {
        if isComposing { return }
        var fixes: [(line: Range<AttributedString.Index>, id: String)] = []
        for line in MemoTodoLines.lines(in: text) where !line.isEmpty {
            let values = text[line].runs[MemoAttributes.Table.self].map(\.0)
            guard let first = values.compactMap({ $0 }).first, values.contains(where: { $0 != first }) else { continue }
            fixes.append((line, first))
        }
        guard !fixes.isEmpty else { return }
        text.transform(updating: &selection) { text in
            for fix in fixes { text[fix.line][MemoAttributes.Table.self] = fix.id }
        }
    }
}

/// The text view's side of tables: the keys `MemoMenuHost` hands over, and making a change.
@MainActor
enum MemoTableKeys {
    private static let returnKey: UInt16 = 36
    private static let enterKey: UInt16 = 76
    private static let tabKey: UInt16 = 48
    private static let deleteKey: UInt16 = 51
    private static let forwardDeleteKey: UInt16 = 117

    private static let tableKey = MemoLineStyler.tableKey

    /// Tab, ⇧Tab, Return and Delete in a table, and Delete at the front of the line under one:
    /// true when the key was used here. Ahead of the list keys, so a row's tabs are never a list's.
    /// ⇧Return and ⌥Return are Return here too: a cell holds no line break.
    static func handle(_ event: NSEvent, in textView: NSTextView) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let code = event.keyCode
        let isReturn = code == returnKey || code == enterKey
        guard [returnKey, enterKey, tabKey, deleteKey, forwardDeleteKey].contains(code),
              modifiers.isEmpty || (code == tabKey && modifiers == .shift) || (isReturn && (modifiers == .shift || modifiers == .option)),
              let storage = textView.textStorage else { return false }
        let selected = textView.selectedRange()
        if code == forwardDeleteKey {
            guard !textView.hasMarkedText(), selected.length == 0, let table = MemoLineStyler.table(in: storage, at: selected.location),
                  let change = MemoTables.deleteForward(in: storage.string, rows: table.rows, caret: selected.location) else { return false }
            apply(change, id: nil, to: textView)
            return true
        }
        if code == deleteKey {
            // Delete while composing takes back a letter of the syllable; a selection goes as usual.
            guard !textView.hasMarkedText(), selected.length == 0 else { return false }
            let caret = selected.location
            let rows = MemoLineStyler.table(in: storage, at: caret)?.rows
            let string = storage.string as NSString
            let lineStart = string.lineRange(for: NSRange(location: caret, length: 0)).location
            let above = rows == nil && caret > 0 && caret == lineStart ? MemoLineStyler.table(in: storage, at: caret - 1)?.rows : nil
            guard let change = MemoTables.deleteBackward(in: storage.string, rows: rows, above: above, caret: caret) else { return false }
            apply(change, id: nil, to: textView)
            return true
        }
        guard MemoLineStyler.table(in: storage, at: selected.location) != nil else { return false }
        // A Korean syllable is finished first, as Return would finish it; that may move the caret.
        finishComposing(textView)
        let caret = textView.selectedRange().location
        guard let table = MemoLineStyler.table(in: storage, at: caret) else { return true }
        let change = code == tabKey
            ? MemoTables.tab(in: storage.string, rows: table.rows, caret: caret, backward: modifiers == .shift)
            : MemoTables.returnKey(in: storage.string, rows: table.rows, caret: caret)
        if let change { apply(change, id: table.id, to: textView) }
        return true
    }

    /// A menu item's change; false when it makes none (no table at the caret, or two columns left).
    static func perform(_ action: MemoTableAction, in textView: NSTextView) -> Bool {
        guard textView.isEditable, let storage = textView.textStorage else { return false }
        let string = storage.string
        let caret = textView.selectedRange().location
        if action == .insert {
            guard MemoLineStyler.table(in: storage, at: caret) == nil else { return false }
            apply(MemoTables.newTable(in: string, caret: caret), id: String(UUID().uuidString.prefix(8)).lowercased(), to: textView)
            return true
        }
        guard let table = MemoLineStyler.table(in: storage, at: caret),
              let here = MemoTables.cell(at: caret, rows: table.rows, in: string as NSString) else { return false }
        let change: MemoLists.Change? = switch action {
        case .insert, .toText: nil
        case .rowAbove: MemoTables.insertRow(rows: table.rows, at: here.row, below: false, in: string)
        case .rowBelow: MemoTables.insertRow(rows: table.rows, at: here.row, below: true, in: string)
        case .columnLeft: MemoTables.insertColumn(rows: table.rows, at: here.column, right: false, caretRow: here.row, in: string)
        case .columnRight: MemoTables.insertColumn(rows: table.rows, at: here.column, right: true, caretRow: here.row, in: string)
        case .deleteRow: MemoTables.deleteRow(rows: table.rows, at: here.row, in: string)
        case .deleteColumn: MemoTables.deleteColumn(rows: table.rows, at: here.column, caretRow: here.row, in: string)
        case .deleteTable: MemoTables.deleteTable(rows: table.rows, in: string)
        }
        guard let change else { return false }
        apply(change, id: table.id, to: textView)
        return true
    }

    /// The table's columns in the caret's table; 0 outside one.
    static func columnCount(in textView: NSTextView) -> Int {
        guard let storage = textView.textStorage, let table = MemoLineStyler.table(in: storage, at: textView.selectedRange().location) else { return 0 }
        return MemoTables.columnCount(of: table.rows, in: storage.string as NSString)
    }

    /// Makes the edits one after another, then puts the selection where the change says.
    static func apply(_ change: MemoLists.Change, id: String?, to textView: NSTextView) {
        textView.breakUndoCoalescing()
        for edit in change.edits { replace(edit.range, with: edit.text, id: id, in: textView) }
        let length = (textView.string as NSString).length
        let location = min(change.selection.location, length)
        textView.setSelectedRange(NSRange(location: location, length: min(change.selection.length, length - location)))
    }

    /// One edit, as the text view's own. New letters are plain memo letters of the table `id`
    /// (line breaks of none), whatever the letters around them look like.
    private static func replace(_ range: NSRange, with letters: String, id: String?, in textView: NSTextView) {
        guard let storage = textView.textStorage, NSMaxRange(range) <= storage.length,
              textView.shouldChangeText(in: range, replacementString: letters) else { return }
        var attributes = textView.typingAttributes
        for name in [MemoAttributes.Bold.name, MemoAttributes.Italic.name, MemoAttributes.Underline.name, MemoAttributes.Strike.name,
                     MemoAttributes.Paragraph.name, MemoAttributes.Code.name, MemoAttributes.Math.name, MemoAttributes.Script.name,
                     MemoAttributes.Ink.name, MemoAttributes.Highlight.name, MemoAttributes.Todo.name, MemoAttributes.TodoBox.name,
                     MemoAttributes.Table.name] {
            attributes[NSAttributedString.Key(name)] = nil
        }
        for key in [NSAttributedString.Key.backgroundColor, .underlineStyle, .strikethroughStyle, .baselineOffset] { attributes[key] = nil }
        attributes[.font] = NSFont.systemFont(ofSize: MemoStyle.size)
        attributes[.foregroundColor] = NSColor(Color.ink)
        let added = NSMutableAttributedString(string: letters, attributes: attributes)
        if let id {
            let string = letters as NSString
            for index in 0..<string.length where string.character(at: index) != 0x0A {
                added.addAttribute(tableKey, value: id, range: NSRange(location: index, length: 1))
            }
        }
        storage.replaceCharacters(in: range, with: added)
        textView.didChangeText()
    }

    /// A Korean syllable being composed is finished as it stands.
    private static func finishComposing(_ textView: NSTextView) {
        guard textView.hasMarkedText() else { return }
        textView.unmarkText()
        textView.inputContext?.discardMarkedText()
    }
}
