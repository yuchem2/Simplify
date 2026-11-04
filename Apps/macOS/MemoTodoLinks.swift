import AppKit
import SwiftUI
import SimplifyKit

// The memo's side of stage 6: ToDo chips in the text, lines made into ToDos (⌘⇧T), and `[[`.

extension MemoDraft {
    private var todos: TodoBook { book.todos }

    private func lookup(_ id: UUID) -> (title: String, isDone: Bool)? {
        todos.item(id).map { ($0.title, $0.isDone) }
    }

    /// Redraws chips from their ToDos: when the memo opens and whenever a ToDo changes.
    func refreshChips() {
        guard !isUnreadable, !MemoChips.chips(in: text).isEmpty else { return }
        text.transform(updating: &selection) { MemoChips.refresh(&$0, lookup: lookup) }
    }

    /// Letters typed against a chip take its attributes; they go back to plain words, and a chip
    /// edited inside turns into plain words too.
    func keepChipsWhole() {
        // Not while a Korean syllable is being composed: changing the text would break it up.
        // The finished syllable is another change, and is tidied then.
        if isComposing { return }
        guard !MemoChips.chips(in: text).isEmpty else { return }
        let strays = MemoChips.strays(in: text) { todos.item($0)?.title }
        let boxMarks = MemoChips.strayBoxMarks(in: text)
        guard !strays.isEmpty || !boxMarks.isEmpty else { return }
        text.transform(updating: &selection) { text in
            text[strays][MemoAttributes.Todo.self] = nil
            text[strays][MemoAttributes.TodoBox.self] = nil
            text[boxMarks][MemoAttributes.TodoBox.self] = nil
        }
    }

