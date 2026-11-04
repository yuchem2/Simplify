import AppKit
import SwiftUI
import SimplifyKit

// Lists, quotes and the Aa button's 문단 bar. A list or quote is letters at the front of its line
// (`MemoLists`), drawn by `MemoLineStyler`; the editing rules give back edits that are made in the
// text view, as typing would, so each is one undo step.

extension MemoDraft {
    /// The list or quote marker of the line the selection starts on.
    var lineMarker: MemoLists.Marker? {
        guard let start = selectedRanges.first?.lowerBound else { return nil }
        return MemoLists.marker(in: String(text.characters), at: String(text[text.startIndex..<start].characters).utf16.count)
    }

    /// The list kind of the line the selection starts on, in a quote or not.
    var listKind: MemoLists.Kind? {
        lineMarker.flatMap { $0.kind == .quote ? nil : $0.kind }
    }

    /// The line the selection starts on is in a quote.
    var isQuoted: Bool { lineMarker?.isQuoted == true }

    /// 서식 › 글머리 기호·대시·번호 목록, 인용문, and the 문단 bar: the selection's lines become
    /// that kind, or plain lines again when they all are.
    func setList(_ kind: MemoLists.Kind) {
        guard !isUnreadable, editLines?({ MemoLists.setKind(kind, in: $0, selection: $1) }) == true else {
            NSSound.beep()
            return
        }
        focusRequest += 1
    }

    /// ⌘] and ⌘[: list items a level in or out, other lines by a leading tab.
    func indentLines(by step: Int) {
        guard !isUnreadable, editLines?({ MemoLists.indent(in: $0, selection: $1, by: step, listsOnly: false) }) == true else {
            NSSound.beep()
            return
        }
        focusRequest += 1
    }

    /// Return at the end of a title, heading or subheading: the next line is body text. Called
    /// after the line break went in, with the caret after it.
    func typeBodyAfterParagraph() {
        guard case .insertionPoint(let caret) = selection.indices(in: text) else { return }
        selection = AttributedTextSelection(insertionPoint: caret, typingAttributes: AttributeContainer())
    }
}

/// The text view's side of lists: the keys `MemoMenuHost` hands over, and making a change.
@MainActor
enum MemoListKeys {
    private static let returnKey: UInt16 = 36
    private static let enterKey: UInt16 = 76
    private static let tabKey: UInt16 = 48
    private static let deleteKey: UInt16 = 51
    private static let spaceKey: UInt16 = 49

    private static let codeKey = NSAttributedString.Key(MemoAttributes.Code.name)
    private static let paragraphKey = NSAttributedString.Key(MemoAttributes.Paragraph.name)

