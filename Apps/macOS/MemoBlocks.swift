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
        // A table row's leading tab is a cell, not a level.
        guard !isUnreadable, !touchesTable, editLines?({ MemoLists.setKind(kind, in: $0, selection: $1) }) == true else {
            NSSound.beep()
            return
        }
        focusRequest += 1
    }

    /// ⌘] and ⌘[: list items a level in or out, other lines by a leading tab.
    func indentLines(by step: Int) {
        guard !isUnreadable, !touchesTable, editLines?({ MemoLists.indent(in: $0, selection: $1, by: step, listsOnly: false) }) == true else {
            NSSound.beep()
            return
        }
        focusRequest += 1
    }

    /// Return at the end of a title, heading or subheading: the next line is body text. Called
    /// after the line break went in, with the caret after it.
    func typeBodyAfterParagraph() {
        guard case .insertionPoint(let caret) = selection.indices(in: text) else { return }
        // The alignment goes on, as it does after a body line.
        var typing = AttributeContainer()
        if caret > text.startIndex { typing[MemoAttributes.Align.self] = text.runs[text.characters.index(before: caret)][MemoAttributes.Align.self] }
        selection = AttributedTextSelection(insertionPoint: caret, typingAttributes: typing)
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
    private static let leftKey: UInt16 = 123
    private static let rightKey: UInt16 = 124
    private static let forwardDeleteKey: UInt16 = 117

    private static let codeKey = NSAttributedString.Key(MemoAttributes.Code.name)
    private static let paragraphKey = NSAttributedString.Key(MemoAttributes.Paragraph.name)

    /// Return, Tab, ⇧Tab, Delete and a space typed in the memo's text view: true when the key was
    /// used here. Anything else, or the same keys where they mean what they always do, goes on to
    /// the text view.
    static func handle(_ event: NSEvent, in textView: NSTextView, draft: MemoDraft) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let code = event.keyCode
        // ← → and Delete step over a line's invisible plain mark as if it were not there.
        if modifiers.isEmpty, !textView.hasMarkedText(), stepOverPlainMark(code, in: textView) { return true }
        guard [returnKey, enterKey, tabKey, deleteKey, spaceKey].contains(code), modifiers.isEmpty || (code == tabKey && modifiers == .shift) else {
            return false
        }
        // A table row's tabs and letters are cells; the table keys handle what they need.
        if let storage = textView.textStorage, MemoLineStyler.table(in: storage, at: textView.selectedRange().location) != nil { return false }
        if code == spaceKey {
            let caret = textView.selectedRange()
            guard !textView.hasMarkedText(), caret.length == 0, !isCode(at: caret.location, in: textView) else { return false }
            // The space goes in first, a step of its own; a `* ` it made becomes `• ` as the next
            // step, so ⌘Z takes the bullet back to the star and then the space.
            if startsWithStar(textView) {
                textView.breakUndoCoalescing()
                replace(caret, with: " ", in: textView)
                textView.setSelectedRange(NSRange(location: caret.location + 1, length: 0))
                Task { @MainActor in
                    guard let change = MemoLists.autoBullet(in: textView.string, caret: textView.selectedRange().location) else { return }
                    apply(change, to: textView)
                }
                return true
            }
            // A space that makes a list item or quote (`1. `, `- `, `> `): it goes in with the plain
            // mark, then the mark comes out as a step of its own. ⌘Z right after puts the mark
            // back: the letters stay, the line is plain. ⌘Z again takes the space.
            if let at = MemoLists.autoFormat(in: textView.string, caret: caret.location) {
                let mark = (MemoLists.plainMark as NSString).length
                let typed = (textView.string as NSString).substring(with: NSRange(location: at, length: caret.location - at))
                textView.breakUndoCoalescing()
                replace(NSRange(location: at, length: caret.location - at), with: MemoLists.plainMark + typed + " ", in: textView)
                let after = caret.location + mark + 1
                textView.setSelectedRange(NSRange(location: after, length: 0))
                Task { @MainActor in
                    let string = textView.string as NSString
                    guard at + mark <= string.length, string.substring(with: NSRange(location: at, length: mark)) == MemoLists.plainMark else { return }
                    apply(MemoLists.Change(edits: [MemoLists.Edit(range: NSRange(location: at, length: mark), text: "")],
                                           selection: NSRange(location: max(at, textView.selectedRange().location - mark), length: 0)), to: textView)
                }
                return true
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

    /// ← past a line's plain mark (`MemoLists.plainMark`), → over it, ⌦ just before it (the next
    /// letter goes with it), and Delete just after it
    /// (a quote's `> ` comes off; elsewhere the letter before it goes with it) or after the
    /// line's first letter (the mark goes with the letter): the caret never stops twice at one
    /// place, and Delete never brings the formatting back by taking the mark alone. True when
    /// the key was used here.
    private static func stepOverPlainMark(_ code: UInt16, in textView: NSTextView) -> Bool {
        guard [leftKey, rightKey, deleteKey, forwardDeleteKey].contains(code) else { return false }
        let caret = textView.selectedRange()
        guard caret.length == 0 else { return false }
        let string = textView.string as NSString
        guard caret.location <= string.length else { return false }
        let line = MemoLists.lineContent(of: string.lineRange(for: NSRange(location: caret.location, length: 0)), in: string)
        guard let mark = MemoLists.plainMarkRange(of: line, in: string) else { return false }
        switch code {
        case leftKey:
            // From just after the mark the caret goes on as from before it.
            if NSMaxRange(mark) == caret.location { textView.setSelectedRange(NSRange(location: mark.location, length: 0)) }
            return false
        case rightKey:
            if mark.location == caret.location { textView.setSelectedRange(NSRange(location: NSMaxRange(mark), length: 0)) }
            return false
        case forwardDeleteKey:
            // Before the mark: the letter after it goes with it, never the mark alone.
            guard mark.location == caret.location, NSMaxRange(mark) < string.length else { return false }
            let next = string.rangeOfComposedCharacterSequence(at: NSMaxRange(mark))
            replace(NSRange(location: mark.location, length: NSMaxRange(next) - mark.location), with: "", in: textView)
            textView.setSelectedRange(NSRange(location: mark.location, length: 0))
            return true
        default:
            if NSMaxRange(mark) == caret.location {
                // In a quote: Delete takes the quote off, as at any quote's words, and the line stays plain.
                if mark.location == line.location + 2, string.substring(with: NSRange(location: line.location, length: 2)) == "> " {
                    replace(NSRange(location: line.location, length: 2), with: "", in: textView)
                    textView.setSelectedRange(NSRange(location: line.location + (MemoLists.plainMark as NSString).length, length: 0))
                    return true
                }
                // After leading tabs: one tab comes off, as Delete there would take it; the line stays plain.
                if mark.location > line.location {
                    replace(NSRange(location: mark.location - 1, length: 1), with: "", in: textView)
                    textView.setSelectedRange(NSRange(location: NSMaxRange(mark) - 1, length: 0))
                    return true
                }
                // At the memo's very front there is nothing before it to take.
                guard mark.location > 0 else { return true }
                let before = string.rangeOfComposedCharacterSequence(at: mark.location - 1)
                replace(NSRange(location: before.location, length: NSMaxRange(mark) - before.location), with: "", in: textView)
                textView.setSelectedRange(NSRange(location: before.location, length: 0))
                return true
            }
            guard NSMaxRange(mark) < string.length else { return false }
            let first = string.rangeOfComposedCharacterSequence(at: NSMaxRange(mark))
            guard NSMaxRange(first) == caret.location else { return false }
            replace(NSRange(location: mark.location, length: NSMaxRange(first) - mark.location), with: "", in: textView)
            textView.setSelectedRange(NSRange(location: mark.location, length: 0))
            return true
        }
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

/// Whether the Aa button's 문단 bar is pinned under the "메모" rule as a one-line toolbar, the
/// floating bar's 핀, the 서식 menu's 서식 막대 늘 보이기 and the setting alike. Remembered on this
/// Mac; off at first.
@MainActor
@Observable
final class MemoBarPin {
    static let shared = MemoBarPin()
    private static let key = "memoParagraphBarPinned"

    var isPinned = UserDefaults.standard.bool(forKey: MemoBarPin.key) {
        didSet { UserDefaults.standard.set(isPinned, forKey: Self.key) }
    }
}

#if DEBUG
/// Where the bar's and the pinned toolbar's buttons are, by name, in window coordinates (top-left
/// origin), for `MemoFormatCheck` to click them as the pointer would.
@MainActor
enum MemoBarFrames {
    static var byName: [String: CGRect] = [:]
}

/// Notes a view's place; going away it takes off only its own note, since another view of the
/// same name (the pinned toolbar's other line-up) may have noted its place since.
private struct BarFrameNote: ViewModifier {
    let name: String
    @State private var noted: CGRect?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                // A line-up being swapped out reports no place.
                guard !frame.isNull, !frame.isInfinite else { return }
                noted = frame
                MemoBarFrames.byName[name] = frame
            }
            .onDisappear {
                if MemoBarFrames.byName[name] == noted { MemoBarFrames.byName[name] = nil }
            }
    }
}
#endif

extension View {
    /// Debug builds note the view's place under `name` for the format check.
    func barFrame(_ name: String) -> some View {
        #if DEBUG
        modifier(BarFrameNote(name: name))
        #else
        self
        #endif
    }
}

/// Where the Aa button is, for the bar and the shortcut card to hang under it.
struct MemoAaAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// One of the 문단 bar's buttons: what it is, how it looks, and what it does.
private struct MemoBarItem {
    var name: String
    var shortcut: String?
    var symbol: String

    var help: String { shortcut.map { "\(name) (\($0))" } ?? name }

    static let alignLeft = MemoBarItem(name: "왼쪽 정렬", shortcut: "⌘⇧L", symbol: "text.alignleft")
    static let alignCenter = MemoBarItem(name: "가운데 정렬", shortcut: "⌘⇧E", symbol: "text.aligncenter")
    static let alignRight = MemoBarItem(name: "오른쪽 정렬", shortcut: "⌘⇧R", symbol: "text.alignright")
    static let bullet = MemoBarItem(name: "글머리 기호 목록", shortcut: "⌘⇧7", symbol: "list.bullet")
    static let dash = MemoBarItem(name: "대시 목록", shortcut: "⌘⇧8", symbol: "list.dash")
    static let number = MemoBarItem(name: "번호 목록", shortcut: "⌘⇧9", symbol: "list.number")
    static let quote = MemoBarItem(name: "인용문", shortcut: "⌘'", symbol: "text.quote")
    static let table = MemoBarItem(name: "표 넣기", shortcut: nil, symbol: "tablecells")
    static let attach = MemoBarItem(name: "파일 첨부", shortcut: "⌘⇧A", symbol: "paperclip")
    static let link = MemoBarItem(name: "링크", shortcut: "⌘K", symbol: "link")
}

/// The buttons the bar and the pinned toolbar share, for the caret's line.
@MainActor
private struct MemoBarButtons {
    let draft: MemoDraft
    /// Square side: the floating bar's, or the pinned toolbar's smaller one.
    var side: CGFloat

    /// Alignment is for lines of words (`MemoDraft.canAlign`).
    private var canAlign: Bool { draft.canAlign }

    @ViewBuilder var aligns: some View {
        let align = draft.align
        square(.alignLeft, isOn: canAlign && align == nil, isEnabled: canAlign) { draft.setAlign(nil) }
        square(.alignCenter, isOn: canAlign && align == .center, isEnabled: canAlign) { draft.setAlign(.center) }
        square(.alignRight, isOn: canAlign && align == .right, isEnabled: canAlign) { draft.setAlign(.right) }
    }

    @ViewBuilder var lists: some View {
        let kind = draft.listKind
        square(.bullet, isOn: kind == .bullet) { draft.setList(.bullet) }
        square(.dash, isOn: kind == .dash) { draft.setList(.dash) }
        square(.number, isOn: kind == .number) { draft.setList(.number) }
        square(.quote, isOn: draft.isQuoted) { draft.setList(.quote) }
    }

    @ViewBuilder var inserts: some View {
        square(.table, isOn: false, isEnabled: !draft.isInTable) { draft.tableAction(.insert) }
        square(.attach, isOn: false) { draft.askToAttach() }
        // On picked letters within one line and cell, or at the caret; it opens the address field.
        square(.link, isOn: false, isEnabled: draft.canLink) { draft.askForLink() }
    }

    /// The pin: floats the bar under Aa, or keeps it under the "메모" rule.
    var pin: some View {
        let pin = MemoBarPin.shared
        let name = pin.isPinned ? "서식 막대 고정 풀기" : "서식 막대 고정"
        return Button {
            draft.showsParagraphBar = false
            pin.isPinned.toggle()
            draft.focusRequest += 1
        } label: {
            Image(systemName: pin.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(pin.isPinned ? Color.onInk : Color.ink)
                .frame(width: side, height: side)
                .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
        }
        .buttonStyle(FormatButtonStyle(isOn: pin.isPinned))
        .focusable(false)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(pin.isPinned ? .isSelected : [])
        .barFrame(name)
    }

    func square(_ item: MemoBarItem, isOn: Bool, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: pick(action)) {
            Image(systemName: item.symbol)
                .font(.system(size: side > 22 ? 13 : 12))
                .foregroundStyle(isOn ? Color.onInk : isEnabled ? Color.ink : Color.inkFaint)
                .frame(width: side + 2, height: side)
                .overlay(Rectangle().strokeBorder(isEnabled ? Color.ink : Color.inkFaint, lineWidth: Metrics.line))
        }
        .buttonStyle(FormatButtonStyle(isOn: isOn))
        .focusable(false)
        .disabled(!isEnabled)
        .help(item.help)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .barFrame(item.name)
    }

    /// The line changes and the caret goes back to the memo; the bar stays open for the next pick.
    func pick(_ action: @escaping () -> Void) -> () -> Void {
        {
            action()
            draft.focusRequest += 1
        }
    }
}

/// The section rule's Aa: opens the 문단 bar for the caret's line, and shows the format shortcuts
/// a moment after the pointer comes to rest on it. While the bar is pinned it shows switched on
/// and dimmed; the pinned toolbar is the bar then.
struct MemoParagraphButton: View {
    @Bindable var draft: MemoDraft
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        let isPinned = MemoBarPin.shared.isPinned
        let isOn = draft.showsParagraphBar || isPinned
        Button {
            hoverTask?.cancel()
            draft.showsShortcutCard = false
            // A click judged outside the bar just closed it, though it landed on Aa (should the
            // frames be out of date): Aa then leaves it closed rather than opening it again.
            if ProcessInfo.processInfo.systemUptime - draft.barClosedByClick < 0.35 { return }
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
        .disabled(draft.isUnreadable || isPinned)
        .opacity(isPinned ? 0.5 : 1)
        .accessibilityLabel("문단 서식")
        .accessibilityHint(isPinned ? "서식 막대가 메모 위에 고정되어 있어요" : "")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        // On a wrapper, so the card shows while the button is dimmed by the pin too.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onHover { inside in
                    hoverTask?.cancel()
                    guard inside else {
                        draft.showsShortcutCard = false
                        return
                    }
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled, !draft.showsParagraphBar else { return }
                        draft.showsShortcutCard = true
                    }
                }
        }
        .anchorPreference(key: MemoAaAnchor.self, value: .bounds) { $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { draft.aaFrame = $0 }
        .onDisappear {
            hoverTask?.cancel()
            draft.showsShortcutCard = false
        }
    }
}

