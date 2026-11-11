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

    private static func log(_ line: String) {
        lines.append(line)
        // Also on standard output, for a run started from a terminal that cannot read the container.
        print(line)
        fflush(stdout)
        // As it goes, so a crash midway still leaves what passed.
        try? lines.joined(separator: "\n").write(to: FileManager.default.temporaryDirectory.appending(path: "memo-check.txt"), atomically: true, encoding: .utf8)
    }

    private static func check(_ ok: Bool, _ what: String, _ got: @autoclosure () -> String = "") {
        log((ok ? "PASS  " : "FAIL  ") + what + (ok ? "" : "  got: \(got())"))
    }

    private static func run(model: AppModel, only: String) async {
        let tablesOnly = only == "tables"
        let memos = MemoBook(container: try! SimplifyStore.makeContainer(inMemory: true), isSaved: true)
        let calendars = CalendarController(container: try! SimplifyStore.makeCacheContainer(inMemory: true), calendar: model.calendar)
        // The panel's remembered settings are put back at the end.
        let kept = (model.isPanelHidden, model.isPanelWide, model.panelWidth, model.miniMonthWidth, model.calendarView)
        let keptLayout = model.memoLayout
        defer {
            model.calendarView = kept.4
            (model.isPanelHidden, model.isPanelWide, model.panelWidth, model.miniMonthWidth) = (kept.0, kept.1, kept.2, kept.3)
            model.memoLayout = keptLayout
        }
        model.memoLayout = .one
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

        if only == "memos" {
            await checkMemos(memos: memos, model: model, editor: editor, window: window, reset: reset, type: type, key: key)
            window.close()
            return
        }
        if only == "attachments" {
            await checkAttachments(draft: draft, editor: editor, window: window, reset: reset, key: key)
            window.close()
            return
        }
        if only == "tablepaste" {
            await checkTablePaste(draft: draft, editor: editor, window: window, reset: reset, key: key)
            window.close()
            return
        }
        if only == "mdpaste" {
            await checkMarkdownPaste(draft: draft, editor: editor, window: window, reset: reset, key: key)
            window.close()
            return
        }
        if only == "aabar" {
            await checkAaBar(memos: memos, model: model, editor: editor, window: window, reset: reset, type: type, key: key)
            window.close()
            return
        }
        if only == "order" {
            await checkOrder(memos: memos, model: model, editor: editor, window: window)
            window.close()
            return
        }
        if only == "links" {
            await checkLinks(draft: draft, editor: editor, window: window, reset: reset, type: type, key: key)
            window.close()
            return
        }
        if only == "stripfit" {
            await checkStripFit(model: model, window: window)
            window.close()
            return
        }
        if only == "chiplines" {
            await checkChipLines(memos: memos, model: model, editor: editor, window: window, reset: reset)
            window.close()
            return
        }
        if only == "find" {
            await checkFind(memos: memos, model: model, editor: editor, window: window, reset: reset, key: key)
            window.close()
            return
        }
        if only == "todofold" {
            await checkTodoFold(memos: memos, model: model, editor: editor, window: window)
            window.close()
            return
        }
        if only == "perf" {
            await checkPerf(memos: memos, model: model, editor: editor, window: window, reset: reset)
            window.close()
            return
        }
        if tablesOnly {
            await checkTables(draft: draft, editor: editor, window: window, model: model, reset: reset, type: type, key: key)
            window.close()
            return
        }

        // Periods by name: 오늘 · 이번 주 · 이번 달 for the ones holding today, dates alone otherwise.
        let now = model.today
        let today = Period(containing: now, scope: .day, calendar: model.calendar)
        let lastYear = Period(containing: model.calendar.date(byAdding: .year, value: -1, to: now)!, scope: .day, calendar: model.calendar)
        let thisWeek = Period(containing: now, scope: .week, calendar: model.calendar)
        let thisMonth = Period(containing: now, scope: .month, calendar: model.calendar)
        check(TodoNames.long(today, now: now).hasSuffix(" · 오늘") && TodoNames.short(today, now: now).hasSuffix(" 오늘"), "today's ToDo place says 오늘",
              TodoNames.long(today, now: now))
        check(TodoNames.long(thisWeek, now: now) == thisWeek.title + " · 이번 주" && TodoNames.long(thisMonth, now: now) == thisMonth.title + " · 이번 달",
              "this week's and month's say 이번 주, 이번 달", TodoNames.long(thisWeek, now: now))
        check(!TodoNames.long(lastYear, now: now).contains("·") && !TodoNames.short(lastYear, now: now).contains(" "), "another day is its date alone",
              TodoNames.long(lastYear, now: now))
        func names(_ chosen: Date) -> [String] {
            PeriodScope.allCases.map { DayPanel.scopeName($0, chosen: chosen, today: now, calendar: model.calendar) }
        }
        check(names(now) == ["오늘", "이번 주", "이번 달"], "the panel's periods read 오늘 · 이번 주 · 이번 달 on today", "\(names(now))")
        let yearAgo = model.calendar.date(byAdding: .year, value: -1, to: now)!
        check(names(yearAgo) == ["일", "주", "월"], "and 일 · 주 · 월 on a day a year ago", "\(names(yearAgo))")
        let sameMonth = model.calendar.date(byAdding: .day, value: model.calendar.component(.day, from: now) > 8 ? -8 : 8, to: now)!
        check(names(sameMonth) == ["일", "주", "이번 달"], "a day of this month in another week reads 일 · 주 · 이번 달", "\(names(sameMonth))")
        window.makeFirstResponder(editor)

        // A title and a heading read from the store get their own line heights, not the memo's
        // exact 26 pt, so their letters do not run into the next line.
        for (style, height) in [("title", TextStyle.title.lineHeight), ("heading", TextStyle.heading.lineHeight)] {
            let stored = #"{"runs":[{"p":"\#(style)","t":"온톨로지 특강"},{"t":"\n> 지식 그래프와"}],"v":2}"#
            await reset(MemoText.decode(stored.data(using: .utf8)!))
            var heights: [CGFloat] = []
            editor.textLayoutManager?.enumerateTextLayoutFragments(from: editor.textLayoutManager?.documentRange.location, options: [.ensuresLayout]) {
                heights.append($0.layoutFragmentFrame.height)
                return true
            }
            check(heights.first == height && heights.count == 2, "a stored \(style) line is \(height) pt tall", "\(heights)")
        }

        // ToDos push the memo under the panel's foot: the panel scrolls to the caret's line.
        let pushed = (1...25).compactMap { memos.todos.add("할 일 \($0)", to: model.panelPeriod) }
        try? await Task.sleep(for: .seconds(0.6))
        // The panel's own scroll view, around the memo's.
        var outerScroll: NSScrollView? {
            var view = editor.enclosingScrollView?.superview
            while let next = view, !(next is NSScrollView) { view = next.superview }
            return view as? NSScrollView
        }
        func caretShows() -> (Bool, String) {
            guard let outer = outerScroll else { return (false, "no panel scroll view") }
            let screen = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
            guard screen != .zero else { return (false, "no caret rect, first responder \(window.firstResponder === editor), range \(editor.selectedRange()), length \(editor.string.count)") }
            let caret = window.convertFromScreen(screen)
            let shown = outer.convert(outer.bounds, to: nil)
            return (shown.minY <= caret.minY && caret.maxY <= shown.maxY, "caret \(caret) panel \(shown)")
        }
        let longMemo = AttributedString((1...14).map { "줄 \($0)" }.joined(separator: "\n"))
        if let outer = outerScroll {
            outer.contentView.scroll(to: .zero)
            outer.reflectScrolledClipView(outer.contentView)
        }
        try? await Task.sleep(for: .seconds(0.4))
        window.makeFirstResponder(editor)
        try? await Task.sleep(for: .seconds(0.3))
        await reset(longMemo)
        // As typing there would: the memo's own view keeps its caret in sight.
        editor.scrollRangeToVisible(editor.selectedRange())
        try? await Task.sleep(for: .seconds(0.6))
        let atEnd = caretShows()
        check(atEnd.0, "the panel scrolls down to a caret under its foot", atEnd.1)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
        try? await Task.sleep(for: .seconds(0.6))
        let atStart = caretShows()
        check(atStart.0, "the panel scrolls back up to a caret over its top", atStart.1)
        let offset = outerScroll?.contentView.bounds.origin.y
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        try? await Task.sleep(for: .seconds(0.6))
        check(offset != nil && outerScroll?.contentView.bounds.origin.y == offset, "a caret already in view leaves the panel still", "\(String(describing: offset))")
        memos.todos.entries(for: model.panelPeriod).filter { entry in pushed.contains { $0.id == entry.todoID } }.forEach(memos.todos.remove)
        try? await Task.sleep(for: .seconds(0.4))
        window.makeFirstResponder(editor)
        try? await Task.sleep(for: .seconds(0.3))
        check(draft.hasFocus, "the memo has focus again after the scroll checks")

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

        // Lists go deeper than three levels, the bullets starting over.
        await reset(AttributedString("• 하나\n\t\t\t• 넷"))
        editor.setSelectedRange(NSRange(location: (letters as NSString).length, length: 0))
        await key(tab.0, tab.1)
        check(letters == "• 하나\n\t\t\t\t• 넷", "Tab takes an item past the third level", letters.debugDescription)
        func x(_ location: Int) -> CGFloat {
            window.convertFromScreen(editor.firstRect(forCharacterRange: NSRange(location: location, length: 1), actualRange: nil)).minX
        }
        let deepBullet = ("• 하나\n\t\t\t\t" as NSString).length
        check(abs(x(deepBullet) - x(0) - 4 * MemoLists.levelIndent) < 1.5, "a fifth-level bullet sits four levels in",
              "\(x(deepBullet) - x(0))")
        await key(returnKey.0, returnKey.1)
        await type("다섯")
        check(letters == "• 하나\n\t\t\t\t• 넷\n\t\t\t\t• 다섯", "Return goes on at the fifth level", letters.debugDescription)

        // A timeline line's children: lines with a tab under it start at its words, lists too.
        await reset(AttributedString("11.02 08:30 회의\n\t안건"))
        await key(returnKey.0, returnKey.1)
        check(letters == "11.02 08:30 회의\n\t안건\n\t", "Return on a time line's child makes another child", letters.debugDescription)
        await type("1. 견적서")
        await key(returnKey.0, returnKey.1)
        await type("시안")
        await key(tab.0, tab.1)
        check(letters == "11.02 08:30 회의\n\t안건\n\t1. 견적서\n\t\ta. 시안", "a list in a child counts from 1. and goes in with Tab",
              letters.debugDescription)
        try? await Task.sleep(for: .seconds(0.4))
        let words = x(("11.02 08:30 " as NSString).length)
        let child = x(("11.02 08:30 회의\n\t" as NSString).length)
        let item = x(("11.02 08:30 회의\n\t안건\n\t" as NSString).length)
        let inner = x(("11.02 08:30 회의\n\t안건\n\t1. 견적서\n\t\t" as NSString).length)
        check(abs(child - words) < 1.5, "a child's words start under the time line's words", "words \(words) child \(child)")
        check(abs(item - words - MemoLineStyler.listInset) < 1.5, "a list in a child starts there too, its inset in", "words \(words) item \(item)")
        check(abs(inner - words - MemoLineStyler.listInset - MemoLists.levelIndent) < 1.5, "and its next level one step in", "words \(words) inner \(inner)")
        capture(window, "timeline-children")
        // Empty items step out a level at a time, to the child, then out of the children.
        for _ in 0..<4 { await key(returnKey.0, returnKey.1) }
        check(letters == "11.02 08:30 회의\n\t안건\n\t1. 견적서\n\t\ta. 시안\n", "Return on empty children steps out to a plain line",
              letters.debugDescription)

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

    /// `SIMPLIFY_MEMO_CHECK=tablepaste`: tables through the clipboard, copied here and pasted back,
    /// and from Markdown, tab-split lines and HTML as Excel, Google Sheets and Numbers give it;
    /// filling a table from a cell, and one undo. The clipboard is put back as it was.
    private static func checkTablePaste(draft: MemoDraft, editor: NSTextView, window: NSWindow,
                                        reset: (AttributedString, Int?) async -> Void,
                                        key: (UInt16, String, NSEvent.ModifierFlags) async -> Void) async {
        let board = NSPasteboard.general
        // What was on the clipboard, every item and type, to put back at the end.
        let kept: [[(NSPasteboard.PasteboardType, Data)]] = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            board.clearContents()
            board.writeObjects(kept.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types { item.setData(data, forType: type) }
                return item
            })
        }
        func wait(_ seconds: Double = 0.4) async { try? await Task.sleep(for: .seconds(seconds)) }
        var letters: String { String(draft.text.characters) }
        func tables() -> [String: [String]] {
            var found: [String: [String]] = [:]
            for line in MemoTodoLines.lines(in: draft.text) where !line.isEmpty {
                if let id = draft.text.runs[line.lowerBound][MemoAttributes.Table.self] { found[id, default: []].append(String(draft.text[line].characters)) }
            }
            return found
        }
        func put(_ words: String? = nil, html: String? = nil) {
            board.clearContents()
            if let html { board.setString(html, forType: .html) }
            if let words { board.setString(words, forType: .string) }
        }
        func caret(_ location: Int) async {
            window.makeFirstResponder(editor)
            editor.setSelectedRange(NSRange(location: location, length: 0))
            await wait(0.3)
        }

        // Ours: copied with a table in it, pasted back as a new table, formatting kept.
        var bold = AttributeContainer()
        bold[MemoAttributes.Bold.self] = true
        var ours = MemoTablePaste.table([[MemoTablePaste.Cell("품목"), MemoTablePaste.Cell("값")], [MemoTablePaste.Cell("사과"), MemoTablePaste.Cell("1,200", bold: true)]], id: "t1")
        ours += AttributedString("\n")
        await reset(ours, nil)
        draft.selection = AttributedTextSelection(range: draft.text.startIndex..<draft.text.characters.index(before: draft.text.endIndex))
        await wait(0.3)
        draft.copySelection()
        let types = Set(board.types ?? [])
        check(types.contains(.string) && types.contains(.html) && types.contains(MemoTableClipboard.memoType), "copying a table writes words, HTML and the memo's own", "\(types)")
        check(board.string(forType: .string) == "품목\t값\n사과\t1,200", "the words are tab-split", board.string(forType: .string)?.debugDescription ?? "nil")
        check(board.string(forType: .html)?.contains("<table>") == true, "the HTML has a table", board.string(forType: .html) ?? "nil")
        await caret((editor.string as NSString).length)
        await key(9, "v", [.command])
        var found = tables()
        check(found.count == 2 && found.values.allSatisfy { $0 == ["품목\t값", "사과\t1,200"] }, "⌘V puts it back as a table of its own", "\(found)")
        check(draft.text.runs.filter { $0[MemoAttributes.Bold.self] == true }.count == 2, "its cell formatting comes too")
        editor.undoManager?.undo()
        await wait()
        check(tables().count == 1 && letters == "품목\t값\n사과\t1,200\n", "one undo takes the paste back", letters.debugDescription)

        // Markdown after words on the caret's line: the table starts on the next line.
        await reset(AttributedString("앞 글"), nil)
        put("| 항목 | 수 |\n|---|---:|\n| 사과 | 3 |\n| 배 | 5 |")
        await key(9, "v", [.command])
        found = tables()
        check(letters == "앞 글\n항목\t수\n사과\t3\n배\t5" && found.count == 1, "a Markdown table goes in as a table under the line", letters.debugDescription)
        capture(window, "tablepaste-markdown")

        // Tab-split lines as the 메모 app's table gives them.
        await reset(AttributedString(""), nil)
        put("측정\t결과\n단일 케이스 12개 × 3회 (14:1x)\t화면 요청은 모두 1번이었습니다.\n상품명 10개 × 3회 × 3구조\t평균 S4 14.9초")
        draft.paste()
        await wait()
        found = tables()
        check(found.values.first?.count == 3 && found.values.first?.first == "측정\t결과", "the 메모 app's table words become a table", "\(found)")
        // A list with tabs stays words.
        await reset(AttributedString(""), nil)
        put("• 하나\t둘\n• 셋\t넷")
        draft.paste()
        await wait()
        check(tables().isEmpty && letters == "• 하나\t둘\n• 셋\t넷", "list lines with tabs stay words", letters.debugDescription)

        // HTML as Excel gives it: a merged cell, a line break in a cell, shown numbers.
        await reset(AttributedString(""), nil)
        put("이름\t합계\n사과 빨강\t1,200\t12%", html: """
        <html><body><table border=0><tr><td>이름</td><td colspan=2 style='font-weight:700'>합계</td></tr>        <tr><td>사과<br>빨강</td><td align=right>1,200</td><td>12%</td></tr></table></body></html>
        """)
        draft.paste()
        await wait()
        found = tables()
        check(found.values.first == ["이름\t합계\t", "사과 빨강\t1,200\t12%"], "Excel's HTML: merged cell spread, line break a space", "\(found)")
        check(draft.text.runs.contains { $0[MemoAttributes.Bold.self] == true && String(draft.text[$0.range].characters) == "합계" }, "a bold cell stays bold")
        capture(window, "tablepaste-excel")
        // Google Sheets' HTML, with empty edge rows; words around a web page's table.
        await reset(AttributedString(""), nil)
        put("a\tb", html: "<meta charset='utf-8'><google-sheets-html-origin><table><tbody><tr><td></td><td></td></tr><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></tbody></table>")
        draft.paste()
        await wait()
        check(tables().values.first == ["a\tb", "c\td"], "Google Sheets' HTML, empty edge row dropped", "\(tables())")
        await reset(AttributedString(""), nil)
        put("x", html: "<p>위 문단</p><table><tr><th>열1</th><th>열2</th></tr><tr><td>1</td><td>2</td></tr></table><p>아래 문단</p>")
        draft.paste()
        await wait()
        check(letters.hasPrefix("위 문단\n열1\t열2\n1\t2\n아래 문단") && tables().count == 1, "a web page's words stay around its table", letters.debugDescription)
        // HTML without a table: as before (the words).
        await reset(AttributedString(""), nil)
        put("그냥 글", html: "<p>그냥 <b>글</b></p>")
        check(MemoTableClipboard.read() == nil, "HTML with no table is no table paste")

        // In a table cell: the table fills from there, growing where it runs past.
        var cells = MemoTablePaste.table([[MemoTablePaste.Cell("가"), MemoTablePaste.Cell("나")], [MemoTablePaste.Cell("다"), MemoTablePaste.Cell("라")]], id: "t9")
        cells += AttributedString("\n끝")
        await reset(cells, nil)
        await caret(("가\t" as NSString).length)
        put("1\t2\n3\t4\n5\t6")
        draft.paste()
        await wait()
        found = tables()
        check(found["t9"] == ["가\t1\t2", "다\t3\t4", "\t5\t6"] && letters.hasSuffix("\n끝"), "pasting in a cell fills right and down, rows and columns added", "\(found)")
        check(editor.selectedRange().location == ("가\t1\t2\n다\t3\t4\n\t5\t6" as NSString).length, "the caret ends in the last cell filled", "\(editor.selectedRange())")
        capture(window, "tablepaste-fill")
        editor.undoManager?.undo()
        await wait()
        check(tables()["t9"] == ["가\t나", "다\t라"], "one undo puts the table back")

        // ⌘C from the keyboard; a row copied with its line break, pasted in a cell, fills.
        var keyed = MemoTablePaste.table([[MemoTablePaste.Cell("ㄱ"), MemoTablePaste.Cell("ㄴ")], [MemoTablePaste.Cell("ㄷ"), MemoTablePaste.Cell("ㄹ")]], id: "k1")
        keyed += AttributedString("\n")
        await reset(keyed, nil)
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: ("ㄱ\tㄴ\n" as NSString).length))
        await wait(0.3)
        await key(8, "c", [.command])
        check(board.data(forType: MemoTableClipboard.memoType) != nil, "⌘C on a row with its line break writes the memo's own")
        await caret(("ㄱ\tㄴ\nㄷ\t" as NSString).length)
        await key(9, "v", [.command])
        check(tables()["k1"] == ["ㄱ\tㄴ\t", "ㄷ\tㄱ\tㄴ"], "the row fills from the caret's cell, a column added, not split", "\(tables())")
        // A word inside a cell copies as a word, and pastes into another cell as a word.
        await reset(keyed, nil)
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 1))
        await wait(0.3)
        await key(8, "c", [.command])
        check(board.data(forType: MemoTableClipboard.memoType) == nil, "a word in a cell is not copied as a table")
        await caret(("ㄱ\tㄴ\nㄷ" as NSString).length)
        // Not ours: the text view's own paste (the menu's, done directly, as the menu item is
        // only enabled while this window is the key one).
        check(MemoTableClipboard.read() == nil, "a word copied in a cell is no table paste")
        editor.paste(nil)
        await wait()
        check(tables()["k1"] == ["ㄱ\tㄴ", "ㄷㄱ\tㄹ"], "and goes into the cell at the caret", "\(tables())")
        // The memo's own tab-aligned lines (no table) paste back as lines.
        await reset(AttributedString("이름\t홍길동\n전화\t010\n"), nil)
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: ("이름\t홍길동\n전화\t010" as NSString).length))
        await wait(0.3)
        await key(8, "c", [.command])
        await caret((editor.string as NSString).length)
        check(MemoTableClipboard.read() == nil, "the memo's own tab lines are no table paste")
        editor.paste(nil)
        await wait()
        check(tables().isEmpty && letters == "이름\t홍길동\n전화\t010\n이름\t홍길동\n전화\t010", "the memo's tab lines paste back as lines", letters.debugDescription)
        // RTF alone, as Numbers or Word may give it.
        if let html = "<table><tr><td>열A</td><td>열B</td></tr><tr><td>1</td><td>2</td></tr></table>".data(using: .utf8),
           let rich = try? NSAttributedString(data: html, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                    .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil),
           let rtf = try? rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            await reset(AttributedString(""), nil)
            board.clearContents()
            board.setData(rtf, forType: .rtf)
            board.setString("열A\t열B", forType: .string)
            draft.paste()
            await wait()
            check(tables().values.first == ["열A\t열B", "1\t2"], "an RTF table becomes a table", "\(tables()) \(letters.debugDescription)")
        }

        // In a cell, words and a table together: under the table, the table left whole.
        await reset(keyed, nil)
        await caret(("ㄱ" as NSString).length)
        put("앞 글\n| a | b |\n|---|---|\n| 1 | 2 |")
        draft.paste()
        await wait()
        found = tables()
        check(found["k1"] == ["ㄱ\tㄴ", "ㄷ\tㄹ"] && letters.hasPrefix("ㄱ\tㄴ\nㄷ\tㄹ\n앞 글\na\tb\n1\t2"), "words and a table pasted in a cell go under the table",
              letters.debugDescription)

        // Very large: asked first, nothing in yet.
        await reset(AttributedString(""), nil)
        put((0..<210).map { "칸\($0)\t값" }.joined(separator: "\n"))
        draft.paste()
        await wait(0.6)
        check(letters.isEmpty, "a table past 200 rows asks before going in", "\(letters.count) letters")
        check(NSApp.windows.contains { $0 !== window && $0.isVisible && $0 is NSPanel }, "and the question shows, as an ink menu")
        await key(53, "\u{1b}", [])
    }

    /// `SIMPLIFY_MEMO_CHECK=mdpaste`: Markdown pasted with ⌘V as the memo's formatting, ⌘Z twice
    /// (its marks, then nothing), 일반 텍스트로 붙여넣기 as typed, left as typed in a code block and
    /// a table cell, a heading after words starting its own line, a table inside Markdown. The
    /// clipboard is put back as it was.
    private static func checkMarkdownPaste(draft: MemoDraft, editor: NSTextView, window: NSWindow,
                                           reset: (AttributedString, Int?) async -> Void,
                                           key: (UInt16, String, NSEvent.ModifierFlags) async -> Void) async {
        let board = NSPasteboard.general
        let kept: [[(NSPasteboard.PasteboardType, Data)]] = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            board.clearContents()
            board.writeObjects(kept.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types { item.setData(data, forType: type) }
                return item
            })
        }
        func wait(_ seconds: Double = 0.4) async { try? await Task.sleep(for: .seconds(seconds)) }
        var letters: String { String(draft.text.characters) }
        func put(_ words: String) {
            board.clearContents()
            board.setString(words, forType: .string)
        }
        func caret(_ location: Int) async {
            window.makeFirstResponder(editor)
            editor.setSelectedRange(NSRange(location: location, length: 0))
            await wait(0.3)
        }
        /// The letters carrying `key`, joined by `|`.
        func marked<K: AttributedStringKey>(_ key: K.Type) -> String where K.Value: Hashable & Sendable {
            draft.text.runs[key].compactMap { value, range in value == nil ? nil : String(draft.text[range].characters) }.joined(separator: "|")
        }

        // The memo's first edit is left alone: a new memo's first save takes the undo steps
        // with it, whatever was pasted (so does a table's), which is not what is checked here.
        await reset(AttributedString("준비"), nil)
        editor.insertText("!", replacementRange: editor.selectedRange())
        await wait(1.5)

        // ⌘V: the memo's formatting, no marks.
        let answer = """
        ## 회의 정리

        이번 주 **결론**은 *범위를 줄이고* 마감을 지키는 것. 자세한 건 [문서](https://example.com/doc)를 보세요.

        - 배포는 `화요일`
          - QA는 ~~월요일~~ 수요일
        1. 첫째
        2. 둘째

        > 인용한 말

        - [ ] 남은 일
        - [x] 끝난 일

        ---

        넓이는 $\\pi r^2$ 이에요.

        ```swift
        let a = 1
        ```
        """
        await reset(AttributedString(""), nil)
        put(answer)
        await key(9, "v", [.command])
        await wait()
        let expected = "회의 정리\n\n이번 주 결론은 범위를 줄이고 마감을 지키는 것. 자세한 건 문서를 보세요.\n\n- 배포는 화요일\n\t- QA는 월요일 수요일\n1. 첫째\n2. 둘째\n\n> 인용한 말\n\n- 남은 일\n- 끝난 일\n\n────\n\n넓이는 \\pi r^2 이에요.\n\nlet a = 1"
        check(letters == expected, "⌘V on Markdown puts in the memo's letters, no marks", letters.debugDescription)
        check(draft.text.runs.contains { $0[MemoAttributes.Paragraph.self] == .heading && String(draft.text[$0.range].characters) == "회의 정리" },
              "## is a 머리말 line")
        check(marked(MemoAttributes.Bold.self) == "결론" && marked(MemoAttributes.Italic.self) == "범위를 줄이고", "bold and italic", marked(MemoAttributes.Bold.self))
        check(marked(MemoAttributes.InlineCode.self) == "화요일" && marked(MemoAttributes.Code.self) == "let a = 1", "inline code and a code block",
              marked(MemoAttributes.Code.self))
        check(marked(MemoAttributes.Strike.self) == "월요일|끝난 일", "strikethrough, and a done ToDo line struck", marked(MemoAttributes.Strike.self))
        check(draft.text.runs[MemoAttributes.Link.self].compactMap { $0.0 } == ["https://example.com/doc"], "the link keeps its address")
        check(marked(MemoAttributes.Math.self) == "\\pi r^2", "an inline formula", marked(MemoAttributes.Math.self))
        check(draft.text.runs.allSatisfy { $0[MemoAttributes.Todo.self] == nil }, "ToDo lines make no chips")
        check(editor.selectedRange().location == (expected as NSString).length, "the caret ends after the paste", "\(editor.selectedRange())")
        capture(window, "mdpaste-format")

        // ⌘Z twice: first the words with their marks, then nothing.
        editor.undoManager?.undo()
        await wait()
        check(letters == answer, "the first ⌘Z leaves the Markdown as typed", letters.debugDescription)
        check(marked(MemoAttributes.Bold.self).isEmpty && marked(MemoAttributes.Paragraph.self).isEmpty, "with no formatting")
        capture(window, "mdpaste-undo")
        editor.undoManager?.undo()
        await wait()
        check(letters.isEmpty, "the second ⌘Z takes the paste away", letters.debugDescription)

        // 일반 텍스트로 붙여넣기: as typed, one step.
        await reset(AttributedString(""), nil)
        put("**굵게** 그대로\n| a | b |\n|---|---|\n| 1 | 2 |")
        await caret(0)
        await key(9, "v", [.command, .option, .shift])
        await wait()
        check(letters == "**굵게** 그대로\n| a | b |\n|---|---|\n| 1 | 2 |" && marked(MemoAttributes.Bold.self).isEmpty && marked(MemoAttributes.Table.self).isEmpty,
              "일반 텍스트로 붙여넣기 leaves marks and tables as typed", letters.debugDescription)
        editor.undoManager?.undo()
        await wait()
        check(letters.isEmpty, "and one ⌘Z takes it away", letters.debugDescription)

        // Tab-split words with a sign in them still make a table, as before.
        put("name\t_id_\nfoo\tbar")
        if case .pieces? = MemoTableClipboard.read() { check(true, "a tab grid with a sign in it is still a table") } else { check(false, "a tab grid with a sign in it is still a table") }
        // Rich text with links keeps going to the linked paste.
        board.clearContents()
        board.setString("<a href=\"https://a.com\">*글*</a>", forType: .html)
        board.setString("*글*", forType: .string)
        check(MemoTableClipboard.read() == nil, "rich text with links is no Markdown paste")

        // Plain words are no Markdown paste.
        put("그냥 글, snake_case_name, $5")
        check(MemoTableClipboard.read() == nil, "words without a sure sign are no Markdown paste")

        // In a code block: as typed.
        var code = AttributedString("let a = 1")
        code[MemoAttributes.Code.self] = true
        await reset(code, nil)
        await caret(("let a = 1" as NSString).length)
        put(" // **그대로**")
        // Left to the text view's own paste (done directly: its menu item is only on while this
        // window is the key one).
        check(!MemoTableClipboard.paste(into: editor, draft: draft), "in a code block Markdown is no paste of ours")
        editor.paste(nil)
        await wait()
        check(letters == "let a = 1 // **그대로**" && marked(MemoAttributes.Bold.self).isEmpty, "in a code block Markdown stays as typed", letters.debugDescription)

        // In a table cell: as typed.
        var cells = MemoTablePaste.table([[MemoTablePaste.Cell("가"), MemoTablePaste.Cell("나")], [MemoTablePaste.Cell("다"), MemoTablePaste.Cell("라")]], id: "m1")
        cells += AttributedString("\n끝")
        await reset(cells, nil)
        await caret(("가" as NSString).length)
        put("**굵**")
        check(!MemoTableClipboard.paste(into: editor, draft: draft), "in a table cell Markdown is no paste of ours")
        editor.paste(nil)
        await wait()
        check(letters.hasPrefix("가**굵**\t나\n") && marked(MemoAttributes.Bold.self).isEmpty, "in a table cell Markdown stays as typed", letters.debugDescription)

        // A heading after words on the caret's line starts the next line.
        await reset(AttributedString("앞 글"), nil)
        put("## 머리말\n본문 **굵게**")
        await key(9, "v", [.command])
        await wait()
        check(letters == "앞 글\n머리말\n본문 굵게", "a heading pasted after words goes on the next line", letters.debugDescription)
        check(draft.text.runs.contains { $0[MemoAttributes.Paragraph.self] == .heading && String(draft.text[$0.range].characters) == "머리말" }
              && draft.text.runs.allSatisfy { !($0[MemoAttributes.Paragraph.self] != nil && String(draft.text[$0.range].characters).contains("앞")) },
              "and only that line is a heading")
        capture(window, "mdpaste-heading")

        // A table inside Markdown.
        await reset(AttributedString(""), nil)
        put("**표**\n\n| 항목 | 값 |\n|---|---|\n| 사과 | **3** |\n\n끝")
        await key(9, "v", [.command])
        await wait()
        let tableIDs = Set(draft.text.runs.compactMap { $0[MemoAttributes.Table.self] })
        check(letters == "표\n\n항목\t값\n사과\t3\n\n끝" && tableIDs.count == 1, "a table in Markdown is a memo table", letters.debugDescription)
        check(marked(MemoAttributes.Bold.self) == "표|3", "its cell keeps bold", marked(MemoAttributes.Bold.self))
        capture(window, "mdpaste-table")
    }

    /// `SIMPLIFY_MEMO_CHECK=stripfit`: the pinned toolbar inside the panel at its narrowest and at
    /// its usual width, in 하나씩 and 모아 보기, so it never makes the panel wider than its place.
    private static func checkStripFit(model: AppModel, window: NSWindow) async {
        let pin = MemoBarPin.shared
        let wasPinned = pin.isPinned
        defer { pin.isPinned = wasPinned }
        pin.isPinned = true
        model.panelMode = .normal
        for layout in [AppModel.MemoLayout.one, .all] {
            model.memoLayout = layout
            for width in [PanelLayout.normalMin, 340, 420] {
                model.panelWidth = width
                try? await Task.sleep(for: .seconds(1))
                let strip = MemoBarFrames.byName["서식 막대"] ?? .null
                let room = width - 2 * Metrics.spaceXxl
                log("INFO  \(layout) panel \(Int(width)): strip \(strip.integral)")
                check(!strip.isNull && strip.width <= room + 0.5, "\(layout) \(Int(width)): the toolbar fits the panel", "\(strip.width) > \(room)")
                capture(window, "stripfit-\(layout)-\(Int(width))")
            }
        }
    }

    /// `SIMPLIFY_MEMO_CHECK=aabar`: the Aa bar under its button (하나씩 with tabs, 모아 보기), open
    /// while picking and closed by Esc, typing and a click elsewhere, the shortcut card, alignment,
    /// the pinned toolbar, inline code against a code block, and the lists' inset.
    private static func checkAaBar(memos: MemoBook, model: AppModel, editor: NSTextView, window: NSWindow,
                                   reset: (AttributedString, Int?) async -> Void, type: (String) async -> Void,
                                   key: (UInt16, String, NSEvent.ModifierFlags) async -> Void) async {
        let draft = memos.draft
        let pin = MemoBarPin.shared
        let wasPinned = pin.isPinned
        defer { pin.isPinned = wasPinned }
        pin.isPinned = false
        func wait(_ seconds: Double = 0.4) async { try? await Task.sleep(for: .seconds(seconds)) }
        var letters: String { String(draft.text.characters) }
        /// The accessibility element with this label in the window, as SwiftUI makes them.
        /// How many of the pinned toolbar show: its place is noted while it is on screen.
        func strips() -> Int { MemoBarFrames.byName["서식 막대"] == nil ? 0 : 1 }
        /// A point in the content's top-left coordinates (as SwiftUI's global frames are) in the window's.
        func inWindow(_ top: CGPoint) -> CGPoint {
            let content = window.contentView!
            return content.convert(content.isFlipped ? top : CGPoint(x: top.x, y: content.bounds.height - top.y), to: nil)
        }
        /// A real click (down and up) at a point in the content (top-left origin).
        func click(at top: CGPoint) async {
            let local = inWindow(top)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    NSApp.postEvent(event, atStart: false)
                }
            }
            await wait()
        }
        func press(_ label: String) async -> Bool {
            // Once the panel has settled: a toolbar just put in moves things for a moment.
            var last = CGRect.null, same = 0
            for _ in 0..<20 where same < 3 {
                let now = (MemoBarFrames.byName[label].map(draft.inContent) ?? .null).union(draft.inContent(draft.aaFrame))
                same = now == last ? same + 1 : 0
                last = now
                await wait(0.25)
            }
            guard let frame = MemoBarFrames.byName[label].map(draft.inContent) else { return false }
            // The pinned toolbar's row is right under the rule's Aa (SwiftUI does not always report
            // the toolbar's own place again once the panel has moved around it).
            let y = pin.isPinned ? draft.inContent(draft.aaFrame).maxY + Metrics.spaceM + frame.height / 2 : frame.midY
            // The pin ends the row under Aa's right end.
            let x = pin.isPinned && label == "서식 막대 고정 풀기" ? draft.inContent(draft.aaFrame).maxX - frame.width / 2 : frame.midX
            await click(at: CGPoint(x: x, y: y))
            return true
        }
        /// The bar's top against the Aa button's foot, and their right ends.
        func barUnderAa() -> (Bool, String) {
            let aa = draft.aaFrame, bar = draft.paragraphBarFrame
            let ok = !bar.isNull && bar.minY >= aa.maxY - 0.5 && bar.minY - aa.maxY <= Metrics.spaceS && abs(bar.maxX - aa.maxX) < 1.5
            return (ok, "aa \(aa) bar \(bar)")
        }
        guard draft.period != nil else { return log("FAIL  no open period") }

        // The title bar with no calendar connected: 캘린더 연결, light and dark.
        for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: look)
            await wait(0.6)
            if let frame = window.contentView?.superview, let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
                frame.cacheDisplay(in: frame.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: FileManager.default.temporaryDirectory.appending(path: "memo-check-titlebar-\(name).png"))
            }
        }
        NSApp.appearance = nil
        // 하나씩 with two memos, so the tabs stand between the rule and the memo.
        model.memoLayout = .one
        await reset(AttributedString("첫 메모"), nil)
        draft.flush()
        draft.newMemo()
        draft.commitRename(toBody: true)
        await wait(0.6)
        window.makeFirstResponder(textView(window.contentView!))
        await wait()
        guard let live = textView(window.contentView!) else { return log("FAIL  no memo text view") }
        await reset(AttributedString("회의 메모\n다음 주 일정"), 0)
        // After the period has opened: opening a memo closes the bar.
        await wait(0.6)
        draft.showsParagraphBar = true
        await wait(0.6)
        var under = barUnderAa()
        check(under.0, "하나씩 with tabs: the bar hangs right under Aa, right ends lined up", under.1)
        capture(window, "aabar-one")

        // Picks keep it open: 제목, then 가운데.
        check(await press("제목"), "the bar's 제목 is there")
        check(draft.paragraph == .title && draft.showsParagraphBar, "제목 picked, the bar stays open",
              "\(String(describing: draft.paragraph)) open \(draft.showsParagraphBar)")
        check(await press("가운데 정렬"), "the bar has 가운데 정렬")
        check(draft.align == .center && draft.showsParagraphBar, "가운데 picked as well, still open",
              "\(String(describing: draft.align)) open \(draft.showsParagraphBar)")
        check(live.window?.firstResponder === live, "the caret is back in the memo after a pick")
        await wait()
        let first = live.firstRect(forCharacterRange: NSRange(location: 0, length: 1), actualRange: nil)
        let second = live.firstRect(forCharacterRange: NSRange(location: ("회의 메모\n" as NSString).length, length: 1), actualRange: nil)
        check(first.minX - second.minX > 40, "the centred title is drawn in from the left line", "title \(first.minX) body \(second.minX)")
        capture(window, "aabar-picked")

        // Esc, typing and a click elsewhere close it.
        await key(53, "\u{1b}", [])
        check(!draft.showsParagraphBar, "Esc closes the bar")
        draft.showsParagraphBar = true
        await wait()
        live.setSelectedRange(NSRange(location: (live.string as NSString).length, length: 0))
        await key(0, "a", [])
        check(!draft.showsParagraphBar && letters.hasSuffix("a"), "a letter typed closes the bar and goes in", letters.debugDescription)
        draft.showsParagraphBar = true
        await wait()
        let content = window.contentView!
        await click(at: CGPoint(x: 60, y: 300))
        check(!draft.showsParagraphBar, "a click outside closes the bar")
        window.makeFirstResponder(live)
        await wait()

        // The shortcut card (a posted pointer move does not reach SwiftUI's hover, so it is shown
        // as the hover would show it): under Aa, and clicks go through it.
        draft.showsShortcutCard = true
        await wait(0.6)
        capture(window, "aabar-card")
        draft.showsShortcutCard = false

        // 모아 보기: still under Aa.
        model.memoLayout = .all
        await wait(1)
        draft.showsParagraphBar = true
        await wait(0.6)
        under = barUnderAa()
        check(under.0, "모아 보기: the bar hangs right under Aa", under.1)
        capture(window, "aabar-all")
        draft.showsParagraphBar = false
        model.memoLayout = .one
        await wait(1)
        guard let one = textView(window.contentView!) else { return log("FAIL  no memo text view") }
        window.makeFirstResponder(one)
        await wait()

        // Alignment: the shortcut and the menu, left again, not on a list line.
        func reset2(_ text: AttributedString, _ caret: Int) async {
            draft.text = text
            await wait()
            one.setSelectedRange(NSRange(location: caret, length: 0))
            await wait(0.3)
        }
        await reset2(AttributedString("오른쪽\n• 목록"), 0)
        // The 서식 menu's items reach the memo through the scene's focused value, which this
        // check's own window does not give them; the calls are the ones the items make.
        draft.setAlign(.right)
        await wait()
        check(draft.align == .right, "오른쪽 정렬 sets the line right", String(describing: draft.align))
        draft.setAlign(nil)
        await wait()
        check(draft.align == nil && draft.text.runs.allSatisfy { $0[MemoAttributes.Align.self] == nil }, "왼쪽 정렬 sets it left again",
              String(describing: draft.align))
        one.setSelectedRange(NSRange(location: ("오른쪽\n• " as NSString).length, length: 0))
        await wait(0.3)
        draft.setAlign(.center)
        check(draft.text.runs.allSatisfy { $0[MemoAttributes.Align.self] == nil }, "a list line stays left")
        var centred = AttributeContainer()
        centred[MemoAttributes.Align.self] = .center
        let mirrored = NotesHTML.body(name: "이름", text: AttributedString("가운데", attributes: centred)) ?? ""
        check(mirrored.contains(#"<div style="text-align: center">가운데</div>"#), "the 메모 app's note is centred too", mirrored)
        var menuKeys: [String] = []
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if item.title.hasSuffix("정렬") {
                    let shift = item.keyEquivalentModifierMask.contains(.shift) || item.keyEquivalent != item.keyEquivalent.lowercased()
                    menuKeys.append("\(item.title) \(shift ? "⇧" : "")\(item.keyEquivalent.lowercased())")
                }
                if let sub = item.submenu { walk(sub) }
            }
        }
        if let main = NSApp.mainMenu { walk(main) }
        check(menuKeys == ["왼쪽 정렬 ⇧l", "가운데 정렬 ⇧e", "오른쪽 정렬 ⇧r"], "서식 has the three alignments with ⌘⇧L E R", "\(menuKeys)")
        // None of them is another menu item's key.
        var taken: [String: [String]] = [:]
        func keys(_ menu: NSMenu) {
            for item in menu.items {
                if !item.keyEquivalent.isEmpty {
                    let mask = item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control]).rawValue
                    taken["\(item.keyEquivalent.lowercased())/\(mask | (item.keyEquivalent != item.keyEquivalent.lowercased() ? NSEvent.ModifierFlags.shift.rawValue : 0))", default: []].append(item.title)
                }
                if let sub = item.submenu { keys(sub) }
            }
        }
        if let main = NSApp.mainMenu { keys(main) }
        let clashes = taken.values.filter { $0.count > 1 && $0.contains { $0.hasSuffix("정렬") } }
        check(clashes.isEmpty, "no other menu item shares an alignment key", "\(clashes)")

        // Pinned: one toolbar under the rule, working on the memo being written; 모아 보기 too.
        await reset2(AttributedString("고정\n둘째"), 0)
        pin.isPinned = true
        await wait(0.6)
        check(strips() == 1, "pinned: the toolbar under the rule", "\(strips())")
        capture(window, "aabar-pinned")
        await wait(1.5)
        check(await press("가운데 정렬"), "the toolbar has 가운데 정렬")
        check(draft.align == .center, "the toolbar's 가운데 sets the caret's line", String(describing: draft.align))
        check(await press("글머리 기호 목록"), "the toolbar has the bullet list")
        check(letters.hasPrefix("• 고정"), "the toolbar's bullet makes a list item", letters.debugDescription)
        model.memoLayout = .all
        await wait(2)
        check(strips() == 1, "모아 보기 pinned: the toolbar is there", "\(strips())")
        // The caret on the body line, not the list item.
        draft.selection = AttributedTextSelection(insertionPoint: draft.text.endIndex)
        await wait(0.3)
        check(await press("오른쪽 정렬"), "모아 보기: the toolbar's 오른쪽 정렬")
        check(draft.align == .right, "모아 보기: it sets the memo being written's line", String(describing: draft.align))
        capture(window, "aabar-pinned-all")
        check(await press("서식 막대 고정 풀기"), "the toolbar's pin is at its end")
        check(!pin.isPinned && strips() == 0, "the pin floats the bar again", "pinned \(pin.isPinned)")
        model.memoLayout = .one
        await wait(1)
        guard let back = textView(window.contentView!) else { return log("FAIL  no memo text view") }
        window.makeFirstResponder(back)
        await wait()

        // Inline code: letters picked within a line; a code block otherwise.
        func reset3(_ text: AttributedString, _ range: NSRange) async {
            draft.text = text
            await wait()
            back.setSelectedRange(range)
            await wait(0.3)
        }
        let line = "설치는 install.sh 로 해요"
        let pick = (line as NSString).range(of: "install.sh")
        await reset3(AttributedString(line + "\n다음 줄"), pick)
        draft.toggleCode()
        await wait()
        let inline = draft.text.runs.filter { $0[MemoAttributes.InlineCode.self] == true }.map { String(draft.text[$0.range].characters) }
        check(inline == ["install.sh"], "{ } on letters within a line: just those letters", "\(inline)")
        check(draft.text.runs.allSatisfy { $0[MemoAttributes.Code.self] == nil }, "and no code block")
        check(draft.isCode, "{ } shows switched on for them")
        back.setSelectedRange(NSRange(location: 0, length: 0))
        await wait(0.3)
        let shownFont = back.textStorage?.attribute(.font, at: pick.location, effectiveRange: nil) as? NSFont
        check(shownFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true, "inline code is fixed-width", String(describing: shownFont))
        let save = MemoText.encode(draft.text).map { String(decoding: $0, as: UTF8.self) } ?? ""
        check(save.contains(#""kc":true"#) && save.contains(#""v":1"#), "saved as kc, still version 1", save)
        let again = MemoText.encode(MemoText.decode(MemoText.encode(draft.text))).map { String(decoding: $0, as: UTF8.self) } ?? ""
        check(again == save, "and read back the same", again)
        let html = NotesHTML.body(name: "이름", text: draft.text) ?? ""
        check(html.contains("<tt>install.sh</tt>") && !html.contains("<tt>설치는"), "the 메모 app gets the letters fixed-width", html)
        // Typing at the line's front does not spread it.
        back.setSelectedRange(NSRange(location: 0, length: 0))
        back.insertText("✓ ", replacementRange: back.selectedRange())
        await wait()
        let still = draft.text.runs.filter { $0[MemoAttributes.InlineCode.self] == true }.map { String(draft.text[$0.range].characters) }
        check(still == ["install.sh"], "typing on its line leaves inline code as it was", "\(still)")
        // Again on the same letters: plain.
        back.setSelectedRange(NSRange(location: pick.location + 2, length: pick.length))
        await wait(0.3)
        draft.toggleCode()
        await wait()
        check(draft.text.runs.allSatisfy { $0[MemoAttributes.InlineCode.self] == nil }, "{ } again takes it off")
        // No pick, the whole line, or across lines: a code block.
        await reset3(AttributedString(line + "\n다음 줄"), NSRange(location: 3, length: 0))
        draft.toggleCode()
        await wait()
        check(draft.text.runs.filter { $0[MemoAttributes.Code.self] == true }.map { String(draft.text[$0.range].characters) } == [line],
              "{ } with a caret: the line is a code block")
        await reset3(AttributedString(line + "\n다음 줄"), NSRange(location: 3, length: (line as NSString).length))
        draft.toggleCode()
        await wait()
        check(draft.text.runs.contains { $0[MemoAttributes.Code.self] == true && String(draft.text[$0.range].characters).contains("다음 줄") }
              && draft.text.runs.allSatisfy { $0[MemoAttributes.InlineCode.self] == nil }, "{ } across lines: a code block of both")
        // Return at the end of inline code: the next line is plain; ⌘⇧C with a caret typing it stops it.
        var codeTail = AttributedString("실행: ")
        var inlineOn = AttributeContainer()
        inlineOn[MemoAttributes.InlineCode.self] = true
        codeTail += AttributedString("make", attributes: inlineOn)
        await reset3(codeTail, NSRange(location: ("실행: make" as NSString).length, length: 0))
        await key(36, "\r", [])
        await type("다음")
        let carried = draft.text.runs.filter { $0[MemoAttributes.InlineCode.self] == true }
            .map { String(draft.text[$0.range].characters).trimmingCharacters(in: .newlines) }
        check(carried == ["make"], "Return after inline code: the next line types plain", "\(carried)")
        await reset3(codeTail, NSRange(location: ("실행: make" as NSString).length, length: 0))
        check(draft.isCode, "a caret after inline code shows { } on")
        draft.toggleCode()
        await type("다음")
        check(draft.text.runs.allSatisfy { $0[MemoAttributes.Code.self] == nil }
              && draft.text.runs.filter { $0[MemoAttributes.InlineCode.self] == true }.map { String(draft.text[$0.range].characters) } == ["make"],
              "{ } there stops inline code, no code block", "\(draft.text.runs.map { String(draft.text[$0.range].characters) })")
        // A timeline line's child keeps to the time's column; an empty line goes left whole.
        await reset3(AttributedString("11.02 08:30 회의\n\t안건"), NSRange(location: ("11.02 08:30 회의\n\t안" as NSString).length, length: 0))
        check(!draft.canAlign, "a timeline child cannot be aligned")
        draft.setAlign(.center)
        check(draft.text.runs.allSatisfy { $0[MemoAttributes.Align.self] == nil }, "and setting it leaves the child left")
        var centredLines = AttributedString("가운데\n\n", attributes: centred)
        centredLines += AttributedString("끝")
        await reset3(centredLines, NSRange(location: ("가운데\n" as NSString).length, length: 0))
        draft.setAlign(nil)
        await wait()
        let emptyBreak = draft.text.runs.first { String(draft.text[$0.range].characters).hasSuffix("\n\n") || String(draft.text[$0.range].characters) == "\n" }
        check(draft.align == nil && draft.text.runs.filter { $0[MemoAttributes.Align.self] != nil }.allSatisfy { String(draft.text[$0.range].characters).hasPrefix("가운데") && !String(draft.text[$0.range].characters).hasSuffix("\n\n") },
              "왼쪽 on an empty line takes its line break left too", "\(String(describing: emptyBreak))")
        capture(window, "aabar-code")

        // Lists start a little in, at every level and in a quote.
        await reset3(AttributedString("위 문단\n• 하나\n\t• 둘\n> • 인용\n> 인용만"), NSRange(location: 0, length: 0))
        func x(_ words: String) -> CGFloat {
            let range = (back.string as NSString).range(of: words)
            return window.convertFromScreen(back.firstRect(forCharacterRange: NSRange(location: range.location, length: 1), actualRange: nil)).minX
        }
        let left = x("위 문단")
        let bullet = window.convertFromScreen(back.firstRect(forCharacterRange: NSRange(location: ("위 문단\n" as NSString).length, length: 1), actualRange: nil)).minX
        check(abs(bullet - left - MemoLineStyler.listInset) < 1.5, "a first-level bullet sits 12 pt in", "\(bullet - left)")
        check(abs(x("둘") - x("하나") - MemoLists.levelIndent) < 1.5, "the next level one step further, as before", "\(x("둘") - x("하나"))")
        // The words after the bullet: from the quote's words as the list's are from the left line.
        let quoted = x("인용\n") - x("인용만"), plain = x("하나") - left
        check(abs(quoted - plain) < 1.5, "a list in a quote is set in from the quote's words as one outside is", "quoted \(quoted) plain \(plain)")
        let listHTML = NotesHTML.body(name: "이름", text: draft.text) ?? ""
        check(!listHTML.contains("padding") && !listHTML.contains("margin") && listHTML.contains("<ul>\n<li>하나</li>"), "the 메모 app gets plain lists, no inset", listHTML)
        capture(window, "aabar-lists")
    }

    /// A period's several memos: making, names, renaming in the tab, leaving an empty one, 모아
    /// 보기, deleting, ToDos made from a memo and 가져오기, the 메모 app's names, and the caret's line
    /// kept in view in 모아 보기.
    private static func checkMemos(memos: MemoBook, model: AppModel, editor: NSTextView, window: NSWindow,
                                   reset: (AttributedString, Int?) async -> Void, type: (String) async -> Void,
                                   key: (UInt16, String, NSEvent.ModifierFlags) async -> Void) async {
        let draft = memos.draft
        let returnKey: (UInt16, String) = (36, "\r")
        let escape: (UInt16, String) = (53, "\u{1b}")
        let tabKey: (UInt16, String) = (48, "\t")
        func wait(_ seconds: Double = 0.4) async { try? await Task.sleep(for: .seconds(seconds)) }
        guard let period = draft.period else {
            log("FAIL  no open period")
            return
        }
        func names() -> [String] { memos.tabs(for: period).map(\.name) }
        func stored() -> [String] { memos.tabs(for: period).compactMap { tab in tab.id.map { _ in tab.name } } }
        var nameEditor: NSTextView? { (window.firstResponder as? NSTextView).flatMap { $0.isFieldEditor ? $0 : nil } }
        /// Until the name's field has taken the keyboard (it does so a moment after it shows).
        func waitForName() async {
            for _ in 0..<20 where nameEditor == nil { try? await Task.sleep(for: .seconds(0.1)) }
        }
        func renameShowsOnlyACaret() -> (Bool, String) {
            guard let field = nameEditor, field.isFieldEditor else { return (false, "first responder \(String(describing: window.firstResponder))") }
            let range = field.selectedRange()
            return (range.length == 0 && range.location == (field.string as NSString).length, "\(field.string) \(range)")
        }

        // An empty day shows one empty memo; its first letters save it without a name.
        check(names() == ["새 메모"] && draft.noteID == nil, "a day with no memo shows one empty 새 메모", "\(names())")
        window.makeFirstResponder(editor)
        await reset(AttributedString(), nil)
        await type("첫 메모")
        draft.flush()
        let first = draft.noteID
        check(first != nil && stored() == ["새 메모"], "typing saves the day's first memo, shown as 새 메모", "\(names())")
        check(memos.stored(note: first ?? UUID(), calendar: model.calendar).noteName(period) == NotesHTML.noteName(for: period),
              "a memo without a name keeps the date alone in the 메모 app")

        // + 새 메모: named 새 메모(1), its name in the tab with the caret at its end; Return goes to the memo.
        draft.newMemo()
        await wait(0.3)
        await waitForName()
        let second = draft.noteID
        check(second != nil && second != first && names() == ["새 메모", "새 메모(1)"], "+ 새 메모 makes 새 메모(1)", "\(names())")
        check(draft.renaming == second, "the new memo's name is open in its tab")
        capture(window, "memos-rename")
        let caret = renameShowsOnlyACaret()
        check(caret.0, "the name shows only a caret at its end, nothing picked", caret.1)
        await key(returnKey.0, returnKey.1, [])
        await wait()
        check(draft.renaming == nil && names() == ["새 메모", "새 메모(1)"], "Return keeps the name", "\(names())")
        check(window.firstResponder === editor && draft.hasFocus, "Return goes on to the memo", "\(String(describing: window.firstResponder))")

        // Left blank under its 새 메모(n) name, it goes once another memo is opened.
        draft.select(first)
        await wait()
        check(names() == ["새 메모"] && draft.noteID == first, "an empty 새 메모(n) goes when it is left", "\(names())")

        // A new one with words stays; numbers take the first free one.
        draft.newMemo()
        await wait(0.3)
        await waitForName()
        await key(tabKey.0, tabKey.1, [])
        check(draft.renaming == nil && window.firstResponder === editor, "Tab also leaves the name for the memo")
        await type("안건 하나\n[ ] 견적서 보내기")
        draft.flush()
        let meeting = draft.noteID!
        draft.newMemo()
        await wait(0.3)
        await waitForName()
        let third = draft.noteID!
        check(names() == ["새 메모", "새 메모(1)", "새 메모(2)"], "numbers go on to the first free one", "\(names())")

        // Renaming in the tab: typed over, Return; a name another memo has gets (1); Esc puts it back.
        nameEditor?.selectAll(nil)
        nameEditor?.insertText("회의록", replacementRange: nameEditor?.selectedRange() ?? NSRange())
        await key(returnKey.0, returnKey.1, [])
        await wait()
        check(names()[2] == "회의록", "a name typed in the tab is kept", "\(names())")
        await wait(0.6)
        draft.startRenaming(meeting)
        await wait(0.3)
        await waitForName()
        check(draft.noteID == meeting && renameShowsOnlyACaret().0, "이름 바꾸기 opens the memo and its name with a caret", renameShowsOnlyACaret().1)
        nameEditor?.selectAll(nil)
        nameEditor?.insertText("회의록", replacementRange: nameEditor?.selectedRange() ?? NSRange())
        await key(returnKey.0, returnKey.1, [])
        await wait()
        check(names() == ["새 메모", "회의록(1)", "회의록"], "a name another memo has gets (1)", "\(names())")
        await wait(0.6)
        draft.startRenaming(meeting)
        await wait(0.3)
        await waitForName()
        nameEditor?.insertText(" 바꿈", replacementRange: nameEditor?.selectedRange() ?? NSRange())
        await key(escape.0, escape.1, [])
        await wait()
        check(names()[1] == "회의록(1)" && draft.renaming == nil, "Esc puts the name back", "\(names())")
        await wait(0.6)
        draft.startRenaming(third)
        await wait(0.3)
        await waitForName()
        nameEditor?.selectAll(nil)
        nameEditor?.deleteBackward(nil)
        await key(returnKey.0, returnKey.1, [])
        await wait()
        check(names()[2] == "새 메모(1)", "a name cleared away takes the 새 메모 rule", "\(names())")
        await wait(0.6)
        draft.startRenaming(third)
        await wait(0.3)
        await waitForName()
        nameEditor?.selectAll(nil)
        nameEditor?.insertText("빈 메모", replacementRange: nameEditor?.selectedRange() ?? NSRange())
        await key(returnKey.0, returnKey.1, [])
        draft.select(first)
        await wait()
        check(names() == ["새 메모", "회의록(1)", "빈 메모"], "a renamed memo stays though it is empty", "\(names())")
        check(memos.has(period), "the day keeps its pencil mark")

        // The 메모 app's names: the date and the memo's name.
        check(memos.stored(note: meeting, calendar: model.calendar).noteName(period) == NotesHTML.noteName(for: period) + " - 회의록(1)",
              "a named memo's 메모 app note is the date and its name",
              memos.stored(note: meeting, calendar: model.calendar).noteName(period) ?? "nil")

        // ToDos made from a memo name it; 가져오기 finds its lines under its name.
        draft.select(meeting)
        await wait()
        let lines = memos.todoLines(calendar: model.calendar).filter { $0.note == meeting }
        check(lines.count == 1 && lines.first?.name == "회의록(1)", "가져오기 finds the memo's ToDo line under its name", "\(lines.map(\.name))")
        draft.makeTodos(fromLines: [1], in: period)
        await wait()
        let made = memos.todos.entries(for: period).first { $0.title == "견적서 보내기" }
        check(made?.sourceNoteID == meeting, "a ToDo made from the memo names that memo", "\(String(describing: made?.sourceNoteID))")
        check(memos.label(ofNote: meeting, calendar: model.calendar) == "회의록(1)", "the ToDo's memo link says which memo")
        // A rewrite of a memo not open lands in it, not in the open one.
        draft.select(first)
        await wait()
        memos.rewrite(note: meeting) { $0.append(AttributedString("\n덧붙임")) }
        check(memos.text(note: meeting).map { String($0.characters) }?.hasSuffix("덧붙임") == true && String(draft.text.characters) == "첫 메모",
              "a change to a memo not open goes to that memo", String(draft.text.characters))

        capture(window, "memos-one")
        // 모아 보기: the memos one under another; only the open one is an editor.
        draft.resignEditor?()
        model.memoLayout = .all
        await wait(1.0)
        capture(window, "memos-all")
        var readOnly = textViews(in: window.contentView!).filter { MemoTextViews.readOnly.contains($0) }
        var waited = 0
        while readOnly.count < 2, waited < 30 {
            await wait(0.1)
            waited += 1
            readOnly = textViews(in: window.contentView!).filter { MemoTextViews.readOnly.contains($0) }
        }
        check(readOnly.count == 2, "모아 보기 draws the other two memos read-only", "\(readOnly.count) after \(waited * 100) ms more")
        if waited > 0 { log("NOTE  the read-only memos took \(waited * 100) ms more to be found") }
        check(readOnly.allSatisfy { $0.textContentStorage?.delegate is MemoLineStyler }, "each is drawn by the memo's own styler")
        check(readOnly.contains { $0.string.contains("견적서") }, "a read-only memo shows its words")
        check(UserDefaults.standard.string(forKey: "memoLayout") == "all", "the layout is remembered on this Mac")
        // Another day in 모아 보기 is opened, its memo the one written.
        draft.resignEditor?()
        model.select(model.today.addingTimeInterval(86_400))
        await wait(0.8)
        check(draft.period?.key == model.panelPeriod.key && draft.period?.key != period.key, "모아 보기 opens the day picked",
              "\(String(describing: draft.period?.key))")
        draft.resignEditor?()
        model.select(model.today)
        await wait(0.8)
        check(draft.period?.key == period.key && draft.noteID == first, "and back on the day, its memo last open", "\(String(describing: draft.period?.key))")
        // A click on one moves the writing to it.
        // As drawn now: the day was left and opened again, so these are new text views.
        if let target = textViews(in: window.contentView!).filter({ MemoTextViews.readOnly.contains($0) }).first(where: { $0.string.contains("안건") }) {
            await wait(0.6)
            click(target, in: window)
            await wait(1.0)
            check(draft.noteID == meeting, "a click on a read-only memo opens it", "\(String(describing: draft.noteID))")
            let live = window.firstResponder as? NSTextView
            check(live.map { !$0.isFieldEditor && !MemoTextViews.readOnly.contains($0) } == true && draft.hasFocus, "and the caret goes into it",
                  "\(String(describing: window.firstResponder))")
            check(textViews(in: window.contentView!).filter { MemoTextViews.readOnly.contains($0) }.count == 2, "the memo left is drawn read-only",
                  "views \(textViews(in: window.contentView!).map { "\(MemoTextViews.readOnly.contains($0) ? "R" : "W"):\($0.string.prefix(8))" })")
        } else {
            check(false, "the meeting memo is drawn read-only")
        }
        // The caret's line kept in view: ToDos push the memos down, the last memo is written in.
        let pushed = (1...20).compactMap { memos.todos.add("미는 할 일 \($0)", to: period) }
        draft.resignEditor?()
        draft.focusOnAppear = true
        draft.select(third)
        await wait(1.0)
        // The editor takes focus as it appears (`focusOnAppear`).
        if let live = window.firstResponder as? NSTextView, !live.isFieldEditor, !MemoTextViews.readOnly.contains(live) {
            live.setSelectedRange(NSRange(location: (live.string as NSString).length, length: 0))
            live.insertText("마지막 메모의 줄", replacementRange: live.selectedRange())
            await wait(0.8)
            var outer: NSScrollView? = live.enclosingScrollView?.superview.flatMap { view in
                var next: NSView? = view
                while let current = next, !(current is NSScrollView) { next = current.superview }
                return next as? NSScrollView
            }
            if outer == nil { outer = nil }
            let screen = live.firstRect(forCharacterRange: live.selectedRange(), actualRange: nil)
            let caretRect = window.convertFromScreen(screen)
            let shown = outer.map { $0.convert($0.bounds, to: nil) } ?? .zero
            check(screen != .zero && shown.minY <= caretRect.minY && caretRect.maxY <= shown.maxY,
                  "모아 보기 scrolls the panel to the caret's line", "caret \(caretRect) panel \(shown)")
        } else {
            check(false, "모아 보기 has an editor for the open memo, with focus", "\(String(describing: window.firstResponder))")
        }
        memos.todos.entries(for: period).filter { entry in pushed.contains { $0.id == entry.todoID } }.forEach(memos.todos.remove)
        await wait(0.4)

        // The memos scroll on their own, to the panel's foot, as 하나씩's memo does: a long last
        // memo written at its end moves the memos' scroll, not the panel's.
        /// The scroll views around `view`, nearest first (the memo's own, then the memos', then the panel's).
        func scrollViews(around view: NSView) -> [NSScrollView] {
            var found: [NSScrollView] = []
            var next = view.superview
            while let current = next {
                if let scroll = current as? NSScrollView { found.append(scroll) }
                next = current.superview
            }
            return found
        }
        if let live = window.firstResponder as? NSTextView, !live.isFieldEditor, !MemoTextViews.readOnly.contains(live) {
            live.setSelectedRange(NSRange(location: (live.string as NSString).length, length: 0))
            for line in 1...30 {
                live.insertText("\n긴 메모 줄 \(line)", replacementRange: live.selectedRange())
                await wait(0.05)
            }
            await wait(1.0)
            let around = scrollViews(around: live)
            check(around.count >= 3, "모아 보기's memos have a scroll view of their own inside the panel's", "\(around.count)")
            if around.count >= 3 {
                let memosScroll = around[1], panel = around[2]
                let inner = memosScroll.convert(memosScroll.bounds, to: nil), outer = panel.convert(panel.bounds, to: nil)
                // AppKit's window coordinates: y grows upward, so the foot is minY.
                check(abs(inner.minY - outer.minY) <= Metrics.spaceXxl + 2, "the memos reach the panel's foot", "memos \(inner) panel \(outer)")
                check(panel.contentView.bounds.minY == 0 || panel.contentView.bounds.origin.y.magnitude < 1, "the panel itself did not scroll",
                      "\(panel.contentView.bounds)")
                check(memosScroll.contentView.bounds.origin.y.magnitude > 1, "the memos scrolled to the caret", "\(memosScroll.contentView.bounds)")
                let caret = window.convertFromScreen(live.firstRect(forCharacterRange: live.selectedRange(), actualRange: nil))
                check(inner.minY <= caret.minY && caret.maxY <= inner.maxY, "the caret's line shows in the memos", "caret \(caret) memos \(inner)")
                // Scrolled back to the top, a read-only memo there still opens on a click.
                memosScroll.contentView.scroll(to: .zero)
                memosScroll.reflectScrolledClipView(memosScroll.contentView)
                await wait(0.8)
                if let target = textViews(in: window.contentView!).filter({ MemoTextViews.readOnly.contains($0) }).first(where: { $0.string.contains("첫 메모") }) {
                    click(target, in: window)
                    await wait(1.0)
                    check(draft.noteID == first, "after scrolling the memos, a click on a read-only memo opens it", "\(String(describing: draft.noteID))")
                } else {
                    check(false, "the first memo is drawn read-only after scrolling the memos")
                }
            }
        }
        draft.resignEditor?()
        model.memoLayout = .one
        await wait(0.8)
        check(textViews(in: window.contentView!).filter { MemoTextViews.readOnly.contains($0) }.isEmpty, "하나씩 shows one memo again")

        // 메모 지우기: asked in the panel when the memo has words; straight away when it has none.
        draft.select(meeting)
        await wait()
        draft.askToDelete(meeting)
        await wait()
        check(draft.confirmingDelete == meeting && stored().count == 3, "deleting a memo with words asks first")
        draft.delete(meeting)
        await wait()
        check(names() == ["새 메모", "빈 메모"] && draft.noteID == first, "deleting opens the memo before it", "\(names())")
        check(memos.stored(note: meeting, calendar: model.calendar).isGone, "the deleted memo's 메모 app note goes too")
        // 빈 메모 took a line in 모아 보기; emptied again, it goes without asking.
        draft.select(third)
        await reset(AttributedString(), nil)
        draft.flush()
        draft.askToDelete(third)
        await wait()
        check(draft.confirmingDelete == nil && names() == ["새 메모"], "an empty memo goes without asking", "\(names())")
        // Back to one empty memo, as it began.
        draft.select(first)
        await reset(AttributedString(), nil)
        draft.flush()
        model.select(model.today.addingTimeInterval(86_400))
        await wait(0.6)
        check(memos.tabs(for: period).map(\.id) == [nil], "the emptied first memo goes when the day is left", "\(memos.tabs(for: period).map(\.name))")
        model.select(model.today)
        await wait(0.4)
        _ = escape
    }

    // MARK: Memo order

    /// The middle of a view noted under `name` (`barFrame`), in the window's coordinates.
    private static func middle(of name: String, in window: NSWindow, draft: MemoDraft) -> CGPoint? {
        // SwiftUI's global frame, moved to the content's place as the memo's own clicks are.
        guard let frame = MemoBarFrames.byName[name].map(draft.inContent), let content = window.contentView else { return nil }
        let top = CGPoint(x: frame.midX, y: frame.midY)
        return content.convert(content.isFlipped ? top : CGPoint(x: top.x, y: content.bounds.height - top.y), to: nil)
    }

    /// `SIMPLIFY_MEMO_CHECK=order`: a period's memos moved (as a drop of a tab or header does)
    /// and moved one place with 앞으로/뒤로 옮기기, drawn in that order in 하나씩 and 모아 보기.
    /// The drag itself is tried by hand or with agent-desktop: posted mouse events do not land
    /// on the tabs in the check's window.
    private static func checkOrder(memos: MemoBook, model: AppModel, editor: NSTextView, window: NSWindow) async {
        let draft = memos.draft
        func wait(_ seconds: Double = 0.4) async { try? await Task.sleep(for: .seconds(seconds)) }
        guard let period = draft.period else {
            log("FAIL  no open period")
            return
        }
        func names() -> [String] { memos.tabs(for: period).map(\.name) }
        var made: [UUID] = []
        for name in ["가", "나", "다"] {
            guard let id = memos.create(in: period) else { continue }
            memos.rename(id, to: name)
            made.append(id)
        }
        draft.select(made.first)
        await wait(0.8)
        check(names() == ["가", "나", "다"], "three memos in the order made", "\(names())")
        // 다 to the front through the book, as a drop does.
        memos.move(made[2], to: 0)
        await wait()
        check(names() == ["다", "가", "나"], "a memo moved to the front comes first", "\(names())")
        capture(window, "order-tabs")

        /// The names in the order the tabs (or headers) are drawn, left to right and top to bottom.
        /// Only the three memos: the app's own window draws its period's memo under the same names.
        func drawn(_ prefix: String) -> [String] {
            MemoBarFrames.byName.filter { $0.key.hasPrefix(prefix) && ["가", "나", "다"].contains(String($0.key.dropFirst(prefix.count))) }
                .sorted { ($0.value.minY, $0.value.minX) < ($1.value.minY, $1.value.minX) }
                .map { String($0.key.dropFirst(prefix.count)) }
        }
        check(drawn("메모 탭 ") == ["다", "가", "나"], "the tabs are drawn in that order", "\(drawn("메모 탭 "))")
        // 앞으로/뒤로 옮기기, as the right-click menu and VoiceOver's actions do them.
        memos.move(made[0], by: 1)
        await wait()
        check(names() == ["다", "나", "가"], "뒤로 옮기기 moves a memo one place on", "\(names())")
        memos.move(made[1], by: -1)
        await wait()
        check(names() == ["나", "다", "가"], "앞으로 옮기기 moves a memo one place back", "\(names())")
        memos.move(made[1], by: -1)
        memos.move(made[0], by: 1)
        await wait()
        check(names() == ["나", "다", "가"], "nothing moves past either end", "\(names())")
        check(drawn("메모 탭 ") == ["나", "다", "가"], "the tabs are drawn in the new order", "\(drawn("메모 탭 "))")

        // 모아 보기: the memos one under another in the same order.
        draft.resignEditor?()
        model.memoLayout = .all
        await wait(1.2)
        check(drawn("메모 머리글 ") == ["나", "다", "가"], "모아 보기 draws the memos in that order", "\(drawn("메모 머리글 "))")
        memos.move(made[0], by: -1)
        await wait(0.8)
        check(drawn("메모 머리글 ") == ["나", "가", "다"], "a move in 모아 보기 redraws the memos", "\(drawn("메모 머리글 "))")
        capture(window, "order-all")
        draft.resignEditor?()
        model.memoLayout = .one
        await wait(0.8)
        check(names() == ["나", "가", "다"] && drawn("메모 탭 ") == ["나", "가", "다"], "하나씩 shows the same order", "\(drawn("메모 탭 "))")
        for id in made { memos.delete(id) }
        await wait()
    }

    // MARK: Chip lines

    /// `SIMPLIFY_MEMO_CHECK=chiplines`: a line with a ToDo chip in it (in a list, on its own, mid
    /// sentence, in a table cell) is as tall as its neighbours and has its baseline where theirs is,
    /// and a click anywhere on the box ticks it. Pictures of 하나씩 and 모아 보기 for the eye.
    private static func checkChipLines(memos: MemoBook, model: AppModel, editor: NSTextView, window: NSWindow,
                                       reset: (AttributedString, Int?) async -> Void) async {
        let draft = memos.draft
        func wait(_ seconds: Double = 0.4) async { try? await Task.sleep(for: .seconds(seconds)) }
        let titles = ["AI 허브 규칙 만들기", "전시 구성안 고치기", "견적서 보내기", "표 안의 할 일"]
        let made = titles.compactMap { memos.todos.add($0, to: model.panelPeriod) }
        guard made.count == titles.count else {
            log("FAIL  could not make the ToDos")
            return
        }
        memos.todos.setDone(made[1].id, true)
        await wait()
        func chip(_ number: Int) -> AttributedString {
            MemoChips.chip(id: made[number].id, title: made[number].title, isDone: number == 1)
        }
        func row(_ text: AttributedString) -> AttributedString {
            var text = text
            text[MemoAttributes.Table.self] = "t1"
            return text
        }
        var text = AttributedString("• 위 글머리 줄\n• ") + chip(0) + AttributedString("\n\t• 아래 하위 줄\n")
        text += chip(1) + AttributedString("\n보통 줄\n문장 가운데 ") + chip(2) + AttributedString(" 뒤에 이어지는 글\n보통 줄 둘\n")
        text += row(chip(3) + AttributedString("\t메모")) + AttributedString("\n") + row(AttributedString("둘째\t칸")) + AttributedString("\n끝")
        await reset(text, 0)
        await wait(0.6)
        check(MemoChips.chips(in: draft.text).count == 4, "the four chips stay chips", "\(MemoChips.chips(in: draft.text).count)")

        /// Each paragraph's first words, height and baseline (from the paragraph's top).
        func lines() -> [(words: String, height: CGFloat, baseline: CGFloat)] {
            var found: [(String, CGFloat, CGFloat)] = []
            guard let manager = editor.textLayoutManager else { return [] }
            manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
                let words = (fragment.textElement as? NSTextParagraph)?.attributedString.string ?? ""
                if let line = fragment.textLineFragments.first {
                    found.append((words.trimmingCharacters(in: .newlines), fragment.layoutFragmentFrame.height,
                                  line.typographicBounds.minY + line.glyphOrigin.y))
                }
                return true
            }
            return found
        }
        let measured = lines()
        for line in measured { log("      \(line.height)  \(line.baseline)  \(line.words.prefix(20))") }
        func line(_ prefix: String) -> (words: String, height: CGFloat, baseline: CGFloat)? {
            measured.first { $0.words.hasPrefix(prefix) }
        }
        let pairs: [(chip: String, plain: String, what: String)] = [
            ("● □", "● 위", "a chip in a list"),
            ("☑", "보통 줄", "a done chip on its own line"),
            ("문장 가운데", "보통 줄 둘", "a chip mid sentence"),
            ("□ 표", "둘째", "a chip in a table cell"),
        ]
        for pair in pairs {
            guard let chipLine = line(pair.chip), let plainLine = line(pair.plain) else {
                check(false, "\(pair.what) is laid out", "\(measured.map(\.words))")
                continue
            }
            check(abs(chipLine.height - plainLine.height) < 0.5, "\(pair.what) is as tall as a plain line",
                  "\(chipLine.height) vs \(plainLine.height)")
            check(abs(chipLine.baseline - plainLine.baseline) < 0.5, "\(pair.what) sits on a plain line's baseline",
                  "\(chipLine.baseline) vs \(plainLine.baseline)")
        }
        capture(window, "chiplines-one")

        // A click on the box's left edge, middle and right edge finds it, and ticks it each time.
        // Asked of the styler the way the memo's click monitor asks it: posted clicks do not reach
        // a check window that cannot become key. The click itself is tried with agent-desktop.
        let string = editor.string as NSString
        let boxAt = string.range(of: "• □").location + 2
        if let styler = editor.textLayoutManager?.delegate as? MemoLineStyler, let manager = editor.textLayoutManager,
           let content = manager.textContentManager, let start = content.location(content.documentRange.location, offsetBy: boxAt),
           let end = content.location(start, offsetBy: 1), let range = NSTextRange(location: start, end: end) {
            var box = CGRect.null
            manager.enumerateTextSegments(in: range, type: .standard, options: []) { _, frame, _, _ in
                box = box.union(frame)
                return true
            }
            box = box.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
            log("      box \(box)")
            for (name, x) in [("left edge", box.minX + 1), ("middle", box.midX), ("right edge", box.maxX - 1), ("2 pt left of it", box.minX - 2)] {
                let before = memos.todos.item(made[0].id)?.isDone
                let found = styler.todoBox(at: CGPoint(x: x, y: box.midY))
                if let found { draft.clickBox(at: found, count: 1) }
                draft.tickedByClick = nil
                await wait()
                let after = memos.todos.item(made[0].id)?.isDone
                check(found == boxAt && before != nil && after == !(before ?? false), "a click on the box's \(name) ticks it",
                      "\(String(describing: found)) \(String(describing: before)) → \(String(describing: after))")
            }
            check(styler.todoBox(at: CGPoint(x: box.maxX + 12, y: box.midY)) == nil, "a click on the chip's words is not on its box")
            // A double-click on the box ticks it once.
            let before = memos.todos.item(made[0].id)?.isDone
            draft.clickBox(at: boxAt, count: 1)
            draft.clickBox(at: boxAt, count: 2)
            await wait()
            check(memos.todos.item(made[0].id)?.isDone == !(before ?? false), "a double-click on the box ticks it once")
            draft.tickedByClick = nil
            check(MemoChips.chips(in: draft.text).count == 4, "the chips stay chips after the clicks", "\(MemoChips.chips(in: draft.text).count)")
        } else {
            check(false, "the first chip's box is found")
        }

        // 모아 보기 draws a memo not being written as plain text.
        draft.resignEditor?()
        model.memoLayout = .all
        await wait(1.2)
        capture(window, "chiplines-all")
        model.memoLayout = .one
        await wait(0.6)
        memos.todos.entries(for: model.panelPeriod).filter { entry in made.contains { $0.id == entry.todoID } }.forEach(memos.todos.remove)
        await wait()
    }

    // MARK: Links

    /// `SIMPLIFY_MEMO_CHECK=links`: ⌘K, an address pasted on picked letters, links typed, ⌘-click,
    /// links in table cells and through the clipboard, and ⌘Z on formatting made as a space is typed.
    private static func checkLinks(draft: MemoDraft, editor: NSTextView, window: NSWindow,
                                   reset: (AttributedString, Int?) async -> Void, type: (String) async -> Void,
                                   key: (UInt16, String, NSEvent.ModifierFlags) async -> Void) async {
        let board = NSPasteboard.general
        let keptBoard: [[(NSPasteboard.PasteboardType, Data)]] = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let keptOpener = MemoLinkEdit.opener
        var opened: [URL] = []
        MemoLinkEdit.opener = { opened.append($0) }
        defer {
            MemoLinkEdit.opener = keptOpener
            board.clearContents()
            board.writeObjects(keptBoard.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types { item.setData(data, forType: type) }
                return item
            })
        }
        func wait(_ seconds: Double = 0.4) async { try? await Task.sleep(for: .seconds(seconds)) }
        var letters: String { String(draft.text.characters) }
        /// The linked letters and their addresses, in order.
        func links() -> [String] {
            draft.text.runs.compactMap { run in
                run[MemoAttributes.Link.self].map { "\(String(draft.text[run.range].characters))→\($0)" }
            }
        }
        func range(of words: String) -> NSRange { (editor.string as NSString).range(of: words) }
        func undo() async {
            editor.undoManager?.undo()
            await wait()
        }
        let space: (UInt16, String) = (49, " ")
        let returnKey: (UInt16, String) = (36, "\r")

        // ⌘K on picked letters: the field under them, an address typed, Return.
        await reset(AttributedString("발표 자료는 디자인 시스템 문서에 있어요."), nil)
        editor.setSelectedRange(range(of: "디자인 시스템 문서"))
        await wait()
        check(draft.canLink, "letters on one line can take a link")
        draft.askForLink()
        await wait(0.6)
        if case .link(_, let length, let address)? = draft.book.todos.pop {
            check(length == 10 && address == nil, "⌘K opens an empty address field for the picked letters", "\(length) \(String(describing: address))")
        } else {
            check(false, "⌘K opens the address field", "\(String(describing: draft.book.todos.pop))")
        }
        capture(window, "link-field")
        if let field = window.firstResponder as? NSTextView, field.isFieldEditor {
            field.insertText("https://figma.com/file/simplify-ds", replacementRange: field.selectedRange())
            await key(returnKey.0, returnKey.1, [])
            await wait()
        } else {
            check(false, "the address field has the keyboard", "\(String(describing: window.firstResponder))")
            draft.putLink("https://figma.com/file/simplify-ds", location: range(of: "디자인 시스템 문서").location, length: 10)
            await wait()
        }
        check(draft.book.todos.pop == nil && links() == ["디자인 시스템 문서→https://figma.com/file/simplify-ds"], "Return puts the link on the letters", "\(links())")
        check(letters == "발표 자료는 디자인 시스템 문서에 있어요.", "the letters stay as they were", letters)
        capture(window, "link-drawn")
        // Typed at the link's end, letters are not part of it.
        editor.setSelectedRange(NSRange(location: NSMaxRange(range(of: "디자인 시스템 문서")), length: 0))
        await wait()
        await type("들")
        check(links() == ["디자인 시스템 문서→https://figma.com/file/simplify-ds"], "letters typed at a link's end are not linked", "\(links())")
        // ⌘Z takes the link back off in one step (with the letter typed after it first).
        await undo()
        await undo()
        check(links().isEmpty && letters == "발표 자료는 디자인 시스템 문서에 있어요.", "⌘Z takes the link off", "\(links()) \(letters)")
        editor.undoManager?.redo()
        await wait()
        check(links().count == 1, "⌘⇧Z puts it back", "\(links())")

        // ⌘K in a link: its address to change, or 링크 지우기.
        editor.setSelectedRange(NSRange(location: range(of: "시스템").location, length: 0))
        await wait()
        draft.askForLink()
        await wait(0.6)
        if case .link(let location, let length, let address)? = draft.book.todos.pop {
            check(address == "https://figma.com/file/simplify-ds" && NSRange(location: location, length: length) == range(of: "디자인 시스템 문서"),
                  "⌘K in a link opens its whole link with the address", "\(location),\(length) \(String(describing: address))")
            draft.putLink("https://figma.com/file/simplify-ds-v2", location: location, length: length)
            await wait()
            check(links() == ["디자인 시스템 문서→https://figma.com/file/simplify-ds-v2"], "고치기 changes the address", "\(links())")
            draft.removeLink(location: location, length: length)
            await wait()
            check(links().isEmpty, "링크 지우기 leaves the letters plain", "\(links())")
        } else {
            check(false, "⌘K in a link opens the field", "\(String(describing: draft.book.todos.pop))")
        }
        // Other addresses are refused; nothing picked puts the address itself in.
        check(!draft.putLink("javascript:alert(1)", location: 0, length: 2), "a javascript: address is refused")
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        await wait()
        draft.askForLink()
        await wait(0.4)
        if case .link(let location, let length, _)? = draft.book.todos.pop {
            draft.putLink("www.apple.com", location: location, length: length)
        }
        await wait()
        check(letters.hasSuffix("https://www.apple.com") && links() == ["https://www.apple.com→https://www.apple.com"],
              "⌘K at a caret puts the address in as a link", "\(links())")
        // Lines across: no link.
        await reset(AttributedString("가나\n다라"), nil)
        editor.setSelectedRange(NSRange(location: 1, length: 3))
        await wait()
        check(!draft.canLink, "letters over two lines cannot take one link")

        // An address pasted on picked letters links them.
        await reset(AttributedString("다음 분기 계획 정리 보기"), nil)
        board.clearContents()
        board.setString("  https://notion.so/q4-plan\n", forType: .string)
        editor.setSelectedRange(range(of: "계획 정리"))
        await wait()
        await key(9, "v", [.command])
        check(letters == "다음 분기 계획 정리 보기" && links() == ["계획 정리→https://notion.so/q4-plan"], "an address pasted on picked letters links them", "\(letters) \(links())")
        await undo()
        check(letters == "다음 분기 계획 정리 보기" && links().isEmpty, "one ⌘Z takes that link off", "\(letters) \(links())")
        // Not an address, or two lines picked: left to the usual paste. (The check's window may
        // not pass ⌘V on to the text view's own paste, so that is asked of it directly.)
        board.clearContents()
        board.setString("그냥 글", forType: .string)
        editor.setSelectedRange(range(of: "계획 정리"))
        await wait()
        check(!MemoLinkEdit.pasteAddress(into: editor, draft: draft) && !MemoLinkEdit.pasteLinked(into: editor, draft: draft),
              "words on the clipboard are left to the usual paste")
        editor.paste(nil)
        await wait()
        check(letters == "다음 분기 그냥 글 보기" && links().isEmpty, "and paste as words", letters)
        await reset(AttributedString("가나\n다라"), nil)
        board.clearContents()
        board.setString("https://a.com", forType: .string)
        editor.setSelectedRange(NSRange(location: 1, length: 3))
        await wait()
        check(!MemoLinkEdit.pasteAddress(into: editor, draft: draft), "over two lines an address is left to the usual paste")
        editor.paste(nil)
        await wait()
        check(letters == "가https://a.com라" && links().isEmpty, "and pastes as letters", letters)
        // ⌥⇧⌘V: the address's letters, as always.
        await reset(AttributedString("다음 분기 계획 정리 보기"), nil)
        editor.setSelectedRange(range(of: "계획 정리"))
        await wait()
        editor.pasteAsPlainText(nil)
        await wait()
        check(letters == "다음 분기 https://a.com 보기" && links().isEmpty, "⌥⇧⌘V puts the address in as letters", letters)

        // A typed address becomes a link at the space; ⌘Z once takes the link off, again the space.
        await reset(AttributedString("참고: "), nil)
        await type("https://developer.apple.com/documentation")
        await key(space.0, space.1, [])
        await wait()
        check(links() == ["https://developer.apple.com/documentation→https://developer.apple.com/documentation"], "an address and a space make a link", "\(links())")
        await undo()
        check(links().isEmpty && letters == "참고: https://developer.apple.com/documentation ", "⌘Z leaves the address as plain letters", "\(links()) \(letters.debugDescription)")
        await undo()
        // The space goes; SwiftUI's undo takes it with the letters typed before it, as it always has.
        check("참고: https://developer.apple.com/documentation".hasPrefix(letters) && links().isEmpty, "⌘Z again takes the space", letters.debugDescription)
        // And at Return; not in inline code.
        await reset(AttributedString(""), nil)
        await type("www.naver.com.")
        await key(returnKey.0, returnKey.1, [])
        await wait()
        check(links() == ["www.naver.com→https://www.naver.com"], "an address and Return make a link, the full stop left out", "\(links())")
        var code = AttributeContainer()
        code[MemoAttributes.InlineCode.self] = true
        await reset(AttributedString("https://a.com", attributes: code), nil)
        await key(space.0, space.1, [])
        await wait()
        check(links().isEmpty, "no link is made in inline code", "\(links())")

        // ⌘-click opens it; a plain click only puts the caret.
        // On the third line: the check's window measures the box's top a title bar lower.
        var linked = AttributedString("\n\n열기: ")
        var linkContainer = AttributeContainer()
        linkContainer[MemoAttributes.Link.self] = "https://example.com/open"
        linked += AttributedString("예제 링크", attributes: linkContainer)
        await reset(linked, nil)
        await wait(0.4)
        let screen = editor.firstRect(forCharacterRange: range(of: "예제"), actualRange: nil)
        let point = window.convertFromScreen(screen)
        let at = CGPoint(x: point.midX, y: point.midY)
        func clickLink(_ flags: NSEvent.ModifierFlags) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: type, location: at, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    NSApp.postEvent(event, atStart: false)
                }
            }
        }
        clickLink([])
        await wait(0.6)
        check(opened.isEmpty, "a plain click on a link opens nothing", "\(opened)")
        clickLink(.command)
        await wait(0.6)
        check(opened.map(\.absoluteString) == ["https://example.com/open"], "⌘-click opens the link", "\(opened)")

        // Copied with its link: HTML and RTF links, and back here as a link.
        editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
        await wait()
        await key(8, "c", [.command])
        let html = board.string(forType: .html) ?? ""
        let rtf = board.data(forType: .rtf).map { String(decoding: $0, as: UTF8.self) } ?? ""
        check(html.contains("<a href=\"https://example.com/open\">예제 링크</a>"), "a copy's HTML has the link", html)
        check(rtf.contains("HYPERLINK") && rtf.contains("example.com/open"), "a copy's RTF has the link")
        check(board.string(forType: .string) == "\n\n열기: 예제 링크", "a copy's words are the letters")
        await reset(AttributedString("붙임: "), nil)
        await key(9, "v", [.command])
        check(links() == ["예제 링크→https://example.com/open"] && letters == "붙임: \n\n열기: 예제 링크", "pasted back here it is a link again", "\(links()) \(letters)")
        // From a web page: the link kept, others dropped.
        await reset(AttributedString(""), nil)
        board.clearContents()
        board.setString("웹 링크와 나쁜 링크", forType: .string)
        board.setString("<meta charset=\"utf-8\"><a href=\"https://www.apple.com/kr/\">웹 링크</a>와 <a href=\"javascript:alert(1)\">나쁜 링크</a>", forType: .html)
        await key(9, "v", [.command])
        check(links() == ["웹 링크→https://www.apple.com/kr/"] && letters.hasPrefix("웹 링크와 나쁜 링크"), "a web page's link pastes as a link, javascript: as words", "\(links()) \(letters.debugDescription)")

        // In a table cell: ⌘K on a cell's letters, not across cells; copied and pasted with the table.
        await reset(tableSample(), nil)
        editor.setSelectedRange(range(of: "시안 2종"))
        await wait()
        check(draft.canLink, "letters in one cell can take a link")
        draft.askForLink()
        await wait(0.4)
        if case .link(let location, let length, _)? = draft.book.todos.pop { draft.putLink("https://figma.com/x", location: location, length: length) }
        await wait()
        let cellRun = draft.text.runs.first { $0[MemoAttributes.Link.self] != nil }
        check(links() == ["시안 2종→https://figma.com/x"] && cellRun?[MemoAttributes.Table.self] == "t1", "a cell's letters take a link and stay in the table", "\(links())")
        editor.setSelectedRange(range(of: "1,200,000\t시안"))
        await wait()
        check(!draft.canLink, "letters across cells cannot take a link")
        capture(window, "link-table")
        let table = range(of: "항목\t금액\t메모\n디자인\t1,200,000\t시안 2종\n개발\t3,400,000\t4주")
        editor.setSelectedRange(table)
        await wait()
        await key(8, "c", [.command])
        check((board.string(forType: .html) ?? "").contains("<a href=\"https://figma.com/x\">시안 2종</a>"), "a copied table's HTML keeps the cell's link")
        await reset(AttributedString("\n"), 0)
        await key(9, "v", [.command])
        check(links() == ["시안 2종→https://figma.com/x"], "the table pastes back with its link", "\(links())")
        // A table from elsewhere with a link in a cell.
        await reset(AttributedString(""), nil)
        board.clearContents()
        board.setString("항목\t자료\n회의록\tnotion", forType: .string)
        board.setString("<meta charset=\"utf-8\"><table><tr><td>항목</td><td>자료</td></tr><tr><td>회의록</td><td><a href=\"https://notion.so/weekly-1109\">notion</a> 보기</td></tr></table>", forType: .html)
        await key(9, "v", [.command])
        check(links() == ["notion→https://notion.so/weekly-1109"] && draft.text.runs.contains { $0[MemoAttributes.Table.self] != nil },
              "a pasted table keeps a cell's link", "\(links()) \(letters.debugDescription)")

        // Formatting made as a space is typed: ⌘Z once leaves the letters plain, again takes the space.
        let mark = MemoLists.plainMark
        for typed in ["1.", "-", ">", "> 1."] {
            await reset(AttributedString(typed == "> 1." ? "> " : ""), nil)
            await type(typed == "> 1." ? "1." : typed)
            await key(space.0, space.1, [])
            await wait()
            let made = letters
            let isList = MemoLists.marker(made) != nil && !made.contains(mark)
            check(isList && made == typed + " ", "‘\(typed) ’ makes its list or quote", made.debugDescription)
            await undo()
            let plain = letters
            let expectedPlain = typed == "> 1." ? "> \(mark)1. " : "\(mark)\(typed) "
            let stillQuote = typed == "> 1." ? MemoLists.marker(plain)?.kind == .quote : MemoLists.marker(plain) == nil
            check(plain == expectedPlain && stillQuote, "⌘Z after ‘\(typed) ’ keeps the letters and takes the formatting", plain.debugDescription)
            await undo()
            // The space goes (with the letters typed before it, as SwiftUI's undo always took them).
            let before = typed == "> 1." ? "> 1." : typed
            check(!letters.contains(mark) && before.hasPrefix(letters), "⌘Z again after ‘\(typed) ’ takes the space", letters.debugDescription)
        }
        // A line left plain: Return is a plain line break, the menu makes it a list, copies leave the mark out.
        await reset(AttributedString(""), nil)
        await type("1.")
        await key(space.0, space.1, [])
        await wait()
        await undo()
        await type("회의 준비")
        await key(returnKey.0, returnKey.1, [])
        check(letters == "\(mark)1. 회의 준비\n", "Return on a line left plain is a plain line break", letters.debugDescription)
        editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
        await wait()
        await key(8, "c", [.command])
        check(board.string(forType: .string) == "1. 회의 준비\n" && !(board.string(forType: .html) ?? "").contains(mark), "a copy leaves the mark out",
              (board.string(forType: .string) ?? "").debugDescription)
        // ← → step over it once; Delete after it joins lines as at any line's front.
        await reset(AttributedString("가\n\(mark)1. 나"), 3)
        await key(123, "\u{F702}", [])
        check(editor.selectedRange().location == 1, "← from just after the mark goes on to the line above", "\(editor.selectedRange())")
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        await key(124, "\u{F703}", [])
        check(editor.selectedRange().location == 4, "→ at the line's front steps over the mark", "\(editor.selectedRange())")
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        await key(51, "\u{7f}", [])
        check(letters == "가1. 나", "Delete just after the mark joins the line to the one above", letters.debugDescription)
        await reset(AttributedString("\(mark)1. 회의"), 1)
        draft.setList(.number)
        await wait()
        check(letters == "1. 회의" && MemoLists.marker(letters)?.kind == .number, "번호 목록 on a line left plain makes it a list", letters.debugDescription)
        // `* `: ⌘Z gives the star back, again the space.
        await reset(AttributedString(""), nil)
        await type("*")
        await key(space.0, space.1, [])
        await wait()
        check(letters == "• ", "* and a space still make a bullet", letters.debugDescription)
        await undo()
        check(letters == "* ", "⌘Z gives the star back", letters.debugDescription)
        await undo()
        check(!letters.hasSuffix(" ") && "*".hasPrefix(letters), "⌘Z again takes the space", letters.debugDescription)
    }

    /// The app's memory as Activity Monitor counts it (physical footprint), in MB.
    private static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// `SIMPLIFY_MEMO_CHECK=perf`: memory while typing (하나씩 and 모아 보기) and how long the
    /// panel takes to switch periods. Numbers only, logged as `PERF` lines.
    private static func checkPerf(memos: MemoBook, model: AppModel, editor: NSTextView, window: NSWindow,
                                  reset: (AttributedString, Int?) async -> Void) async {
        let draft = memos.draft
        func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
        func perf(_ line: String) { log("PERF  " + line) }
        func mb(_ value: Double) -> String { String(format: "%.1f MB", value) }
        /// From a change to the panel drawn: laid out and displayed, and the run loop's turn over.
        func timed(_ change: () -> Void) async -> Double {
            let start = ProcessInfo.processInfo.systemUptime
            change()
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            return (ProcessInfo.processInfo.systemUptime - start) * 1000
        }
        func stats(_ values: [Double]) -> String {
            let sorted = values.sorted()
            return String(format: "median %.1f ms, max %.1f ms (n=%d)", sorted[sorted.count / 2], sorted.last ?? 0, sorted.count)
        }
        /// Types `count` letters one by one, the way keys come, and logs the footprint as it grows.
        func typeLetters(_ count: Int, label: String) async -> [Double] {
            let words = Array("오늘 회의에서 정한 것들을 적어 둔다. 다음 주까지 견적을 보내고 일정을 맞춘다.\n")
            var times: [Double] = []
            for index in 0..<count {
                let letter = String(words[index % words.count])
                let start = ProcessInfo.processInfo.systemUptime
                editor.insertText(letter, replacementRange: editor.selectedRange())
                await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
                times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                try? await Task.sleep(for: .milliseconds(8))
                if (index + 1) % 500 == 0 { perf("\(label) after \(index + 1) letters: \(mb(footprint()))") }
            }
            return times
        }

        let switchOnly = ProcessInfo.processInfo.environment["SIMPLIFY_PERF_ONLY"] == "switch"
        model.memoLayout = .one
        await reset(sample(), nil)
        window.makeFirstResponder(editor)
        await wait(1)
        if !switchOnly {
            let base = footprint()
            perf("하나씩 before typing: \(mb(base))")
            let oneTimes = await typeLetters(2000, label: "하나씩")
            await wait(2)
            let oneAfter = footprint()
            perf("하나씩 idle after: \(mb(oneAfter)) (+\(mb(oneAfter - base)))")
            perf("하나씩 per letter: \(stats(oneTimes))")
            draft.flush()

            // 모아 보기 with four memos of the sample under the one being written.
            guard let period = draft.period else { return }
            for _ in 0..<4 {
                draft.newMemo()
                await wait(0.4)
                draft.commitRename(toBody: true)
                await wait(0.3)
                draft.text = sample()
                draft.flush()
            }
            model.memoLayout = .all
            await wait(1.5)
            let first = memos.tabs(for: period).first?.id
            draft.select(first)
            await wait(1)
            let written = textViews(in: window.contentView!).first { $0.isEditable }
            if let written {
                window.makeFirstResponder(written)
                written.setSelectedRange(NSRange(location: (written.string as NSString).length, length: 0))
            }
            await wait(0.5)
            let allBase = footprint()
            perf("모아 보기 (\(memos.tabs(for: period).count) memos) before typing: \(mb(allBase))")
            var allTimes: [Double] = []
            if let written {
                for index in 0..<1000 {
                    let start = ProcessInfo.processInfo.systemUptime
                    written.insertText(index % 40 == 39 ? "\n" : "가", replacementRange: written.selectedRange())
                    await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
                    allTimes.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                    try? await Task.sleep(for: .milliseconds(8))
                    if (index + 1) % 500 == 0 { perf("모아 보기 after \(index + 1) letters: \(mb(footprint()))") }
                }
            }
            await wait(2)
            let allAfter = footprint()
            perf("모아 보기 idle after: \(mb(allAfter)) (+\(mb(allAfter - allBase)))")
            if !allTimes.isEmpty { perf("모아 보기 per letter: \(stats(allTimes))") }
            draft.flush()

        }
        if switchOnly { await wait(8) }
        // Switching the panel's period, in both layouts.
        for layout in [AppModel.MemoLayout.one, .all] {
            model.memoLayout = layout
            await wait(0.8)
            var times: [Double] = []
            for _ in 0..<(switchOnly ? 30 : 6) {
                for scope in [PeriodScope.week, .month, .day] {
                    times.append(await timed { model.panelScope = scope })
                    await wait(0.25)
                }
            }
            perf("switch \(layout == .one ? "하나씩" : "모아 보기"): \(stats(times))")
        }
        // Moving day by day.
        model.memoLayout = .one
        var days: [Double] = []
        for step in 1...12 {
            days.append(await timed { model.select(model.today.addingTimeInterval(Double(step % 2 == 0 ? 0 : 86_400))) })
            await wait(0.25)
        }
        perf("day change: \(stats(days))")
        perf("end: \(mb(footprint()))")
        // For `heap` and `vmmap` from outside: the app stays a while before it quits.
        if let hold = ProcessInfo.processInfo.environment["SIMPLIFY_PERF_HOLD"].flatMap(Double.init) { await wait(hold) }
    }

    private static func textViews(in view: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        if let textView = view as? NSTextView, !textView.isFieldEditor, textView.window != nil, !textView.isHiddenOrHasHiddenAncestor { found.append(textView) }
        for subview in view.subviews { found += textViews(in: subview) }
        return found
    }

    /// A left click in the middle of `view`, posted to the app as the mouse would send it.
    private static func click(_ view: NSView, in window: NSWindow) {
        let point = view.convert(NSPoint(x: min(view.bounds.midX, 40), y: view.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                NSApp.postEvent(event, atStart: false)
            }
        }
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

    // MARK: Find

    /// `SIMPLIFY_MEMO_CHECK=find`: ⌘F in the open memo. How many places and in what order, the chip
    /// passed over, the marks drawn (in tables, code and quotes too), the room under the box and the
    /// shown place in sight under it, ⌘G and Return, replacing one and ⌘Z, replacing all and one ⌘Z,
    /// a replacement in a table cell keeping its cells, another day found again, Esc, ⌘G with the
    /// box closed, the 찾기 menu, and pictures in the light and dark themes.
    private static func checkFind(memos: MemoBook, model: AppModel, editor: NSTextView, window: NSWindow,
                                  reset: (AttributedString, Int?) async -> Void,
                                  key: (UInt16, String, NSEvent.ModifierFlags) async -> Void) async {
        let draft = memos.draft
        let find = draft.find
        func wait(_ seconds: Double = 0.4) async { try? await Task.sleep(for: .seconds(seconds)) }
        /// A picture of the window, and with SIMPLIFY_FIND_PAUSE a pause for a real screenshot
        /// (`screencapture -l <window>`): `cacheDisplay` leaves TextKit 2's drawing of the marks out.
        let pauses = ProcessInfo.processInfo.environment["SIMPLIFY_FIND_PAUSE"] != nil
        func picture(_ name: String) async {
            capture(window, name)
            guard pauses else { return }
            log("SHOT  \(window.windowNumber) \(name)")
            await wait(3)
        }
        var letters: String { String(draft.text.characters) }
        let keptAppearance = NSApp.appearance
        defer { NSApp.appearance = keptAppearance }
        NSApp.appearance = NSAppearance(named: .aqua)
        model.panelMode = .normal
        model.panelWidth = PanelLayout.normalMin
        await wait(0.8)

        // The 편집 menu has 찾기 with its five items.
        if let edit = NSApp.mainMenu?.items.first(where: { $0.submenu?.items.contains { $0.title == "찾기" } == true })?.submenu {
            log("INFO  편집: \(edit.items.map { $0.isSeparatorItem ? "—" : $0.title })")
            let items = edit.items.first { $0.title == "찾기" }?.submenu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []
            check(items == ["찾기…", "찾아서 바꾸기…", "다음 찾기", "이전 찾기", "선택 항목으로 찾기"], "편집 › 찾기 has its five items", "\(items)")
            check(edit.items.filter { $0.title == "찾기" || $0.title == "Find" }.count == 1, "and only one 찾기")
        } else {
            log("INFO  menus: \(NSApp.mainMenu?.items.map(\.title) ?? [])")
            check(false, "편집 › 찾기 is in the menu bar")
        }

        let todo = memos.todos.add("회의 자료 보내기", to: model.panelPeriod)
        var text = AttributedString("주간 회의 준비 · 11월 2주\n• 회의실 B 예약 확인\n• 지난 회의 메모 정리\n")
        if let todo { text += MemoChips.chip(id: todo.id, title: todo.title, isDone: false) }
        text += AttributedString("\n오후 회의는 4시로\n")
        var row1 = AttributedString("품목\t회의 시간"), row2 = AttributedString("사과\t1,200")
        row1[MemoAttributes.Table.self] = "t1"
        row2[MemoAttributes.Table.self] = "t1"
        text += row1 + AttributedString("\n") + row2 + AttributedString("\n")
        var code = AttributedString("let 회의 = 1")
        code[MemoAttributes.Code.self] = true
        text += code + AttributedString("\n> 인용 속 회의\n")
        for number in 1...16 { text += AttributedString("빈 줄 \(number)\n") }
        text += AttributedString("다음 주 회의 안건 모으기")
        await reset(text, 0)
        await wait(0.6)
        let original = letters
        let expected = MemoFind.matches(of: "회의", in: draft.text)
        check(expected.count == 8, "the sample has eight places outside the chip", "\(expected.count)")

        // ⌘F in the memo opens the box, its field focused, the memo's letters under it.
        await key(3, "f", [.command])
        await wait()
        check(find.isOpen && find.focusedField == .find, "⌘F opens the box with its field focused", "\(find.isOpen) \(String(describing: find.focusedField))")
        check(editor.textContainerInset.height < 1, "the memo is not pushed down", "\(editor.textContainerInset)")
        let box = find.frameInContent
        log("INFO  box \(box.integral)")
        check(abs(box.width - MemoFindBox.width) < 0.5 && abs(box.height - 40) < 0.5, "the box is 248 wide and one row of 40", "\(box.size)")
        find.query = "회의"
        await wait()
        check(find.matches == expected, "every place is found, front to back", "\(find.matches)")
        check(find.current == 0 && find.countText == "1/8", "the first after the caret is shown, 1/8", find.countText)
        if let todo, let chip = MemoChips.chips(in: draft.text).first(where: { $0.todo.id == todo.id }) {
            let chipRange = NSRange(chip.range, in: draft.text)
            check(!find.matches.contains { NSIntersectionRange($0, chipRange).length > 0 }, "the chip's 회의 is passed over")
        }
        find.query = "워크숍"
        await wait()
        check(find.foundNothing && find.countText == "없음", "a word not in the memo reads 없음", find.countText)
        await picture("find-none-light")
        find.query = "회"
        await wait()
        check(find.matches.count == 8, "회 finds 회의 too", "\(find.matches.count)")
        find.query = "회의"
        await wait()

        /// The places are drawn by a layer in the memo's text view, under its letters: a grey box a
        /// line of each place, the shown one's edged. A picture of the window (`cacheDisplay`) leaves
        /// TextKit 2's letters out, so the drawing itself is seen in the SIMPLIFY_FIND_PAUSE shots.
        func shownIsEdged(_ what: String) async {
            find.reveal()
            await wait(0.5)
            let places = find.placeFrames(in: editor)
            let shown = places.filter(\.isShown)
            check(shown.count >= 1 && places.count >= find.matches.count - 1, "\(what): every place in sight has its box, the shown one edged",
                  "\(places.count) boxes, \(shown.count) edged")
        }
        await shownIsEdged("a plain line")
        check(editor.subviews.contains { String(describing: type(of: $0)) == "FindMarksView" }, "drawn by a layer in the memo's text view")

        // Return and ⌘G go on, ⇧Return and ⇧⌘G go back, round the ends.
        await key(36, "\r", [])
        check(find.current == 1, "Return in the field shows the next", "\(String(describing: find.current))")
        await key(5, "g", [.command])
        check(find.current == 2, "⌘G the next again", "\(String(describing: find.current))")
        await key(5, "g", [.command, .shift])
        await key(36, "\r", [.shift])
        check(find.current == 0, "⇧⌘G and ⇧Return go back", "\(String(describing: find.current))")
        await key(36, "\r", [.shift])
        check(find.current == 7, "and round to the last", "\(String(describing: find.current))")

        // The last is far down: scrolled into sight, under the box.
        await wait(0.5)
        if let frame = find.currentFrame, let scroll = editor.enclosingScrollView {
            let clip = scroll.contentView
            let shown = clip.convert(frame, from: editor)
            check(shown.minY >= clip.bounds.minY + MemoFindState.oneRowCover - 0.5 && shown.maxY <= clip.bounds.maxY + 0.5,
                  "the last place is scrolled into sight below the box", "\(shown) in \(clip.bounds)")
        }
        await picture("find-scrolled-light")
        // In a table row, code and a quote: the fragments that draw themselves draw the marks too.
        for (index, what) in [(4, "a table cell"), (5, "inline code's line"), (6, "a quote")] {
            while find.current != index { find.step(1) }
            await shownIsEdged(what)
        }
        await picture("find-table-light")

        // ⌥⌘F brings out the replace row, its field focused, and more room.
        await key(3, "f", [.command, .option])
        await wait()
        check(find.showsReplaceRow && find.focusedField == .replace, "⌥⌘F brings out the replace row", "\(find.showsReplaceRow) \(String(describing: find.focusedField))")
        check(abs(find.frameInContent.height - 68) < 0.5, "the box is two rows, 68", "\(find.frameInContent.size)")
        find.replacement = "미팅"
        while find.current != 0 { find.step(1) }
        await wait()
        find.reveal()
        await picture("find-replace-light")

        // 바꾸기: the shown place, then the next is shown; ⌘Z puts it back.
        await key(36, "\r", [])
        await wait(0.6)
        check(letters.hasPrefix("주간 미팅 준비") && find.matches.count == 7, "Return in 바꿀 글 replaces the shown place", "\(letters.prefix(12)) \(find.matches.count)")
        check(find.current == 0 && find.matches.first?.location == expected[1].location + 0, "and the next place is shown", "\(String(describing: find.current)) \(find.matches.first.map(\.location) ?? -1)")
        editor.undoManager?.undo()
        await wait(0.6)
        check(letters == original, "⌘Z puts it back", String(letters.prefix(20)))

        // In a table cell, a tab in the replacement does not split the cell.
        find.refresh(from: 0)
        while find.current != 4 { find.step(1) }
        find.replacement = "회\t의실"
        find.replaceCurrent()
        await wait(0.6)
        let rows = MemoTodoLines.lines(in: draft.text).map { String(draft.text[$0].characters) }.filter { $0.hasPrefix("품목") }
        check(rows == ["품목\t회의실 시간"], "a replacement in a cell keeps the row's cells", "\(rows)")
        editor.undoManager?.undo()
        await wait(0.6)
        check(letters == original, "⌘Z puts the cell back", String(letters.prefix(20)))

        // 모두 8: every place in one edit, the chip as it was; one ⌘Z puts all back.
        find.replacement = "미팅"
        find.refresh(from: 0)
        await key(36, "\r", [.command, .option])
        await wait(0.8)
        let after = letters
        check(MemoFind.matches(of: "회의", in: draft.text).isEmpty && after.components(separatedBy: "미팅").count - 1 == 8,
              "⌥⌘Return replaces all eight", "\(after.components(separatedBy: "미팅").count - 1)")
        check(after.contains("회의 자료 보내기") && MemoChips.chips(in: draft.text).count == 1, "the chip keeps its words")
        check(find.matches.isEmpty && find.countText == "없음", "and nothing is left to find", find.countText)
        editor.undoManager?.undo()
        await wait(0.8)
        check(letters == original, "one ⌘Z puts all eight back", String(letters.prefix(20)))
        find.refresh(from: 0)
        check(find.matches.count == 8, "and they are found again", "\(find.matches.count)")

        // Another day: the box stays open and finds there; back again, here.
        let today = model.selectedDay
        model.select(model.calendar.date(byAdding: .day, value: 1, to: today)!)
        await wait(0.8)
        check(find.isOpen && find.matches.isEmpty, "on another day the box stays open and finds again there", "\(find.isOpen) \(find.matches.count)")
        draft.text = AttributedString("회의 둘, 회의 하나")
        await wait(0.6)
        check(find.matches.count == 2, "and follows that day's letters", "\(find.matches.count)")
        draft.text = AttributedString()
        await wait(0.3)
        model.select(today)
        await wait(0.8)
        check(find.matches.count == 8, "back on the day, its eight", "\(find.matches.count)")

        // Dark pictures: one row, replace row, nothing found.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        await wait(0.8)
        find.refresh(from: 0)
        await wait(0.4)
        await shownIsEdged("dark theme")
        await picture("find-replace-dark")
        find.toggleReplace()
        await wait(0.4)
        check(!find.showsReplaceRow && abs(find.frameInContent.height - 40) < 0.5, "⇄ takes the replace row in", "\(find.frameInContent.size)")
        await picture("find-dark")
        find.query = "워크숍"
        await wait(0.4)
        await picture("find-none-dark")
        find.query = "회의"
        NSApp.appearance = NSAppearance(named: .aqua)
        await wait(0.6)
        await picture("find-light")

        // Esc: the box goes, the memo takes focus with the shown place picked, the room goes.
        let shown = find.current.map { find.matches[$0] }
        find.focus(.find)
        await wait()
        await key(53, "\u{1b}", [])
        await wait(0.5)
        check(!find.isOpen && window.firstResponder === editor, "Esc closes the box and the memo takes focus", "\(find.isOpen) \(String(describing: window.firstResponder))")
        check(editor.selectedRange() == shown, "with the shown place picked", "\(editor.selectedRange()) vs \(String(describing: shown))")
        check(!editor.subviews.contains { String(describing: type(of: $0)) == "FindMarksView" }, "and the marks are gone")

        // ⌘G with the box closed: from the caret, the next place picked.
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        await wait(0.3)
        await key(5, "g", [.command])
        check(editor.selectedRange() == expected[0], "⌘G with the box closed picks the next place", "\(editor.selectedRange())")
        await key(5, "g", [.command])
        check(editor.selectedRange() == expected[1], "and the one after", "\(editor.selectedRange())")
        // ⌘E: picked letters become the words looked for.
        editor.setSelectedRange(NSRange(location: (letters as NSString).range(of: "오후").location, length: 2))
        await wait(0.3)
        await key(14, "e", [.command])
        check(find.query == "오후" && !find.isOpen, "⌘E takes the picked letters, the box stays closed", find.query)
        await key(3, "f", [.command])
        await wait()
        check(find.isOpen && find.query == "오후" && find.matches.count == 1, "⌘F with letters picked looks for them", "\(find.query) \(find.matches.count)")
        await key(53, "\u{1b}", [])
        await wait()
        if let todo { memos.todos.remove(memos.todos.entries(for: model.panelPeriod).first { $0.todoID == todo.id }!) }
        await wait()
    }

    /// `SIMPLIFY_MEMO_CHECK=todofold`: the panel's ToDo list three plain rows tall at most, scrolled
    /// inside past that with the add row under it, the memo in the same place however many ToDos
    /// there are, a new or picked row scrolled into view, and the rule's chevron folding the list
    /// (remembered, kept folded when a ToDo comes in, the count on the rule). Pictures light and dark.
    private static func checkTodoFold(memos: MemoBook, model: AppModel, editor: NSTextView, window: NSWindow) async {
        func wait(_ seconds: Double = 0.5) async { try? await Task.sleep(for: .seconds(seconds)) }
        let todos = memos.todos
        let wasFolded = model.isTodoFolded
        defer { model.isTodoFolded = wasFolded }
        model.isTodoFolded = false
        model.panelMode = .normal
        await wait(1.0)
        let period = model.panelPeriod
        let cap = TodoList.listCap
        func frame(_ name: String) -> CGRect? { MemoBarFrames.byName[name] }
        var list: CGRect? { frame("할 일 목록") }
        /// The memo's top, from the window's top.
        var memoTop: CGFloat? {
            guard let box = editor.enclosingScrollView, let content = window.contentView else { return nil }
            return content.bounds.height - box.convert(box.bounds, to: nil).maxY
        }
        /// The rows' own scroll view, the one `listCap` tall.
        var rowsScroll: NSScrollView? { Self.scrollViews(in: window.contentView!).first { abs($0.frame.height - cap) < 1 } }
        /// Whether the row of `id` shows whole in the rows' scroll; every row here is a plain one.
        func rowShows(_ id: UUID) -> (Bool, String) {
            guard let index = todos.entries(for: period).firstIndex(where: { $0.id == id }) else { return (false, "no row") }
            guard let scroll = rowsScroll else { return (false, "no rows scroll view") }
            let offset = scroll.contentView.bounds.origin.y, top = CGFloat(index) * TodoList.rowHeight
            return (top >= offset - 0.5 && top + TodoList.rowHeight <= offset + cap + 0.5, "row \(index) at \(top), scrolled \(offset)")
        }
        /// A real click (down and up) in the middle of a `.global` frame.
        func click(_ global: CGRect, at point: CGPoint? = nil, count: Int = 1) async {
            let frame = memos.draft.inContent(global)
            let content = window.contentView!
            let top = point.map { CGPoint(x: frame.minX + $0.x, y: frame.minY + $0.y) } ?? CGPoint(x: frame.midX, y: frame.midY)
            let local = content.convert(content.isFlipped ? top : CGPoint(x: top.x, y: content.bounds.height - top.y), to: nil)
            for click in 1...count {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [],
                                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                      context: nil, eventNumber: 0, clickCount: click, pressure: 1) {
                        NSApp.postEvent(event, atStart: false)
                    }
                }
            }
            await wait(0.6)
        }
        /// Types into the add row's field and presses Return, as a person would.
        func addFromField(_ title: String) async -> Bool {
            guard let field = Self.textFields(in: window.contentView!).first(where: { $0.placeholderString == "할 일 추가" }) else { return false }
            window.makeFirstResponder(field)
            await wait(0.3)
            field.currentEditor()?.insertText(title)
            await wait(0.2)
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, characters: "\r",
                                             charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
                NSApp.postEvent(event, atStart: false)
            }
            await wait(1.0)
            return true
        }
        /// Every accessibility label under `element`, for the folded rule's count.
        func labels(_ element: Any, depth: Int = 0) -> [String] {
            guard depth < 40, let object = element as? NSAccessibilityProtocol else { return [] }
            var found: [String] = []
            if let label = object.accessibilityLabel(), !label.isEmpty { found.append(label) }
            for child in object.accessibilityChildren() ?? [] { found += labels(child, depth: depth + 1) }
            return found
        }
        func add(_ count: Int, from start: Int) -> [TodoItem] {
            (start..<(start + count)).compactMap { todos.add("할 일 \($0)", to: period) }
        }

        // Two rows: as tall as they are, no scroll.
        var made = add(2, from: 1)
        await wait()
        let top2 = memoTop
        check(list.map { abs($0.height - 2 * TodoList.rowHeight) < 0.6 } == true, "two ToDos stand two rows tall (\(Int(2 * TodoList.rowHeight)))",
              "\(String(describing: list))")
        // Three: the cap, still no scroll.
        made += add(1, from: 3)
        await wait()
        let top3 = memoTop
        check(list.map { abs($0.height - cap) < 0.6 } == true, "three ToDos stand at the cap (\(Int(cap)))", "\(String(describing: list))")
        check(top2 != nil && top3 != nil && abs(top3! - top2! - TodoList.rowHeight) < 0.6, "the third row moves the memo down one row",
              "\(String(describing: top2)) → \(String(describing: top3))")
        // Renaming a row of exactly three: the field is no taller than the row, so the list keeps
        // its height and does not start scrolling under the caret.
        if let list {
            await click(list, at: CGPoint(x: 60, y: TodoList.rowHeight * 1.5), count: 2)
            await wait(0.4)
            let editing = window.firstResponder as? NSTextView
            check(editing != nil && editing!.string == "할 일 2", "a double-click renames the row", "\(String(describing: window.firstResponder))")
            check(frame("할 일 목록").map { abs($0.height - cap) < 0.6 } == true && rowsScroll == nil,
                  "renaming one of three keeps the rows at the cap, unscrolled", "\(String(describing: frame("할 일 목록"))) scroll \(rowsScroll != nil)")
            editing?.insertText("할 일 2 고침", replacementRange: NSRange(location: 0, length: (editing!.string as NSString).length))
            await wait(0.3)
            check(window.firstResponder === editing, "and keeps the caret while typing", "\(String(describing: window.firstResponder))")
            window.makeFirstResponder(editor)
            await wait(0.6)
            check(todos.entries(for: period)[1].title == "할 일 2 고침", "leaving the field keeps the new name", todos.entries(for: period)[1].title)
        }
        // A fourth from the add row: the rows start scrolling, and the new one is scrolled to.
        if await addFromField("넷째 할 일"), let fourth = todos.entries(for: period).last, fourth.title == "넷째 할 일" {
            check(rowsScroll != nil && rowShows(fourth.id).0, "the fourth row, added from the add row, starts the scroll and shows", rowShows(fourth.id).1)
        } else {
            check(false, "the add row adds a fourth")
        }
        window.makeFirstResponder(editor)
        await wait(0.3)
        // Ten: the cap, scrolled inside; the memo stays where three left it.
        made += add(6, from: 5)
        await wait()
        let top10 = memoTop
        check(list.map { abs($0.height - cap) < 0.6 } == true, "ten ToDos stand at the cap too", "\(String(describing: list))")
        check(top3 != nil && top10 != nil && abs(top10! - top3!) < 0.6, "and the memo stays where it was with three",
              "\(String(describing: top3)) → \(String(describing: top10))")
        if let add = frame("할 일 추가 줄"), let list {
            check(add.minY >= list.maxY - 0.5 && add.minY - list.maxY < 1, "the add row shows right under the scrolled rows", "add \(add) list \(list)")
        } else {
            check(false, "the add row is drawn", "\(MemoBarFrames.byName.keys.filter { $0.hasPrefix("할 일") }.count) frames")
        }
        let first = made[0].id, last = made[made.count - 1].id
        // Scrolled one row down by the fourth's reveal: the second row shows, the tenth is under the cap.
        check(rowShows(made[1].id).0 && !rowShows(last).0, "the rows above show, the tenth is under the cap", rowShows(made[1].id).1 + " / " + rowShows(last).1)

        // A row added from the add row is scrolled into view.
        let field = Self.textFields(in: window.contentView!).first { $0.placeholderString == "할 일 추가" }
        if let field {
            window.makeFirstResponder(field)
            await wait(0.3)
            field.currentEditor()?.insertText("새로 넣은 할 일")
            await wait(0.2)
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, characters: "\r",
                                             charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
                NSApp.postEvent(event, atStart: false)
            }
            await wait(1.0)
            let added = todos.entries(for: period).first { $0.title == "새로 넣은 할 일" }
            check(added != nil, "Return in the add row adds a ToDo")
            if let added { check(rowShows(added.id).0, "the new row is scrolled into view", rowShows(added.id).1) }
            check(frame("할 일 추가 줄") != nil && window.firstResponder === field.currentEditor(), "the add row stays, with the caret, for the next one",
                  "\(String(describing: window.firstResponder))")
        } else {
            check(false, "the add row has a field")
        }
        // Picking the first row (set as a click sets it) scrolls back up to it.
        window.makeFirstResponder(editor)
        await wait(0.3)
        todos.selectedRow = first
        await wait(0.8)
        check(rowShows(first).0, "a picked row out of view is scrolled into view", rowShows(first).1)
        capture(window, "todofold-picked")

        // The ends: scrolled to the middle, both ends have rows past them.
        let middle = todos.entries(for: period)[4].id
        todos.selectedRow = nil
        await wait(0.3)
        todos.selectedRow = middle
        await wait(0.8)
        todos.selectedRow = nil
        await wait(0.5)
        for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: look)
            await wait(0.8)
            capture(window, "todofold-open-\(name)")
        }
        NSApp.appearance = nil
        await wait(0.4)

        // The wheel over the rows scrolls them; at their end it may hand on to the panel. Looked at
        // with a short window, so the panel has room to scroll.
        let tall = window.frame
        window.setFrame(NSRect(x: tall.minX, y: tall.maxY - 640, width: tall.width, height: 640), display: true)
        await wait(1.0)
        let scrollViews = Self.scrollViews(in: window.contentView!)
        let inner = scrollViews.first { view in
            guard let list else { return false }
            let height = view.frame.height
            return abs(height - cap) < 1 && abs(view.convert(view.bounds, to: nil).width - (list.width + 2 * Metrics.spaceXs)) < 1.5
        }
        let outer = inner.flatMap { inner in scrollViews.first { $0 !== inner && inner.isDescendant(of: $0) } }
        if let inner, let outer {
            func wheel(_ dy: Int32) {
                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0),
                      let event = NSEvent(cgEvent: cg) else { return }
                inner.scrollWheel(with: event)
            }
            outer.contentView.scroll(to: .zero)
            outer.reflectScrolledClipView(outer.contentView)
            let before = inner.contentView.bounds.origin.y
            wheel(-30)
            await wait(0.5)
            let after = inner.contentView.bounds.origin.y
            check(after > before, "the wheel over the rows scrolls them", "\(before) → \(after)")
            for _ in 0..<20 { wheel(-60) }
            await wait(0.6)
            let outerBefore = outer.contentView.bounds.origin.y
            for _ in 0..<4 { wheel(-60) }
            await wait(0.8)
            let outerAfter = outer.contentView.bounds.origin.y
            log("INFO  at the rows' end the wheel \(outerAfter > outerBefore ? "moves the panel" : "leaves the panel still") (\(outerBefore) → \(outerAfter))")
            outer.contentView.scroll(to: .zero)
            outer.reflectScrolledClipView(outer.contentView)
        } else {
            log("INFO  could not find the rows' scroll view (\(scrollViews.count) scroll views)")
        }
        window.setFrame(tall, display: true)
        await wait(1.0)

        // Another day's rows open at their top, not where this day's were scrolled.
        todos.selectedRow = made[made.count - 1].id
        await wait(0.8)
        let nextDay = Period(containing: model.calendar.date(byAdding: .day, value: 2, to: period.start)!, scope: .day, calendar: model.calendar)
        let other = (1...6).compactMap { todos.add("다른 날 \($0)", to: nextDay) }
        model.select(nextDay.start)
        await wait(1.0)
        check(rowsScroll.map { $0.contentView.bounds.origin.y < 0.5 } == true, "another day's rows open at their top",
              "\(String(describing: rowsScroll?.contentView.bounds.origin.y))")
        todos.entries(for: nextDay).filter { entry in other.contains { $0.id == entry.todoID } }.forEach(todos.remove)
        model.select(period.start)
        await wait(1.0)

        // Folding: the rows and the add row go, the memo moves up, the state is remembered.
        let openTop = memoTop
        todos.selectedRow = first
        await wait(0.4)
        guard let chevron = frame("할 일 접기") else { return check(false, "the ToDo rule has a chevron") }
        check(abs(chevron.width - 20) < 0.6 && abs(chevron.height - 20) < 0.6, "the chevron is 20 × 20", "\(chevron)")
        await click(chevron)
        check(model.isTodoFolded && UserDefaults.standard.bool(forKey: "isTodoFolded"), "a click on the chevron folds the list, remembered")
        check(list == nil && frame("할 일 추가 줄") == nil, "folded, the rows and the add row are gone",
              "\(String(describing: list)) \(String(describing: frame("할 일 추가 줄")))")
        check(todos.selectedRow == nil, "folding lets the picked row go", "\(String(describing: todos.selectedRow))")
        check(openTop != nil && memoTop != nil && memoTop! < openTop! - cap, "the memo moves up", "\(String(describing: openTop)) → \(String(describing: memoTop))")
        let total = todos.entries(for: period).count
        todos.setDone(made[1].id, true)
        todos.setDone(made[2].id, true)
        await wait()
        var summary = DayPanel.todoSummary(todos.entries(for: period))
        check(summary?.shown == "\(total) · 완료 2" && summary?.spoken == "할 일 \(total)개, 완료 2개",
              "the rule's count reads \(total) · 완료 2, said 할 일 \(total)개, 완료 2개", "\(String(describing: summary))")
        // SwiftUI builds its accessibility tree for an assistive app; without one this may find nothing.
        let said = labels(window.contentView!)
        log("INFO  accessibility labels with 할 일: \(said.filter { $0.contains("할 일") }.prefix(8))")
        // A ToDo coming in while folded (⌘⇧T makes one the same way) leaves the list folded.
        _ = add(1, from: 50)
        await wait()
        summary = DayPanel.todoSummary(todos.entries(for: period))
        check(model.isTodoFolded && list == nil, "a ToDo added while folded keeps the list folded")
        check(summary?.shown == "\(total + 1) · 완료 2", "and the count goes up", "\(String(describing: summary))")
        for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: look)
            await wait(0.8)
            capture(window, "todofold-folded-\(name)")
        }
        NSApp.appearance = nil
        await wait(0.4)
        // Another day is folded too (one setting); a day with no ToDos has no count.
        model.select(model.calendar.date(byAdding: .day, value: 1, to: period.start)!)
        await wait(0.8)
        check(model.isTodoFolded && frame("할 일 목록") == nil && DayPanel.todoSummary(todos.entries(for: model.panelPeriod)) == nil,
              "the next day is folded too, with no count for no ToDos", "\(todos.entries(for: model.panelPeriod).count)")
        model.select(period.start)
        await wait(0.8)
        // Open again: the rows come back at the cap. Clicked where the chevron was first noted, since
        // a day's chevron going away can leave a stale note of the next day's.
        await click(chevron)
        check(!model.isTodoFolded && !UserDefaults.standard.bool(forKey: "isTodoFolded"), "a second click opens it, remembered")
        check(rowsScroll != nil, "open again, the rows stand at the cap, scrolled inside", "\(String(describing: list))")
        check(memoTop != nil && openTop != nil && abs(memoTop! - openTop!) < 0.6, "and the memo is back where it was",
              "\(String(describing: openTop)) → \(String(describing: memoTop))")
        // The day before the check: none of its ToDos left.
        todos.entries(for: period).forEach(todos.remove)
        await wait()
    }

    private static func textFields(in view: NSView) -> [NSTextField] {
        var found: [NSTextField] = []
        if let field = view as? NSTextField, field.isEditable { found.append(field) }
        for subview in view.subviews { found += textFields(in: subview) }
        return found
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        if let scroll = view as? NSScrollView, !scroll.isHiddenOrHasHiddenAncestor { found.append(scroll) }
        for subview in view.subviews { found += scrollViews(in: subview) }
        return found
    }

    private static func capture(_ window: NSWindow, _ name: String) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: FileManager.default.temporaryDirectory.appending(path: "memo-check-\(name).png"))
    }
}

extension MemoBook.Stored {
    /// The 메모 app note's name for this memo, nil when it is gone or unreadable.
    func noteName(_ period: Period) -> String? {
        guard case .memo(let period, _, let name) = self else { return nil }
        return NotesHTML.noteName(for: period, memo: name)
    }

    var isGone: Bool {
        if case .gone = self { return true }
        return false
    }
}
#endif
