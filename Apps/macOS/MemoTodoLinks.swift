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

    /// The picked letters as plain text, for the right-click menu's copy.
    /// The first picked range only, the same one cut deletes.
    var selectedPlainText: String {
        selectedRanges.first { !$0.isEmpty }.map { String(text[$0].characters) } ?? ""
    }

    /// The right-click menu's cut, copy and paste, done on the memo's letters directly: the menu
    /// cannot count on the text view being first responder.
    func copySelection() {
        let picked = selectedPlainText
        guard !picked.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(picked, forType: .string)
    }

    func cutSelection() {
        copySelection()
        replaceSelection(with: "")
    }

    func paste() {
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
            result.append(Target(name: "이 날", detail: "\(c.month!)월 \(c.day!)일", period: memo))
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
/// its own menu, so a right-click inside the box opens this one: cut, copy and paste, then the
/// ToDo items. It works on the selection as it is, so lines are picked first. The editor's own
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

        // Top-left origin, like the box it measures.
        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            draft?.selectionLineRect = { [weak self] in self?.selectionLineRect() }
            draft?.selectionLineInWindow = { [weak self] in self?.selectionLineInWindow() }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown, .keyDown]) { [weak self] event in
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let window = self.window, event.window === window, let draft = self.draft else { return false }
                    switch event.type {
                    case .keyDown:
                        // ⌘⇧T while the memo is being written; ahead of the text view and the menus.
                        // By the key's place, not its letter: with a Korean input source T types ㅅ.
                        guard draft.hasFocus, draft.book.todos.pop == nil, event.keyCode == Self.keyT,
                              event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function]) == [.command, .shift]
                        else { return false }
                        draft.askToMakeTodos()
                        return true
                    case .leftMouseDown:
                        if self.isInBox(event) {
                            draft.lastBoxClick = ProcessInfo.processInfo.systemUptime
                            draft.lastClickCount = event.clickCount
                        }
                        return false
                    default:
                        guard self.isInBox(event), let menu = self.menu() else { return false }
                        NSMenu.popUpContextMenu(menu, with: event, for: self)
                        return true
                    }
                }
                return handled ? nil : event
            }
        }

        /// `kVK_ANSI_T`.
        private static let keyT: UInt16 = 17

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

        @MainActor
        private func menu() -> NSMenu? {
            guard let draft, let period = draft.period, !draft.isUnreadable else { return nil }
            let menu = NSMenu()
            menu.autoenablesItems = false
            let hasSelection = draft.hasSelectedText
            menu.addItem(ActionItem("잘라내기", key: "x", enabled: hasSelection) { draft.cutSelection() })
            menu.addItem(ActionItem("복사하기", key: "c", enabled: hasSelection) { draft.copySelection() })
            menu.addItem(ActionItem("붙여넣기", key: "v", enabled: NSPasteboard.general.string(forType: .string) != nil) { draft.paste() })
            menu.addItem(.separator())

            let lines = draft.pickableLines
            let make = NSMenuItem(title: "할 일로 만들기", action: nil, keyEquivalent: "")
            make.isEnabled = !lines.isEmpty
            let targets = NSMenu()
            targets.autoenablesItems = false
            for target in TodoTargets.choices(for: period) {
                targets.addItem(ActionItem("\(target.name)  ·  \(target.detail)") { draft.makeTodos(fromLines: lines, in: target.period) })
            }
            targets.addItem(.separator())
            targets.addItem(ActionItem("다른 날짜…") { draft.showPop(.pickDay(.makeTodos(lines: lines))) })
            make.submenu = targets
            menu.addItem(make)
            menu.addItem(ActionItem("할 일 가져오기…") { draft.askToLinkTodo() })
            if let chip = draft.chipAtCaret, let item = draft.book.todos.item(chip.todo.id) {
                menu.addItem(.separator())
                menu.addItem(ActionItem(item.isDone ? "체크 풀기" : "체크하기") { draft.toggleChipAtCaret() })
            }
            return menu
        }
    }

    /// A menu item that runs a closure.
    @MainActor
    final class ActionItem: NSMenuItem {
        private let run: @MainActor () -> Void

        init(_ title: String, key: String = "", enabled: Bool = true, run: @escaping @MainActor () -> Void) {
            self.run = run
            super.init(title: title, action: #selector(fire), keyEquivalent: key)
            target = self
            isEnabled = enabled
        }

        required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

        @objc private func fire() {
            run()
        }
    }
}