    /// A Korean syllable (or any input method's text) is being composed in the focused text view.
    /// Asked through the input-method interface: the memo's view is not an `NSTextView`.
    var isComposing: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
    }

    /// `[[` just typed: the brackets go and the ToDo search opens where they were.
    func catchSearchTrigger() {
        if skipsSearchTrigger {
            skipsSearchTrigger = false
            return
        }
        guard todos.pop == nil, case .insertionPoint(let caret) = selection.indices(in: text) else { return }
        let characters = text.characters
        guard characters.distance(from: characters.startIndex, to: caret) >= 2 else { return }
        let second = characters.index(before: caret)
        let first = characters.index(before: second)
        guard characters[first] == "[", characters[second] == "[" else { return }
        // Shell tests and formulas use brackets too.
        let run = text.runs[first]
        guard run[MemoAttributes.Code.self] != true, run[MemoAttributes.Math.self] != true else { return }
        let offset = characters.distance(from: characters.startIndex, to: first)
        text.transform(updating: &selection) { $0.removeSubrange(first..<caret) }
        showPop(.search(at: offset, typed: true))
    }

    /// The `[[` search was closed without a pick: the brackets come back, and the caret after them.
    func cancelSearch(at offset: Int, typed: Bool) {
        if typed {
            skipsSearchTrigger = true
            let offset = min(offset, text.characters.count)
            text.transform(updating: &selection) { $0.insert(AttributedString("[["), at: $0.characters.index($0.startIndex, offsetBy: offset)) }
            selection = AttributedTextSelection(insertionPoint: text.characters.index(text.startIndex, offsetBy: offset + 2))
        }
        focusRequest += 1
    }

    /// A click on a chip's box, or a double-click anywhere on a chip, ticks its ToDo. The text
    /// view puts the caret just after a clicked box, and a double-click picks a word in the chip
    /// (sometimes with the space after it).
    func selectionChanged() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastBoxClick < 0.6 else { return }
        let hit: MemoChips.Chip?
        switch selection.indices(in: text) {
        case .insertionPoint(let caret):
            hit = lastClickCount == 1 ? MemoChips.chip(withBoxAt: caret, in: text) : nil
        case .ranges(let ranges):
            let picked = ranges.ranges.filter { !$0.isEmpty }
            hit = lastClickCount == 2 && picked.count == 1 ? MemoChips.chips(in: text).first { chip in
                let range = picked[0]
                guard range.overlaps(chip.range) else { return false }
                let before = range.lowerBound < chip.range.lowerBound ? String(text[range.lowerBound..<chip.range.lowerBound].characters) : ""
                let after = range.upperBound > chip.range.upperBound ? String(text[chip.range.upperBound..<range.upperBound].characters) : ""
                return (before + after).allSatisfy(\.isWhitespace)
            } : nil
        }
        guard let chip = hit else { return }
        // The double-click's first click may have ticked this chip already.
        if let last = tickedByClick, last.id == chip.todo.id, now - last.at < 0.8 {
            if lastClickCount == 1 { return }
        } else {
            toggle(chip.todo.id)
            tickedByClick = (chip.todo.id, now)
        }
        // The caret leaves the chip, so a second click on it is a change again and no word stays
        // picked to bring up the format bar.
        if let redrawn = MemoChips.chips(in: text).first(where: { $0.todo.id == chip.todo.id }) {
            selection = AttributedTextSelection(insertionPoint: redrawn.range.upperBound, typingAttributes: AttributeContainer())
        }
    }

    /// Opens a pop about the memo, beside the line the selection is on.
    func showPop(_ pop: PanelPop) {
        todos.popAnchor = selectionLineInWindow?()
        todos.pop = pop
    }

    /// The picked letters as plain text, for the right-click menu's copy, formulas in `$…$` and
    /// attachments as `📎 name`. The first picked range only, the same one cut deletes.
    var selectedPlainText: String {
        selectedRanges.first { !$0.isEmpty }.map { MemoAttachments.plainText(AttributedString(text[$0])) } ?? ""
    }

    /// The right-click menu's cut, copy and paste, done on the memo's letters directly: the menu
    /// cannot count on the text view being first responder.
    func copySelection() {
        let picked = selectedPlainText
        guard !picked.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(picked, forType: .string)
        if let range = selectedRanges.first(where: { !$0.isEmpty }) { rememberCopied(AttributedString(text[range])) }
    }

    /// Keeps letters with attachments in them for `pasteRemembered`; others are forgotten.
    func rememberCopied(_ piece: AttributedString) {
        copiedPiece = MemoAttachments.attachments(in: piece).isEmpty ? nil : (piece, NSPasteboard.general.changeCount)
    }

    /// The letters last cut or copied here, cards and all, in place of the selection; false when
    /// the clipboard has changed since.
    func pasteRemembered() -> Bool {
        guard !isUnreadable, let piece = copiedPiece, piece.changeCount == NSPasteboard.general.changeCount,
              // Not once a card's file has been cleared away meanwhile: then the words alone.
              MemoAttachments.attachments(in: piece.text).allSatisfy({ AttachmentShelf.shared.store.exists($0.ref) }),
              let range = selectedRanges.first(where: { !$0.isEmpty }) ?? selectedRanges.first else { return false }
        let start = text.characters.distance(from: text.startIndex, to: range.lowerBound)
        text.transform(updating: &selection) { $0.replaceSubrange(range, with: piece.text) }
        let caret = text.characters.index(text.startIndex, offsetBy: min(start + piece.text.characters.count, text.characters.count))
        selection = AttributedTextSelection(insertionPoint: caret, typingAttributes: AttributeContainer())
        focusRequest += 1
        return true
    }

    func cutSelection() {
        copySelection()
        replaceSelection(with: "")
    }

    func paste() {
        if pasteRemembered() { return }
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        replaceSelection(with: pasted)
    }

    private func replaceSelection(with letters: String) {
        guard let range = selectedRanges.first(where: { !$0.isEmpty }) ?? selectedRanges.first else { return }
        let start = text.characters.distance(from: text.startIndex, to: range.lowerBound)
        text.transform(updating: &selection) { $0.replaceSubrange(range, with: AttributedString(letters)) }
        let caret = text.characters.index(text.startIndex, offsetBy: min(start + letters.count, text.characters.count))
        selection = AttributedTextSelection(insertionPoint: caret, typingAttributes: AttributeContainer())
        focusRequest += 1
    }

    /// The right-click menu's 모두 선택.
    func selectAll() {
        selection = AttributedTextSelection(range: text.startIndex..<text.endIndex)
        focusRequest += 1
    }

    /// The chip the caret or selection starts in, for 서식 › 할 일 체크 and the right-click menu.
    var chipAtCaret: MemoChips.Chip? {
        guard let start = selectedRanges.first?.lowerBound else { return nil }
        return MemoChips.chips(in: text).first { $0.range.contains(start) || $0.range.upperBound == start }
    }

    func toggleChipAtCaret() {
        if let chip = chipAtCaret { toggle(chip.todo.id) }
    }

    private func toggle(_ id: UUID) {
        guard let item = todos.item(id) else { return }
        todos.setDone(id, !item.isDone)
        refreshChips()
    }

    /// The lines the caret or selection touches that can become ToDos: not blank, not chips.
    var pickableLines: [Int] {
        let lines = MemoTodoLines.lines(in: text)
        let chips = MemoChips.chips(in: text)
        let picked = selectedRanges
        return lines.indices.filter { number in
            let line = lines[number]
            let touched = picked.contains { range in
                range.isEmpty ? line.lowerBound <= range.lowerBound && range.lowerBound <= line.upperBound
                    : range.lowerBound < line.upperBound && line.lowerBound < range.upperBound
            }
            guard touched, !MemoTodoLines.title(of: String(text[line].characters)).isEmpty else { return false }
            return !chips.contains { $0.range.overlaps(line) }
        }
    }

    /// ⌘⇧T: asks where the picked lines go.
    func askToMakeTodos() {
        let lines = pickableLines
        guard !lines.isEmpty, !isUnreadable else {
            NSSound.beep()
            return
        }
        showPop(.makeTodos(lines: lines))
    }

    /// 할 일 가져오기…: the `[[` search at the caret, without typing the brackets.
    func askToLinkTodo() {
        guard !isUnreadable, let start = selectedRanges.first?.lowerBound else { return }
        showPop(.search(at: text.characters.distance(from: text.startIndex, to: start), typed: false))
    }

    /// Files each line as a new ToDo under `target` and puts a chip where the line was.
    func makeTodos(fromLines lines: [Int], in target: Period) {
        guard let period else { return }
        // Saved first, so the ToDos can name the note they came from.
        flush()
        let noteID = book.noteID(for: period)
        let all = MemoTodoLines.lines(in: text)
        var made: [(line: Int, item: TodoItem)] = []
        for number in lines where all.indices.contains(number) {
            let title = MemoTodoLines.title(of: String(text[all[number]].characters))
            if let item = todos.add(title, to: target, sourceNoteID: noteID) { made.append((number, item)) }
        }
        rewrite { text in
            for (number, item) in made {
                MemoTodoLines.replaceLine(number, in: &text, with: MemoChips.chip(id: item.id, title: item.title, isDone: item.isDone))
            }
        }
        focusRequest += 1
    }

    /// Puts a chip for the ToDo at `offset` with a plain space after it, and the caret after that.
    func insertChip(_ id: UUID, at offset: Int) {
        guard let item = todos.item(id) else { return }
        var piece = MemoChips.chip(id: item.id, title: item.title, isDone: item.isDone)
        piece.append(AttributedString(" "))
        let offset = min(offset, text.characters.count)
        text.transform(updating: &selection) { text in
            text.insert(piece, at: text.characters.index(text.startIndex, offsetBy: offset))
        }
        let after = text.characters.index(text.startIndex, offsetBy: offset + piece.characters.count)
        selection = AttributedTextSelection(insertionPoint: after, typingAttributes: AttributeContainer())
        focusRequest += 1
    }

    /// Changes the open memo's letters, keeping the caret where it was.
    func rewrite(_ change: (inout AttributedString) -> Void) {
        text.transform(updating: &selection) { change(&$0) }
    }
}

