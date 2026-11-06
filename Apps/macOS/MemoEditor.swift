import AppKit
import QuickLook
import SwiftUI
import SimplifyKit

/// The memo being written in the panel: its text, the selection, and saving after a pause.
@MainActor
@Observable
final class MemoDraft {
    var text = AttributedString()
    var selection = AttributedTextSelection()
    private(set) var period: Period?
    /// The open memo of `period`; nil for the empty memo of a period that has none yet, saved as a
    /// memo without a name on its first letter.
    private(set) var noteID: UUID?
    /// The memo whose tab (or, in 모아 보기, header) is being renamed in place.
    var renaming: UUID?
    /// The name as typed while renaming.
    var renameText = ""
    /// The memo 메모 지우기 is asking about, in the panel.
    var confirmingDelete: UUID?
    /// The stored memo could not be read (written by a newer version, or damaged); it is shown
    /// empty and never saved over.
    private(set) var isUnreadable = false
    @ObservationIgnored private var saved = AttributedString()
    /// When the last left click in the memo box happened (system uptime) and its click count, set
    /// by `MemoMenuHost`, so a selection change right after it is that click and not a redraw.
    @ObservationIgnored var lastBoxClick: TimeInterval = 0
    @ObservationIgnored var lastClickCount = 0
    /// The click that last ticked a chip, so one click ticks once and a double-click whose first
    /// click already ticked does not tick back.
    @ObservationIgnored var tickedByClick: (id: UUID, at: TimeInterval)?
    /// The memo has keyboard focus; ⌘⇧T and ⌃⌘T are caught only then, and its section rule thickens.
    var hasFocus = false
    /// How tall the open memo's letters are laid out, for 모아 보기, where each memo is as tall as
    /// its text; set by `MemoMenuHost`.
    var contentHeight: CGFloat = 0
    /// The day chosen in the calendar: a week or month memo's timeline line names it when today is
    /// outside the memo's period.
    @ObservationIgnored var chosenDay: Date?
    /// Draws the rules and timeline lines again after the letters, the caret or the focus changed;
    /// set by `MemoMenuHost`, which can reach the text view.
    @ObservationIgnored var redrawLines: (() -> Void)?
    /// The part of the box the panel shows, in window coordinates (top-left origin), as SwiftUI
    /// lays it out. Right-clicks and clicks are judged against it.
    @ObservationIgnored var visibleBox: CGRect = .null
    /// Where the selection's first line sits in the box, top-left origin; set by `MemoMenuHost`,
    /// which can ask the text view. Nil when it cannot tell.
    @ObservationIgnored var selectionLineRect: (() -> CGRect?)?
    /// The caret's line in the box, top-left origin, measured from the text's layout so it is known
    /// even where the panel has scrolled it out of sight; set by `MemoMenuHost`. Nil without focus.
    @ObservationIgnored var caretLineRect: (() -> CGRect?)?
    /// The same line in window coordinates, top-left origin, for placing pops beside it.
    @ObservationIgnored var selectionLineInWindow: (() -> CGRect?)?
    /// Lets go of keyboard focus when the memo's text view has it, before the view is taken away
    /// (모아 보기 moving the editor to another memo, or the layout changing): AppKit must not lose a
    /// first responder from under it. Set by `MemoMenuHost`.
    @ObservationIgnored var resignEditor: (() -> Void)?
    /// Gives the focused text view the ink caret and a grey selection.
    @ObservationIgnored var inkTextView: (() -> Void)?
    /// Opens the right-click menu under the selection, for VoiceOver's 메뉴 보기.
    @ObservationIgnored var showMenu: (() -> Void)?
    /// The next text change is `[[` being put back after a closed search; it opens nothing.
    @ObservationIgnored var skipsSearchTrigger = false
    /// Bumped to put keyboard focus back in the box after a pop closes.
    var focusRequest = 0
    /// Bumped to take keyboard focus out of the box, as a name starts being changed in its tab:
    /// SwiftUI would otherwise give the box its focus back over the name's field.
    var blurRequest = 0
    /// The editor about to appear takes keyboard focus (모아 보기 moves the editor to the memo picked).
    @ObservationIgnored var focusOnAppear = false
    /// The Aa button's 문단 bar is open under it.
    var showsParagraphBar = false
    /// The pointer has rested on the Aa button: its shortcut card shows under it.
    var showsShortcutCard = false
    /// The Aa button and its open bar in window coordinates (top-left origin): a click outside
    /// both closes the bar.
    @ObservationIgnored var aaFrame: CGRect = .null
    @ObservationIgnored var paragraphBarFrame: CGRect = .null
    /// When a click closed the bar (system uptime): the Aa button that same click lands on does
    /// not open it again.
    @ObservationIgnored var barClosedByClick: TimeInterval = 0
    /// The memo box's whole frame in SwiftUI's global coordinates (set by the editor), and how far
    /// SwiftUI's global origin is from the window content's top-left (set by `MemoMenuHost`, which
    /// knows the box's place in the window): the content can sit under the title bar's toolbar or
    /// not, so the frames above are moved by it before a click is judged against them.
    @ObservationIgnored var boxFrame: CGRect = .null
    @ObservationIgnored var contentOffset: (() -> CGPoint?)?

    /// A frame from SwiftUI's global coordinates in the window content's (top-left origin).
    func inContent(_ frame: CGRect) -> CGRect {
        guard !frame.isNull, let offset = contentOffset?() else { return frame }
        return frame.offsetBy(dx: offset.x, dy: offset.y)
    }
    /// Makes a list change in the memo's text view, as typing would (one undo step): given the
    /// text view's letters and selection, the change to make, or nil for none. False when nothing
    /// was changed. Set by `MemoMenuHost`, which can reach the text view.
    @ObservationIgnored var editLines: ((_ make: (String, NSRange) -> MemoLists.Change?) -> Bool)?
    /// The formula being written, in the text view's letters (UTF-16), and starting an empty one
    /// at a place; set by `MemoMenuHost`, which draws them.
    @ObservationIgnored var openFormula: (() -> NSRange?)?
    /// Makes a table change in the memo's text view (`MemoTableKeys.perform`); false when none was
    /// made. Set by `MemoMenuHost`.
    @ObservationIgnored var editTable: ((MemoTableAction) -> Bool)?
    /// The caret's table's columns, 0 outside one; set by `MemoMenuHost`.
    @ObservationIgnored var tableColumns: (() -> Int)?
    @ObservationIgnored var startFormula: ((Int) -> Void)?
    /// A short note under the caret (`25MB까지 붙일 수 있어요`); set by `MemoMenuHost`.
    @ObservationIgnored var notify: ((String) -> Void)?
    /// The picked card's letter in the text view (UTF-16), set by `MemoMenuHost`.
    @ObservationIgnored var pickedCard: (() -> Int?)?
    /// The letters last cut or copied from this memo with attachments in them, and the clipboard's
    /// change count then: pasting that clipboard puts them back whole, cards and all, since the
    /// clipboard itself carries only `📎 name`.
    @ObservationIgnored var copiedPiece: (text: AttributedString, changeCount: Int)?
    /// The attached file Quick Look shows, while it is open.
    var previewURL: URL?
    /// The attachments the memo had when last saved, so a save that drops one clears it away later.
    @ObservationIgnored private var savedAttachments: Set<String> = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored let book: MemoBook
    /// The highlighter ⌘⇧H puts on. Remembered across launches.
    var lastHighlight = Palette(rawValue: UserDefaults.standard.string(forKey: "memoLastHighlight") ?? "") ?? .yellow {
        didSet { UserDefaults.standard.set(lastHighlight.rawValue, forKey: "memoLastHighlight") }
    }

