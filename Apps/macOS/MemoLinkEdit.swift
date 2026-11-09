import AppKit
import SwiftUI
import SimplifyKit

/// Links in the memo's text view: putting one on letters, taking it off, finding one under the
/// pointer or the caret, a typed address becoming one, and links through the clipboard. Every
/// change is the text view's own edit, so it is one undo step and reaches SwiftUI's copy.
@MainActor
enum MemoLinkEdit {
    static let key = NSAttributedString.Key(MemoAttributes.Link.name)
    private static let codeKey = NSAttributedString.Key(MemoAttributes.Code.name)
    private static let inlineCodeKey = NSAttributedString.Key(MemoAttributes.InlineCode.name)
    private static let todoKey = NSAttributedString.Key(MemoAttributes.Todo.name)
    private static let todoBoxKey = NSAttributedString.Key(MemoAttributes.TodoBox.name)

    /// Opens a link's address; the format check puts a recorder here instead of a browser.
    static var opener: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// ⌘-click: the address, if it is one a link may hold.
    static func open(_ address: String) {
        guard let address = MemoLinks.stored(address), let url = URL(string: address) else { return }
        opener(url)
    }

    // MARK: Finding

    /// The link a letter belongs to, all of it (over the runs other formatting splits it into).
    static func link(in text: NSAttributedString, at location: Int) -> (range: NSRange, address: String)? {
        guard location >= 0, location < text.length else { return nil }
        var range = NSRange()
        guard let value = text.attribute(key, at: location, longestEffectiveRange: &range, in: NSRange(location: 0, length: text.length)) as? String,
              let address = MemoLinks.stored(value) else { return nil }
        return (range, address)
    }

    /// The link a caret stands in or at the end of.
    static func link(in text: NSAttributedString, caret: Int) -> (range: NSRange, address: String)? {
        link(in: text, at: caret) ?? link(in: text, at: caret - 1)
    }

    /// Every link in `range` of rich text from elsewhere (`.link`, a URL or a string) or of the
    /// memo (`key`), its letters and address; links `MemoLinks` would not take are left out.
    static func links(in rich: NSAttributedString, range: NSRange) -> [(range: NSRange, address: String)] {
        var found: [(range: NSRange, address: String)] = []
        rich.enumerateAttributes(in: range) { attributes, part, _ in
            let value = attributes[.link] ?? attributes[key]
            let raw = (value as? URL)?.absoluteString ?? value as? String
            guard let raw, let address = MemoLinks.stored(raw) else { return }
            if let last = found.last, last.address == address, NSMaxRange(last.range) == part.location {
                found[found.count - 1].range.length += part.length
            } else {
                found.append((part, address))
            }
        }
        return found
    }

    /// The memo's own links in `range` (its `key` alone, so a long memo is looked through quickly).
    static func memoLinks(in text: NSAttributedString, range: NSRange) -> [(range: NSRange, address: String)] {
        var found: [(range: NSRange, address: String)] = []
        text.enumerateAttribute(key, in: range) { value, part, _ in
            guard let value = value as? String, let address = MemoLinks.stored(value) else { return }
            if let last = found.last, last.address == address, NSMaxRange(last.range) == part.location {
                found[found.count - 1].range.length += part.length
            } else {
                found.append((part, address))
            }
        }
        return found
    }

    /// The parts of `range` a link may cover: its letters between line breaks and table tabs.
    static func carried(_ range: NSRange, in string: NSString) -> [NSRange] {
        var parts: [NSRange] = []
        var start = range.location
        for index in range.location...NSMaxRange(range) {
            let ends = index == NSMaxRange(range) || [0x0A, 0x0D, 0x09, 0x2028, 0x2029].contains(string.character(at: index))
            guard ends else { continue }
            if index > start { parts.append(NSRange(location: start, length: index - start)) }
            start = index + 1
        }
        return parts
    }

