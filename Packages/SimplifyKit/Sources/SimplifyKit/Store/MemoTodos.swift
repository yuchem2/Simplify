import Foundation

/// ToDo chips inside a memo: `□ 제목` letters carrying `MemoAttributes.Todo`.
///
/// The memo box can only colour letters, so a chip is ordinary text that the editor keeps whole:
/// typing next to it never joins it, and editing inside it turns it back into plain words.
public enum MemoChips {
    /// □ and ☑ both come from the system font, so they match each other and the memo's letters.
    /// (☐ would fall back to another font.)
    public static let openBox: Character = "□"
    public static let doneBox: Character = "☑"

    public struct Chip {
        public var range: Range<AttributedString.Index>
        public var todo: MemoTodo
    }

    /// What a ToDo looks like as a chip.
    public static func chip(id: UUID, title: String, isDone: Bool) -> AttributedString {
        var container = AttributeContainer()
        container[MemoAttributes.Todo.self] = MemoTodo(id: id, isDone: isDone)
        var box = container
        box[MemoAttributes.TodoBox.self] = true
        return AttributedString(String(isDone ? doneBox : openBox), attributes: box) + AttributedString(" \(title)", attributes: container)
    }

    public static func chips(in text: AttributedString) -> [Chip] {
        text.runs[MemoAttributes.Todo.self].compactMap { value, range in
            value.map { Chip(range: range, todo: $0) }
        }
    }

    /// The text with every chip redrawn from its ToDo (title and box), and chips whose ToDo is gone
    /// turned into plain words. Returns nil when nothing changes.
    public static func refreshed(_ text: AttributedString, lookup: (UUID) -> (title: String, isDone: Bool)?) -> AttributedString? {
        var text = text
        return refresh(&text, lookup: lookup) ? text : nil
    }

    /// `refreshed` in place, for the editor to run inside a selection-keeping transform. Returns
    /// whether anything changed.
    @discardableResult
    public static func refresh(_ text: inout AttributedString, lookup: (UUID) -> (title: String, isDone: Bool)?) -> Bool {
        var changed = false
        // Found again after every change: indices do not outlive a mutation. Last chip first, so
        // a chip that stops being one leaves the earlier ones at their numbers.
        for number in chips(in: text).indices.reversed() {
            let chip = chips(in: text)[number]
            guard let todo = lookup(chip.todo.id) else {
                text[chip.range][MemoAttributes.Todo.self] = nil
                text[chip.range][MemoAttributes.TodoBox.self] = nil
                changed = true
                continue
            }
            let fresh = Self.chip(id: chip.todo.id, title: todo.title, isDone: todo.isDone)
            // Chips saved before the box had its own mark are redrawn too.
            let hasBox = text.runs[chip.range.lowerBound][MemoAttributes.TodoBox.self] == true
            let letters = String(text[chip.range].characters)
            let freshLetters = String(fresh.characters)
            if hasBox, letters.dropFirst() == freshLetters.dropFirst() {
                // Only ticked or unticked: swap the box letter and keep the chip's formatting.
                guard chip.todo.isDone != todo.isDone || letters.first != freshLetters.first else { continue }
                let start = text.characters.distance(from: text.startIndex, to: chip.range.lowerBound)
                let count = letters.count
                let box = text.characters.index(text.startIndex, offsetBy: start)
                text.characters.replaceSubrange(box...box, with: [todo.isDone ? doneBox : openBox])
                let from = text.characters.index(text.startIndex, offsetBy: start)
                let range = from..<text.characters.index(from, offsetBy: count)
                text[range][MemoAttributes.Todo.self] = MemoTodo(id: chip.todo.id, isDone: todo.isDone)
                text[from..<text.characters.index(after: from)][MemoAttributes.TodoBox.self] = true
                changed = true
            } else if letters != freshLetters || chip.todo.isDone != todo.isDone || !hasBox {
                text.replaceSubrange(chip.range, with: fresh)
                changed = true
            }
        }
        return changed
    }

    /// Letters wearing a chip's attribute that are not the chip itself: typed right before or
    /// after it (they take the neighbour's attributes), or a whole chip broken by editing inside
    /// it. The editor strips the attribute from these. `title` gives each ToDo's current title;
    /// chips it does not know are left for `refreshed`.
    public static func strays(in text: AttributedString, title: (UUID) -> String?) -> RangeSet<AttributedString.Index> {
        var strays = RangeSet<AttributedString.Index>()
        for chip in chips(in: text) {
            guard let title = title(chip.todo.id) else { continue }
            let letters = String(text[chip.range].characters)
            let expected = "\(chip.todo.isDone ? doneBox : openBox) \(title)"
            guard letters != expected else { continue }
            guard let found = letters.range(of: expected) else {
                strays.insert(contentsOf: chip.range)
                continue
            }
            let lead = letters.distance(from: letters.startIndex, to: found.lowerBound)
            let kept = expected.count
            let keptStart = text.characters.index(chip.range.lowerBound, offsetBy: lead)
            let keptEnd = text.characters.index(keptStart, offsetBy: kept)
            if keptStart > chip.range.lowerBound { strays.insert(contentsOf: chip.range.lowerBound..<keptStart) }
            if keptEnd < chip.range.upperBound { strays.insert(contentsOf: keptEnd..<chip.range.upperBound) }
        }
        // A box mark left on letters that are no longer a chip.
        for (box, range) in text.runs[MemoAttributes.TodoBox.self] where box == true {
            if text.runs[range.lowerBound][MemoAttributes.Todo.self] == nil { strays.insert(contentsOf: range) }
        }
        return strays
    }