    init(book: MemoBook) {
        self.book = book
    }

    /// Saves what is open, then shows `period`'s memo: the one last open there this run, else its
    /// first. The same period under another calendar (the week's first day or the zone changed)
    /// opens again, so names worked out from it follow.
    func open(_ period: Period) {
        guard period != self.period || period.calendar != self.period?.calendar else { return }
        leave()
        show(book.chosenNote(in: period), in: period)
    }

    /// Opens another memo of the open period, saving (and maybe discarding) the one left.
    func select(_ id: UUID?) {
        guard let period, id != noteID else { return }
        leave()
        show(id, in: period)
    }

    /// `+ 새 메모`: a new memo of the open period, its name in its tab ready to change.
    func newMemo() {
        guard let period else { return }
        leave()
        guard let id = book.create(in: period) else {
            show(book.chosenNote(in: period), in: period)
            return
        }
        show(id, in: period)
        startRenaming(id)
    }

    /// 메모 지우기: straight away for a memo with no words, otherwise asked in the panel first.
    func askToDelete(_ id: UUID) {
        let words = id == noteID ? text : book.text(note: id)
        if let words, MemoText.isBlank(words) {
            delete(id)
        } else {
            confirmingDelete = id
        }
    }

    func delete(_ id: UUID) {
        guard let period else { return }
        confirmingDelete = nil
        if renaming == id { renaming = nil }
        let tabs = book.tabs(for: period)
        let index = tabs.firstIndex { $0.id == id }
        if id == noteID {
            pending?.cancel()
            pending = nil
            noteID = nil
        }
        book.delete(id)
        // The tab before it, or the one after for the first.
        let rest = book.tabs(for: period)
        let next = index.map { rest[max(0, min($0 - 1, rest.count - 1))].id } ?? rest.first?.id
        if noteID == nil {
            show(next, in: period)
        }
    }

    /// Starts changing memo `id`'s name in its tab, a caret at the end of it; for the empty memo
    /// of a period with none (`id` nil), the memo is saved first as `새 메모`.
    func startRenaming(_ id: UUID?) {
        guard let period else { return }
        guard let id else {
            flush()
            if let noteID { startRenaming(noteID) } else { newMemo() }
            return
        }
        if id != noteID { select(id) }
        renameText = book.tabs(for: period).first { $0.id == id }?.name ?? Memos.defaultName
        blurRequest += 1
        renaming = id
    }

    /// Return, Tab, or the name losing focus: the name as typed, made unique (`Memos.rename`).
    /// `toBody` puts the caret in the memo after.
    func commitRename(toBody: Bool) {
        guard let id = renaming else { return }
        renaming = nil
        book.rename(id, to: renameText)
        if toBody { focusRequest += 1 }
    }

    /// Esc: the name as it was.
    func cancelRename() {
        guard renaming != nil else { return }
        renaming = nil
        focusRequest += 1
    }

    /// Saves the open memo and lets it go if nobody would miss it (blank, still `새 메모(n)`).
    private func leave() {
        flush()
        if renaming != nil { commitRename(toBody: false) }
        confirmingDelete = nil
        if let noteID { book.discardIfEmpty(noteID) }
    }

    private func show(_ id: UUID?, in period: Period) {
        self.period = period
        noteID = id
        book.choose(id, in: period)
        let stored = book.text(note: id)
        isUnreadable = stored == nil
        text = stored ?? AttributedString()
        saved = text
        // The bar is about the memo left.
        showsParagraphBar = false
        savedAttachments = MemoAttachments.ids(in: text)
        selection = AttributedTextSelection()
        // Chips show their ToDo as it is now; a change found here is saved like any other edit.
        refreshChips()
    }