    /// Letters a link may be put on as one: within one line and one table cell, no attached file.
    static func canTake(_ letters: String) -> Bool {
        !letters.isEmpty && !letters.contains(where: { $0.isNewline || $0 == "\t" || $0 == MemoAttachments.placeholder })
    }

    // MARK: Changing

    /// Puts `address` on `range` (nil takes the link off), as the text view's own edit: one undo
    /// step of its own. The letters are put back in with the new link rather than given it in
    /// place: the memo's undo (SwiftUI's) takes back changed letters, not changed attributes.
    @discardableResult
    static func set(_ address: String?, on range: NSRange, in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, range.length > 0, NSMaxRange(range) <= storage.length else { return false }
        let letters = storage.copiedPart(range)
        let whole = NSRange(location: 0, length: letters.length)
        letters.removeAttribute(key, range: whole)
        if let address {
            for part in carried(whole, in: letters.string as NSString) { letters.addAttribute(key, value: address, range: part) }
        }
        let selected = textView.selectedRanges
        MemoTableClipboard.replace(range, with: letters, in: textView)
        textView.selectedRanges = selected
        textView.breakUndoCoalescing()
        return true
    }

    /// ⌘K with nothing picked: the address itself goes in at the caret as a link.
    static func insert(_ address: String, at range: NSRange, in textView: NSTextView) {
        var attributes = textView.typingAttributes
        attributes[todoKey] = nil
        attributes[todoBoxKey] = nil
        attributes[key] = address
        MemoTableClipboard.replace(range, with: NSAttributedString(string: address, attributes: attributes), in: textView)
        let end = range.location + (address as NSString).length
        textView.setSelectedRange(NSRange(location: min(end, (textView.string as NSString).length), length: 0))
    }

    // MARK: Typing

    /// Space or Return about to be typed after an address: the address's letters, before the
    /// caret on its line, to become a link once the key is in. Not in code, nor where it is a
    /// link already.
    static func typedAddress(in textView: NSTextView) -> (range: NSRange, address: String)? {
        guard let storage = textView.textStorage, !textView.hasMarkedText() else { return nil }
        let caret = textView.selectedRange()
        guard caret.length == 0, caret.location > 0 else { return nil }
        let string = storage.string as NSString
        var start = caret.location
        while start > 0 {
            let letter = string.character(at: start - 1)
            if let scalar = Unicode.Scalar(letter), CharacterSet.whitespacesAndNewlines.contains(scalar) { break }
            start -= 1
        }
        guard start < caret.location else { return nil }
        let word = string.substring(with: NSRange(location: start, length: caret.location - start))
        guard let found = MemoLinks.typedAddress(word) else { return nil }
        let range = NSRange(location: start, length: found.length)
        let isCode = (storage.attribute(codeKey, at: start, effectiveRange: nil) as? Bool) == true
            || (storage.attribute(inlineCodeKey, at: start, effectiveRange: nil) as? Bool) == true
        guard !isCode, link(in: storage, at: start).map({ $0.range.location <= start && NSMaxRange($0.range) >= NSMaxRange(range) }) != true else { return nil }
        return (range, found.address)
    }

    /// The typed address becomes a link, a step of its own after the key's, if its letters are
    /// still where they were.
    static func finishTyped(_ typed: (range: NSRange, address: String), word: String, in textView: NSTextView) {
        guard let storage = textView.textStorage, NSMaxRange(typed.range) <= storage.length,
              (storage.string as NSString).substring(with: typed.range) == word else { return }
        set(typed.address, on: typed.range, in: textView)
    }

    // MARK: Clipboard

    /// ⌘V with letters picked on one line and an address alone on the clipboard: the letters
    /// stay and become a link to it (a link already there takes the new address). False for
    /// anything else, which pastes as usual.
    static func pasteAddress(into textView: NSTextView, draft: MemoDraft) -> Bool {
        guard !draft.isUnreadable, let storage = textView.textStorage, textView.selectedRanges.count == 1 else { return false }
        let picked = textView.selectedRange()
        guard picked.length > 0, NSMaxRange(picked) <= storage.length,
              canTake((storage.string as NSString).substring(with: picked)),
              let words = NSPasteboard.general.string(forType: .string), let address = MemoLinks.address(words) else { return false }
        set(address, on: picked, in: textView)
        draft.focusRequest += 1
        return true
    }