    /// Letters wearing the box mark that are not a chip's first letter. Formatting a selection
    /// can copy the box's attributes over the whole chip; the editor takes the mark off these.
    public static func strayBoxMarks(in text: AttributedString) -> RangeSet<AttributedString.Index> {
        let starts = chips(in: text).map(\.range.lowerBound)
        var strays = RangeSet<AttributedString.Index>()
        for (box, range) in text.runs[MemoAttributes.TodoBox.self] where box == true {
            var index = range.lowerBound
            while index < range.upperBound {
                let next = text.characters.index(after: index)
                if !starts.contains(index) { strays.insert(contentsOf: index..<next) }
                index = next
            }
        }
        return strays
    }

    /// The chip whose box is at `index` or just before it: where a click on the box puts the caret.
    public static func chip(withBoxAt index: AttributedString.Index, in text: AttributedString) -> Chip? {
        chips(in: text).first { chip in
            guard chip.range.lowerBound < text.endIndex else { return false }
            let afterBox = text.characters.index(after: chip.range.lowerBound)
            return index == afterBox
        }
    }
}

/// A line of a memo that reads like a ToDo: `[ ] 할 일`, `- [ ] 할 일` or `TODO: 할 일`.
public struct MemoTodoLine: Hashable, Sendable {
    /// The line's number in the memo, from 0.
    public var line: Int
    /// The words after the marker.
    public var title: String
    /// The line as written, marker included.
    public var text: String
}

/// Finding ToDo-like lines in memos and turning lines into chips.
public enum MemoTodoLines {
    /// Every unticked ToDo line that is not already a chip.
    public static func find(in text: AttributedString) -> [MemoTodoLine] {
        let chipped = MemoChips.chips(in: text)
        return lines(in: text).enumerated().compactMap { number, range in
            guard !chipped.contains(where: { $0.range.overlaps(range) }) else { return nil }
            let letters = String(text[range].characters)
            guard let title = candidateTitle(letters) else { return nil }
            return MemoTodoLine(line: number, title: title, text: letters.trimmingCharacters(in: .whitespaces))
        }
    }

    /// The ToDo a candidate line names, or nil when the line is not one. A ticked `[x]` is not.
    public static func candidateTitle(_ line: String) -> String? {
        // A line left plain with ⌘Z (`MemoLists.plainMark`) reads as its letters.
        var rest = Substring(MemoLists.withoutPlainMarks(line)).drop { $0.isWhitespace }
        if let bullet = rest.first, bullets.contains(bullet) { rest = rest.dropFirst().drop { $0.isWhitespace } }
        if rest.hasPrefix("[ ]") || rest.hasPrefix("[]") {
            rest = rest.drop { $0 != "]" }.dropFirst()
        } else if rest.prefix(5).uppercased() == "TODO:" {
            rest = rest.dropFirst(5)
        } else {
            return nil
        }
        let title = rest.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    /// A line made into a ToDo with ⌘⇧T: its candidate title, or the words without a list bullet.
    public static func title(of line: String) -> String {
        if let title = candidateTitle(line) { return title }
        var rest = Substring(MemoLists.withoutPlainMarks(line)).drop { $0.isWhitespace }
        if let bullet = rest.first, bullets.contains(bullet) { rest = rest.dropFirst() }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    /// Each line's letters, line breaks left out; an empty memo has one empty line.
    public static func lines(in text: AttributedString) -> [Range<AttributedString.Index>] {
        let characters = text.characters
        var result: [Range<AttributedString.Index>] = []
        var start = characters.startIndex
        var index = start
        while index < characters.endIndex {
            if characters[index].isNewline {
                result.append(start..<index)
                start = characters.index(after: index)
            }
            index = characters.index(after: index)
        }
        result.append(start..<characters.endIndex)
        return result
    }

    /// Puts `chip` where line `number` was, keeping the line's leading indent.
    public static func replaceLine(_ number: Int, in text: inout AttributedString, with chip: AttributedString) {
        let all = lines(in: text)
        guard all.indices.contains(number) else { return }
        let range = all[number]
        let letters = text[range].characters
        let indent = letters.prefix { $0 == " " || $0 == "\t" }.count
        let start = text.characters.index(range.lowerBound, offsetBy: indent)
        text.replaceSubrange(start..<range.upperBound, with: chip)
    }

    private static let bullets: Set<Character> = ["-", "–", "•", "*", "·"]
}