    /// After typing stops for half a second the memo is saved.
    func textChanged() {
        keepCodeBlocksWhole()
        keepParagraphsWhole()
        keepTablesWhole()
        keepChipsWhole()
        keepAttachmentsWhole()
        catchSearchTrigger()
        guard text != saved else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Saves now: when the period changes, the editor goes away, or the app quits. A failed save
    /// keeps the text unsaved, so the next pause or flush tries again.
    func flush() {
        pending?.cancel()
        pending = nil
        guard let period, !isUnreadable, text != saved else { return }
        guard case .saved(let id) = book.save(text, note: noteID, in: period) else { return }
        noteID = id
        saved = text
        // An attachment no longer used here may be used nowhere: it waits to be cleared away.
        let attachments = MemoAttachments.ids(in: text)
        if !savedAttachments.subtracting(attachments).isEmpty { book.sweepAttachments() }
        savedAttachments = attachments
    }

    /// The stored memo changed underneath (another device's text arrived after this box was
    /// saved): show what is stored. Text added at the end keeps the caret where it was.
    func storedChanged() {
        guard let period else { return }
        // The period had no memo here and another device's arrived: it is opened. Letters typed
        // meanwhile are saved first, as a memo of their own.
        if noteID == nil {
            flush()
            if noteID == nil { show(book.chosenNote(in: period), in: period) }
            return
        }
        // Deleted on the other device: the period's memo there is shown instead.
        if let noteID, !book.exists(noteID) {
            pending?.cancel()
            pending = nil
            self.noteID = nil
            if renaming == noteID { renaming = nil }
            show(book.chosenNote(in: period), in: period)
            return
        }
        let stored = book.text(note: noteID)
        isUnreadable = stored == nil
        let fresh = stored ?? AttributedString()
        if fresh != text {
            text.transform(updating: &selection) { text in
                if fresh.characters.starts(with: text.characters) {
                    let end = fresh.characters.index(fresh.startIndex, offsetBy: text.characters.count)
                    text.append(fresh[end...])
                }
                if text != fresh { text = fresh }
            }
        }
        saved = text
        savedAttachments = MemoAttachments.ids(in: text)
    }

    // MARK: Formatting

    /// Some letters are picked, not just a caret.
    var hasSelectedText: Bool {
        guard case .ranges(let ranges) = selection.indices(in: text) else { return false }
        return ranges.ranges.contains { !$0.isEmpty }
    }

    /// Every picked letter (or the caret's typing style) has this switched on.
    func isOn<K: AttributedStringKey>(_ key: K.Type) -> Bool where K.Value == Bool {
        selection.attributes(in: text)[key].allSatisfy { $0 == true }
    }

    /// The value every picked letter shares, or nil when they differ or have none.
    func shared<K: AttributedStringKey>(_ key: K.Type) -> K.Value? where K.Value: Hashable & Sendable {
        let values = Set(selection.attributes(in: text)[key])
        return values.count == 1 ? values.first! : nil
    }

    /// The caret's or selection's lines are a code block, or the letters picked within a line are
    /// all inline code. Judged by the lines, since a caret at the start of a code line types with
    /// the plain line break before it.
    var isCode: Bool {
        let lines = lineRanges(of: selectedRanges)
        guard lines.ranges.contains(where: { !$0.isEmpty }) else { return isOn(MemoAttributes.Code.self) }
        if text[lines].runs[MemoAttributes.Code.self].allSatisfy({ $0.0 == true }) { return true }
        // A caret typing inline code.
        if !hasSelectedText { return isOn(MemoAttributes.InlineCode.self) }
        guard let pick = inlinePick else { return false }
        return text[pick].runs[MemoAttributes.InlineCode.self].allSatisfy { $0.0 == true }
    }

    /// The picked letters when they are part of one line: one range, no line break in it, short
    /// of the whole line. `{ }` makes these inline code instead of a code block.
    var inlinePick: Range<AttributedString.Index>? {
        let picked = selectedRanges.filter { !$0.isEmpty }
        guard picked.count == 1, let range = picked.first, !text[range].characters.contains(where: \.isNewline) else { return nil }
        guard lineRanges(of: [range]).ranges.first != range else { return nil }
        return range
    }

    func toggle<K: AttributedStringKey>(_ key: K.Type) where K.Value == Bool {
        let on = !isOn(key)
        change { $0[key] = on ? true : nil }
    }

    func setInk(_ palette: Palette?) {
        change { $0[MemoAttributes.Ink.self] = palette }
    }

    func setHighlight(_ palette: Palette?) {
        if let palette { lastHighlight = palette }
        change { $0[MemoAttributes.Highlight.self] = palette }
    }

    /// ⌘⇧H: the last highlighter, or off again where it is already on.
    func repeatHighlight() {
        setHighlight(shared(MemoAttributes.Highlight.self) == lastHighlight ? nil : lastHighlight)
    }

    /// Letters picked within one line become inline code, or plain again when they all are. A code
    /// block takes whole lines: every line the selection touches, with no pick or a pick across
    /// lines (or the whole line); a code block line goes back to plain whole, however it is picked.
    func toggleCode() {
        let lines = lineRanges(of: selectedRanges)
        let inBlock = lines.ranges.contains { !$0.isEmpty } && text[lines].runs[MemoAttributes.Code.self].allSatisfy { $0.0 == true }
        // A caret typing inline code stops typing it.
        if !inBlock, !hasSelectedText, isOn(MemoAttributes.InlineCode.self) {
            change { $0[MemoAttributes.InlineCode.self] = nil }
            return
        }
        if !inBlock, let pick = inlinePick {
            let on = !text[pick].runs[MemoAttributes.InlineCode.self].allSatisfy { $0.0 == true }
            text.transform(updating: &selection) { text in
                text[pick][MemoAttributes.InlineCode.self] = on ? true : nil
                if on { text[pick][MemoAttributes.Highlight.self] = nil }
            }
            return
        }
        toggleCodeBlock()
    }

    private func toggleCodeBlock() {
        let on = !isCode
        var lines = lineRanges(of: selectedRanges)
        // Off takes the line breaks around the lines too, so no code is left for a later edit to
        // spread back over them.
        if !on { widenToLineBreaks(&lines) }
        text.transform(updating: &selection) { text in
            text[lines][MemoAttributes.Code.self] = on ? true : nil
            // The block takes over any inline code in its lines.
            text[lines][MemoAttributes.InlineCode.self] = nil
            if on { text[lines][MemoAttributes.Highlight.self] = nil }
        }
        // Also the caret's typing style, so an empty line starts the block. Not for a selection,
        // which may hold a line break that would carry code into the next line.
        if !hasSelectedText { change { $0[MemoAttributes.Code.self] = on ? true : nil } }
    }

    /// A caret at the front of a line does not go on typing inline code carried over the line
    /// break (Return at the end of some): inline code is letters within a line.
    func dropInlineCodeAtLineStart() {
        guard case .insertionPoint(let caret) = selection.indices(in: text), caret > text.startIndex,
              text.characters[text.characters.index(before: caret)].isNewline, isOn(MemoAttributes.InlineCode.self) else { return }
        // The line break it went over too, so no code ground is left at the line's end.
        let lineBreak = text.characters.index(before: caret)..<caret
        text.transform(updating: &selection) { $0[lineBreak][MemoAttributes.InlineCode.self] = nil }
        change { $0[MemoAttributes.InlineCode.self] = nil }
    }

    /// The paragraph style the caret's or selection's lines share; nil for body lines or a mix.
    var paragraph: MemoParagraph? {
        let lines = lineRanges(of: selectedRanges)
        guard lines.ranges.contains(where: { !$0.isEmpty }) else { return shared(MemoAttributes.Paragraph.self) }
        let values = Set(text[lines].runs[MemoAttributes.Paragraph.self].map(\.0))
        return values.count == 1 ? values.first! : nil
    }

    /// 제목, 머리말, 부머리말 (nil: 본문), on every line the selection touches.
    func setParagraph(_ paragraph: MemoParagraph?) {
        var lines = lineRanges(of: selectedRanges)
        // Off takes the line breaks around the lines too, as a code block's does.
        if paragraph == nil { widenToLineBreaks(&lines) }
        text.transform(updating: &selection) { text in
            text[lines][MemoAttributes.Paragraph.self] = paragraph
        }
        // An empty line types in the style it was given.
        if !hasSelectedText { change { $0[MemoAttributes.Paragraph.self] = paragraph } }
    }

    /// The alignment the caret's or selection's lines share; nil for left lines or a mix.
    var align: MemoAlign? {
        let lines = lineRanges(of: selectedRanges)
        guard lines.ranges.contains(where: { !$0.isEmpty }) else { return shared(MemoAttributes.Align.self) }
        let values = Set(text[lines].runs[MemoAttributes.Align.self].map(\.0))
        return values.count == 1 ? values.first! : nil
    }

    /// The caret's line can be centred or right-set (`canTakeAlign`).
    var canAlign: Bool {
        guard let caret = selectedRanges.first?.lowerBound else { return false }
        let string = String(text.characters) as NSString
        let location = text.characters[..<caret].reduce(0) { $0 + $1.utf16.count }
        let line = MemoLists.lineContent(of: string.lineRange(for: NSRange(location: location, length: 0)), in: string)
        // The line's first letter, wherever the caret is on it.
        var start = caret
        while start > text.startIndex, !text.characters[text.characters.index(before: start)].isNewline {
            start = text.characters.index(before: start)
        }
        let run = line.length > 0 ? text.runs[start] : nil
        return canTakeAlign(line, in: string, run: run)
    }

    /// A line of words: list, quote, table, code block, timeline lines and their children, and
    /// rules keep to their own columns, so stay left. `run` is the line's first run (nil when empty).
    private func canTakeAlign(_ line: NSRange, in string: NSString, run: AttributedString.Runs.Run?) -> Bool {
        guard line.length > 0, let run else { return true }
        let letters = string.substring(with: line)
        return MemoLists.marker(in: string, line: line) == nil && !MemoTimeline.isChild(line, in: string)
            && run[MemoAttributes.Table.self] == nil && run[MemoAttributes.Code.self] != true
            && MemoTimeline.stampLength(letters) == nil && !MemoTimeline.isRule(letters)
    }

    /// 왼쪽·가운데·오른쪽 정렬 (nil: left), on every line the selection touches that can take it
    /// (`canTakeAlign`). A beep when none can.
    func setAlign(_ align: MemoAlign?) {
        guard !isUnreadable else { return NSSound.beep() }
        let string = String(text.characters) as NSString
        // Judged against the selection itself: a caret is an empty range, which a range set drops.
        let picked = selectedRanges
        let characters = text.characters
        var lines = RangeSet<AttributedString.Index>()
        var hasEmpty = false
        var offset = 0
        for line in MemoTodoLines.lines(in: text) {
            let length = text[line].characters.reduce(0) { $0 + $1.utf16.count }
            // The line break after it, in UTF-16 units (`\r\n` is one letter of two).
            let breakLength = line.upperBound < characters.endIndex ? characters[line.upperBound].utf16.count : 0
            defer { offset += length + breakLength }
            let touched = picked.contains { range in
                range.isEmpty ? line.lowerBound <= range.lowerBound && range.lowerBound <= line.upperBound
                    : range.overlaps(line) || (line.isEmpty && range.lowerBound <= line.lowerBound && line.lowerBound < range.upperBound)
            }
            guard touched else { continue }
            if line.isEmpty {
                // Its line break is the line TextKit draws: it takes the alignment too.
                hasEmpty = true
                if line.lowerBound < characters.endIndex { lines.insert(line.lowerBound, within: characters) }
                continue
            }
            guard canTakeAlign(NSRange(location: offset, length: length), in: string, run: text.runs[line.lowerBound]) else { continue }
            lines.insert(contentsOf: line)
        }
        guard !lines.isEmpty || hasEmpty else { return NSSound.beep() }
        // Off takes the line breaks around the lines too, as a paragraph style's does.
        if align == nil { widenToLineBreaks(&lines) }
        if !lines.isEmpty {
            text.transform(updating: &selection) { text in
                text[lines][MemoAttributes.Align.self] = align
            }
        }
        // An empty line types in the alignment it was given.
        if !hasSelectedText { change { $0[MemoAttributes.Align.self] = align } }
    }

    /// 지우기: back to plain text. A code block and a paragraph style go whole lines at a time,
    /// as they came.
    func clearFormatting() {
        var lines = lineRanges(of: selectedRanges)
        widenToLineBreaks(&lines)
        text.transform(updating: &selection) { text in
            text[lines][MemoAttributes.Code.self] = nil
            text[lines][MemoAttributes.Paragraph.self] = nil
            text[lines][MemoAttributes.Align.self] = nil
        }
        change { container in
            container[MemoAttributes.Bold.self] = nil
            container[MemoAttributes.Italic.self] = nil
            container[MemoAttributes.Underline.self] = nil
            container[MemoAttributes.Strike.self] = nil
            container[MemoAttributes.Paragraph.self] = nil
            container[MemoAttributes.Code.self] = nil
            container[MemoAttributes.InlineCode.self] = nil
            container[MemoAttributes.Align.self] = nil
            container[MemoAttributes.Math.self] = nil
            container[MemoAttributes.Script.self] = nil
            container[MemoAttributes.Ink.self] = nil
            container[MemoAttributes.Highlight.self] = nil
        }
    }

    /// The editor's onChange picks up the new text and schedules the save.
    func change(_ body: (inout AttributeContainer) -> Void) {
        text.transformAttributes(in: &selection, body: body)
    }

    /// A line with any code in it is code throughout, so letters typed at the start of a code
    /// line join the block instead of sitting in it as plain text.
    private func keepCodeBlocksWhole() {
        // Not mid-syllable: widening would break the composition up; the finished letter comes next.
        if isComposing { return }
        var partial = RangeSet<AttributedString.Index>()
        // Line by line: widening the whole text at once would read the memo as one long line.
        for line in MemoTodoLines.lines(in: text) where !line.isEmpty {
            let flags = text[line].runs[MemoAttributes.Code.self].map { $0.0 == true }
            if flags.contains(true), flags.contains(false) { partial.insert(contentsOf: line) }
        }
        guard !partial.isEmpty else { return }
        text.transform(updating: &selection) { text in
            text[partial][MemoAttributes.Code.self] = true
            text[partial][MemoAttributes.Highlight.self] = nil
        }
    }

    /// A line in two paragraph styles or alignments (letters typed at the front of a title, or two
    /// lines joined) takes the first one in it throughout.
    private func keepParagraphsWhole() {
        if isComposing { return }
        var paragraphs: [(line: Range<AttributedString.Index>, paragraph: MemoParagraph)] = []
        var aligns: [(line: Range<AttributedString.Index>, align: MemoAlign)] = []
        for line in MemoTodoLines.lines(in: text) where !line.isEmpty {
            // Both read in one pass over the line's runs.
            var values: [MemoParagraph?] = [], sides: [MemoAlign?] = []
            for (paragraph, side, _) in text[line].runs[MemoAttributes.Paragraph.self, MemoAttributes.Align.self] {
                values.append(paragraph)
                sides.append(side)
            }
            if let first = values.compactMap({ $0 }).first, values.contains(where: { $0 != first }) { paragraphs.append((line, first)) }
            if let first = sides.compactMap({ $0 }).first, sides.contains(where: { $0 != first }) { aligns.append((line, first)) }
        }
        guard !paragraphs.isEmpty || !aligns.isEmpty else { return }
        text.transform(updating: &selection) { text in
            for fix in paragraphs { text[fix.line][MemoAttributes.Paragraph.self] = fix.paragraph }
            for fix in aligns { text[fix.line][MemoAttributes.Align.self] = fix.align }
        }
    }

    /// The line breaks on either side of each line, added in.
    private func widenToLineBreaks(_ lines: inout RangeSet<AttributedString.Index>) {
        let characters = text.characters
        for line in lines.ranges {
            if line.lowerBound > characters.startIndex { lines.insert(characters.index(before: line.lowerBound), within: characters) }
            if line.upperBound < characters.endIndex { lines.insert(line.upperBound, within: characters) }
        }
    }

    var selectedRanges: [Range<AttributedString.Index>] {
        switch selection.indices(in: text) {
        case .insertionPoint(let index): [index..<index]
        case .ranges(let ranges): Array(ranges.ranges)
        }
    }

    /// Each range widened to the whole lines it touches, line breaks left out. A selection that
    /// ends just after a line break (a triple-click) stays on its own line.
    private func lineRanges(of ranges: [Range<AttributedString.Index>]) -> RangeSet<AttributedString.Index> {
        let characters = text.characters
        var lines = RangeSet<AttributedString.Index>()
        for range in ranges {
            var start = range.lowerBound
            while start > characters.startIndex, !characters[characters.index(before: start)].isNewline {
                start = characters.index(before: start)
            }
            var end = range.upperBound
            if !range.isEmpty, end > start, characters[characters.index(before: end)].isNewline {
                end = characters.index(before: end)
            } else {
                while end < characters.endIndex, !characters[end].isNewline {
                    end = characters.index(after: end)
                }
            }
            lines.insert(contentsOf: start..<end)
        }
        return lines
    }
}

/// How memo formatting looks: 15 pt SF on 26 pt lines, palette colours by name.
enum MemoStyle {
    static let size: CGFloat = TextStyle.memo.size
    static let lineHeight: CGFloat = TextStyle.memo.lineHeight
    /// The memo's least height, when the panel has less left for it.
    static let minHeight: CGFloat = 170
    /// Where the text view draws its first letter inside its own frame; the placeholder and the
    /// snapshot's text sit that much further in, so they line up with typed text.
    static let textViewInset = CGSize(width: 5, height: 4)