    /// ⌘V with linked letters on the clipboard (a web page's, a document's, or this memo's own
    /// copy): their words go in as a paste would put them, the links kept. False when the
    /// clipboard holds no link this memo would keep, so the paste goes on as usual.
    static func pasteLinked(into textView: NSTextView, draft: MemoDraft) -> Bool {
        guard !draft.isUnreadable, let storage = textView.textStorage else { return false }
        let board = NSPasteboard.general
        let letters: NSMutableAttributedString
        var base = textView.typingAttributes
        base[todoKey] = nil
        base[todoBoxKey] = nil
        base[key] = nil
        if let data = board.data(forType: MemoTableClipboard.memoType), board.changeCount == MemoTableClipboard.ownCopy,
           let text = MemoTablePaste.unclip(data), text.runs.contains(where: { $0[MemoAttributes.Link.self] != nil }) {
            // The memo's own copy: its letters whole, links and all.
            letters = MemoTableClipboard.rendered(text)
        } else {
            let rich: NSAttributedString?
            if let html = board.data(forType: .html), MemoTableClipboard.contains(html, "href") {
                rich = MemoTableClipboard.rich(MemoTableClipboard.withoutLoads(html), type: .html)
            } else if let rtf = board.data(forType: .rtf), MemoTableClipboard.contains(rtf, "HYPERLINK") {
                rich = MemoTableClipboard.rich(rtf, type: .rtf)
            } else {
                rich = nil
            }
            guard let rich else { return false }
            let found = links(in: rich, range: NSRange(location: 0, length: rich.length))
            guard !found.isEmpty else { return false }
            // The words as a paste puts them; formatting is the caret's, as with any paste here.
            letters = NSMutableAttributedString(string: rich.string, attributes: base)
            for link in found {
                for part in carried(link.range, in: letters.string as NSString) { letters.addAttribute(key, value: link.address, range: part) }
            }
        }
        let picked = textView.selectedRange()
        // A table cell takes letters of one line only; several lines paste as usual.
        if MemoLineStyler.table(in: storage, at: picked.location) != nil, letters.string.contains(where: { $0.isNewline || $0 == "\t" }) { return false }
        MemoTableClipboard.replace(picked, with: letters, in: textView)
        let end = picked.location + letters.length
        textView.setSelectedRange(NSRange(location: min(end, (textView.string as NSString).length), length: 0))
        draft.focusRequest += 1
        return true
    }

    /// Copied letters with a link in them, and no table (`MemoTableClipboard` writes those): as
    /// words, HTML and RTF with the links, and the memo's own letters, so they paste back here
    /// as links. False for other letters, which the text view copies as usual.
    @discardableResult
    static func writeCopy(_ piece: AttributedString) -> Bool {
        guard piece.runs.contains(where: { $0[MemoAttributes.Link.self] != nil }) else { return false }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(MemoAttachments.plainText(piece), forType: .string)
        if let html = NotesHTML.fragment(piece) { board.setString("<meta charset=\"utf-8\">" + html, forType: .html) }
        let rich = NSMutableAttributedString()
        for run in piece.runs {
            var letters = String(piece[run.range].characters)
            if let ref = run[MemoAttributes.Attachment.self].flatMap(MemoAttachments.Ref.init(value:)) {
                letters = letters.map { $0 == MemoAttachments.placeholder ? MemoAttachments.label(ref) : String($0) }.joined()
            }
            // Bold and italic as the text view's own copy has them, and the link.
            var font = NSFont.systemFont(ofSize: MemoStyle.size, weight: run[MemoAttributes.Bold.self] == true ? .bold : .regular)
            if run[MemoAttributes.Italic.self] == true { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if run[MemoAttributes.Underline.self] == true { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if run[MemoAttributes.Strike.self] == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let address = run[MemoAttributes.Link.self].flatMap(MemoLinks.stored), let url = URL(string: address) { attributes[.link] = url }
            rich.append(NSAttributedString(string: letters, attributes: attributes))
        }
        if let rtf = try? rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            board.setData(rtf, forType: .rtf)
        }
        if let data = MemoTablePaste.clip(piece) { board.setData(data, forType: MemoTableClipboard.memoType) }
        MemoTableClipboard.noteOwnCopy()
        return true
    }
}

// MARK: - The memo's side

extension MemoDraft {
    /// A link can go on the selection: one line's letters within one table cell, no attached
    /// file; or a caret, where ⌘K puts the address itself in.
    var canLink: Bool {
        guard !isUnreadable else { return false }
        let picked = selectedRanges.filter { !$0.isEmpty }
        guard picked.count <= 1 else { return false }
        guard let range = picked.first else { return true }
        return MemoLinkEdit.canTake(String(text[range].characters))
    }

