#if DEBUG
import AppKit
import SwiftUI
import SimplifyKit

/// Debug-only: types into a memo the way a person would (keys posted to the window, so they pass
/// the memo's key monitor and the menus) and checks lists, quotes, paragraph styles, underline and
/// strikethrough, then pictures the memo and quits. The memo is in memory; nothing is saved to the
/// real store or mirrored. Run with `open --env SIMPLIFY_MEMO_CHECK=1 Simplify.app`; the result
/// lands in `~/Library/Containers/dev.yoom.simplify/Data/tmp/memo-check.txt`, pictures beside it.
@MainActor
enum MemoFormatCheck {
    private static var lines: [String] = []
    private static var started = false

    static func runIfRequested(model: AppModel) {
        // The check's own window shows MainView too.
        guard let mode = ProcessInfo.processInfo.environment["SIMPLIFY_MEMO_CHECK"], !started else { return }
        started = true
        if mode == "show" {
            show(model: model)
            return
        }
        Task {
            await run(model: model, only: mode)
            let file = FileManager.default.temporaryDirectory.appending(path: "memo-check.txt")
            try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    /// `SIMPLIFY_MEMO_CHECK=show`: the sample memo in a window of its own to try by hand, kept in
    /// memory only. The app stays open. The 서식 menu's shortcuts need a SwiftUI scene's focus,
    /// so here they are reached through the Aa button, the format bar and the right-click menu.
    private static func show(model: AppModel) {
        Task {
            let memos = MemoBook(container: try! SimplifyStore.makeContainer(inMemory: true), isSaved: true)
            let calendars = CalendarController(container: try! SimplifyStore.makeCacheContainer(inMemory: true), calendar: model.calendar)
            let window = NSWindow(contentRect: NSRect(x: 120, y: 80, width: 1300, height: 860), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "메모 서식 미리보기 · 저장 안 됨"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MainView(model: model, calendars: calendars, memos: memos))
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(2))
            memos.draft.text = sample() + AttributedString("\n") + formulaSample()
            if let editor = window.contentView.flatMap(textView) { window.makeFirstResponder(editor) }
            kept.append(window)
        }
    }

    private static var kept: [NSWindow] = []

    private static func log(_ line: String) { lines.append(line) }

    private static func check(_ ok: Bool, _ what: String, _ got: @autoclosure () -> String = "") {
        log((ok ? "PASS  " : "FAIL  ") + what + (ok ? "" : "  got: \(got())"))
    }

    private static func run(model: AppModel, only: String) async {
        let tablesOnly = only == "tables"
        let memos = MemoBook(container: try! SimplifyStore.makeContainer(inMemory: true), isSaved: true)
        let calendars = CalendarController(container: try! SimplifyStore.makeCacheContainer(inMemory: true), calendar: model.calendar)
        // The panel's remembered settings are put back at the end.
        let kept = (model.isPanelHidden, model.isPanelWide, model.panelWidth, model.miniMonthWidth, model.calendarView)
        defer {
            model.calendarView = kept.4
            (model.isPanelHidden, model.isPanelWide, model.panelWidth, model.miniMonthWidth) = (kept.0, kept.1, kept.2, kept.3)
        }
        model.calendarView = .month
        model.panelMode = .wide
        model.select(model.today)
        model.panelScope = .day
        let window = NSWindow(contentRect: NSRect(x: 80, y: 60, width: 1300, height: 860), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainView(model: model, calendars: calendars, memos: memos))
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(2))
        let draft = memos.draft
        guard let editor = window.contentView.flatMap(textView) else {
            log("FAIL  no memo text view")
            return
        }
        window.makeFirstResponder(editor)
        try? await Task.sleep(for: .seconds(0.5))
        check(draft.hasFocus, "the memo has focus")
        var letters: String { String(draft.text.characters) }

        func reset(_ text: AttributedString = AttributedString(), caret: Int? = nil) async {
            draft.text = text
            try? await Task.sleep(for: .seconds(0.4))
            editor.setSelectedRange(NSRange(location: caret ?? (editor.string as NSString).length, length: 0))
            editor.undoManager?.removeAllActions()
            try? await Task.sleep(for: .seconds(0.3))
        }
        func type(_ words: String) async {
            editor.insertText(words, replacementRange: editor.selectedRange())
            try? await Task.sleep(for: .seconds(0.3))
        }
        func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = []) async {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, characters: characters,
                                             charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
                NSApp.postEvent(event, atStart: false)
            }
            try? await Task.sleep(for: .seconds(0.4))
        }
        let returnKey: (UInt16, String) = (36, "\r")
        let tab: (UInt16, String) = (48, "\t")
        let delete: (UInt16, String) = (51, "\u{7f}")
        let space: (UInt16, String) = (49, " ")

        if only == "attachments" {
            await checkAttachments(draft: draft, editor: editor, window: window, reset: reset, key: key)
            window.close()
            return
        }
        if tablesOnly {
            await checkTables(draft: draft, editor: editor, window: window, model: model, reset: reset, type: type, key: key)
            window.close()
            return
        }

        // `* ` becomes a bullet; ⌘Z takes it back to the star.
        await reset()
        await type("*")
        await key(space.0, space.1)
        check(letters == "• ", "* and a space make a bullet", letters.debugDescription)
        editor.undoManager?.undo()
        try? await Task.sleep(for: .seconds(0.4))
        check(letters == "* ", "⌘Z right after gives the star back", letters.debugDescription)

        // Numbers: Return continues, Tab nests, Return on an empty item steps out, then ends.
        await reset()
        await type("1.")
        await key(space.0, space.1)
        await type("견적서")
        await key(returnKey.0, returnKey.1)
        check(letters == "1. 견적서\n2. ", "Return makes the next number", letters.debugDescription)
        await type("리뷰")
        await key(returnKey.0, returnKey.1)
        await key(tab.0, tab.1)
        check(letters == "1. 견적서\n2. 리뷰\n\ta. ", "Tab nests with letters", letters.debugDescription)
        await type("시안")
        await key(returnKey.0, returnKey.1)
        await key(returnKey.0, returnKey.1)
        check(letters == "1. 견적서\n2. 리뷰\n\ta. 시안\n3. ", "Return on an empty nested item steps out and counts on", letters.debugDescription)
        await key(returnKey.0, returnKey.1)
        check(letters == "1. 견적서\n2. 리뷰\n\ta. 시안\n", "Return on an empty item ends the list", letters.debugDescription)
        await key(returnKey.0, returnKey.1)
        check(letters == "1. 견적서\n2. 리뷰\n\ta. 시안\n\n", "Return on a plain line is a line break", letters.debugDescription)

        // ⇧Tab and Delete at an item's start.
        await reset(AttributedString("• 하나\n\t• 둘"))
        await key(tab.0, tab.1, .shift)
        check(letters == "• 하나\n• 둘", "⇧Tab steps out", letters.debugDescription)
        editor.setSelectedRange(NSRange(location: ("• 하나\n• " as NSString).length, length: 0))
        await key(delete.0, delete.1)
        check(letters == "• 하나\n둘", "Delete at an item's start takes only the bullet", letters.debugDescription)
        await key(delete.0, delete.1)
        check(letters == "• 하나둘", "Delete again joins the lines as usual", letters.debugDescription)

        // A code block keeps `* ` and Return as typed.
        var code = AttributeContainer()
        code[MemoAttributes.Code.self] = true
        await reset(AttributedString("*", attributes: code))
        await key(space.0, space.1)
        check(letters == "* ", "* stays a star in a code block", letters.debugDescription)
        await reset(AttributedString("- item", attributes: code))
        await key(returnKey.0, returnKey.1)
        check(letters == "- item\n", "Return in a code block is a line break", letters.debugDescription)

        // Taking a title off leaves no title on its line break, so the memo saves as version 1.
        var titleOnly = AttributeContainer()
        titleOnly[MemoAttributes.Paragraph.self] = .title
        await reset(AttributedString("제목", attributes: titleOnly))
        await key(returnKey.0, returnKey.1)
        await type("본문")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        try? await Task.sleep(for: .seconds(0.3))
        draft.setParagraph(nil)
        try? await Task.sleep(for: .seconds(0.3))
        let plainSave = MemoText.encode(draft.text).map { String(decoding: $0, as: UTF8.self) } ?? ""
        check(!plainSave.contains(#""p""#) && plainSave.contains(#""v":1"#), "본문 again saves without a title", plainSave)

        // A quote continues on Return.
        await reset()
        await type(">")
        await key(space.0, space.1)
        await type("범위를 줄이고")
        await key(returnKey.0, returnKey.1)
        check(letters == "> 범위를 줄이고\n> ", "Return continues a quote", letters.debugDescription)

        // Lists and titles inside a quote.
        await reset()
        await type(">")
        await key(space.0, space.1)
        await type("-")
        await key(space.0, space.1)
        await type("하나")
        await key(returnKey.0, returnKey.1)
        check(letters == "> - 하나\n> - ", "a dash list inside a quote continues", letters.debugDescription)
        await key(tab.0, tab.1)
        await type("둘")
        check(letters == "> - 하나\n> \t- 둘", "Tab nests inside a quote", letters.debugDescription)
        await key(returnKey.0, returnKey.1)
        await key(returnKey.0, returnKey.1)
        await key(returnKey.0, returnKey.1)
        check(letters == "> - 하나\n> \t- 둘\n> ", "empty items step out to the quote", letters.debugDescription)
        await type("말")
        draft.setList(.number)
        try? await Task.sleep(for: .seconds(0.3))
        check(letters == "> - 하나\n> \t- 둘\n> 1. 말", "번호 목록 inside a quote keeps the quote", letters.debugDescription)
        draft.setParagraph(.heading)
        try? await Task.sleep(for: .seconds(0.3))
        check(draft.paragraph == .heading && draft.isQuoted, "a heading inside a quote", "\(String(describing: draft.paragraph)) \(draft.isQuoted)")
        draft.setList(.quote)
        try? await Task.sleep(for: .seconds(0.3))
        check(letters == "> - 하나\n> \t- 둘\n1. 말", "인용문 off keeps the list item", letters.debugDescription)
        await reset(AttributedString("> "))
        await type("*")
        await key(space.0, space.1)
        check(letters == "> • ", "* and a space make a bullet inside a quote", letters.debugDescription)

        // After a title, the next line is body text.
        var title = AttributeContainer()
        title[MemoAttributes.Paragraph.self] = .title
        await reset(AttributedString("11월 정리", attributes: title))
        let stored = editor.textStorage?.attribute(NSAttributedString.Key(MemoAttributes.Paragraph.name), at: 0, effectiveRange: nil)
        log("INFO  paragraph value in the text view: \(stored.map { "\(Swift.type(of: $0)) \($0)" } ?? "none")")
        await key(returnKey.0, returnKey.1)
        try? await Task.sleep(for: .seconds(0.3))
        await type("본문")
        let body = draft.text.runs.filter { String(draft.text[$0.range].characters).contains("본") }
        check(letters == "11월 정리\n본문", "Return after a title opens a line", letters.debugDescription)
        check(body.allSatisfy { $0[MemoAttributes.Paragraph.self] == nil }, "the line after a title is body text",
              "\(body.map { $0[MemoAttributes.Paragraph.self].map(\.rawValue) ?? "nil" })")

        // A list change from the menu is one undo step. (After a format change made from the
        // bar or menu, SwiftUI's own undo takes back both together, as it does with typing.)
        await reset(AttributedString("가\n나"))
        draft.setList(.bullet)
        try? await Task.sleep(for: .seconds(0.4))
        check(letters == "• 가\n나" || letters == "가\n• 나", "목록 from the menu", letters.debugDescription)
        editor.undoManager?.undo()
        try? await Task.sleep(for: .seconds(0.4))
        check(letters == "가\n나", "⌘Z takes a menu list change back", letters.debugDescription)

        // What the 서식 menu's items do. (Its shortcuts need a SwiftUI scene's focus, which this
        // window does not have; they are checked below to be in the menu once each.)
        await reset(AttributedString("견적서 보내기\n회의"))
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        try? await Task.sleep(for: .seconds(0.3))
        draft.toggle(MemoAttributes.Underline.self)
        check(draft.text.runs.first?[MemoAttributes.Underline.self] == true, "밑줄 underlines")
        draft.toggle(MemoAttributes.Strike.self)
        check(draft.text.runs.first?[MemoAttributes.Strike.self] == true, "취소선 strikes through")
        draft.setParagraph(.title)
        check(draft.paragraph == .title, "제목 takes the whole line", "\(String(describing: draft.paragraph))")
        draft.setParagraph(.heading)
        check(draft.paragraph == .heading, "머리말", "\(String(describing: draft.paragraph))")
        draft.setParagraph(.sub)
        check(draft.paragraph == .sub, "부머리말", "\(String(describing: draft.paragraph))")
        let titled = draft.text.runs.filter { $0[MemoAttributes.Paragraph.self] == .sub }.map { String(draft.text[$0.range].characters) }.joined()
        check(titled == "견적서 보내기", "a paragraph style covers its line only", titled.debugDescription)
        draft.setParagraph(nil)
        check(draft.paragraph == nil && !draft.text.runs.contains { $0[MemoAttributes.Paragraph.self] != nil }, "본문")
        draft.setParagraph(.title)
        // SwiftUI hands the change to the text view on its next pass, as it would between two keys.
        try? await Task.sleep(for: .seconds(0.3))
        editor.setSelectedRange(NSRange(location: (letters as NSString).length, length: 0))
        try? await Task.sleep(for: .seconds(0.3))
        for (kind, expected) in [(MemoLists.Kind.bullet, "• 회의"), (.dash, "- 회의"), (.number, "1. 회의")] {
            draft.setList(kind)
            try? await Task.sleep(for: .seconds(0.3))
            check(letters == "견적서 보내기\n" + expected, "목록 \(kind)", letters.debugDescription)
        }
        draft.indentLines(by: 1)
        try? await Task.sleep(for: .seconds(0.3))
        check(letters == "견적서 보내기\n\ta. 회의", "들여쓰기", letters.debugDescription)
        draft.indentLines(by: -1)
        try? await Task.sleep(for: .seconds(0.3))
        check(letters == "견적서 보내기\n1. 회의", "내어쓰기", letters.debugDescription)
        draft.setList(.quote)
        try? await Task.sleep(for: .seconds(0.3))
        check(letters == "견적서 보내기\n> 1. 회의", "인용문 goes around the list item", letters.debugDescription)
        draft.setList(.quote)
        try? await Task.sleep(for: .seconds(0.3))
        check(letters == "견적서 보내기\n1. 회의", "인용문 again takes it off", letters.debugDescription)
        // 지우기 takes the new formats off too.
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        try? await Task.sleep(for: .seconds(0.3))
        let beforeClear = MemoText.encode(draft.text).map { String(decoding: $0, as: UTF8.self) } ?? ""
        draft.clearFormatting()
        let first = draft.text.runs.first
        check(first?[MemoAttributes.Underline.self] == nil && first?[MemoAttributes.Strike.self] == nil && first?[MemoAttributes.Paragraph.self] == nil,
              "서식 지우기 takes underline, strikethrough and the title off")

        // Saved as version 2 with the new keys.
        check(beforeClear.contains(#""u":true"#) && beforeClear.contains(#""x":true"#) && beforeClear.contains(#""p":"title""#)
              && beforeClear.contains(#""v":2"#), "saved with u, x, p and version 2", beforeClear)

        // Shortcuts held by more than one menu item.
        var seen: [String: [String]] = [:]
        func walk(_ menu: NSMenu, path: String) {
            for item in menu.items {
                if !item.keyEquivalent.isEmpty {
                    let mask = item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control])
                    seen["\(mask.rawValue)-\(item.keyEquivalent.lowercased())", default: []].append("\(path) › \(item.title)")
                }
                if let sub = item.submenu { walk(sub, path: path.isEmpty ? item.title : "\(path) › \(item.title)") }
            }
        }
        if let menu = NSApp.mainMenu { walk(menu, path: "") }
        let clashes = seen.values.filter { $0.count > 1 }
        check(clashes.isEmpty, "no shortcut is held twice in the menus", "\(clashes)")
        let ours = seen.filter { entry in entry.value.contains { $0.hasPrefix("서식") } }.flatMap(\.value).sorted()
        log("INFO  서식 menu shortcuts: \(ours.joined(separator: ", "))")

        await checkFormulas(draft: draft, editor: editor, window: window, reset: reset, type: type, key: key)
        await checkTables(draft: draft, editor: editor, window: window, model: model, reset: reset, type: type, key: key)
        await checkAttachments(draft: draft, editor: editor, window: window, reset: reset, key: key)

        // Pictures of every format, light and dark.
        await reset(sample())
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        window.makeFirstResponder(nil)
        try? await Task.sleep(for: .seconds(0.6))
        capture(window, "light")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try? await Task.sleep(for: .seconds(0.6))
        capture(window, "dark")
        NSApp.appearance = nil
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 2, length: 4))
        try? await Task.sleep(for: .seconds(0.6))
        capture(window, "bar")
        editor.setSelectedRange(NSRange(location: ("11월 1주차 정리\n이번 주 목표\n1. 견적서" as NSString).length, length: 0))
        draft.showsParagraphBar = true
        try? await Task.sleep(for: .seconds(0.6))
        capture(window, "aa")
        draft.showsParagraphBar = false
        model.panelMode = .normal
        try? await Task.sleep(for: .seconds(0.6))
        capture(window, "narrow")
        window.close()
    }

    /// Formulas: drawn while the caret is elsewhere, their LaTeX while it is in one, Esc and → to
    /// leave, ⌥⌘E with a caret, letters that cannot be read, and ⌘C.
    private static func checkFormulas(draft: MemoDraft, editor: NSTextView, window: NSWindow, reset: (AttributedString, Int?) async -> Void,
                                      type: (String) async -> Void, key: (UInt16, String, NSEvent.ModifierFlags) async -> Void) async {
        var letters: String { String(draft.text.characters) }
        func shown(_ location: Int) -> NSAttributedString? {
            guard let storage = editor.textContentStorage, let layout = editor.textLayoutManager,
                  let start = storage.location(storage.documentRange.location, offsetBy: location) else { return nil }
            layout.ensureLayout(for: NSTextRange(location: start))
            return (layout.textLayoutFragment(for: start)?.textElement as? NSTextParagraph)?.attributedString
        }
        func has(_ key: NSAttributedString.Key, at location: Int) -> Bool {
            guard let string = shown(location) else { return false }
            var found = false
            string.enumerateAttribute(key, in: NSRange(location: 0, length: string.length)) { value, _, _ in if value != nil { found = true } }
            return found
        }
        func mark(at location: Int) -> String? {
            guard let string = shown(location) else { return nil }
            var found: String?
            string.enumerateAttribute(.memoFormula, in: NSRange(location: 0, length: string.length)) { value, _, _ in if let value = value as? String { found = value } }
            return found
        }
        let quadratic = "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}"
        let text = formulaSample()
        await reset(text, 0)
        let firstLine = ("근의 공식: " as NSString).length
        check(has(.attachment, at: firstLine), "a formula in the text is drawn")
        check(has(.attachment, at: (letters as NSString).range(of: "$$ ").location), "a $$ line is drawn")
        let bad = (letters as NSString).range(of: "\\frac{a}{").location
        check(mark(at: bad) == FormulaMark.unreadable, "unreadable LaTeX keeps its letters", mark(at: bad) ?? "none")
        let hangul = (letters as NSString).range(of: "\\text{합계 }").location
        check(has(.attachment, at: hangul), "Korean in \\text is drawn")
        window.makeFirstResponder(nil)
        try? await Task.sleep(for: .seconds(0.6))
        capture(window, "math")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try? await Task.sleep(for: .seconds(0.6))
        capture(window, "math-dark")
        NSApp.appearance = nil
        window.makeFirstResponder(editor)

        // Into the formula: its LaTeX between `$` marks, then Esc draws it again.
        editor.setSelectedRange(NSRange(location: firstLine + 4, length: 0))
        try? await Task.sleep(for: .seconds(0.5))
        check(mark(at: firstLine) == FormulaMark.open, "the caret in a formula shows its LaTeX", mark(at: firstLine) ?? "none")
        capture(window, "math-open")
        await key(53, "\u{1b}", [])
        check(mark(at: firstLine) == nil && has(.attachment, at: firstLine), "Esc draws it again", mark(at: firstLine) ?? "none")
        check(editor.selectedRange().location == firstLine + (quadratic as NSString).length, "Esc leaves the caret after it", "\(editor.selectedRange())")
        // → at its end leaves too, and what is typed after is not part of it.
        editor.setSelectedRange(NSRange(location: firstLine + 2, length: 0))
        try? await Task.sleep(for: .seconds(0.4))
        editor.setSelectedRange(NSRange(location: firstLine + (quadratic as NSString).length, length: 0))
        try? await Task.sleep(for: .seconds(0.4))
        check(mark(at: firstLine) == FormulaMark.open, "the caret at its end while writing keeps it open", "\(mark(at: firstLine) ?? "none") \(editor.selectedRange())")
        await key(124, "\u{f703}", [.numericPad, .function])
        check(mark(at: firstLine) == nil, "→ at its end draws it again", mark(at: firstLine) ?? "none")
        await type("!")
        let typed = draft.text.runs.first { String(draft.text[$0.range].characters).contains("!") }
        check(typed?[MemoAttributes.Math.self] == nil, "letters typed after a drawn formula are plain")

        // ⌥⌘E with a caret: an empty formula, written as typed, Esc to leave.
        await reset(AttributedString("값: "), nil)
        draft.toggleFormula()
        try? await Task.sleep(for: .seconds(0.4))
        capture(window, "math-empty")
        await type("x^2")
        let made = draft.text.runs.filter { $0[MemoAttributes.Math.self] == true }.map { String(draft.text[$0.range].characters) }.joined()
        check(made == "x^2", "⌥⌘E then typing writes a formula", made.debugDescription)
        check(mark(at: 4) == FormulaMark.open, "it shows its LaTeX while written", mark(at: 4) ?? "none")
        capture(window, "math-new")
        await key(53, "\u{1b}", [])
        await type(" 끝")
        check(has(.attachment, at: 4), "Esc draws the new formula")
        check(letters == "값: x^2 끝" && draft.text.runs.last?[MemoAttributes.Math.self] == nil, "and what follows is plain", letters.debugDescription)

        // ⌥⌘E right after a drawn formula opens that one.
        editor.setSelectedRange(NSRange(location: ("값: x^2" as NSString).length, length: 0))
        try? await Task.sleep(for: .seconds(0.4))
        check(mark(at: 4) == nil, "the caret after a drawn formula leaves it drawn", mark(at: 4) ?? "none")
        draft.toggleFormula()
        try? await Task.sleep(for: .seconds(0.4))
        check(mark(at: 4) == FormulaMark.open, "⌥⌘E right after a formula opens it", mark(at: 4) ?? "none")
        await key(53, "\u{1b}", [])

        // Picked letters become a formula and back.
        await reset(AttributedString("a^2 + b^2 = c^2"), nil)
        editor.setSelectedRange(NSRange(location: 0, length: 15))
        try? await Task.sleep(for: .seconds(0.3))
        draft.toggleFormula()
        check(draft.text.runs.allSatisfy { $0[MemoAttributes.Math.self] == true }, "⌥⌘E makes picked letters a formula")
        draft.toggleFormula()
        check(draft.text.runs.allSatisfy { $0[MemoAttributes.Math.self] == nil }, "⌥⌘E again makes them letters")

        // ⌘C puts formulas on the clipboard in `$…$`. The clipboard's letters are put back after.
        let kept = NSPasteboard.general.string(forType: .string)
        await reset(text, 0)
        editor.setSelectedRange(NSRange(location: 0, length: ("근의 공식: " + quadratic + " 로 풀기") .utf16.count))
        try? await Task.sleep(for: .seconds(0.3))
        await key(8, "c", [.command])
        try? await Task.sleep(for: .seconds(0.3))
        let copied = NSPasteboard.general.string(forType: .string) ?? ""
        check(copied == "근의 공식: $\(quadratic)$ 로 풀기", "⌘C writes formulas as $…$", copied)
        NSPasteboard.general.clearContents()
        if let kept { NSPasteboard.general.setString(kept, forType: .string) }
    }

    /// Formulas in the text and on a line of their own, one that cannot be read, Korean in one,
    /// one in a colour and highlighter, and a matrix taller than the line.
    private static func formulaSample() -> AttributedString {
        func styled(_ string: String, _ build: (inout AttributeContainer) -> Void = { _ in }) -> AttributedString {
            var container = AttributeContainer()
            build(&container)
            return AttributedString(string, attributes: container)
        }
        let math: (inout AttributeContainer) -> Void = { $0[MemoAttributes.Math.self] = true }
        var text = styled("근의 공식: ")
        text += styled("x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}", math)
        text += styled(" 로 풀기\n할인 후 금액 ")
        text += styled("p' = p(1 - r)") { $0[MemoAttributes.Math.self] = true; $0[MemoAttributes.Ink.self] = .blue; $0[MemoAttributes.Highlight.self] = .yellow }
        text += styled("\n$$ S = \\sum_{i=1}^{n} p_i\n면적 ")
        text += styled("\\frac{a}{", math)
        text += styled(" 다시 쓰기\n")
        text += styled("\\text{합계 } \\sum p_i = 1000\\text{원}", math)
        text += styled("\n행렬 ")
        text += styled("A = \\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}", math)
        text += styled(" 처럼 높은 것\n예전 ")
        text += styled("w = 0.9w", math)
        text += styled("0") { $0[MemoAttributes.Math.self] = true; $0[MemoAttributes.Script.self] = .lowered }
        text += styled(" 끝")
        return MemoMath.upgradingScripts(text)
    }

    /// Tables: Tab, ⇧Tab and Return between cells, a new row from the last cell, Delete that
    /// never takes a table apart, the right-click menu's items, 표 넣기, saving, fitting the
    /// memo's width, and pictures.
    private static func checkTables(draft: MemoDraft, editor: NSTextView, window: NSWindow, model: AppModel,
                                    reset: (AttributedString, Int?) async -> Void, type: (String) async -> Void,
                                    key: (UInt16, String, NSEvent.ModifierFlags) async -> Void) async {
        let tab: (UInt16, String) = (48, "\t")
        let returnKey: (UInt16, String) = (36, "\r")
        let delete: (UInt16, String) = (51, "\u{7f}")
        var letters: String { String(draft.text.characters) }
        var caret: Int { editor.selectedRange().location }
        // -100 for letters not there, so a failed step is reported rather than overflowing.
        func at(_ words: String) -> Int { (editor.string as NSString).range(of: words).location == NSNotFound ? -100 : (editor.string as NSString).range(of: words).location }
        func end(_ words: String) -> Int { at(words) < 0 ? -100 : NSMaxRange((editor.string as NSString).range(of: words)) }
        /// The table id on the letter at `location` in the memo's text.
        func mark(_ location: Int) -> String? {
            let characters = draft.text.characters
            guard location >= 0, location < characters.count else { return nil }
            return draft.text.runs[characters.index(characters.startIndex, offsetBy: location)][MemoAttributes.Table.self]
        }
        func put(_ location: Int) async {
            editor.setSelectedRange(NSRange(location: max(0, location), length: 0))
            try? await Task.sleep(for: .seconds(0.3))
        }
        let sample = tableSample()
        let original = String(sample.characters)

        await reset(sample, nil)
        window.makeFirstResponder(editor)
        await put(end("디자인"))
        await key(tab.0, tab.1, [])
        check(caret == end("1,200,000"), "Tab goes to the next cell's end", "\(caret)")
        await key(tab.0, tab.1, .shift)
        check(caret == end("디자인"), "⇧Tab goes back", "\(caret)")
        await put(end("금액"))
        await key(returnKey.0, returnKey.1, [])
        check(caret == end("1,200,000") && letters == original, "Return goes to the next row's same cell", "\(caret)")

        // The last cell's Tab makes a new row, marked as the table's.
        await put(end("4주"))
        await key(tab.0, tab.1, [])
        check(letters.contains("4주\n\t\t\n표 다음 줄"), "Tab in the last cell makes a new row", letters.debugDescription)
        check(caret == end("4주") + 1 && mark(caret) == "t1", "the caret is in the new row's first cell, and the row is the table's",
              "\(caret) \(String(describing: mark(caret)))")
        await type("합계")
        check(mark(caret - 1) == "t1", "letters typed in a cell are the table's")
        // Korean being composed is finished before Tab moves on.
        editor.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try? await Task.sleep(for: .seconds(0.3))
        await key(tab.0, tab.1, [])
        check(!editor.hasMarkedText() && letters.contains("합계ㅎ\t") && caret == end("합계ㅎ") + 1,
              "Tab while composing finishes the syllable, then moves", letters.debugDescription)
        // Return in the last row leaves the table for a new line under it.
        await key(returnKey.0, returnKey.1, [])
        check(letters.contains("합계ㅎ\t\t\n\n표 다음 줄") && mark(caret) == nil, "Return in the last row leaves the table", letters.debugDescription)
        editor.undoManager?.undo()
        try? await Task.sleep(for: .seconds(0.4))
        check(letters.contains("합계ㅎ\t\t\n표 다음 줄"), "⌘Z takes the new line back", letters.debugDescription)

        // Delete at the front of a cell, of a row and of the words under the table.
        await reset(sample, nil)
        window.makeFirstResponder(editor)
        await put(at("금액"))
        await key(delete.0, delete.1, [])
        check(letters == original && caret == at("금액"), "Delete at a cell's front does nothing", letters.debugDescription)
        await put(at("개발"))
        await key(delete.0, delete.1, [])
        check(letters == original, "Delete at a row's front does nothing", letters.debugDescription)
        await put(at("표 다음 줄"))
        await key(delete.0, delete.1, [])
        check(letters == original && caret == end("4주"), "Delete under the table keeps it and goes to its last cell", "\(caret)")
        await put(end("디자인") - 1)
        await key(delete.0, delete.1, [])
        check(letters.contains("디인\t1,200,000"), "Delete inside a cell's words deletes", letters.debugDescription)

        // List keys and menus leave rows alone; ⇧Return is Return; forward delete never joins cells.
        await reset(sample, nil)
        window.makeFirstResponder(editor)
        await put(end("디자인"))
        await type("*")
        await key(49, " ", [])
        check(letters.contains("디자인* \t1,200,000"), "* and a space in a cell stay as typed", letters.debugDescription)
        await reset(sample, nil)
        window.makeFirstResponder(editor)
        await put(end("금액"))
        await key(returnKey.0, returnKey.1, .shift)
        check(letters == original && caret == end("1,200,000"), "⇧Return in a cell is Return", "\(caret)")
        await key(117, "\u{F728}", [])
        check(letters == original, "forward delete at a cell's end does nothing", letters.debugDescription)
        draft.indentLines(by: 1)
        try? await Task.sleep(for: .seconds(0.3))
        check(letters == original, "⌘] leaves a table row alone", letters.debugDescription)

        // The right-click menu's items.
        func menu(_ action: MemoTableAction, after words: String) async {
            await reset(sample, nil)
            window.makeFirstResponder(editor)
            await put(end(words))
            draft.tableAction(action)
            try? await Task.sleep(for: .seconds(0.4))
        }
        await menu(.rowAbove, after: "디자인")
        check(letters.contains("메모\n\t\t\n디자인") && mark(caret) == "t1", "위에 행 넣기", letters.debugDescription)
        await menu(.rowBelow, after: "디자인")
        check(letters.contains("시안 2종\n\t\t\n개발"), "아래에 행 넣기", letters.debugDescription)
        await menu(.columnLeft, after: "금액")
        check(letters.contains("항목\t\t금액\t메모\n디자인\t\t1,200,000"), "왼쪽에 열 넣기", letters.debugDescription)
        await menu(.columnRight, after: "금액")
        check(letters.contains("항목\t금액\t\t메모\n디자인\t1,200,000\t\t시안"), "오른쪽에 열 넣기", letters.debugDescription)
        check(mark(at("\t\t메모") + 1) == "t1", "a new column's tabs are the table's")
        await menu(.deleteRow, after: "디자인")
        check(letters.contains("메모\n개발") && !letters.contains("디자인"), "행 지우기", letters.debugDescription)
        await menu(.deleteColumn, after: "금액")
        check(letters.contains("항목\t메모\n디자인\t시안 2종\n개발\t4주"), "열 지우기", letters.debugDescription)
        await menu(.toText, after: "금액")
        check(letters == original && mark(at("항목")) == nil && mark(at("넓은 표")) == "t2", "표를 글로 바꾸기 keeps the letters, not the table",
              "\(letters.debugDescription) \(String(describing: mark(at("항목"))))")
        await menu(.deleteTable, after: "금액")
        check(letters.hasPrefix("비용\n표 다음 줄"), "표 지우기", letters.debugDescription)
        editor.undoManager?.undo()
        try? await Task.sleep(for: .seconds(0.4))
        check(letters == original, "⌘Z brings the table back", letters.debugDescription)

        // 표 넣기: two by two on an empty line, under a line with words; not inside a table.
        await reset(AttributedString("위\n\n아래"), 2)
        draft.tableAction(.insert)
        try? await Task.sleep(for: .seconds(0.4))
        check(letters == "위\n\t\n\t\n아래" && mark(2) != nil && mark(2) == mark(4) && mark(3) == nil && caret == 2,
              "표 넣기 on an empty line", letters.debugDescription)
        await reset(AttributedString("위에 글"), 2)
        draft.tableAction(.insert)
        try? await Task.sleep(for: .seconds(0.4))
        check(letters == "위에 글\n\t\n\t" && caret == 5, "표 넣기 under a line with words", letters.debugDescription)
        let saved = MemoText.encode(draft.text).map { String(decoding: $0, as: UTF8.self) } ?? ""
        check(saved.contains(#""tl":""#) && saved.contains(#""v":2"#) && !saved.contains(#""tb""#), "saved under tl, version 2", saved)

        // Wide tables stay within the memo, wide panel and normal.
        await reset(sample, nil)
        window.makeFirstResponder(editor)
        await put(at("둘째 칸") + 4)
        func widest() -> (table: CGFloat, room: CGFloat) {
            guard let layout = editor.textLayoutManager, let container = editor.textContainer else { return (0, 0) }
            var widest: CGFloat = 0
            layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
                if let paragraph = fragment.textElement as? NSTextParagraph, paragraph.attributedString.length > 0,
                   let look = paragraph.attributedString.attribute(.memoTable, at: 0, effectiveRange: nil) as? TableRowLook {
                    widest = max(widest, look.width)
                }
                return true
            }
            return (widest, container.size.width - container.lineFragmentPadding * 2)
        }
        let wide = widest()
        check(wide.table > 0 && wide.table <= wide.room, "a wide table fits the wide memo", "\(wide)")
        capture(window, "table")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try? await Task.sleep(for: .seconds(0.6))
        capture(window, "table-dark")
        NSApp.appearance = nil
        model.panelMode = .normal
        try? await Task.sleep(for: .seconds(0.8))
        let narrow = widest()
        check(narrow.table > 0 && narrow.table <= narrow.room && narrow.room < wide.room, "and the normal one, fitted again", "\(narrow)")
        capture(window, "table-narrow")
        await put(end("넷째 칸도 길게 써 두었어요"))
        try? await Task.sleep(for: .seconds(0.4))
        capture(window, "table-narrow-caret")
        // The caret past what fits: the letters before it show, after a `…`.
        await put(end("보는 줄이에요"))
        try? await Task.sleep(for: .seconds(0.4))
        capture(window, "table-narrow-tail")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try? await Task.sleep(for: .seconds(0.6))
        capture(window, "table-narrow-dark")
        NSApp.appearance = nil
        draft.showsParagraphBar = true
        try? await Task.sleep(for: .seconds(0.6))
        capture(window, "table-aa")
        draft.showsParagraphBar = false
        model.panelMode = .wide
        try? await Task.sleep(for: .seconds(0.4))
    }

    /// The mockup's cost table, a wide one, and words around them.
    private static func tableSample() -> AttributedString {
        func row(_ string: String, _ id: String) -> AttributedString {
            var container = AttributeContainer()
            container[MemoAttributes.Table.self] = id
            return AttributedString(string, attributes: container)
        }
        var text = AttributedString("비용\n")
        text += row("항목\t금액\t메모", "t1") + AttributedString("\n")
        text += row("디자인\t1,200,000\t시안 2종", "t1") + AttributedString("\n")
        text += row("개발\t3,400,000\t4주", "t1") + AttributedString("\n")
        text += AttributedString("표 다음 줄\n")
        text += row("넓은 표\t둘째 칸에 아주 긴 글을 써서 메모 폭을 넘기면 어떻게 되는지 보는 줄이에요\t셋째\t넷째 칸도 길게 써 두었어요", "t2") + AttributedString("\n")
        text += row("\t\t\t", "t2") + AttributedString("\n")
        text += AttributedString("끝")
        return text
    }

    /// The mockup's memo: a title, headings, numbers to three levels, bullets, a dash, a quote,
    /// underlined and struck-through words, a chip and a timeline line beside them.
    private static func sample() -> AttributedString {
        func styled(_ string: String, _ build: (inout AttributeContainer) -> Void = { _ in }) -> AttributedString {
            var container = AttributeContainer()
            build(&container)
            return AttributedString(string, attributes: container)
        }
        var text = styled("11월 1주차 정리") { $0[MemoAttributes.Paragraph.self] = .title }
        text += styled("\n")
        text += styled("이번 주 목표") { $0[MemoAttributes.Paragraph.self] = .heading }
        text += styled("\n1. 견적서 ")
        text += styled("금요일까지") { $0[MemoAttributes.Underline.self] = true }
        text += styled(" 보내기\n2. 디자인 리뷰 준비\n\ta. 시안 두 장 고르기\n\tb. 색상 휠 다시 보기 ")
        text += styled("다음 주로") { $0[MemoAttributes.Strike.self] = true }
        text += styled("\n\t\ti. 세 번째 단계는 이렇게 그리고 줄이 길어지면 기호 뒤에 맞춰 매달려서 다음 줄로 넘어가요. 패널이 넓어도 넘어가도록 이 줄은 일부러 아주 길게 써 두었어요, 한 줄을 다 채우고도 남게\n3. 치과 예약\n")
        text += styled("회의 메모") { $0[MemoAttributes.Paragraph.self] = .sub }
        text += styled("\n• 배포는 다음 주 화요일\n\t• QA 일정은 김 팀장에게 확인\n\t\t• 세 번째 단계\n- 회의록은 공유 폴더에\n> 이번 분기엔 범위를 줄이고\n> 마감을 지키자, 줄이 길어지면 인용문도 세로줄을 따라 이어서 그려져요. 이 줄도 넘어가도록 길게 써 두었어요, 패널 끝을 지나 다음 줄까지 가요\n11.03 14:25 타임라인 줄은 그대로\n────\n")
        text += styled("> 인용문 안 머리말") { $0[MemoAttributes.Paragraph.self] = .heading }
        text += styled("\n> • 인용문 안 글머리\n> \ta. 인용문 안 번호\n> \tb. 둘째\n> - 대시도 돼요\n끝")
        return text
    }

    /// Attachments, in a test folder in place of the App Group's: put in from a file, a drop and
    /// a pasted picture, 25 MB refused, pictures and cards drawn, the three states, click, double-click
    /// and Space, the card's menu, removal and clearing away, ⌘C, and under a table.
    private static func checkAttachments(draft: MemoDraft, editor: NSTextView, window: NSWindow, reset: (AttributedString, Int?) async -> Void,
                                         key: (UInt16, String, NSEvent.ModifierFlags) async -> Void) async {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appending(path: "memo-check-attachments", directoryHint: .isDirectory)
        try? fm.removeItem(at: folder)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let shelf = AttachmentShelf.shared
        let realStore = shelf.store
        shelf.store = AttachmentStore(root: folder.appending(path: "Attachments", directoryHint: .isDirectory))
        defer { shelf.store = realStore }
        check(shelf.store.root.path.hasPrefix(fm.temporaryDirectory.path), "attachments go to a test folder", shelf.store.root.path)

        // Files to attach: a PDF, a wide picture, and one over the limit.
        let pdf = folder.appending(path: "견적서_v3.pdf")
        try? Data(repeating: 0x25, count: 248_000).write(to: pdf)
        let png = folder.appending(path: "화면 캡처 2026-11-03.png")
        let picture = NSImage(size: NSSize(width: 1600, height: 700), flipped: false) { rect in
            NSColor(calibratedRed: 0.55, green: 0.68, blue: 0.9, alpha: 1).setFill()
            rect.fill()
            NSColor.white.setFill()
            NSRect(x: 120, y: 120, width: 900, height: 460).fill()
            return true
        }
        if let tiff = picture.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) { try? rep.representation(using: .png, properties: [:])?.write(to: png) }
        let big = folder.appending(path: "디자인_원본.zip")
        fm.createFile(atPath: big.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: big) {
            try? handle.truncate(atOffset: UInt64(MemoAttachments.limit + 1))
            try? handle.close()
        }
        var letters: String { String(draft.text.characters) }
        func found() -> [MemoAttachments.Ref] { MemoAttachments.attachments(in: draft.text).map(\.ref) }
        /// The card drawn for the attachment letter at `location`.
        func card(at location: Int) -> AttachmentCard? {
            guard let layout = editor.textLayoutManager, let storage = editor.textContentStorage,
                  let place = storage.location(storage.documentRange.location, offsetBy: location),
                  let fragment = layout.textLayoutFragment(for: place), let paragraph = fragment.textElement as? NSTextParagraph else { return nil }
            let offset = storage.offset(from: fragment.rangeInElement.location, to: place)
            guard offset >= 0, offset < paragraph.attributedString.length else { return nil }
            return paragraph.attributedString.attribute(.attachment, at: offset, effectiveRange: nil) as? AttachmentCard
        }
        func placeholder(_ number: Int = 0) -> Int {
            let string = editor.string as NSString
            var at = 0, seen = 0
            while at < string.length {
                let found = string.range(of: String(MemoAttachments.placeholder), range: NSRange(location: at, length: string.length - at))
                guard found.location != NSNotFound else { return -1 }
                if seen == number { return found.location }
                seen += 1
                at = NSMaxRange(found)
            }
            return -1
        }
        func click(_ location: Int, count: Int) async {
            guard let frame = editor.textLayoutManager.flatMap({ _ in cardFrame(location) }) else { return }
            let point = editor.convert(CGPoint(x: frame.midX, y: frame.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
                NSApp.postEvent(event, atStart: false)
            }
            try? await Task.sleep(for: .seconds(0.5))
        }
        func cardFrame(_ location: Int) -> CGRect? {
            guard let layout = editor.textLayoutManager, let storage = editor.textContentStorage,
                  let start = storage.location(storage.documentRange.location, offsetBy: location),
                  let end = storage.location(start, offsetBy: 1), let range = NSTextRange(location: start, end: end) else { return nil }
            var frame: CGRect?
            layout.enumerateTextSegments(in: range, type: .standard, options: []) { _, segment, _, _ in
                frame = segment
                return false
            }
            let origin = editor.textContainerOrigin
            return frame.map { $0.offsetBy(dx: origin.x, dy: origin.y) }
        }

        // A file goes in on a line of its own, copied into the folder.
        await reset(AttributedString("자료"), nil)
        draft.attach([pdf])
        try? await Task.sleep(for: .seconds(0.6))
        let pdfRef = found().first
        check(letters == "자료\n\(MemoAttachments.placeholder)\n", "파일 첨부 puts the file on its own line", letters.debugDescription)
        check(pdfRef?.name == "견적서_v3.pdf" && pdfRef.map(shelf.store.exists) == true, "the file is copied into the attachment folder", "\(String(describing: pdfRef))")
        let saved = MemoText.encode(draft.text).map { String(decoding: $0, as: UTF8.self) } ?? ""
        check(saved.contains(#""fa":""#) && saved.contains("견적서_v3.pdf") && saved.contains(#""v":2"#), "saved with fa as id/name, version 2", saved)
        check(editor.selectedRange().location == (editor.string as NSString).length, "the caret is on the line after it")

        // Over 25 MB: refused, and the memo says so.
        let before = letters
        draft.attach([big])
        try? await Task.sleep(for: .seconds(0.4))
        let notice = editor.subviews.contains { $0 is MemoNoticeView }
        check(letters == before && notice, "over 25MB is refused with 25MB까지 붙일 수 있어요", "\(letters.debugDescription) notice=\(notice)")
        check(shelf.store.ids().count == 1, "nothing of the refused file is kept", "\(shelf.store.ids())")

        // A file card: one line, the mockup's 44 pt card with its room around it.
        let pdfAt = placeholder()
        let pdfCard = card(at: pdfAt)
        check(pdfCard?.look.state == .ready(size: 248_000) && pdfCard?.look.pictureSize == nil, "a file is drawn as a card, ready with its size", "\(String(describing: pdfCard?.look))")
        check(pdfRef.map(shelf.kindName) == "PDF 문서", "the card names the kind in Korean", pdfRef.map(shelf.kindName) ?? "")
        let cardHeight = cardFrame(pdfAt)?.height ?? 0
        check(cardHeight >= 2 * AttachmentCard.margin + AttachmentCard.cardHeight && cardHeight <= 64, "the card's line is the card's height", "\(cardHeight)")

        // A picture: across the memo, at most 240 pt high.
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        try? await Task.sleep(for: .seconds(0.3))
        draft.attach([png])
        try? await Task.sleep(for: .seconds(0.6))
        let pngAt = placeholder(1)
        let pngCard = card(at: pngAt)
        check(pngCard?.look.pictureSize != nil, "a picture is drawn as itself", "\(String(describing: pngCard?.look))")
        if let look = pngCard?.look, let frame = cardFrame(pngAt) {
            let room = (editor.textContainer?.size.width ?? 0) - 2 * (editor.textContainer?.lineFragmentPadding ?? 0)
            let drawn = AttachmentCard.size(of: look, width: room)
            let narrow = AttachmentCard.size(of: look, width: 300)
            // Wide memo: 240 pt high, as wide as that makes it; narrow: the memo's width.
            check(drawn.height == AttachmentCard.pictureMaxHeight && abs(drawn.width - 240 * 1600 / 700) <= 1
                  && narrow.width == 300 - 2 * AttachmentCard.margin && narrow.height < 240 && frame.height >= drawn.height,
                  "the picture fits the memo's width, 240 pt high at most", "\(drawn) \(narrow) \(frame)")
        } else {
            check(false, "the picture has a place")
        }

        // Click picks a card (ink outline); a double-click and Space show it.
        await click(pdfAt, count: 1)
        check(editor.selectedRange() == NSRange(location: pdfAt + 1, length: 0) && draft.pickedAttachment?.ref == pdfRef,
              "a click picks the card, the caret just after it (no selection grey)", "\(editor.selectedRange())")
        try? await Task.sleep(for: .seconds(0.8))
        check(card(at: pdfAt)?.look.isPicked == true, "a picked card is drawn with its outline")
        capture(window, "attach-picked")
        draft.previewURL = nil
        await key(49, " ", [])
        check(draft.previewURL?.lastPathComponent == "견적서_v3.pdf", "Space on a picked card opens 훑어보기", "\(String(describing: draft.previewURL))")
        await key(8, "c", .command)
        let copiedFiles = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        check(NSPasteboard.general.string(forType: .string) == "📎 견적서_v3.pdf" && copiedFiles.first?.lastPathComponent == "견적서_v3.pdf",
              "⌘C on a picked card copies its file and 📎 name", NSPasteboard.general.string(forType: .string) ?? "nil")
        draft.previewURL = nil
        try? await Task.sleep(for: .seconds(0.5))
        await click(pngAt, count: 1)
        await click(pngAt, count: 2)
        check(draft.previewURL?.lastPathComponent == "화면 캡처 2026-11-03.png", "a double-click opens 훑어보기", "\(String(describing: draft.previewURL))")
        draft.previewURL = nil
        try? await Task.sleep(for: .seconds(0.5))
        // Moving the caret away lets the card go.
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        try? await Task.sleep(for: .seconds(0.4))
        check(draft.pickedAttachment == nil, "the card is no longer picked once the caret moves")

        // The card's menu, as the mockup's.
        if let picked = MemoAttachments.attachments(in: draft.text).first {
            let titles = draft.cardMenu(picked.ref, range: picked.range, window: window).compactMap { $0.item?.title }
            check(titles == ["훑어보기", "기본 앱으로 열기", "Finder에서 보기", "복사", "다른 이름으로 저장…", "첨부 지우기"], "the card's right-click menu", "\(titles)")
        }

        // ⌘C writes the name after a clip.
        editor.setSelectedRange(NSRange(location: 0, length: pdfAt + 1))
        try? await Task.sleep(for: .seconds(0.3))
        await key(8, "c", .command)
        check(NSPasteboard.general.string(forType: .string) == "자료\n📎 견적서_v3.pdf", "⌘C copies 📎 and the name",
              NSPasteboard.general.string(forType: .string)?.debugDescription ?? "nil")
        let mirror = NotesHTML.body(name: "이름", text: draft.text) ?? ""
        check(mirror.contains("<div>📎 견적서_v3.pdf</div>") && mirror.contains("📎 화면 캡처 2026-11-03.png"), "the 메모 app's copy has 📎 and the name", mirror)

        // The card's 복사 puts the file on the clipboard; ⌘V there brings the same attachment back.
        if let pdfRef {
            shelf.copy(pdfRef)
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            try? await Task.sleep(for: .seconds(0.3))
            await key(9, "v", .command)
            check(found().filter { $0 == pdfRef }.count == 2 && shelf.store.ids().count == 2, "a copied card pastes as the same attachment", "\(found())")
        }

        // ⌘X and ⌘V move a card with the letters around it, still a card.
        let beforeCut = found()
        editor.setSelectedRange(NSRange(location: 0, length: pdfAt + 2))
        try? await Task.sleep(for: .seconds(0.3))
        await key(7, "x", .command)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        try? await Task.sleep(for: .seconds(0.3))
        await key(9, "v", .command)
        check(found().count == beforeCut.count && Set(found()) == Set(beforeCut) && letters.hasSuffix("자료\n\(MemoAttachments.placeholder)\n"),
              "⌘X and ⌘V keep the card", "\(found().count) \(letters.suffix(8).debugDescription)")

        // A pasted picture alone becomes an attachment.
        NSPasteboard.general.clearContents()
        if let tiff = picture.tiffRepresentation { NSPasteboard.general.setData(tiff, forType: .tiff) }
        await key(9, "v", .command)
        let pasted = found().last
        check(pasted?.name.hasPrefix("이미지 ") == true && pasted?.fileExtension == "png" && pasted.map(shelf.store.exists) == true,
              "a pasted picture becomes an attachment", "\(String(describing: pasted))")

        // A file dropped from Finder goes in where it is let go.
        let count = found().count
        let board = NSPasteboard(name: NSPasteboard.Name("memo-check-drop"))
        board.clearContents()
        board.writeObjects([pdf as NSURL])
        let dropAt = editor.convert(CGPoint(x: 1, y: 10), to: nil)
        let drag = CheckDrag(pasteboard: board, location: dropAt, window: window)
        let entered = editor.draggingEntered(drag)
        let taken = editor.performDragOperation(drag)
        try? await Task.sleep(for: .seconds(0.5))
        check(entered == .copy && taken && found().count == count + 1 && letters.hasPrefix("\(MemoAttachments.placeholder)\n") && found().first?.name == "견적서_v3.pdf",
              "a file dropped on the memo is attached there", "entered \(entered.rawValue) taken \(taken) \(letters.prefix(6).debugDescription)")
        let words = NSPasteboard(name: NSPasteboard.Name("memo-check-drop-words"))
        words.clearContents()
        words.setString("글", forType: .string)
        check(MemoFileDrop.files(in: CheckDrag(pasteboard: words, location: dropAt, window: window)).isEmpty, "a drag of words is left to the text view")

        // The three states, light and dark.
        let waitingRef = MemoAttachments.Ref(id: UUID().uuidString, name: "디자인_원본.zip")
        let missingRef = MemoAttachments.Ref(id: UUID().uuidString, name: "계약서_초안.docx")
        shelf.synced(waiting: [waitingRef.id], changed: [])
        var states = AttributedString("자료\n")
        for ref in [pdfRef, waitingRef, missingRef].compactMap({ $0 }) + [found().first { $0.fileExtension == "png" }].compactMap({ $0 }) {
            var mark = AttributeContainer()
            mark[MemoAttributes.Attachment.self] = ref.value
            states += AttributedString(String(MemoAttachments.placeholder), attributes: mark) + AttributedString("\n")
        }
        states += AttributedString("끝")
        await reset(states, 0)
        try? await Task.sleep(for: .seconds(0.4))
        let looks = (0..<4).compactMap { card(at: placeholder($0))?.look.state }
        check(looks.count == 4 && looks[0] == .ready(size: 248_000) && looks[1] == .waiting && looks[2] == .missing,
              "cards show ready, 다른 기기에서 받는 중… and 파일을 찾을 수 없어요", "\(looks)")
        window.makeFirstResponder(nil)
        try? await Task.sleep(for: .seconds(0.6))
        capture(window, "attach-light")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try? await Task.sleep(for: .seconds(0.8))
        capture(window, "attach-dark")
        NSApp.appearance = nil
        try? await Task.sleep(for: .seconds(0.4))
        window.makeFirstResponder(editor)
        shelf.synced(waiting: [], changed: [])

        // 첨부 지우기 takes the letter and its line; the file waits, then is cleared away with a mark.
        if let first = MemoAttachments.attachments(in: draft.text).first {
            draft.removeAttachment(first.range)
            try? await Task.sleep(for: .seconds(0.4))
            check(!found().contains(first.ref) && letters.hasPrefix("자료\n\(MemoAttachments.placeholder)"), "첨부 지우기 takes the card and its line",
                  letters.debugDescription)
            check(shelf.store.exists(first.ref), "its file stays while undo can bring it back")
            shelf.store.sweep(referenced: Set(found().map(\.id)), launch: shelf.launch)
            check(shelf.store.exists(first.ref), "within the run it waits")
            shelf.store.sweep(referenced: Set(found().map(\.id)), launch: "next run")
            check(!shelf.store.exists(first.ref) && shelf.store.marks().contains(first.ref.id), "the next run clears it away and marks it")
        }

        // In a table: under it, not in a cell.
        var row = AttributeContainer()
        row[MemoAttributes.Table.self] = "t1"
        await reset(AttributedString("가\t나", attributes: row) + AttributedString("\n") + AttributedString("다\t라", attributes: row) + AttributedString("\n끝"), 1)
        draft.attach([pdf])
        try? await Task.sleep(for: .seconds(0.5))
        check(letters == "가\t나\n다\t라\n\(MemoAttachments.placeholder)\n끝", "in a table the file goes under it", letters.debugDescription)
        check(editor.selectedRange().location == ("가\t나\n다\t라\n\(MemoAttachments.placeholder)\n" as NSString).length, "the caret is on the line after it",
              "\(editor.selectedRange())")
        try? fm.removeItem(at: folder)
    }

    private static func textView(_ view: NSView) -> NSTextView? {
        if let found = view as? NSTextView, !found.isFieldEditor { return found }
        for subview in view.subviews {
            if let found = textView(subview) { return found }
        }
        return nil
    }

    /// A drag for the drop check: a pasteboard let go at a point.
    @MainActor
    private final class CheckDrag: NSObject, @preconcurrency NSDraggingInfo {
        let draggingPasteboard: NSPasteboard
        let draggingLocation: NSPoint
        let draggingDestinationWindow: NSWindow?
        init(pasteboard: NSPasteboard, location: NSPoint, window: NSWindow) {
            draggingPasteboard = pasteboard
            draggingLocation = location
            draggingDestinationWindow = window
        }
        var draggingSourceOperationMask: NSDragOperation { .copy }
        var draggedImageLocation: NSPoint { draggingLocation }
        var draggedImage: NSImage? { nil }
        var draggingSource: Any? { nil }
        var draggingSequenceNumber: Int { 1 }
        func slideDraggedImage(to screenPoint: NSPoint) {}
        var draggingFormation: NSDraggingFormation = .default
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                    searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        func resetSpringLoading() {}
    }

    private static func capture(_ window: NSWindow, _ name: String) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: FileManager.default.temporaryDirectory.appending(path: "memo-check-\(name).png"))
    }
}
#endif