    /// A chip's box letter: larger than the text, so it is easy to hit.
    static let boxSize: CGFloat = 20

    static func font(bold: Bool, italic: Bool, code: Bool, math: Bool, script: MemoScript?, box: Bool = false,
                     paragraph: MemoParagraph? = nil, inlineCode: Bool = false) -> Font {
        // In the memo's own face, only larger.
        if box { return .system(size: boxSize) }
        // Inline code: fixed-width at the code block's size, or at its title's or heading's.
        if inlineCode && !code {
            let size: CGFloat = switch paragraph {
            case .title?: TextStyle.title.size
            case .heading?: TextStyle.heading.size
            default: 13
            }
            var font: Font = .system(size: size, weight: paragraph == nil ? .regular : .semibold, design: .monospaced)
            if bold { font = font.bold() }
            if italic { font = font.italic() }
            return font
        }
        // The title and heading tokens, and the memo's letters at 600 for a subheading; no new sizes.
        if let paragraph, !code {
            var font: Font = switch paragraph {
            case .title: TextStyle.title.font
            case .heading: TextStyle.heading.font
            case .sub: .system(size: Self.size, weight: bold ? .bold : .semibold)
            }
            if italic || math { font = font.italic() }
            return font
        }
        var size = code ? 13 : math ? 16 : Self.size
        if script != nil { size = (size * 0.7).rounded() }
        var font: Font = code ? .system(size: size, design: .monospaced) : math ? .system(size: size, design: .serif) : .system(size: size)
        if bold { font = font.bold() }
        if italic || math { font = font.italic() }
        return font
    }