    /// ⌘K, the bars' 링크 and 서식 › 링크…: the address field under the picked letters, filled
    /// with the link's address when they are in one. A beep where no link can go.
    func askForLink() {
        guard canLink, let target = linkTarget?() else { return NSSound.beep() }
        showsParagraphBar = false
        showPop(.link(location: target.range.location, length: target.range.length, address: target.address))
    }

    /// The address field's 넣기 or 고치기: the typed address on the letters, or, with none
    /// picked, in at the caret as a link. False for an address no link may hold.
    @discardableResult
    func putLink(_ typed: String, location: Int, length: Int) -> Bool {
        guard let address = MemoLinks.address(typed) else { return false }
        book.todos.pop = nil
        editLink?(NSRange(location: location, length: length), address)
        focusRequest += 1
        return true
    }

    /// 링크 지우기: the letters stay, plain.
    func removeLink(location: Int, length: Int) {
        book.todos.pop = nil
        editLink?(NSRange(location: location, length: length), nil)
        focusRequest += 1
    }

    /// Letters typed at a link's end are not part of it: the caret's typing style drops the
    /// link there (in the middle of one, typing goes on in it).
    func dropLinkTypingAtEnd() {
        guard case .insertionPoint(let caret) = selection.indices(in: text),
              let address = selection.attributes(in: text)[MemoAttributes.Link.self].compactMap({ $0 }).first else { return }
        if caret < text.endIndex, text.runs[caret][MemoAttributes.Link.self] == address { return }
        change { $0[MemoAttributes.Link.self] = nil }
    }
}

/// ⌘K's field under the picked letters: the address, 넣기 (or 고치기 for a link already there)
/// and 링크 지우기. Return puts it in, Esc closes it.
struct LinkPop: View {
    let draft: MemoDraft
    let location: Int
    let length: Int
    let address: String?
    let close: () -> Void
    @State private var typed = ""
    @State private var isWrong = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceXs) {
            HStack(spacing: Metrics.spaceS) {
                TextField("https://", text: $typed)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(put)
                    .onChange(of: typed) { isWrong = false }
                    .drawnField(.box, focused: focused)
                    .accessibilityLabel("링크 주소")
                Button(address == nil ? "넣기" : "고치기", action: put)
                    .buttonStyle(DrawnButtonStyle(.primary))
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                if address != nil {
                    Button("링크 지우기") { draft.removeLink(location: location, length: length) }
                        .buttonStyle(DrawnButtonStyle(.text))
                }
            }
            Text(isWrong ? "http, https, mailto 주소만 넣을 수 있어요." : "Return 넣기 · Esc 취소")
                .textStyle(.cell)
                .foregroundStyle(isWrong ? Color.danger : Color.inkSoft)
        }
        .onAppear {
            typed = address ?? ""
            focused = true
        }
    }

    private func put() {
        if !draft.putLink(typed, location: location, length: length) { isWrong = true }
    }
}