/// The bar or the shortcut card, hung under the Aa button's right end, over whatever is below.
/// Drawn over the memo section, so tabs above the memo or 모아 보기's headers never push it down.
struct MemoAaLayer: View {
    let draft: MemoDraft
    let anchor: Anchor<CGRect>?

    var body: some View {
        GeometryReader { proxy in
            if let anchor, !draft.isUnreadable, draft.showsParagraphBar || draft.showsShortcutCard {
                let aa = proxy[anchor]
                Group {
                    if draft.showsParagraphBar {
                        MemoParagraphBar(draft: draft)
                    } else {
                        MemoShortcutCard().allowsHitTesting(false)
                    }
                }
                .fixedSize()
                .frame(width: max(aa.maxX, 0), alignment: .topTrailing)
                .offset(y: aa.maxY + Metrics.spaceXs)
            }
        }
    }
}

/// The Aa button's bar: the caret line's paragraph style (제목, 머리말, 부, 본문), alignment and
/// list kind, a table and an attachment, and the pin. It stays open while picking, so 제목 and
/// 가운데 go on one after another; Esc, typing, a click elsewhere or Aa close it.
struct MemoParagraphBar: View {
    let draft: MemoDraft
    private var buttons: MemoBarButtons { MemoBarButtons(draft: draft, side: 24) }