    /// Return, Tab, ⇧Tab, Delete and a space typed in the memo's text view: true when the key was
    /// used here. Anything else, or the same keys where they mean what they always do, goes on to
    /// the text view.
    static func handle(_ event: NSEvent, in textView: NSTextView, draft: MemoDraft) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let code = event.keyCode
        guard [returnKey, enterKey, tabKey, deleteKey, spaceKey].contains(code), modifiers.isEmpty || (code == tabKey && modifiers == .shift) else {
            return false
        }
        if code == spaceKey {
            // The space goes in first, as typed; a `* ` it made becomes `• ` as a step of its own.
            if !textView.hasMarkedText(), startsWithStar(textView), !isCode(at: textView.selectedRange().location, in: textView) {
                Task { @MainActor in
                    guard let change = MemoLists.autoBullet(in: textView.string, caret: textView.selectedRange().location) else { return }
                    apply(change, to: textView)
                }
            }
            return false
        }
        // Delete while composing takes back a letter of the syllable.
        if code == deleteKey, textView.hasMarkedText() { return false }
        let selected = textView.selectedRange()
        guard !isCode(at: selected.location, in: textView) else { return false }
        if code == deleteKey {
            guard selected.length == 0, let change = MemoLists.deleteBackward(in: textView.string, caret: selected.location) else { return false }
            apply(change, to: textView)
            return true
        }
        // Return and Tab where they make a list change (or leave a title line) finish a Korean
        // syllable first, then do it; elsewhere they go on as usual.
        let shift = modifiers == .shift ? -1 : 1
        let isUsed = code == tabKey
            ? MemoLists.indent(in: textView.string, selection: selected, by: shift) != nil
            : selected.length == 0 && (MemoLists.returnKey(in: textView.string, caret: selected.location) != nil || endsParagraphLine(textView))
        guard isUsed else { return false }
        finishComposing(textView)
        // Finishing may have moved the letters and the caret.
        let now = textView.selectedRange()
        if code == tabKey {
            if let change = MemoLists.indent(in: textView.string, selection: now, by: shift) { apply(change, to: textView) }
        } else if let change = MemoLists.returnKey(in: textView.string, caret: now.location) {
            apply(change, to: textView)
        } else if endsParagraphLine(textView) {
            replace(now, with: "\n", in: textView)
            // Once SwiftUI has the new line.
            Task { @MainActor in draft.typeBodyAfterParagraph() }
        } else {
            textView.insertNewline(nil)
        }
        return true
    }

    /// Makes the edits one after another, then puts the selection where the change says.
    static func apply(_ change: MemoLists.Change, to textView: NSTextView) {
        // Its own undo step, not folded into the typing or format change before it.
        textView.breakUndoCoalescing()
        for edit in change.edits { replace(edit.range, with: edit.text, in: textView) }
        let length = (textView.string as NSString).length
        let location = min(change.selection.location, length)
        textView.setSelectedRange(NSRange(location: location, length: min(change.selection.length, length - location)))
    }

    /// One edit, as the text view's own: undoable, and passed on to SwiftUI's copy of the memo.
    /// New letters take the look of the front of their line (a marker's plain letters, not the
    /// bold word the caret was after), never a ToDo chip's.
    private static func replace(_ range: NSRange, with letters: String, in textView: NSTextView) {
        guard let storage = textView.textStorage, NSMaxRange(range) <= storage.length,
              textView.shouldChangeText(in: range, replacementString: letters) else { return }
        var attributes = textView.typingAttributes
        if range.length > 0 {
            attributes = storage.attributes(at: range.location, effectiveRange: nil)
        } else {
            let line = (storage.string as NSString).lineRange(for: NSRange(location: range.location, length: 0))
            if line.location < storage.length, line.length > 0, !(storage.string as NSString).substring(with: line).hasPrefix("\n") {
                attributes = storage.attributes(at: line.location, effectiveRange: nil)
            }
        }
        attributes[NSAttributedString.Key(MemoAttributes.Todo.name)] = nil
        attributes[NSAttributedString.Key(MemoAttributes.TodoBox.name)] = nil
        // A line break left after a title would carry the title on, and keep it saved once the
        // title is gone.
        if letters.contains("\n") { attributes[paragraphKey] = nil }
        storage.replaceCharacters(in: range, with: NSAttributedString(string: letters, attributes: attributes))
        textView.didChangeText()
    }

    /// The letters before the caret on its line are tabs and a `*` (after a quote's `> ` or not),
    /// the space about to follow.
    private static func startsWithStar(_ textView: NSTextView) -> Bool {
        let caret = textView.selectedRange()
        guard caret.length == 0, caret.location > 0 else { return false }
        let string = textView.string as NSString
        let line = string.lineRange(for: NSRange(location: caret.location, length: 0))
        var typed = string.substring(with: NSRange(location: line.location, length: caret.location - line.location))
        if typed.hasPrefix("> ") { typed.removeFirst(2) }
        return typed.hasSuffix("*") && typed.dropLast().allSatisfy { $0 == "\t" }
    }

    /// A code block's lines keep Tab and Return as they are.
    private static func isCode(at location: Int, in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let line = (storage.string as NSString).lineRange(for: NSRange(location: min(location, storage.length), length: 0))
        let at = min(line.location, storage.length - 1)
        return storage.attribute(codeKey, at: at, effectiveRange: nil) != nil
    }

    /// The caret is at the end of a title, heading or subheading line with words on it.
    private static func endsParagraphLine(_ textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let caret = textView.selectedRange()
        let string = storage.string as NSString
        guard caret.length == 0, caret.location > 0 else { return false }
        let line = MemoLists.lineContent(of: string.lineRange(for: NSRange(location: caret.location, length: 0)), in: string)
        guard NSMaxRange(line) == caret.location, line.length > 0 else { return false }
        return storage.attribute(paragraphKey, at: caret.location - 1, effectiveRange: nil) != nil
    }

    /// A Korean syllable being composed is finished as it stands, as Return would finish it.
    private static func finishComposing(_ textView: NSTextView) {
        guard textView.hasMarkedText() else { return }
        textView.unmarkText()
        textView.inputContext?.discardMarkedText()
    }
}