    static func baselineOffset(_ script: MemoScript?) -> CGFloat? {
        switch script {
        case .raised: 5
        case .lowered: -3
        case nil: nil
        }
    }

    static func ground(code: Bool, highlight: Palette?, todo: MemoTodo? = nil) -> Color? {
        if code { return Tokens.shadeSoft }
        // A highlighter laid over a chip shows; otherwise the chip's own grey.
        return highlight?.tint ?? (todo != nil ? Tokens.chip : nil)
    }

    /// A chip's letters once its ToDo is done: soft and struck through. Letters struck through by
    /// hand are soft too, unless they have a colour of their own.
    static func ink(_ palette: Palette?, todo: MemoTodo?, struck: Bool = false) -> Color? {
        todo?.isDone == true ? Tokens.inkSoft : palette?.ink ?? (struck ? Tokens.inkSoft : nil)
    }

    /// A done chip's title (the box letter shows its tick unstruck), or letters struck through by hand.
    static func strike(_ todo: MemoTodo?, box: Bool = false, struck: Bool = false) -> Text.LineStyle? {
        (todo?.isDone == true || struck) && !box ? .single : nil
    }

    static func underline(_ on: Bool) -> Text.LineStyle? {
        on ? .single : nil
    }

    /// The memo with SwiftUI's own attributes filled in, for drawing it as plain `Text`.
    static func rendered(_ text: AttributedString) -> AttributedString {
        var text = text
        for run in text.runs {
            let code = run[MemoAttributes.Code.self] == true
            let script = run[MemoAttributes.Script.self]
            let box = run[MemoAttributes.TodoBox.self] == true
            let inline = run[MemoAttributes.InlineCode.self] == true
            text[run.range].font = font(bold: run[MemoAttributes.Bold.self] == true, italic: run[MemoAttributes.Italic.self] == true,
                                        code: code, math: run[MemoAttributes.Math.self] == true, script: script, box: box,
                                        paragraph: run[MemoAttributes.Paragraph.self], inlineCode: inline)
            let todo = run[MemoAttributes.Todo.self]
            let struck = run[MemoAttributes.Strike.self] == true
            text[run.range].foregroundColor = ink(run[MemoAttributes.Ink.self], todo: todo, struck: struck)
            text[run.range].backgroundColor = ground(code: code || inline, highlight: run[MemoAttributes.Highlight.self], todo: todo)
            text[run.range].strikethroughStyle = strike(todo, box: box, struck: struck)
            text[run.range].underlineStyle = underline(run[MemoAttributes.Underline.self] == true)
            text[run.range].baselineOffset = baselineOffset(script)
        }
        return text
    }
}

/// What the memo editor accepts: the memo's own formatting, drawn through SwiftUI's font, colour,
/// baseline and line attributes. Anything else (pasted fonts, links, pasted underlines) is dropped.
struct MemoFormatting: AttributedTextFormattingDefinition {
    struct Scope: AttributeScope {
        let font: AttributeScopes.SwiftUIAttributes.FontAttribute
        let foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        let backgroundColor: AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
        let baselineOffset: AttributeScopes.SwiftUIAttributes.BaselineOffsetAttribute
        let strikethroughStyle: AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute
        let underlineStyle: AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
        let memo: AttributeScopes.MemoScope
    }

