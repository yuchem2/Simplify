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
            await run(model: model)
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

    private static func run(model: AppModel) async {
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

    private static func textView(_ view: NSView) -> NSTextView? {
        if let found = view as? NSTextView, !found.isFieldEditor { return found }
        for subview in view.subviews {
            if let found = textView(subview) { return found }
        }
        return nil
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