    var body: some View {
        let paragraph = draft.paragraph
        VStack(alignment: .leading, spacing: Metrics.spaceS) {
            HStack(spacing: Metrics.spaceXs) {
                label("문단")
                wide("제목", "제목", "⌥⌘1", isOn: paragraph == .title, font: .display(13)) { draft.setParagraph(.title) }
                wide("머리말", "머리말", "⌥⌘2", isOn: paragraph == .heading, font: .display(13, bold: false)) { draft.setParagraph(.heading) }
                wide("부", "부머리말", "⌥⌘3", isOn: paragraph == .sub, font: TextStyle.body.font.weight(.semibold)) { draft.setParagraph(.sub) }
                wide("본문", "본문", "⌥⌘0", isOn: paragraph == nil, font: TextStyle.body.font) { draft.setParagraph(nil) }
                Spacer(minLength: Metrics.spaceL)
                buttons.pin
            }
            HStack(spacing: Metrics.spaceXs) {
                label("정렬")
                buttons.aligns
            }
            HStack(spacing: Metrics.spaceXs) {
                label("목록")
                buttons.lists
                Rectangle().fill(.ink).frame(width: Metrics.line, height: 18).padding(.horizontal, Metrics.spaceXxs)
                buttons.inserts
            }
        }
        .padding(Metrics.spaceM)
        .floatingFrame()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { draft.paragraphBarFrame = $0 }
        .onDisappear { draft.paragraphBarFrame = .null }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("문단 서식")
    }