    var body: some AttributedTextFormattingDefinition<Scope> {
        FontFromFormatting()
        InkFromFormatting()
        GroundFromFormatting()
        BaselineFromFormatting()
        StrikeFromFormatting()
        UnderlineFromFormatting()
    }

    private struct FontFromFormatting: AttributedTextValueConstraint {
        typealias Scope = MemoFormatting.Scope
        typealias AttributeKey = AttributeScopes.SwiftUIAttributes.FontAttribute

        func constrain(_ container: inout Attributes) {
            container[AttributeKey.self] = MemoStyle.font(
                bold: container[MemoAttributes.Bold.self] == true, italic: container[MemoAttributes.Italic.self] == true,
                code: container[MemoAttributes.Code.self] == true, math: container[MemoAttributes.Math.self] == true,
                script: container[MemoAttributes.Script.self], box: container[MemoAttributes.TodoBox.self] == true,
                paragraph: container[MemoAttributes.Paragraph.self], inlineCode: container[MemoAttributes.InlineCode.self] == true)
        }
    }

    private struct InkFromFormatting: AttributedTextValueConstraint {
        typealias Scope = MemoFormatting.Scope
        typealias AttributeKey = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute

        func constrain(_ container: inout Attributes) {
            container[AttributeKey.self] = MemoStyle.ink(container[MemoAttributes.Ink.self], todo: container[MemoAttributes.Todo.self],
                                                         struck: container[MemoAttributes.Strike.self] == true)
        }
    }

    private struct GroundFromFormatting: AttributedTextValueConstraint {
        typealias Scope = MemoFormatting.Scope
        typealias AttributeKey = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute

        func constrain(_ container: inout Attributes) {
            container[AttributeKey.self] = MemoStyle.ground(code: container[MemoAttributes.Code.self] == true || container[MemoAttributes.InlineCode.self] == true, highlight: container[MemoAttributes.Highlight.self],
                                                            todo: container[MemoAttributes.Todo.self])
        }
    }

    private struct BaselineFromFormatting: AttributedTextValueConstraint {
        typealias Scope = MemoFormatting.Scope
        typealias AttributeKey = AttributeScopes.SwiftUIAttributes.BaselineOffsetAttribute

        func constrain(_ container: inout Attributes) {
            container[AttributeKey.self] = MemoStyle.baselineOffset(container[MemoAttributes.Script.self])
        }
    }

    private struct StrikeFromFormatting: AttributedTextValueConstraint {
        typealias Scope = MemoFormatting.Scope
        typealias AttributeKey = AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute

        func constrain(_ container: inout Attributes) {
            container[AttributeKey.self] = MemoStyle.strike(container[MemoAttributes.Todo.self], box: container[MemoAttributes.TodoBox.self] == true,
                                                            struck: container[MemoAttributes.Strike.self] == true)
        }
    }

    private struct UnderlineFromFormatting: AttributedTextValueConstraint {
        typealias Scope = MemoFormatting.Scope
        typealias AttributeKey = AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute

        func constrain(_ container: inout Attributes) {
            container[AttributeKey.self] = MemoStyle.underline(container[MemoAttributes.Underline.self] == true)
        }
    }
}

/// The memo, written straight on the panel's paper under its section rule: no box, the text's left
/// edge on the rule's, lines as wide as the panel. It fills `height` (what the panel
/// has left) and scrolls inside itself; the format bar shows over or under the picked line while
/// letters are picked. Keyboard focus shows as the caret and the section rule's spine weight.
struct MemoEditor: View {
    @Bindable var draft: MemoDraft
    let period: Period
    /// The day chosen in the calendar, for the date a week or month memo's timeline line names.
    let chosenDay: Date
    let height: CGFloat
    /// The section name, for VoiceOver.
    let title: String
    let placeholder: String
    /// The caret's line, in the memo's own place, after the caret moves or the memo takes focus:
    /// the panel scrolls it into view when it is outside.
    var onCaretLine: ((CGRect) -> Void)? = nil
    @FocusState private var focused: Bool
    @Environment(\.isRenderingSnapshot) private var isRenderingSnapshot
    @Environment(\.undoManager) private var undoManager
    /// The memo's top within the panel's scroll view, to put the bar where it fits.
    @State private var top: CGFloat = 0
    /// The selected line in the memo, for putting the bar beside it.
    @State private var line: CGRect?