/// The section rule's Aa: opens the 문단 bar for the caret's line. Nothing shows while writing.
struct MemoParagraphButton: View {
    @Bindable var draft: MemoDraft

    var body: some View {
        let isOn = draft.showsParagraphBar
        Button {
            draft.showsParagraphBar.toggle()
        } label: {
            Text("Aa")
                .font(.display(12))
                .foregroundStyle(isOn ? Color.onInk : Color.ink)
                .padding(.horizontal, Metrics.spaceS)
                .frame(height: 18)
                .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
        }
        .buttonStyle(FormatButtonStyle(isOn: isOn))
        .focusable(false)
        .disabled(draft.isUnreadable)
        .help("문단 서식")
        .accessibilityLabel("문단 서식")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The Aa button's bar: the caret line's paragraph style (제목, 머리말, 부, 본문) and list kind
/// (bullet, dash, number, quote). Picking one changes the line and closes the bar.
struct MemoParagraphBar: View {
    let draft: MemoDraft

    var body: some View {
        let paragraph = draft.paragraph
        let kind = draft.listKind
        VStack(alignment: .leading, spacing: Metrics.spaceS) {
            HStack(spacing: Metrics.spaceXs) {
                label("문단")
                wide("제목", "제목", "⌥⌘1", isOn: paragraph == .title, font: .display(13)) { draft.setParagraph(.title) }
                wide("머리말", "머리말", "⌥⌘2", isOn: paragraph == .heading, font: .display(13, bold: false)) { draft.setParagraph(.heading) }
                wide("부", "부머리말", "⌥⌘3", isOn: paragraph == .sub, font: TextStyle.body.font.weight(.semibold)) { draft.setParagraph(.sub) }
                wide("본문", "본문", "⌥⌘0", isOn: paragraph == nil, font: TextStyle.body.font) { draft.setParagraph(nil) }
            }
            HStack(spacing: Metrics.spaceXs) {
                label("목록")
                square("•", "글머리 기호 목록", "⌘⇧7", isOn: kind == .bullet) { draft.setList(.bullet) }
                square("–", "대시 목록", "⌘⇧8", isOn: kind == .dash) { draft.setList(.dash) }
                square("1.", "번호 목록", "⌘⇧9", isOn: kind == .number, font: TextStyle.cell.font) { draft.setList(.number) }
                square("❝", "인용문", "⌘'", isOn: draft.isQuoted) { draft.setList(.quote) }
            }
        }
        .padding(Metrics.spaceM)
        .frame(width: 296, alignment: .leading)
        .floatingFrame()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("문단 서식")
    }

    private func label(_ title: String) -> some View {
        Text(title).textStyle(.cell).foregroundStyle(.inkSoft).frame(width: 30, alignment: .leading)
    }

    private func wide(_ title: String, _ name: String, _ shortcut: String, isOn: Bool, font: Font, action: @escaping () -> Void) -> some View {
        Button(action: pick(action)) {
            Text(title)
                .font(font)
                .foregroundStyle(isOn ? Color.onInk : Color.ink)
                .padding(.horizontal, Metrics.spaceS)
                .frame(height: 24)
                .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
        }
        .buttonStyle(FormatButtonStyle(isOn: isOn))
        .focusable(false)
        .help("\(name) (\(shortcut))")
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func square(_ title: String, _ name: String, _ shortcut: String, isOn: Bool, font: Font = TextStyle.body.font,
                        action: @escaping () -> Void) -> some View {
        Button(action: pick(action)) {
            Text(title)
                .font(font)
                .foregroundStyle(isOn ? Color.onInk : Color.ink)
                .frame(width: 26, height: 24)
                .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
        }
        .buttonStyle(FormatButtonStyle(isOn: isOn))
        .focusable(false)
        .help("\(name) (\(shortcut))")
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// The bar closes, then the line changes, and the caret goes back to the memo.
    private func pick(_ action: @escaping () -> Void) -> () -> Void {
        {
            draft.showsParagraphBar = false
            action()
            draft.focusRequest += 1
        }
    }
}