    private func label(_ title: String) -> some View {
        Text(title).textStyle(.cell).foregroundStyle(.inkSoft).frame(width: 30, alignment: .leading)
    }

    private func wide(_ title: String, _ name: String, _ shortcut: String, isOn: Bool, font: Font, action: @escaping () -> Void) -> some View {
        Button(action: buttons.pick(action)) {
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
        .barFrame(name)
    }
}

/// What the pointer resting on Aa shows: the paragraph and format shortcuts, so they can be used
/// without opening the bar.
struct MemoShortcutCard: View {
    static let rows: [(name: String, keys: String)] = [
        ("제목 · 머리말 · 부 · 본문", "⌥⌘1 2 3 0"),
        ("왼쪽 · 가운데 · 오른쪽", "⌘⇧L E R"),
        ("글머리 · 대시 · 번호", "⌘⇧7 8 9"),
        ("인용문", "⌘'"),
        ("첨부", "⌘⇧A"),
        ("링크", "⌘K"),
        ("굵게 · 기울임 · 밑줄", "⌘B I U"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceXs) {
            Text("단축키").textStyle(.cell).foregroundStyle(.inkSoft)
            Grid(alignment: .leading, horizontalSpacing: Metrics.spaceL, verticalSpacing: Metrics.spaceXxs) {
                ForEach(Self.rows, id: \.name) { row in
                    GridRow {
                        Text(row.name).textStyle(.cell)
                        Text(row.keys).font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
        .foregroundStyle(.ink)
        .padding(Metrics.spaceM)
        .background(.paper)
        .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("서식 단축키")
    }
}

/// The 문단 bar pinned under the "메모" rule: one line of tools from the left (the paragraph
/// style as a menu, alignment, lists, a table and an attachment) and the pin at the right end.
/// One per panel; in 모아 보기 it works on the memo being written.
struct MemoFormatStrip: View {
    let draft: MemoDraft
    @State private var isMenuOpen = false
    private var buttons: MemoBarButtons { MemoBarButtons(draft: draft, side: 20) }

    var body: some View {
        // One line where the panel has room; in a narrow panel the inserts and the pin go to a
        // second line, so the bar never makes the panel wider than its place.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.spaceXs) {
                formats
                buttons.inserts
                Spacer(minLength: Metrics.spaceS)
                buttons.pin
            }
            VStack(alignment: .leading, spacing: Metrics.spaceS) {
                HStack(spacing: Metrics.spaceXs) { formats }
                HStack(spacing: Metrics.spaceXs) {
                    buttons.inserts
                    Spacer(minLength: Metrics.spaceS)
                    buttons.pin
                }
            }
        }
        .disabled(draft.isUnreadable)
        .padding(.bottom, Metrics.spaceS)
        .overlay(alignment: .bottom) { Rectangle().fill(.shade).frame(height: Metrics.line) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("서식 막대")
        .barFrame("서식 막대")
    }

    /// The paragraph style, alignment and lists.
    @ViewBuilder private var formats: some View {
        paragraphMenu
        divider
        buttons.aligns
        divider
        buttons.lists
    }

    private var divider: some View {
        Rectangle().fill(.shade).frame(width: Metrics.line, height: 14).padding(.horizontal, Metrics.spaceXxs)
    }

    private var paragraphMenu: some View {
        let paragraph = draft.paragraph
        let name = switch paragraph {
        case .title?: "제목"
        case .heading?: "머리말"
        case .sub?: "부머리말"
        case nil: "본문"
        }
        return Button { isMenuOpen = true } label: {
            HStack(spacing: Metrics.spaceXs) {
                Text(name).textStyle(.cell)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.ink)
            .padding(.horizontal, Metrics.spaceS)
            .frame(height: 20)
            .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
        }
        .buttonStyle(FormatButtonStyle(isOn: false))
        .focusable(false)
        .fixedSize()
        .inkMenu(isPresented: $isMenuOpen) {
            [(MemoParagraph?.some(.title), "제목", "⌥⌘1"), (.heading, "머리말", "⌥⌘2"), (.sub, "부머리말", "⌥⌘3"), (nil, "본문", "⌥⌘0")].map { item in
                .item(item.1, detail: item.2, checked: paragraph == item.0) {
                    draft.setParagraph(item.0)
                    draft.focusRequest += 1
                }
            }
        }
        .help("문단 서식")
        .accessibilityLabel("문단 서식")
        .accessibilityValue(name)
    }
}