    /// Where typed letters start: the text view's own inset is taken back on the left, so the
    /// first letter stands on the section rule's edge.
    private var textInset: EdgeInsets {
        EdgeInsets(top: MemoStyle.textViewInset.height, leading: 0, bottom: MemoStyle.textViewInset.height, trailing: 0)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isRenderingSnapshot {
                // ImageRenderer cannot draw the AppKit text view.
                MemoPrint(text: draft.text)
                    .padding(textInset)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            } else {
                TextEditor(text: $draft.text, selection: $draft.selection)
                    .attributedTextFormattingDefinition(MemoFormatting())
                    .textStyle(.memo)
                    .lineHeight(.exact(points: TextStyle.memo.lineHeight))
                    .foregroundStyle(.ink)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .disabled(draft.isUnreadable)
                    .padding(.leading, -MemoStyle.textViewInset.width)
                    .accessibilityLabel(title)
                    .accessibilityHint(placeholder)
                    .accessibilityAction(.showMenu) { draft.showMenu?() }
            }
            if draft.text.characters.isEmpty {
                Text(draft.isUnreadable ? "이 메모는 이 버전에서 열 수 없어요. 앱을 업데이트해 주세요." : placeholder)
                    .textStyle(.memo)
                    // A placeholder is faint; the unreadable notice is read, so it is soft ink.
                    .foregroundStyle(draft.isUnreadable ? Color.inkSoft : Color.inkFaint)
                    .padding(textInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        // Past the end of the lines, or beside a short memo in a wide panel: still the memo.
        .contentShape(Rectangle())
        .onTapGesture { if !draft.isUnreadable { focused = true } }
        .background { if !isRenderingSnapshot { MemoMenuHost(draft: draft).modifier(AttachmentPreview(draft: draft)) } }
        .onGeometryChange(for: CGRect.self) { proxy in
            let local = CGRect(origin: .zero, size: proxy.size)
            let shown = proxy.bounds(of: .scrollView).map { local.intersection($0) } ?? local
            let frame = proxy.frame(in: .global)
            return shown.offsetBy(dx: frame.minX, dy: frame.minY)
        } action: { draft.visibleBox = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { draft.boxFrame = $0 }
        .overlay(alignment: .topLeading) {
            if showsBar {
                MemoFormatBar(draft: draft).offset(y: barY)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { top = $0 }
        // Under the memo the bar would hang past the end of the scroll content, where clicks do not
        // reach it; the room is made inside the content instead.
        .padding(.bottom, showsBar ? max(0, barY + MemoFormatBar.height - height) : 0)
        .focusedValue(\.memoDraft, focused ? draft : nil)
        .onChange(of: focused, initial: true) {
            draft.hasFocus = focused
            // Once the text view has become first responder.
            if focused {
                Task { @MainActor in
                    draft.inkTextView?()
                    if let caret = draft.caretLineRect?() { onCaretLine?(inBox(caret)) }
                }
            }
            draft.redrawLines?()
        }
        .onChange(of: chosenDay, initial: true) { draft.chosenDay = chosenDay }
        // The week's first day counts too: periods equal across calendars still open again under the new one.
        .onChange(of: [period.key, "\(period.start.timeIntervalSinceReferenceDate)", "\(period.calendar.firstWeekday)"], initial: true) {
            draft.open(period)
            // The text view stays the same across days; its undo steps belong to the memo it left.
            // After the text view has taken the new text, so that swap is not left as a step either.
            Task { @MainActor in undoManager?.removeAllActions() }
        }
        .onChange(of: draft.text) {
            draft.textChanged()
            draft.redrawLines?()
        }
        .onChange(of: draft.selection) {
            draft.dropInlineCodeAtLineStart()
            draft.selectionChanged()
            draft.redrawLines?()
            // After the text view has laid the new selection out.
            Task { @MainActor in
                line = draft.selectionLineRect?()
                if let caret = draft.caretLineRect?() { onCaretLine?(inBox(caret)) }
            }
        }
        .onChange(of: draft.focusRequest) { focused = true }
        .onChange(of: draft.blurRequest) { focused = false }
        .onAppear {
            guard draft.focusOnAppear else { return }
            draft.focusOnAppear = false
            Task { @MainActor in
                // Its host finds and sets up the text view (the file drop among it) before the
                // focus does: a focused text view is watched by AppKit and is not changed after.
                try? await Task.sleep(for: .milliseconds(60))
                draft.redrawLines?()
                focused = true
            }
        }
        // Another memo of the period: its undo steps stay with the memo it left, as across days.
        .onChange(of: draft.noteID) { Task { @MainActor in undoManager?.removeAllActions() } }
        .onDisappear {
            draft.flush()
            draft.showsParagraphBar = false
            // A folded panel takes the memo away without a focus change.
            draft.hasFocus = false
        }
    }

    /// The caret's line kept inside the memo: past the memo's own scrolled part, its text view
    /// scrolls the line to the nearer edge, so that is where the panel has to show.
    private func inBox(_ line: CGRect) -> CGRect {
        var line = line
        line.origin.y = min(max(0, line.minY), max(0, height - line.height))
        return line
    }

    /// Not for a picked card: its letter is selected, but there are no letters to format.
    private var showsBar: Bool { focused && draft.hasSelectedText && !draft.showsParagraphBar && draft.pickedAttachment == nil }

    /// The bar's top within the memo. Beside the selected line: over it where the panel shows
    /// enough room, otherwise under it. Without the line's place, over the memo or at its foot.
    private var barY: CGFloat {
        let barHeight = MemoFormatBar.height
        guard let line, line.maxY > 0, line.minY < height else {
            return top > barHeight + Metrics.spaceL ? -barHeight - Metrics.spaceS : height - barHeight - Metrics.spaceS
        }
        return top + line.minY > barHeight + Metrics.spaceL ? line.minY - barHeight - Metrics.spaceS : line.maxY + Metrics.spaceS
    }
}

/// Quick Look on an attachment: a double-click or Space on its card.
private struct AttachmentPreview: ViewModifier {
    @Bindable var draft: MemoDraft

    func body(content: Content) -> some View {
        content.quickLookPreview($draft.previewURL)
    }
}

/// Bold, italic, underline, strikethrough, code (inline for letters picked within a line, else a
/// code block) and formula, then
/// text colour and highlighter from the palette. Shortcuts show on hover and live in the 서식 menu
/// too, with 서식 지우기, which the bar has no room for.
struct MemoFormatBar: View {
    let draft: MemoDraft
    static let height: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceS) {
            HStack(spacing: Metrics.spaceXs) {
                style("B", "굵게", "⌘B", isOn: draft.isOn(MemoAttributes.Bold.self), font: TextStyle.body.font.bold()) { draft.toggle(MemoAttributes.Bold.self) }
                style("I", "기울임", "⌘I", isOn: draft.isOn(MemoAttributes.Italic.self), font: TextStyle.body.font.italic(), design: .serif) { draft.toggle(MemoAttributes.Italic.self) }
                style("U", "밑줄", "⌘U", isOn: draft.isOn(MemoAttributes.Underline.self), font: TextStyle.body.font, line: .underline) { draft.toggle(MemoAttributes.Underline.self) }
                style("S", "취소선", "⌘⇧X", isOn: draft.isOn(MemoAttributes.Strike.self), font: TextStyle.body.font, line: .strike) { draft.toggle(MemoAttributes.Strike.self) }
                style("{ }", draft.inlinePick == nil ? "코드 블록" : "코드", "⌘⇧C", isOn: draft.isCode, font: TextStyle.cell.font.weight(.semibold), design: .monospaced) { draft.toggleCode() }
                Rectangle().fill(.ink).frame(width: Metrics.line, height: 18).padding(.horizontal, Metrics.spaceXxs)
                style("fx", "수식", "⌥⌘E", isOn: draft.isOn(MemoAttributes.Math.self), font: TextStyle.item.font.italic(), design: .serif) { draft.toggleFormula() }
                Spacer(minLength: Metrics.spaceM)
                Button("시각") { draft.insertTime() }
                    .buttonStyle(DrawnButtonStyle(.text))
                    .focusable(false)
                    .help("시각 넣기 (⌃⌘T)")
            }
            let ink = draft.shared(MemoAttributes.Ink.self)
            HStack(spacing: Metrics.spaceXxs) {
                swatch(label: "기본", isOn: ink == nil) {
                    Text("가").textStyle(.item).foregroundStyle(.ink)
                } action: { draft.setInk(nil) }
                ForEach(Palette.allCases, id: \.self) { palette in
                    swatch(label: palette.name, isOn: ink == palette) {
                        Text("가").textStyle(.item).foregroundStyle(palette.ink)
                    } action: { draft.setInk(palette) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("글자색")
            let highlight = draft.shared(MemoAttributes.Highlight.self)
            HStack(spacing: Metrics.spaceXxs) {
                swatch(label: "형광펜 없음", isOn: highlight == nil) {
                    Path { p in p.move(to: CGPoint(x: 2, y: 20)); p.addLine(to: CGPoint(x: 20, y: 2)) }.stroke(.ink, lineWidth: Metrics.line)
                } action: { draft.setHighlight(nil) }
                ForEach(Palette.allCases, id: \.self) { palette in
                    swatch(label: palette.name, help: palette == draft.lastHighlight ? "\(palette.name) 형광펜 (⌘⇧H)" : nil, isOn: highlight == palette) {
                        palette.tint
                    } action: { draft.setHighlight(palette) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("형광펜")
        }
        .padding(Metrics.spaceM)
        .frame(width: 312, height: Self.height, alignment: .topLeading)
        .floatingFrame()
    }

    private enum Line { case underline, strike }

    private func style(_ title: String, _ name: String, _ shortcut: String, isOn: Bool, font: Font, design: Font.Design? = nil, line: Line? = nil,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .fontDesign(design)
                .underline(line == .underline)
                .strikethrough(line == .strike)
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

    private func swatch(label: String, help: String? = nil, isOn: Bool, @ViewBuilder content: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content()
                .frame(width: 22, height: 22)
                .background(.paper)
                .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
                .padding(Metrics.spaceXxs)
        }
        // The swatch keeps its colour; the chosen one stands in an ink square.
        .buttonStyle(FormatButtonStyle(isOn: isOn))
        .focusable(false)
        .help(help ?? label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A format bar button: ink when switched on, the hover step under the pointer. The bar never takes
/// keyboard focus, so it draws no ring.
struct FormatButtonStyle: ButtonStyle {
    var isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        FormatButtonBody(configuration: configuration, isOn: isOn)
    }

    private struct FormatButtonBody: View {
        let configuration: Configuration
        var isOn: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(isOn ? Color.ink : configuration.isPressed ? Color.rowActive : hovering ? Color.hover : Color.paper)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

extension FocusedValues {
    /// The memo being written, while its box has keyboard focus.
    @Entry var memoDraft: MemoDraft?
}

/// The 서식 menu: the format bar's buttons with their shortcuts, for the focused memo.
struct MemoCommands: Commands {
    @FocusedValue(\.memoDraft) private var draft

    var body: some Commands {
        CommandMenu("서식") {
            Group {
                Button("굵게") { draft?.toggle(MemoAttributes.Bold.self) }
                    .keyboardShortcut("b", modifiers: .command)
                Button("기울임") { draft?.toggle(MemoAttributes.Italic.self) }
                    .keyboardShortcut("i", modifiers: .command)
                Button("밑줄") { draft?.toggle(MemoAttributes.Underline.self) }
                    .keyboardShortcut("u", modifiers: .command)
                Button("취소선") { draft?.toggle(MemoAttributes.Strike.self) }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                Button("코드 블록") { draft?.toggleCode() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Divider()
                Button("수식") { draft?.toggleFormula() }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                Divider()
                Button("형광펜 (\((draft?.lastHighlight ?? .yellow).name))") { draft?.repeatHighlight() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("서식 지우기") { draft?.clearFormatting() }
                Divider()
                Button("제목") { draft?.setParagraph(.title) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("머리말") { draft?.setParagraph(.heading) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("부머리말") { draft?.setParagraph(.sub) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("본문") { draft?.setParagraph(nil) }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                Divider()
                // As in the usual document apps (Left, cEnter, Right). Not ⌘{ ⌘| ⌘}: ⌘| is ⌘⇧\,
                // the 보기 menu's panel width.
                Button("왼쪽 정렬") { draft?.setAlign(nil) }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("가운데 정렬") { draft?.setAlign(.center) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("오른쪽 정렬") { draft?.setAlign(.right) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("글머리 기호 목록") { draft?.setList(.bullet) }
                    .keyboardShortcut("7", modifiers: [.command, .shift])
                Button("대시 목록") { draft?.setList(.dash) }
                    .keyboardShortcut("8", modifiers: [.command, .shift])
                Button("번호 목록") { draft?.setList(.number) }
                    .keyboardShortcut("9", modifiers: [.command, .shift])
                Button("인용문") { draft?.setList(.quote) }
                    .keyboardShortcut("'", modifiers: .command)
                Button("들여쓰기") { draft?.indentLines(by: 1) }
                    .keyboardShortcut("]", modifiers: .command)
                Button("내어쓰기") { draft?.indentLines(by: -1) }
                    .keyboardShortcut("[", modifiers: .command)
                // No shortcut: ⌥⌘T is the 보기 menu's toolbar item.
                Button("표 넣기") { draft?.tableAction(.insert) }
                Button("파일 첨부…") { draft?.askToAttach() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
                Button("할 일로 만들기…") { draft?.askToMakeTodos() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("할 일 가져오기…") { draft?.askToLinkTodo() }
                Button("할 일 체크") { draft?.toggleChipAtCaret() }
                Divider()
                Button("시각 넣기") { draft?.insertTime() }
                    .keyboardShortcut("t", modifiers: [.command, .control])
            }
            .disabled(draft == nil)
            Divider()
            // Whether a memo is focused or not. No shortcut: ⌥⌘T is the 보기 menu's toolbar item.
            Toggle("서식 막대 늘 보이기", isOn: Binding(get: { MemoBarPin.shared.isPinned }, set: { MemoBarPin.shared.isPinned = $0 }))
        }
    }
}