/// Where ⌘⇧T and the right-click menu offer to file new ToDos, from the memo's own period: the
/// day, its week and its month (a week's memo starts at its week).
enum TodoTargets {
    struct Target: Identifiable {
        var name: String
        var detail: String
        var period: Period
        var id: String { period.key }
    }

    static func choices(for memo: Period) -> [Target] {
        let calendar = memo.calendar
        var result: [Target] = []
        if memo.scope == .day {
            let c = calendar.dateComponents([.month, .day], from: memo.start)
            result.append(Target(name: "이날", detail: "\(c.month!)월 \(c.day!)일", period: memo))
        }
        if memo.scope != .month {
            let week = Period(containing: memo.start, scope: .week, calendar: calendar)
            result.append(Target(name: "이번 주", detail: week.title, period: week))
        }
        let month = Period(containing: memo.start, scope: .month, calendar: calendar)
        result.append(Target(name: "이번 달", detail: "\(calendar.component(.month, from: month.start))월", period: month))
        return result
    }
}

/// The memo box's right-click menu and ⌘⇧T. SwiftUI's text editor has no way to add items to
/// its own menu, so a right-click inside the box opens this ink menu instead: the ToDo items, then
/// cut, copy, paste and the formats. It works on the selection as it is, so lines are picked first. The editor's own
/// view is not an `NSTextView` one can look for, so the box is found by where it is on screen:
/// a background view the size of the box, watching the window's events before anything else.
struct MemoMenuHost: NSViewRepresentable {
    let draft: MemoDraft

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.draft = draft
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        view.draft = draft
    }

    static func dismantleNSView(_ view: HostView, coordinator: ()) {
        view.stop()
    }

    final class HostView: NSView {
        var draft: MemoDraft?
        private var monitor: Any?
        private let styler = MemoLineStyler()

        // Top-left origin, like the box it measures.
        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            draft?.selectionLineRect = { [weak self] in self?.selectionLineRect() }
            draft?.selectionLineInWindow = { [weak self] in self?.selectionLineInWindow() }
            draft?.inkTextView = { [weak self] in self?.inkTextView() }
            draft?.showMenu = { [weak self] in self?.showMenuUnderSelection() }
            draft?.redrawLines = { [weak self] in self?.redrawLines() }
            draft?.editLines = { [weak self] make in self?.editLines(make) ?? false }
            draft?.editTable = { [weak self] action in self?.editTable(action) ?? false }
            draft?.tableColumns = { [weak self] in self?.styler.textView.map(MemoTableKeys.columnCount(in:)) ?? 0 }
            draft?.openFormula = { [weak self] in self?.styler.openFormula }
            draft?.startFormula = { [weak self] location in self?.styler.startEmptyFormula(at: location) }
            draft?.notify = { [weak self] words in self?.styler.showNotice(words) }
            draft?.pickedCard = { [weak self] in self?.styler.pickedAttachment }
            // Once the text view is in the window beside this view.
            Task { @MainActor [weak self] in self?.redrawLines() }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown, .keyDown]) { [weak self] event in
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let window = self.window, event.window === window, let draft = self.draft else { return false }
                    switch event.type {
                    case .keyDown:
                        // Esc closes the 문단 bar.
                        if draft.showsParagraphBar, event.keyCode == Self.keyEscape {
                            draft.showsParagraphBar = false
                            return true
                        }
                        // Space on a picked card shows it; ⌘V with a picture pastes it as an attachment.
                        if draft.hasFocus, draft.book.todos.pop == nil, let textView = self.styler.textView, window.firstResponder === textView,
                           self.handleAttachmentKey(event, draft: draft) {
                            return true
                        }
                        // Esc, or → at its end, leaves the formula being written; ⌘C and ⌘X put formulas
                        // on the clipboard as `$…$`.
                        if draft.hasFocus, draft.book.todos.pop == nil, let textView = self.styler.textView, window.firstResponder === textView,
                           self.handleFormulaKey(event, in: textView) {
                            return true
                        }
                        // Tab, Return and Delete in and under tables, then in lists, and a typed `* `.
                        if draft.hasFocus, draft.book.todos.pop == nil, let textView = self.styler.textView, window.firstResponder === textView,
                           MemoTableKeys.handle(event, in: textView) {
                            return true
                        }
                        if draft.hasFocus, draft.book.todos.pop == nil, let textView = self.styler.textView, window.firstResponder === textView,
                           MemoListKeys.handle(event, in: textView, draft: draft) {
                            return true
                        }
                        // ⌘⇧T and ⌃⌘T while the memo is being written; ahead of the text view and the menus.
                        // By the key's place, not its letter: with a Korean input source T types ㅅ.
                        guard draft.hasFocus, draft.book.todos.pop == nil, event.keyCode == Self.keyT else { return false }
                        switch event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function]) {
                        case [.command, .shift]: draft.askToMakeTodos()
                        case [.command, .control]: draft.insertTime()
                        default: return false
                        }
                        return true
                    case .leftMouseDown:
                        // A click picks a card; a double-click shows it.
                        if self.isInBox(event), let textView = self.styler.textView,
                           let hit = self.styler.attachment(at: textView.convert(event.locationInWindow, from: nil)) {
                            self.pick(hit.location, in: textView)
                            if event.clickCount >= 2 { draft.preview(hit.ref) }
                            return true
                        }
                        if self.isInBox(event) {
                            draft.lastBoxClick = ProcessInfo.processInfo.systemUptime
                            draft.lastClickCount = event.clickCount
                            if let textView = self.styler.textView {
                                self.styler.lastClick = (textView.convert(event.locationInWindow, from: nil), draft.lastBoxClick)
                            }
                        }
                        return false
                    default:
                        // On a card: the card's own menu.
                        if self.isInBox(event), !draft.isUnreadable, let textView = self.styler.textView,
                           let hit = self.styler.attachment(at: textView.convert(event.locationInWindow, from: nil)) {
                            self.pick(hit.location, in: textView)
                            guard let picked = draft.pickedAttachment else { return true }
                            InkMenuPresenter.popUp(draft.cardMenu(picked.ref, range: picked.range, window: window),
                                                   at: window.convertPoint(toScreen: event.locationInWindow), in: window)
                            return true
                        }
                        guard self.isInBox(event), let menu = self.menu() else { return false }
                        InkMenuPresenter.popUp(menu, at: window.convertPoint(toScreen: event.locationInWindow), in: window)
                        return true
                    }
                }
                return handled ? nil : event
            }
        }

        /// A click on a card picks it: the caret just after it, the card in its outline.
        @MainActor
        private func pick(_ location: Int, in textView: NSTextView) {
            if textView.window?.firstResponder !== textView { textView.window?.makeFirstResponder(textView) }
            styler.clickedAttachment = location
            textView.setSelectedRange(NSRange(location: location + 1, length: 0))
            styler.update()
            draft?.focusRequest += 1
        }

        /// Space on a picked card, and ⌘V with a picture (or a card copied with its menu) on the
        /// clipboard; false for any other key.
        @MainActor
        private func handleAttachmentKey(_ event: NSEvent, draft: MemoDraft) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            switch (event.keyCode, modifiers) {
            case (Self.keySpace, []):
                guard let picked = draft.pickedAttachment else { return false }
                draft.preview(picked.ref)
                return true
            // A picked card copies as its file, and as `📎 name` for words.
            case (Self.keyC, [.command]) where ["c", "ㅊ"].contains(event.charactersIgnoringModifiers?.lowercased() ?? ""):
                guard let picked = draft.pickedAttachment, !draft.hasSelectedText else { return false }
                AttachmentShelf.shared.copy(picked.ref)
                NSPasteboard.general.setString(MemoAttachments.label(picked.ref), forType: .string)
                draft.rememberCopied(AttributedString(draft.text[picked.range]))
                return true
            case (Self.keyV, [.command]) where ["v", "ㅍ"].contains(event.charactersIgnoringModifiers?.lowercased() ?? ""):
                guard !draft.isUnreadable else { return false }
                // Letters cut or copied here with cards in them come back whole.
                if draft.pasteRemembered() { return true }
                let board = NSPasteboard.general
                let files = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
                // A card copied with its menu goes in again as the same attachment, while its file is here.
                let refs = files.compactMap(AttachmentShelf.shared.ref(at:)).filter(AttachmentShelf.shared.store.exists)
                if !files.isEmpty {
                    guard refs.count == files.count else { return false }
                    draft.insertAttachments(refs)
                    return true
                }
                // A picture alone (a screenshot, a copied image); words on the clipboard paste as words.
                guard board.string(forType: .string) == nil, let picture = Self.picture(on: board) else { return false }
                draft.attach(picture: picture)
                return true
            default:
                return false
            }
        }

        /// A picture on the clipboard as PNG.
        private static func picture(on board: NSPasteboard) -> Data? {
            if let png = board.data(forType: .png) { return png }
            guard let tiff = board.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }

        /// `kVK_Space`, `kVK_ANSI_V`.
        private static let keySpace: UInt16 = 49
        private static let keyV: UInt16 = 9

        /// `kVK_ANSI_T`, `kVK_ANSI_C`, `kVK_ANSI_X`, `kVK_RightArrow`.
        private static let keyT: UInt16 = 17
        private static let keyC: UInt16 = 8
        private static let keyX: UInt16 = 7
        private static let keyRight: UInt16 = 124

        /// Formula keys in the focused memo; false for any other key, which goes on as usual.
        @MainActor
        private func handleFormulaKey(_ event: NSEvent, in textView: NSTextView) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            let selection = textView.selectedRange()
            switch (event.keyCode, modifiers) {
            case (Self.keyEscape, []):
                return leaveFormula(in: textView)
            case (Self.keyRight, []):
                guard selection.length == 0, let open = styler.openFormula, selection.location == NSMaxRange(open) else { return false }
                return leaveFormula(in: textView)
            // By place, as with T, and by letter, so another layout's key there is not taken for them.
            case (Self.keyC, [.command]) where ["c", "ㅊ"].contains(event.charactersIgnoringModifiers?.lowercased() ?? ""),
                 (Self.keyX, [.command]) where ["x", "ㅌ"].contains(event.charactersIgnoringModifiers?.lowercased() ?? ""):
                // The text view copies or cuts as usual; then its plain text is written with the
                // formulas in `$…$`. LaTeX picked inside the formula being written stays as it is.
                guard let draft, selection.length > 0, let range = Range(selection, in: draft.text) else { return false }
                if let open = styler.openFormula, NSIntersectionRange(open, selection) == selection { return false }
                let picked = AttributedString(draft.text[range])
                let plain = MemoAttachments.plainText(picked)
                guard plain != String(picked.characters) else { return false }
                if event.keyCode == Self.keyX { textView.cut(nil) } else { textView.copy(nil) }
                NSPasteboard.general.setString(plain, forType: .string)
                draft.rememberCopied(picked)
                return true
            default:
                return false
            }
        }

        /// The caret after the formula being written, which is drawn again; false when none is.
        @MainActor
        private func leaveFormula(in textView: NSTextView) -> Bool {
            guard styler.leaveFormula(moving: { textView.setSelectedRange(NSRange(location: $0, length: 0)) }) else { return false }
            draft?.dropFormulaTyping()
            return true
        }
        /// `kVK_Escape`.
        private static let keyEscape: UInt16 = 53

        /// A list change made in the memo's text view, whether or not it has keyboard focus.
        @MainActor
        private func editLines(_ make: (String, NSRange) -> MemoLists.Change?) -> Bool {
            if !styler.isAttached { redrawLines() }
            guard let textView = styler.textView, textView.isEditable,
                  let change = make(textView.string, textView.selectedRange()), !change.edits.isEmpty else { return false }
            MemoListKeys.apply(change, to: textView)
            return true
        }

        /// A table change made in the memo's text view, whether or not it has keyboard focus.
        @MainActor
        private func editTable(_ action: MemoTableAction) -> Bool {
            if !styler.isAttached { redrawLines() }
            guard let textView = styler.textView else { return false }
            return MemoTableKeys.perform(action, in: textView)
        }

        /// The selection's first line in this view, asked of the focused text view the way an input
        /// method asks it. Nil when the memo does not have focus.
        @MainActor
        private func selectionLineRect() -> CGRect? {
            guard let window, let draft, draft.hasFocus, let client = window.firstResponder as? NSTextInputClient,
                  let start = draft.selectedRanges.first?.lowerBound else { return nil }
            let offset = String(draft.text[draft.text.startIndex..<start].characters).utf16.count
            let screen = client.firstRect(forCharacterRange: NSRange(location: offset, length: 0), actualRange: nil)
            guard screen != .zero else { return nil }
            let rect = convert(window.convertFromScreen(screen), from: nil)
            // Another text field's answer would land outside the box.
            return bounds.insetBy(dx: -2, dy: -MemoStyle.lineHeight).contains(CGPoint(x: rect.minX, y: rect.midY)) ? rect : nil
        }

        @MainActor
        private func selectionLineInWindow() -> CGRect? {
            guard let line = selectionLineRect(), let content = window?.contentView else { return nil }
            let rect = content.convert(convert(line, to: nil), from: nil)
            return content.isFlipped ? rect : CGRect(x: rect.minX, y: content.bounds.height - rect.maxY, width: rect.width, height: rect.height)
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Finds the memo's text view (the one on the part of the panel the memo takes) and has the
        /// styler draw its rules and timeline lines as they are now.
        @MainActor
        private func redrawLines() {
            guard let window, let content = window.contentView, let draft else { return }
            if !styler.isAttached {
                guard let textView = memoTextView(in: content, box: draft.visibleBox) else {
                    // The memo's place may not be measured yet (the panel just came back): once more after this pass.
                    Task { @MainActor [weak self] in
                        guard let self, !self.styler.isAttached, let draft = self.draft,
                              let textView = self.memoTextView(in: content, box: draft.visibleBox) else { return }
                        self.styler.attach(to: textView)
                    }
                    return
                }
                styler.attach(to: textView)
            }
            if let textView = styler.textView { installDrop(on: textView) }
            styler.update()
            // Letters typed after a drawn formula are not part of it.
            if styler.caretIsAfterDrawnFormula { draft.dropFormulaTyping() }
        }

        /// Files dragged onto the memo go in where they are let go.
        @MainActor
        private func installDrop(on textView: NSTextView) {
            MemoFileDrop.install(on: textView) { [weak self, weak textView] urls, point in
                guard let draft = self?.draft, let textView, !draft.isUnreadable else { return false }
                let index = textView.characterIndexForInsertion(at: point)
                let offset = Range(NSRange(location: min(index, (textView.string as NSString).length), length: 0), in: draft.text)
                    .map { draft.text.characters.distance(from: draft.text.startIndex, to: $0.lowerBound) }
                textView.window?.makeFirstResponder(textView)
                draft.attach(urls, at: offset)
                return true
            }
        }

        @MainActor
        private func memoTextView(in view: NSView, box: CGRect) -> NSTextView? {
            if let textView = view as? NSTextView, !textView.isFieldEditor, let content = window?.contentView {
                let frame = content.convert((textView.enclosingScrollView ?? textView).bounds, from: textView.enclosingScrollView ?? textView)
                let top = content.isFlipped ? frame : CGRect(x: frame.minX, y: content.bounds.height - frame.maxY, width: frame.width, height: frame.height)
                return top.intersects(box) ? textView : nil
            }
            for subview in view.subviews {
                if let found = memoTextView(in: subview, box: box) { return found }
            }
            return nil
        }

        /// The menu under the selection's line, or at the box's top left.
        @MainActor
        private func showMenuUnderSelection() {
            guard let window, let content = window.contentView, let draft, let menu = menu() else { return }
            let line = selectionLineInWindow() ?? CGRect(x: draft.visibleBox.minX, y: draft.visibleBox.minY, width: 0, height: 0)
            let corner = CGPoint(x: line.minX, y: content.isFlipped ? line.maxY : content.bounds.height - line.maxY)
            InkMenuPresenter.popUp(menu, at: window.convertPoint(toScreen: content.convert(corner, to: nil)), in: window)
        }

        /// The memo's caret in ink and its selection in the grey of an active row, instead of the
        /// system's accent colour. One-line fields keep the system's.
        @MainActor
        private func inkTextView() {
            guard let draft, draft.hasFocus, let textView = window?.firstResponder as? NSTextView, !textView.isFieldEditor else { return }
            textView.insertionPointColor = NSColor(Color.ink)
            textView.selectedTextAttributes = [.backgroundColor: NSColor(Color.rowActive)]
        }

        /// Drawn formulas take the new theme's ink.
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            // After the change has settled, not while the views are being redrawn for it.
            Task { @MainActor [weak self] in
                guard let self, self.styler.isAttached else { return }
                self.styler.update(force: true)
            }
        }

        // A plain view: clicks go to the text view on top.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// The pointer is on the part of the box the panel shows, with no pop over the panel and no
        /// text field (a pop's search field) under it. Measured with SwiftUI's own layout of the
        /// box: this view's AppKit frame does not follow the panel's scrolling.
        @MainActor
        private func isInBox(_ event: NSEvent) -> Bool {
            guard let draft, draft.book.todos.pop == nil, !isHiddenOrHasHiddenAncestor,
                  let content = window?.contentView else { return false }
            let point = content.convert(event.locationInWindow, from: nil)
            let top = content.isFlipped ? point : CGPoint(x: point.x, y: content.bounds.height - point.y)
            guard draft.visibleBox.contains(top) else { return false }
            if let field = content.hitTest(point) as? NSTextView, field.isFieldEditor { return false }
            return true
        }

        /// In a table: its rows, columns, and the table itself, as the mockup's menu, above the rest.
        @MainActor
        private func tableEntries(_ draft: MemoDraft) -> [InkMenuEntry] {
            [
                .item("위에 행 넣기") { draft.tableAction(.rowAbove) },
                .item("아래에 행 넣기") { draft.tableAction(.rowBelow) },
                .item("왼쪽에 열 넣기") { draft.tableAction(.columnLeft) },
                .item("오른쪽에 열 넣기") { draft.tableAction(.columnRight) },
                .divider,
                .item("행 지우기") { draft.tableAction(.deleteRow) },
                // Two columns are the least a table keeps.
                .item("열 지우기", isEnabled: (draft.tableColumns?() ?? 0) > MemoTables.leastColumns) { draft.tableAction(.deleteColumn) },
                .divider,
                .item("표를 글로 바꾸기") { draft.tableAction(.toText) },
                .item("표 지우기", isDanger: true) { draft.tableAction(.deleteTable) },
                .divider,
            ]
        }

        /// 할 일로 만들기 › and the ToDo items, then editing and the formats the memo uses. The system's
        /// spelling, substitutions, speech and services are left out; the red underlines stay.
        @MainActor
        private func menu() -> [InkMenuEntry]? {
            guard let draft, let period = draft.period, !draft.isUnreadable else { return nil }
            let hasSelection = draft.hasSelectedText
            let lines = draft.pickableLines
            let targets: [InkMenuEntry] = [.section("어디에 둘까요")]
                + TodoTargets.choices(for: period).map { target in
                    .item(target.name, detail: TodoNames.menuDetail(target.period)) { draft.makeTodos(fromLines: lines, in: target.period) }
                }
                + [.divider, .item("다른 날짜…") { draft.showPop(.pickDay(.makeTodos(lines: lines))) }]
            var entries: [InkMenuEntry] = draft.isInTable ? tableEntries(draft) : []
            entries += [
                .submenu("할 일로 만들기", isEnabled: !lines.isEmpty, targets),
                .item("할 일 가져오기…") { draft.askToLinkTodo() },
                .item("시각 넣기", detail: "⌃⌘T") { draft.insertTime() },
            ]
            if let chip = draft.chipAtCaret, let item = draft.book.todos.item(chip.todo.id) {
                entries.append(.item(item.isDone ? "체크 풀기" : "체크하기") { draft.toggleChipAtCaret() })
            }
            entries += [
                .divider,
                .item("잘라내기", detail: "⌘X", isEnabled: hasSelection) { draft.cutSelection() },
                .item("복사", detail: "⌘C", isEnabled: hasSelection) { draft.copySelection() },
                .item("붙여넣기", detail: "⌘V", isEnabled: NSPasteboard.general.string(forType: .string) != nil) { draft.paste() },
                .item("모두 선택", detail: "⌘A", isEnabled: !draft.text.characters.isEmpty) { draft.selectAll() },
                .divider,
                .item("굵게", detail: "⌘B", isEnabled: hasSelection) { draft.toggle(MemoAttributes.Bold.self) },
                .item("기울임", detail: "⌘I", isEnabled: hasSelection) { draft.toggle(MemoAttributes.Italic.self) },
                .item("밑줄", detail: "⌘U", isEnabled: hasSelection) { draft.toggle(MemoAttributes.Underline.self) },
                .item("취소선", detail: "⌘⇧X", isEnabled: hasSelection) { draft.toggle(MemoAttributes.Strike.self) },
                .item("서식 지우기", isEnabled: hasSelection) { draft.clearFormatting() },
                .divider,
            ]
            // The caret's line, picked or not.
            let paragraph = draft.paragraph
            let kind = draft.listKind
            entries.append(.submenu("문단", [
                .item("제목", detail: "⌥⌘1", checked: paragraph == .title) { draft.setParagraph(.title) },
                .item("머리말", detail: "⌥⌘2", checked: paragraph == .heading) { draft.setParagraph(.heading) },
                .item("부머리말", detail: "⌥⌘3", checked: paragraph == .sub) { draft.setParagraph(.sub) },
                .item("본문", detail: "⌥⌘0", checked: paragraph == nil) { draft.setParagraph(nil) },
            ]))
            entries.append(.submenu("목록", [
                .item("글머리 기호", detail: "⌘⇧7", checked: kind == .bullet) { draft.setList(.bullet) },
                .item("대시", detail: "⌘⇧8", checked: kind == .dash) { draft.setList(.dash) },
                .item("번호", detail: "⌘⇧9", checked: kind == .number) { draft.setList(.number) },
                .item("인용문", detail: "⌘'", checked: draft.isQuoted) { draft.setList(.quote) },
                .divider,
                .item("들여쓰기", detail: "⌘]") { draft.indentLines(by: 1) },
                .item("내어쓰기", detail: "⌘[") { draft.indentLines(by: -1) },
            ]))
            if !draft.isInTable { entries.append(.item("표 넣기") { draft.tableAction(.insert) }) }
            entries.append(.item("파일 첨부…", detail: "⌘⇧A") { draft.askToAttach() })
            return entries
        }
    }
}
