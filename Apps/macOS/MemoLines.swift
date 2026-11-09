import AppKit
import SwiftUI
import SimplifyKit

// Rules and timeline lines: how the memo draws `────` and `11.02 08:30 …` lines, and ⌃⌘T. Only the
// drawing changes; the letters stay as typed, so the store, the synced copy and the Notes mirror
// keep them (`MemoTimeline` finds the lines).

extension MemoDraft {
    /// ⌃⌘T, the format bar's 시각 and the right-click menu: `11.03 14:25 ` at the front of the
    /// caret's line, or on a new line under it when the line has words. A day memo names its own
    /// day; a week or month memo today, or the chosen day when today is outside it.
    func insertTime(now: Date = .now) {
        guard let period, !isUnreadable, let caret = selectedRanges.first?.lowerBound else {
            NSSound.beep()
            return
        }
        let calendar = period.calendar
        let day = MemoTimeline.stampDay(for: period, today: calendar.startOfDay(for: now), chosen: chosenDay ?? period.start)
        let stamp = MemoTimeline.stamp(day: day, now: now, calendar: calendar)
        let characters = text.characters
        let put = MemoTimeline.insertion(in: String(characters), caret: characters.distance(from: characters.startIndex, to: caret), stamp: stamp)
        text.transform(updating: &selection) { text in
            text.insert(AttributedString(put.text), at: text.characters.index(text.startIndex, offsetBy: put.offset))
        }
        let after = text.characters.index(text.startIndex, offsetBy: min(put.caretAfter, text.characters.count))
        selection = AttributedTextSelection(insertionPoint: after, typingAttributes: AttributeContainer())
        focusRequest += 1
    }
}

/// Draws the memo's rules, timeline lines, lists, quotes and titles in its text view, through
/// TextKit 2's own hooks: the content storage hands out each paragraph with display-only changes
/// (the time in figures and soft ink with a hanging indent; a rule's letters hidden; a list item's
/// marker by level with the words hanging after it; a quote's `>` hidden; a title's or heading's
/// line height), and the layout manager gives a rule paragraph a fragment that draws an ink line
/// across the memo instead, and a quote one that draws an ink line down its side. A formula's
/// letters give way to its drawing (`FormulaAttachment`). The storage (and so the memo's text) is
/// never touched. A rule shows its letters again while the caret is on it, so it can be edited
/// like any line, and a formula its LaTeX while the caret is in it.
@MainActor
final class MemoLineStyler: NSObject, NSTextContentStorageDelegate, NSTextLayoutManagerDelegate {
    /// The memo's text view, once attached.
    private(set) weak var textView: NSTextView?
    /// The rule paragraph the caret is on, shown as letters.
    private var openRule: NSRange?
    /// Whether some timeline line in the memo has a range (`08:30-09:15`), which widens the time column.
    private var hasRange = false
    /// Which lines are timeline lines' children (`MemoTimeline.childLines`): a line that becomes
    /// one, or stops being one, is made again though its own letters did not change.
    private var childLines: [Int] = []
    /// The formula being written: its letters (a formula line's from the `$$ `), shown as LaTeX.
    private(set) var openFormula: NSRange?
    /// A formula left with Esc or → at its end: drawn again though the caret is beside it.
    private var leftFormula: Int?
    /// Where ⌥⌘E put an empty formula: what is typed there is its LaTeX.
    private var emptyFormula: Int?
    /// The last click in the text view, in its coordinates: a click on a drawn formula opens it.
    var lastClick: (point: CGPoint, at: TimeInterval)?
    /// The written formula drawn small under it.
    private var peek: FormulaPeekView?
    /// Hover tips over formulas that cannot be read, and what they say (the text view keeps only the tags).
    private var tips: [NSView.ToolTipTag] = []
    private var tipOwners: [FormulaTip] = []
    /// What the tips were placed for: the letters, the formula being written and the width.
    private var tipsPlacedFor: (letters: Int, open: NSRange?, width: CGFloat)?

    /// The table cell the caret is in, drawn in an ink box.
    private(set) var tableCaret: TableCaret?
    /// The column edges each table was last drawn with, by id: when typing changes them, the
    /// table's other rows are made again too.
    private var tableEdges: [String: [CGFloat]] = [:]
    /// Each table's measured edges and what they were measured from, so its rows share one measure.
    var measuredTables: [String: (letters: NSAttributedString, width: CGFloat?, edges: [CGFloat])] = [:]
    /// The memo's line width tables were last fitted into.
    private var fittedWidth: CGFloat?
    private var frameObserver: NSObjectProtocol?
    /// The picked card's letter, drawn with an ink outline: a clicked card (the caret then stands
    /// just after it, so no selection grey shows around it), or one selected on its own.
    private(set) var pickedAttachment: Int?
    /// The card last clicked, picked while the caret stays where the click put it.
    var clickedAttachment: Int?
    /// The note under the caret, and what takes it away.
    private var notice: MemoNoticeView?
    private var noticeTask: Task<Void, Never>?
    private var shelfObserver: NSObjectProtocol?

    /// The text view it draws for is still in a window.
    var isAttached: Bool { textView?.window != nil }

    /// Takes over the text view's paragraphs, if nothing else has.
    func attach(to textView: NSTextView) {
        guard let storage = textView.textContentStorage, let layout = textView.textLayoutManager else { return }
        if self.textView === textView, storage.delegate === self { return }
        guard storage.delegate == nil || storage.delegate === self, layout.delegate == nil || layout.delegate === self else { return }
        self.textView = textView
        storage.delegate = self
        layout.delegate = self
        // The memo has no font panel. Keeping it up to date reads the letters around the caret
        // through substrings of SwiftUI's storage that are never freed, on every caret move.
        textView.usesFontPanel = false
        // A wider or narrower memo fits its tables again.
        textView.postsFrameChangedNotifications = true
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: textView, queue: .main) { [weak self] _ in
            // After the text view has resized its container to the new frame.
            DispatchQueue.main.async { self?.refitTables() }
        }
        fittedWidth = tableWidth
        // A file arrived or went: its card is drawn again.
        if shelfObserver == nil {
            shelfObserver = NotificationCenter.default.addObserver(forName: AttachmentShelf.didChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(force: true) }
            }
        }
        update(force: true)
    }

    /// Gives the text view's paragraphs back (a read-only memo of 모아 보기 that took another memo's
    /// text view while the memos were laid out again).
    func detach() {
        guard let textView else { return }
        if textView.textContentStorage?.delegate === self { textView.textContentStorage?.delegate = nil }
        if textView.textLayoutManager?.delegate === self { textView.textLayoutManager?.delegate = nil }
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        frameObserver = nil
        self.textView = nil
    }

    /// After the letters, the caret or the focus changed: paragraphs whose look changed are made again.
    func update(force: Bool = false) {
        guard let textView, let storage = textView.textContentStorage, let text = storage.textStorage else { return }
        let string = text.string
        let widened = Self.hasRange(in: string)
        let children = MemoTimeline.childLines(in: string as NSString)
        var rule: NSRange?
        var formula: NSRange?
        var cell: TableCaret?
        var table: (id: String, rows: [NSRange])?
        var picked: Int?
        if textView.window?.firstResponder === textView, let caret = textView.selectedRanges.first?.rangeValue {
            if caret.length == 0, let clicked = clickedAttachment, caret.location == clicked + 1, Self.attachmentRef(in: text, at: clicked) != nil {
                picked = clicked
            } else if caret.length == 1, NSMaxRange(caret) <= text.length, Self.attachmentRef(in: text, at: caret.location) != nil {
                picked = caret.location
            }
        }
        if picked == nil || picked != clickedAttachment { clickedAttachment = nil }
        if let caret = textView.selectedRanges.first?.rangeValue, let found = Self.table(in: text, at: min(caret.location, text.length)) {
            table = found
        }
        if textView.window?.firstResponder === textView, let caret = textView.selectedRanges.first?.rangeValue {
            let paragraph = (string as NSString).paragraphRange(for: NSRange(location: caret.location, length: 0))
            if caret.length == 0, let table, let row = table.rows.first(where: { caret.location >= $0.location && caret.location <= NSMaxRange($0) }),
               let column = MemoTables.cellRanges(of: row, in: string as NSString).firstIndex(where: { caret.location <= NSMaxRange($0) }) {
                cell = TableCaret(row: row, column: column, location: caret.location)
            }
            if MemoTimeline.isRule(Self.line(string, paragraph)) { rule = paragraph }
            let formulas = Self.formulas(in: text, paragraph: paragraph)
            // Left until the caret moves away from the formula.
            if let left = leftFormula, !formulas.contains(where: { $0.letters.location == left && NSMaxRange($0.letters) == caret.location }) {
                leftFormula = nil
            }
            formula = formulaToOpen(formulas, selection: caret)
            // An open formula emptied by Delete stays open, for its LaTeX to be typed again.
            if formula == nil, caret.length == 0, let open = openFormula, open.location == caret.location, !Self.isFormulaLine(open, in: string) {
                emptyFormula = caret.location
            }
            if let empty = emptyFormula, caret.location != empty || caret.length > 0 || formula.map({ $0.location != empty }) == true { emptyFormula = nil }
        } else {
            emptyFormula = nil
            leftFormula = nil
        }
        defer {
            showPeek()
            placeTips()
        }
        // The caret's table, when typing changed its columns: all its rows are made again.
        var grown: NSRange?
        if let table, let first = table.rows.first, let last = table.rows.last {
            let edges = edges(of: table, in: text)
            if tableEdges[table.id] != edges {
                if tableEdges[table.id] != nil { grown = NSRange(location: first.location, length: NSMaxRange(last) - first.location) }
                tableEdges[table.id] = edges
            }
        }
        let cellMoved = cell != tableCaret
        let pickMoved = picked != pickedAttachment
        let childrenMoved = children != childLines
        guard force || widened != hasRange || rule != openRule || formula != openFormula || cellMoved || grown != nil || pickMoved || childrenMoved else { return }
        var changed: [NSRange] = force || widened != hasRange ? [NSRange(location: 0, length: text.length)] : [openRule, rule].compactMap { $0 }
        if !force, widened == hasRange {
            changed += [grown, tableCaret?.row, cell?.row].compactMap { range in
                range.flatMap { NSMaxRange($0) <= text.length ? (string as NSString).paragraphRange(for: $0) : nil }
            }
        }
        tableCaret = cell
        if !force, widened == hasRange, childrenMoved {
            // The lines that became children or stopped being ones, found by counting lines.
            let moved = Set(children).symmetricDifference(childLines)
            let letters = string as NSString
            let last = moved.max() ?? -1
            var start = 0, index = 0
            while start < letters.length, index <= last {
                let line = letters.lineRange(for: NSRange(location: start, length: 0))
                if moved.contains(index) { changed.append(line) }
                start = NSMaxRange(line)
                index += 1
            }
        }
        childLines = children
        if !force, widened == hasRange, pickMoved {
            changed += [pickedAttachment, picked].compactMap { location in
                location.flatMap { $0 < text.length ? (string as NSString).paragraphRange(for: NSRange(location: $0, length: 0)) : nil }
            }
        }
        pickedAttachment = picked
        if !force, widened == hasRange, formula != openFormula {
            // The paragraphs the formula was or is in, as they are now.
            changed += [openFormula, formula].compactMap { range in
                range.map { (string as NSString).paragraphRange(for: NSRange(location: min($0.location, text.length), length: 0)) }
            }
        }
        hasRange = widened
        openRule = rule
        openFormula = formula
        for range in changed where NSMaxRange(range) <= text.length {
            storage.processEditing(for: text, edited: .editedAttributes, range: range, changeInLength: 0, invalidatedRange: range)
        }
        // Laid out now, so the paragraphs made again show even with no edit or scroll to follow.
        if !changed.isEmpty { textView.textLayoutManager?.textViewportLayoutController.layoutViewport() }
    }

    /// After the memo's width changed: every table is fitted again.
    private func refitTables() {
        guard let textView, let storage = textView.textContentStorage, let text = storage.textStorage else { return }
        let width = tableWidth
        guard width != fittedWidth else { return }
        fittedWidth = width
        let spans = Self.tableSpans(in: text)
        guard !spans.isEmpty else { return }
        tableEdges = [:]
        measuredTables = [:]
        for span in spans {
            let range = (text.string as NSString).paragraphRange(for: span)
            storage.processEditing(for: text, edited: .editedAttributes, range: range, changeInLength: 0, invalidatedRange: range)
        }
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
    }

    // MARK: Formulas

    /// The formula the selection is in, to be shown as letters. A caret beside one opens it only
    /// while it is being written, or after a click on it; any caret on a formula line does.
    private func formulaToOpen(_ formulas: [StoredFormula], selection: NSRange) -> NSRange? {
        for formula in formulas {
            let letters = formula.letters
            if selection.length > 0 {
                if selection.location >= letters.location, NSMaxRange(selection) <= NSMaxRange(letters) { return letters }
                continue
            }
            let caret = selection.location
            guard caret >= letters.location, caret <= NSMaxRange(letters) else { continue }
            if wasClicked(letters) { return letters }
            guard leftFormula != letters.location else { continue }
            if formula.isDisplay || (caret > letters.location && caret < NSMaxRange(letters)) { return letters }
            // ⌥⌘E right after a formula opens that one: what is typed would join it anyway.
            if openFormula?.location == letters.location || emptyFormula == letters.location || emptyFormula == NSMaxRange(letters) { return letters }
        }
        return nil
    }

    /// The last click, a moment ago, landed on the formula's drawing.
    private func wasClicked(_ letters: NSRange) -> Bool {
        guard let click = lastClick, ProcessInfo.processInfo.systemUptime - click.at < 0.6 else { return false }
        return frames(of: letters).contains { $0.insetBy(dx: -2, dy: 0).contains(click.point) }
    }

    /// Esc, or → at the formula's end: the formula is drawn again and the caret, put by `moving`,
    /// stays after it. False when no formula is being written.
    func leaveFormula(moving: (Int) -> Void) -> Bool {
        if emptyFormula != nil {
            emptyFormula = nil
            showPeek()
            return true
        }
        guard let open = openFormula else { return false }
        // A click just before is not one to open it again.
        lastClick = nil
        moving(NSMaxRange(open))
        leftFormula = open.location
        update()
        return true
    }

    /// ⌥⌘E with only a caret: what is typed at it is a new formula, shown as it is written.
    func startEmptyFormula(at location: Int) {
        emptyFormula = location
        leftFormula = nil
        update()
    }

    /// The caret is at the end of a formula that is drawn, not written: letters typed there must
    /// not join it.
    var caretIsAfterDrawnFormula: Bool {
        guard let textView, let text = textView.textStorage, let caret = textView.selectedRanges.first?.rangeValue, caret.length == 0,
              textView.window?.firstResponder === textView else { return false }
        let paragraph = (text.string as NSString).paragraphRange(for: caret)
        return Self.formulas(in: text, paragraph: paragraph).contains { !$0.isDisplay && NSMaxRange($0.letters) == caret.location && $0.letters != openFormula }
    }

    /// Where a range of letters sits in the text view, line by line.
    private func frames(of range: NSRange) -> [CGRect] {
        guard let textView, let layout = textView.textLayoutManager, let storage = textView.textContentStorage,
              let start = storage.location(storage.documentRange.location, offsetBy: range.location),
              let end = storage.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return [] }
        var frames: [CGRect] = []
        let origin = textView.textContainerOrigin
        layout.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            frames.append(frame.offsetBy(dx: origin.x, dy: origin.y))
            return true
        }
        return frames
    }

    /// The small drawing under the formula being written, or the hint under an empty one.
    private func showPeek() {
        guard let textView, let text = textView.textStorage else { return }
        var shown: (latex: String, isDisplay: Bool, ink: Palette?, under: [CGRect])?
        if let open = openFormula, NSMaxRange(open) <= text.length,
           let formula = Self.formulas(in: text, paragraph: (text.string as NSString).paragraphRange(for: open)).first(where: { $0.letters == open }) {
            let ink = formula.latex.length > 0 ? Self.palette(text.attribute(Self.inkKey, at: formula.latex.location, effectiveRange: nil)) : nil
            shown = ((text.string as NSString).substring(with: formula.latex), formula.isDisplay, ink, frames(of: formula.letters))
        } else if let empty = emptyFormula, empty <= text.length {
            shown = ("", false, nil, frames(of: NSRange(location: empty, length: 0)))
        }
        guard let shown, let first = shown.under.first, let last = shown.under.last else {
            peek?.removeFromSuperview()
            peek = nil
            return
        }
        let view = peek ?? FormulaPeekView()
        view.show(latex: shown.latex, isDisplay: shown.isDisplay, ink: shown.ink)
        let size = view.fittingSize
        let x = min(max(0, first.minX - Self.markSpace), max(0, textView.bounds.width - size.width - Metrics.spaceS))
        view.frame = CGRect(x: x, y: last.maxY + Metrics.spaceXs, width: size.width, height: size.height)
        if view.superview !== textView { textView.addSubview(view) }
        peek = view
    }

    /// "수식을 읽을 수 없어요" and why, on hover over each unreadable formula, and a link's address
    /// with "⌘-클릭으로 열기" over its letters. The text view takes tips only from its own letters,
    /// not from the paragraphs drawn for it, so they are its tip areas.
    private func placeTips() {
        guard let textView, let text = textView.textStorage else { return }
        // Not again for a caret move alone.
        let string = text.string as NSString
        // Formulas and links are looked for on each update; with neither, no tips are placed.
        let whole = NSRange(location: 0, length: string.length)
        var hasMath = string.range(of: MemoMath.displayMark).location != NSNotFound
        if !hasMath {
            text.enumerateAttribute(Self.mathKey, in: whole, options: [.longestEffectiveRangeNotRequired]) { value, _, stop in
                if Self.isOn(value) { hasMath = true; stop.pointee = true }
            }
        }
        let links = MemoLinkEdit.memoLinks(in: text, range: whole)
        if !hasMath, links.isEmpty {
            if !tips.isEmpty { tips.forEach(textView.removeToolTip) }
            tips = []
            tipOwners = []
            tipsPlacedFor = nil
            return
        }
        // A link put on or taken off changes no letter: its places and addresses count too.
        let linkMarks = links.map { "\($0.range.location),\($0.range.length),\($0.address)" }.joined(separator: "|")
        let placedFor = ((string as String).hashValue ^ linkMarks.hashValue, openFormula, textView.bounds.width)
        if let last = tipsPlacedFor, last.letters == placedFor.0, last.open == placedFor.1, last.width == placedFor.2 { return }
        tipsPlacedFor = placedFor
        tips.forEach(textView.removeToolTip)
        tips = []
        tipOwners = []
        if hasMath {
            string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]) { _, _, paragraph, _ in
                for formula in Self.formulas(in: text, paragraph: paragraph) where formula.letters != self.openFormula && formula.latex.length > 0 {
                    guard let reason = FormulaPicture.unreadableReason(string.substring(with: formula.latex)) else { continue }
                    let owner = FormulaTip(text: "수식을 읽을 수 없어요: \(reason)")
                    self.tipOwners.append(owner)
                    for frame in self.frames(of: formula.latex) { self.tips.append(textView.addToolTip(frame, owner: owner, userData: nil)) }
                }
            }
        }
        for link in links {
            let owner = FormulaTip(text: "\(link.address) · ⌘-클릭으로 열기")
            tipOwners.append(owner)
            // Letters cut off in a narrow table cell take no room: only the ones that show.
            for frame in frames(of: link.range) where frame.width > 1 { tips.append(textView.addToolTip(frame, owner: owner, userData: nil)) }
        }
    }

    /// The link under a point in the text view: its address. Only letters that show count.
    func link(at point: CGPoint) -> String? {
        guard let textView, let text = textView.textStorage else { return nil }
        for link in MemoLinkEdit.memoLinks(in: text, range: NSRange(location: 0, length: text.length)) {
            if frames(of: link.range).contains(where: { $0.width > 1 && $0.contains(point) }) { return link.address }
        }
        return nil
    }

    /// A formula in the text view's letters.
    struct StoredFormula: Equatable {
        /// What shows as letters while it is written: the LaTeX, or a formula line without its line break.
        var letters: NSRange
        var latex: NSRange
        var isDisplay: Bool
    }

    /// The formulas in one paragraph, as `MemoMath` finds them in the memo.
    static func formulas(in text: NSAttributedString, paragraph: NSRange) -> [StoredFormula] {
        let string = text.string as NSString
        guard paragraph.length > 0, NSMaxRange(paragraph) <= string.length else { return [] }
        var line = paragraph
        while line.length > 0, string.substring(with: NSRange(location: NSMaxRange(line) - 1, length: 1)).rangeOfCharacter(from: .newlines) != nil {
            line.length -= 1
        }
        guard line.length > 0, !isOn(text.attribute(codeKey, at: line.location, effectiveRange: nil)) else { return [] }
        let mark = (MemoMath.displayMark as NSString).length
        if MemoMath.displayLaTeX(string.substring(with: line)) != nil {
            return [StoredFormula(letters: line, latex: NSRange(location: line.location + mark, length: line.length - mark), isDisplay: true)]
        }
        var found: [StoredFormula] = []
        text.enumerateAttribute(mathKey, in: line) { value, range, _ in
            guard isOn(value) else { return }
            if let last = found.last, NSMaxRange(last.latex) == range.location {
                found[found.count - 1].latex.length += range.length
                found[found.count - 1].letters = found[found.count - 1].latex
            } else {
                found.append(StoredFormula(letters: range, latex: range, isDisplay: false))
            }
        }
        return found
    }

    private static func isFormulaLine(_ range: NSRange, in string: String) -> Bool {
        NSMaxRange(range) <= (string as NSString).length && MemoMath.displayLaTeX((string as NSString).substring(with: range)) != nil
    }

    // MARK: NSTextContentStorageDelegate

    // TextKit asks on the main thread, the text view's own.
    nonisolated func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        nonisolated(unsafe) let storage = textContentStorage
        nonisolated(unsafe) var made: NSTextParagraph?
        MainActor.assumeIsolated { made = paragraph(storage, range) }
        return made
    }

    private func paragraph(_ storage: NSTextContentStorage, _ range: NSRange) -> NSTextParagraph? {
        guard let text = storage.textStorage, NSMaxRange(range) <= text.length, range.length > 0 else { return nil }
        let line = Self.line(text.string, range)
        // A table row is drawn as one even when its letters are code.
        if let row = tableParagraph(text, range, caret: tableCaret) {
            return NSTextParagraph(attributedString: row)
        }
        // A code block keeps its own face. By its mark: a line starting with inline code is in the
        // same fixed-width face, and is still a line like any other.
        if Self.isOn(text.attribute(Self.codeKey, at: range.location, effectiveRange: nil)) {
            return NSTextParagraph(attributedString: Self.dressLinks(dressAttachments(nil, text, range) ?? text.copiedPart(range)))
        }
        // The caret as it is now: during an edit the rule's range has already moved.
        if MemoTimeline.isRule(line), !caretIsIn(range) {
            let shown = text.copiedPart(range)
            let letters = NSRange(location: 0, length: (line as NSString).length)
            // Tiny and clear, so a long run of dashes never wraps; the fragment draws the line.
            shown.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 1), .backgroundColor: NSColor.clear], range: letters)
            shown.addAttribute(.memoRule, value: true, range: NSRange(location: 0, length: shown.length))
            return NSTextParagraph(attributedString: shown)
        }
        let shown = MemoTimeline.stampLength(line).map { stampParagraph(text, range, line, $0) } ?? blockParagraph(text, range, line)
        // A plain paragraph too is made here: TextKit's own would take a substring of the memo's text.
        return NSTextParagraph(attributedString: Self.dressLinks(dressAttachments(dressFormulas(shown, text, range), text, range) ?? text.copiedPart(range)))
    }

    // MARK: Links

    /// A link's letters with a thin line in the link colour under them. A link's line is drawn
    /// here, not kept in the memo, so a pasted underline and a link stay apart.
    @discardableResult
    static func dressLinks(_ shown: NSMutableAttributedString) -> NSMutableAttributedString {
        let whole = NSRange(location: 0, length: shown.length)
        shown.enumerateAttribute(MemoLinkEdit.key, in: whole) { value, part, _ in
            guard let value = value as? String, MemoLinks.stored(value) != nil else { return }
            shown.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: NSColor(Tokens.link)], range: part)
        }
        return shown
    }

    // MARK: Attachments

    /// The paragraph's attachments drawn in place of their letters (`AttachmentCard`). The letter
    /// itself stays, so the caret's places are the text's. Nil when it has none and nothing else changed.
    private func dressAttachments(_ shown: NSMutableAttributedString?, _ text: NSTextStorage, _ range: NSRange) -> NSMutableAttributedString? {
        var found: [(offset: Int, ref: MemoAttachments.Ref)] = []
        text.enumerateAttribute(Self.attachmentKey, in: range) { value, part, _ in
            guard let value = value as? String, let ref = MemoAttachments.Ref(value: value) else { return }
            let letters = (text.string as NSString).substring(with: part) as NSString
            for index in 0..<letters.length where letters.character(at: index) == 0xFFFC {
                found.append((part.location + index - range.location, ref))
            }
        }
        guard !found.isEmpty else { return shown }
        let shown = shown ?? text.copiedPart(range)
        guard shown.length == range.length else { return shown }
        let shelf = AttachmentShelf.shared
        for item in found {
            let state = shelf.state(item.ref)
            let look = CardLook(ref: item.ref, state: state, isPicked: pickedAttachment == range.location + item.offset,
                                pictureSize: shelf.image(item.ref)?.size)
            let at = NSRange(location: item.offset, length: 1)
            shown.addAttribute(.attachment, value: AttachmentCard(look: look), range: at)
            // No highlighter or selection grey behind the drawing.
            shown.removeAttribute(.backgroundColor, range: at)
        }
        // The line grows to the drawing; a line of words beside it keeps the memo's height at least.
        let style = ((shown.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.minimumLineHeight = max(style.minimumLineHeight, MemoStyle.lineHeight)
        style.maximumLineHeight = 0
        shown.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: shown.length))
        return shown
    }

    /// The attachment a letter of the text view stands for.
    static func attachmentRef(in text: NSAttributedString, at location: Int) -> MemoAttachments.Ref? {
        guard location < text.length, (text.string as NSString).character(at: location) == 0xFFFC else { return nil }
        return (text.attribute(attachmentKey, at: location, effectiveRange: nil) as? String).flatMap(MemoAttachments.Ref.init(value:))
    }

    /// The drawn attachment under a point in the text view: its letter's place and file.
    func attachment(at point: CGPoint) -> (location: Int, ref: MemoAttachments.Ref)? {
        guard let textView, let text = textView.textStorage else { return nil }
        var hit: (location: Int, ref: MemoAttachments.Ref)?
        text.enumerateAttribute(Self.attachmentKey, in: NSRange(location: 0, length: text.length)) { value, part, stop in
            guard value != nil else { return }
            for location in part.location..<NSMaxRange(part) {
                guard let ref = Self.attachmentRef(in: text, at: location) else { continue }
                if frames(of: NSRange(location: location, length: 1)).contains(where: { $0.contains(point) }) {
                    hit = (location, ref)
                    stop.pointee = true
                    return
                }
            }
        }
        return hit
    }

    /// A short note under the caret for a few seconds.
    func showNotice(_ words: String) {
        guard let textView else { return }
        noticeTask?.cancel()
        notice?.removeFromSuperview()
        let view = MemoNoticeView(words)
        let size = view.fittingSize
        let caret = textView.selectedRange().location
        let line = frames(of: NSRange(location: min(caret, (textView.string as NSString).length), length: 0)).last
            ?? CGRect(x: 0, y: textView.visibleRect.minY + Metrics.spaceS, width: 0, height: 0)
        let x = min(max(0, line.minX), max(0, textView.bounds.width - size.width - Metrics.spaceS))
        view.frame = CGRect(x: x, y: line.maxY + Metrics.spaceXs, width: size.width, height: size.height)
        textView.addSubview(view)
        notice = view
        noticeTask = Task { @MainActor [weak self, weak view] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            view?.removeFromSuperview()
            if self?.notice === view { self?.notice = nil }
        }
    }

    /// A timeline line: the time in figures and soft ink, the words from a column after it.
    private func stampParagraph(_ text: NSTextStorage, _ range: NSRange, _ line: String, _ length: Int) -> NSMutableAttributedString {
        let shown = text.copiedPart(range)
        let stamp = NSRange(location: 0, length: (String(line.prefix(length)) as NSString).length)
        let size = (text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)?.pointSize ?? MemoStyle.size
        let figures = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        shown.addAttributes([.font: figures, .foregroundColor: NSColor(Color.inkSoft)], range: stamp)
        let width = Self.width(of: String(line.prefix(length)), font: figures)
        let column = stampColumn(size: size)
        // The space after the time stretches to the column, so every line's words start together.
        if stamp.length < (line as NSString).length {
            let space = Self.width(of: " ", font: figures)
            shown.addAttribute(.kern, value: max(0, column - width - space), range: NSRange(location: stamp.length, length: 1))
        }
        let style = ((shown.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.headIndent = column
        shown.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: shown.length))
        return shown
    }

    /// Where a timeline line's words start: the time's figures and a space, wider when some line has a range.
    private func stampColumn(size: CGFloat) -> CGFloat {
        let figures = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        return Self.width(of: hasRange ? "00.00 00:00-00:00 " : "00.00 00:00 ", font: figures)
    }

    /// A list item, a quote, a timeline line's child, a title, heading or subheading line, or a
    /// centred or right-set line as drawn; nil for any other.
    private func blockParagraph(_ text: NSTextStorage, _ range: NSRange, _ line: String) -> NSMutableAttributedString? {
        let string = text.string as NSString
        let letters = NSRange(location: range.location, length: (line as NSString).length)
        let isChild = MemoTimeline.isChild(letters, in: string)
        let marker = MemoLists.marker(line, offset: isChild ? 1 : 0)
        let paragraph = Self.paragraph(text.attribute(Self.paragraphKey, at: range.location, effectiveRange: nil))
        // Lists, quotes and a timeline line's children keep to their columns, so stay left.
        let align = marker == nil && !isChild ? Self.align(text.attribute(Self.alignKey, at: range.location, effectiveRange: nil)) : nil
        guard marker != nil || paragraph != nil || isChild || align != nil else { return nil }
        let shown = text.copiedPart(range)
        let whole = NSRange(location: 0, length: shown.length)
        var style = ((shown.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        switch paragraph {
        case .title?, .heading?:
            // The editor's exact 26 pt line comes in a part of the style no setter reaches, and it
            // wins over the line heights below, so a title loaded from the store would stay 26 pt
            // tall under its larger letters. A new style carrying only the settings that matter does not.
            style = Self.plainCopy(of: style)
            // The title and heading tokens' own line heights, and a little room above.
            let height = paragraph == .title ? TextStyle.title.lineHeight : TextStyle.heading.lineHeight
            style.minimumLineHeight = height
            style.maximumLineHeight = height
            style.paragraphSpacingBefore = paragraph == .title ? Metrics.spaceXs : Metrics.spaceM
        case .sub?:
            style.paragraphSpacingBefore = Metrics.spaceS
        case nil:
            break
        }
        switch align {
        case .center?: style.alignment = .center
        case .right?: style.alignment = .right
        case nil: break
        }
        // A quote's `> ` hidden; what follows starts past the ink line, wrapped lines too.
        let quoteIndent = marker?.isQuoted == true ? Metrics.lineSpine + Metrics.spaceL : 0
        if let marker, marker.isQuoted {
            // In the memo's own face, so a heading's larger letters do not push its words out.
            let font = NSFont.systemFont(ofSize: MemoStyle.size)
            shown.addAttribute(.font, value: font, range: NSRange(location: 0, length: 2))
            shown.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(location: 0, length: 1))
            // A list item in it starts `listInset` further, from the `> ` itself, so the quote's
            // line stays where every quote line has it.
            let inset = marker.quoted && marker.kind != .quote ? Self.listInset : 0
            shown.addAttribute(.kern, value: max(0, quoteIndent + inset - Self.width(of: "> ", font: font)), range: NSRange(location: 1, length: 1))
            // Soft ink, except letters given a colour of their own.
            if shown.length > 2 {
                shown.enumerateAttribute(Self.inkKey, in: NSRange(location: 2, length: shown.length - 2)) { value, part, _ in
                    if value == nil { shown.addAttribute(.foregroundColor, value: NSColor(Color.inkSoft), range: part) }
                }
            }
            style.headIndent = quoteIndent
            shown.addAttribute(.memoQuote, value: true, range: whole)
        }
        // A timeline line's child: its first tab reaches the time's words, the rest a level each.
        let childIndent = isChild ? stampColumn(size: MemoStyle.size) : 0
        if isChild, marker == nil {
            let tabs = max(1, line.prefix { $0 == "\t" }.count)
            style.tabStops = (1...tabs).map { NSTextTab(textAlignment: .left, location: childIndent + CGFloat($0 - 1) * MemoLists.levelIndent) }
            style.defaultTabInterval = MemoLists.levelIndent
            style.headIndent = childIndent + CGFloat(tabs - 1) * MemoLists.levelIndent
        }
        if let marker, marker.kind != .quote {
            // A tab a level; the marker, then the words from a column after it, wrapped lines too.
            // As many as the item's level needs, however deep; in a child, from the time's words.
            // Every level starts `listInset` in, so a list stands apart from the lines above it.
            let base = quoteIndent + childIndent + Self.listInset
            // In a quote the `> ` already reaches past the inset.
            if !marker.quoted { style.firstLineHeadIndent = Self.listInset }
            style.tabStops = (1...max(1, marker.level)).map { NSTextTab(textAlignment: .left, location: base + CGFloat($0 - marker.offset) * MemoLists.levelIndent) }
            style.defaultTabInterval = MemoLists.levelIndent
            let label = NSRange(location: marker.labelOffset, length: (marker.label as NSString).length)
            let drawn = MemoLists.shownLabel(marker)
            if drawn != marker.label { shown.replaceCharacters(in: label, with: drawn) }
            let size = (shown.attribute(.font, at: label.location, effectiveRange: nil) as? NSFont)?.pointSize ?? MemoStyle.size
            let font: NSFont = switch marker.kind {
            case .number: .monospacedDigitSystemFont(ofSize: size, weight: .regular)
            // A geometric dot about half the letters' size, raised to their middle.
            case .bullet: .systemFont(ofSize: (size * Self.bulletScale).rounded())
            default: .systemFont(ofSize: size)
            }
            shown.addAttributes([.font: font, .foregroundColor: marker.quoted ? NSColor(Color.inkSoft) : NSColor(Color.ink)], range: label)
            if marker.kind == .bullet { shown.addAttribute(.baselineOffset, value: (size * Self.bulletRise).rounded(), range: label) }
            let space = NSRange(location: NSMaxRange(label), length: 1)
            // In the marker's face, so the measured column is the drawn one on a title line too.
            shown.addAttribute(.font, value: font, range: space)
            let width = Self.width(of: drawn, font: font) + Self.width(of: " ", font: font)
            let column = marker.kind == .number ? Self.numberColumn : MemoLists.levelIndent
            shown.addAttribute(.kern, value: max(0, column - width), range: space)
            style.headIndent = base + CGFloat(marker.labelLevel) * MemoLists.levelIndent + max(column, width)
        }
        shown.addAttribute(.paragraphStyle, value: style, range: whole)
        return shown
    }

    /// The paragraph's formulas: drawn in place of their letters, or, for the one being written
    /// and any that cannot be read, their LaTeX in a fixed-width face. Nil when it has none and
    /// nothing else changed.
    private func dressFormulas(_ shown: NSMutableAttributedString?, _ text: NSTextStorage, _ range: NSRange) -> NSMutableAttributedString? {
        let formulas = Self.formulas(in: text, paragraph: range)
        guard !formulas.isEmpty else { return shown }
        let shown = shown ?? text.copiedPart(range)
        // Every change below keeps the letters' count, so the caret's places stay the text's.
        guard shown.length == range.length else { return shown }
        let style = ((shown.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        let lineHeight = style.maximumLineHeight > 0 ? style.maximumLineHeight : MemoStyle.lineHeight
        let code = NSFont.monospacedSystemFont(ofSize: Self.latexSize, weight: .regular)
        var grows = false
        var marked = false
        for formula in formulas {
            let letters = NSRange(location: formula.letters.location - range.location, length: formula.letters.length)
            let latexRange = NSRange(location: formula.latex.location - range.location, length: formula.latex.length)
            let mark = NSRange(location: letters.location, length: latexRange.location - letters.location)
            let latex = (text.string as NSString).substring(with: formula.latex)
            let isOpen = openFormula?.location == formula.letters.location || emptyFormula == formula.latex.location
            if mark.length > 0 { shown.addAttributes([.font: code, .foregroundColor: NSColor(Color.inkFaint)], range: mark) }
            if isOpen || latex.trimmingCharacters(in: .whitespaces).isEmpty {
                // The LaTeX on a light ground, between `$` marks that are only drawn.
                guard latexRange.length > 0 else { continue }
                shown.addAttribute(.font, value: code, range: latexRange)
                shown.addAttribute(.memoFormula, value: formula.isDisplay ? FormulaMark.line : FormulaMark.open, range: latexRange)
                marked = true
                if !formula.isDisplay {
                    let last = NSMaxRange(latexRange) - 1
                    shown.addAttribute(.kern, value: ((shown.attribute(.kern, at: last, effectiveRange: nil) as? CGFloat) ?? 0) + Self.markRoom,
                                       range: NSRange(location: last, length: 1))
                    if latexRange.location > 0 {
                        let before = latexRange.location - 1
                        shown.addAttribute(.kern, value: ((shown.attribute(.kern, at: before, effectiveRange: nil) as? CGFloat) ?? 0) + Self.markRoom,
                                           range: NSRange(location: before, length: 1))
                    } else {
                        style.firstLineHeadIndent += Self.markRoom
                    }
                }
                continue
            }
            let around = (text.attribute(.font, at: formula.latex.location, effectiveRange: nil) as? NSFont)?.pointSize ?? MemoStyle.size
            var size = formula.isDisplay ? Self.displaySize : max(Self.inlineSize, around)
            switch FormulaPicture.shape(latex, size: size, display: formula.isDisplay) {
            case .failure:
                // Why, on hover: `placeTips`.
                shown.addAttributes([.font: code, .memoFormula: FormulaMark.unreadable], range: latexRange)
                marked = true
            case .success(var shape):
                if !formula.isDisplay {
                    // Made smaller to keep within the line, down to three quarters; past that the line grows.
                    let room = Self.room(lineHeight: lineHeight, font: NSFont.systemFont(ofSize: MemoStyle.size))
                    let scale = max(Self.leastScale, min(1, room.above / max(shape.ascent, 1), room.below / max(shape.descent, 0.01)))
                    let smallerSize = (size * scale * 2).rounded(.down) / 2
                    if smallerSize < size, case .success(let smaller) = FormulaPicture.shape(latex, size: smallerSize, display: false) {
                        size = smallerSize
                        shape = smaller
                    }
                    if shape.ascent > room.above + 0.5 || shape.descent > room.below + 0.5 { grows = true }
                } else {
                    grows = true
                }
                let ink = Self.palette(text.attribute(Self.inkKey, at: formula.latex.location, effectiveRange: nil))
                let attachment = FormulaAttachment(latex: latex, size: size, isDisplay: formula.isDisplay, shape: shape, ink: ink)
                // The letters (and a formula line's `$$ `) take no room; the first stands for the drawing.
                shown.addAttributes([.font: Self.hiddenFont, .foregroundColor: NSColor.clear], range: letters)
                shown.removeAttribute(.backgroundColor, range: mark)
                let first = (shown.string as NSString).rangeOfComposedCharacterSequence(at: latexRange.location)
                var kept = shown.attributes(at: first.location, effectiveRange: nil)
                kept[.font] = nil
                kept[.foregroundColor] = nil
                kept[.attachment] = attachment
                shown.replaceCharacters(in: first, with: NSAttributedString(string: "\u{FFFC}" + String(repeating: "\u{200B}", count: first.length - 1), attributes: kept))
                if NSMaxRange(first) < NSMaxRange(latexRange) {
                    shown.removeAttribute(.backgroundColor, range: NSRange(location: NSMaxRange(first), length: NSMaxRange(latexRange) - NSMaxRange(first)))
                }
                if formula.isDisplay {
                    // The line already reaches a little past the drawing; with this, about the
                    // mockup's 6 pt above and below.
                    style.alignment = .center
                    style.paragraphSpacingBefore = max(style.paragraphSpacingBefore, Metrics.spaceXxs)
                    style.paragraphSpacing = max(style.paragraphSpacing, Metrics.spaceXxs)
                }
            }
        }
        if grows {
            // Only the lines that need it grow; the rest keep the memo's height.
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = 0
        }
        shown.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: shown.length))
        if marked { shown.addAttribute(.memoFormulas, value: true, range: NSRange(location: 0, length: shown.length)) }
        return shown
    }

    // MARK: NSTextLayoutManagerDelegate

    nonisolated func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                                       in textElement: NSTextElement) -> NSTextLayoutFragment {
        let range = textElement.elementRange
        if let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 {
            if paragraph.attributedString.attribute(.memoTable, at: 0, effectiveRange: nil) != nil {
                return TableFragment(textElement: textElement, range: range)
            }
            if paragraph.attributedString.attribute(.memoRule, at: 0, effectiveRange: nil) != nil {
                return RuleFragment(textElement: textElement, range: range)
            }
            if paragraph.attributedString.attribute(.memoQuote, at: 0, effectiveRange: nil) != nil {
                return QuoteFragment(textElement: textElement, range: range)
            }
            if paragraph.attributedString.attribute(.memoFormulas, at: 0, effectiveRange: nil) != nil {
                return FormulaFragment(textElement: textElement, range: range)
            }
        }
        return NSTextLayoutFragment(textElement: textElement, range: range)
    }

    // MARK: Helpers

    /// The focused memo's caret is inside `range` (a whole paragraph, its line break included).
    private func caretIsIn(_ range: NSRange) -> Bool {
        guard let textView, textView.window?.firstResponder === textView,
              let caret = textView.selectedRanges.first?.rangeValue else { return false }
        // The caret's own paragraph, as `update` finds it: at the end after a rule's line break it
        // is on the empty line below.
        return (textView.string as NSString).paragraphRange(for: NSRange(location: caret.location, length: 0)) == range
    }

    /// The paragraph's letters without its line break.
    private static func line(_ string: String, _ range: NSRange) -> String {
        let paragraph = (string as NSString).substring(with: range)
        return paragraph.trimmingCharacters(in: .newlines)
    }

    /// Some line starts with a time range (`11.02 08:30-09:15`). Line by line in the letters, only
    /// a line with `-` where a range has it read further: this runs on every key.
    private static func hasRange(in string: String) -> Bool {
        let letters = string as NSString
        var start = 0
        while start < letters.length {
            let line = letters.lineRange(for: NSRange(location: start, length: 0))
            if line.length >= 17, letters.character(at: line.location + 11) == 0x2D, letters.character(at: line.location + 2) == 0x2E,
               MemoTimeline.stampLength(letters.substring(with: NSRange(location: line.location, length: min(18, line.length)))) == 17 {
                return true
            }
            start = NSMaxRange(line)
        }
        return false
    }

    private static func width(of letters: String, font: NSFont) -> CGFloat {
        (letters as NSString).size(withAttributes: [.font: font]).width
    }

    /// A number item's marker column, a little wider than a bullet's for two figures.
    private static let numberColumn: CGFloat = 26
    /// How far in a list's first level starts: the memo's drawing only, not sent to the 메모 app.
    static let listInset: CGFloat = Metrics.spaceL
    /// A bullet's size and lift against its line's letters.
    private static let bulletScale: CGFloat = 0.5
    private static let bulletRise: CGFloat = 0.15

    private static let paragraphKey = NSAttributedString.Key(MemoAttributes.Paragraph.name)
    private static let inkKey = NSAttributedString.Key(MemoAttributes.Ink.name)
    private static let mathKey = NSAttributedString.Key(MemoAttributes.Math.name)
    private static let codeKey = NSAttributedString.Key(MemoAttributes.Code.name)
    private static let alignKey = NSAttributedString.Key(MemoAttributes.Align.name)
    static let attachmentKey = NSAttributedString.Key(MemoAttributes.Attachment.name)

    /// A formula's LaTeX while written or unreadable: the code block's face.
    nonisolated static let latexSize: CGFloat = 13
    /// A formula in the text, and a formula line: the old formula lettering's size, and larger.
    private static let inlineSize: CGFloat = 16
    private static let displaySize: CGFloat = 19
    private static let leastScale: CGFloat = 0.75
    /// Letters that take no room under a drawn formula.
    private static let hiddenFont = NSFont.systemFont(ofSize: 0.01)
    /// Room for a drawn `$` and its gaps on either side of a formula being written.
    nonisolated static let markSpace: CGFloat = markWidth + 2 * markGap
    /// The kern beside a formula being written: its `$` mark, and a gap outside its ground.
    nonisolated static let markRoom: CGFloat = markSpace + markGap
    nonisolated static let markGap: CGFloat = 3
    nonisolated static let markWidth: CGFloat = ("$" as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: latexSize, weight: .regular)]).width

    /// How far a line of `font` at `lineHeight` reaches above and below its baseline.
    private static func room(lineHeight: CGFloat, font: NSFont) -> (above: CGFloat, below: CGFloat) {
        let letters = font.ascender - font.descender
        let spare = max(0, lineHeight - letters) / 2
        return (font.ascender + spare, -font.descender + spare)
    }

    private static func isOn(_ value: Any?) -> Bool { (value as? Bool) == true }

    /// A palette name as the text view keeps it.
    static func palette(_ value: Any?) -> Palette? {
        if let palette = value as? Palette { return palette }
        return (value as? String).flatMap(Palette.init(rawValue:))
    }

    /// A new paragraph style with the public settings of `style` and nothing else.
    private static func plainCopy(of style: NSParagraphStyle) -> NSMutableParagraphStyle {
        let copy = NSMutableParagraphStyle()
        copy.alignment = style.alignment
        copy.baseWritingDirection = style.baseWritingDirection
        copy.lineBreakMode = style.lineBreakMode
        copy.lineBreakStrategy = style.lineBreakStrategy
        copy.lineSpacing = style.lineSpacing
        copy.paragraphSpacing = style.paragraphSpacing
        copy.paragraphSpacingBefore = style.paragraphSpacingBefore
        copy.headIndent = style.headIndent
        copy.firstLineHeadIndent = style.firstLineHeadIndent
        copy.tailIndent = style.tailIndent
        copy.tabStops = style.tabStops
        copy.defaultTabInterval = style.defaultTabInterval
        copy.hyphenationFactor = style.hyphenationFactor
        copy.allowsDefaultTighteningForTruncation = style.allowsDefaultTighteningForTruncation
        return copy
    }

    /// An alignment as the text view keeps it.
    private static func align(_ value: Any?) -> MemoAlign? {
        if let align = value as? MemoAlign { return align }
        return (value as? String).flatMap(MemoAlign.init(rawValue:))
    }

    /// A paragraph style as the text view keeps it.
    private static func paragraph(_ value: Any?) -> MemoParagraph? {
        if let paragraph = value as? MemoParagraph { return paragraph }
        return (value as? String).flatMap(MemoParagraph.init(rawValue:))
    }
}

extension NSAttributedString.Key {
    /// A rule paragraph, as `MemoLineStyler` hands it out; never in the memo's own text.
    static let memoRule = NSAttributedString.Key("simplify.memo.rule")
    /// A quote paragraph, likewise.
    static let memoQuote = NSAttributedString.Key("simplify.memo.quote")
    /// A formula's letters shown as LaTeX, and how (`FormulaMark`).
    static let memoFormula = NSAttributedString.Key("simplify.memo.formula")
    /// A paragraph with letters under `memoFormula`, on its every letter.
    static let memoFormulas = NSAttributedString.Key("simplify.memo.formulas")
}

/// How a formula's LaTeX shows when it is not drawn.
enum FormulaMark {
    /// Being written in the text: on a light ground between drawn `$` marks.
    static let open = "open"
    /// Being written on a formula line, after its typed `$$ `.
    static let line = "line"
    /// Cannot be read: a faint wavy line under it.
    static let unreadable = "unreadable"
}

/// A paragraph with a formula's LaTeX showing: the ground and `$` marks of one being written,
/// and the wavy line under one that cannot be read.
class FormulaFragment: NSTextLayoutFragment {
    override func draw(at point: CGPoint, in context: CGContext) {
        let marks = formulaMarks()
        guard !marks.isEmpty else { return super.draw(at: point, in: context) }
        let space = MemoLineStyler.markSpace, gap = MemoLineStyler.markGap
        for mark in marks where mark.kind != FormulaMark.unreadable {
            let left = mark.x0 - (mark.isStart && mark.kind == FormulaMark.open ? space : gap)
            let right = mark.x1 + (mark.isEnd && mark.kind == FormulaMark.open ? space : gap)
            let box = CGRect(x: point.x + left, y: point.y + mark.line.minY + 2, width: right - left, height: mark.line.height - 4)
            context.setFillColor(NSColor(Color.raised).cgColor)
            context.fill(box)
            context.setStrokeColor(NSColor(Color.shade).cgColor)
            context.setLineWidth(Metrics.line)
            context.stroke(box.insetBy(dx: Metrics.line / 2, dy: Metrics.line / 2))
        }
        super.draw(at: point, in: context)
        let font = NSFont.monospacedSystemFont(ofSize: MemoLineStyler.latexSize, weight: .regular)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        for mark in marks {
            switch mark.kind {
            case FormulaMark.unreadable:
                // A faint wave under the letters; red is kept for holidays and what cannot be undone.
                let path = NSBezierPath()
                let y = point.y + mark.baseline + 3
                var x = point.x + mark.x0
                path.move(to: CGPoint(x: x, y: y))
                var up = true
                while x < point.x + mark.x1 {
                    x = min(x + 2, point.x + mark.x1)
                    path.line(to: CGPoint(x: x, y: up ? y - 1.5 : y))
                    up.toggle()
                }
                path.lineWidth = Metrics.line
                NSColor(Color.inkFaint).setStroke()
                path.stroke()
            case FormulaMark.open:
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(Color.inkFaint)]
                let top = point.y + mark.baseline - font.ascender
                let width = MemoLineStyler.markWidth
                if mark.isStart { ("$" as NSString).draw(at: CGPoint(x: point.x + mark.x0 - gap - width, y: top), withAttributes: attributes) }
                // x1 is the letters' right edge, and the `$` stands after it.
                if mark.isEnd { ("$" as NSString).draw(at: CGPoint(x: point.x + mark.x1 + gap, y: top), withAttributes: attributes) }
            default:
                break
            }
        }
    }

    private struct Mark {
        var kind: String
        /// Its line's typographic bounds in the fragment, its baseline, and its letters' left and right edges.
        var line: CGRect
        var baseline: CGFloat
        var x0: CGFloat
        var x1: CGFloat
        var isStart: Bool
        var isEnd: Bool
    }

    /// Each formula's LaTeX, line by line.
    private func formulaMarks() -> [Mark] {
        guard let paragraph = textElement as? NSTextParagraph else { return [] }
        let string = paragraph.attributedString
        var marks: [Mark] = []
        string.enumerateAttribute(.memoFormula, in: NSRange(location: 0, length: string.length)) { value, range, _ in
            guard let kind = value as? String else { return }
            for line in textLineFragments {
                let part = NSIntersectionRange(range, line.characterRange)
                guard part.length > 0 else { continue }
                let bounds = line.typographicBounds
                let isStart = part.location == range.location, isEnd = NSMaxRange(part) == NSMaxRange(range)
                // At a line's end the measure stops at the letters.
                let atLineEnd = NSMaxRange(part) >= string.length || (string.string as NSString).character(at: NSMaxRange(part)) == 0x0A
                // A caret's place sits halfway through a kern: the letters start half the room for
                // the `$` after their measured start, and end half of it before their measured end.
                let half = kind == FormulaMark.open ? MemoLineStyler.markRoom / 2 : 0
                marks.append(Mark(kind: kind, line: bounds, baseline: bounds.minY + line.glyphOrigin.y,
                                  x0: bounds.minX + line.locationForCharacter(at: part.location).x + (isStart && part.location > 0 ? half : 0),
                                  x1: bounds.minX + line.locationForCharacter(at: NSMaxRange(part)).x - (isEnd && !atLineEnd ? half : 0),
                                  isStart: isStart, isEnd: isEnd))
            }
        }
        return marks
    }
}

/// A quote paragraph: its words, and a spine-weight ink line down its left side. Quote lines one
/// under another make one line.
final class QuoteFragment: FormulaFragment {
    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard let first = textLineFragments.first, let last = textLineFragments.last else { return }
        context.setFillColor(NSColor(Color.ink).cgColor)
        let top = first.typographicBounds.minY
        context.fill(CGRect(x: point.x + first.typographicBounds.minX, y: point.y + top, width: Metrics.lineSpine,
                            height: last.typographicBounds.maxY - top))
    }
}

/// A rule paragraph: a 1 pt ink line across the memo's width, in the middle of its line.
final class RuleFragment: NSTextLayoutFragment {
    private var lineWidth: CGFloat {
        guard let container = textLayoutManager?.textContainer else { return layoutFragmentFrame.width }
        return container.size.width - container.lineFragmentPadding * 2
    }

    override var renderingSurfaceBounds: CGRect {
        CGRect(x: 0, y: 0, width: max(lineWidth, layoutFragmentFrame.width), height: layoutFragmentFrame.height)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let height = textLineFragments.first?.typographicBounds.height ?? MemoStyle.lineHeight
        // Resolved in the text view's appearance, which is the current drawing one here.
        context.setFillColor(NSColor(Color.ink).cgColor)
        let y = (point.y + height / 2).rounded(.down)
        context.fill(CGRect(x: point.x, y: y, width: lineWidth, height: Metrics.line))
    }
}

/// The memo for pictures (ImageRenderer cannot draw the text view): each line as `Text`, a rule as
/// an ink line and a timeline line with its time in a figure column, as the text view draws them.
struct MemoPrint: View {
    let text: AttributedString

    var body: some View {
        let lines = MemoTodoLines.lines(in: text)
        let plain = lines.map { String(text[$0].characters) }
        let wide = plain.contains { MemoTimeline.stampLength($0) == 17 }
        let children = Set(MemoTimeline.childLines(in: String(text.characters) as NSString))
        let figures = Font.system(size: MemoStyle.size).monospacedDigit()
        let column = (NSString(string: wide ? "00.00 00:00-00:00 " : "00.00 00:00 ")
            .size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: MemoStyle.size, weight: .regular)]).width).rounded(.up)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { number, range in
                let letters = plain[number]
                if MemoTimeline.isRule(letters) {
                    Rectangle().fill(.ink).frame(height: Metrics.line).frame(height: MemoStyle.lineHeight)
                } else if let length = MemoTimeline.stampLength(letters) {
                    let stamp = text.characters.index(range.lowerBound, offsetBy: length)
                    let rest = stamp < range.upperBound ? text.characters.index(after: stamp) : stamp
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(String(letters.prefix(length))).font(figures).foregroundStyle(.inkSoft)
                            .frame(width: column, alignment: .leading)
                        Text(MemoStyle.rendered(AttributedString(text[rest..<range.upperBound])))
                            .lineHeight(.exact(points: MemoStyle.lineHeight))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // As the text view draws it: list, quote, code, table and timeline children stay left.
                    let run = range.isEmpty ? nil : text.runs[range.lowerBound]
                    let align = run.flatMap { run in
                        MemoLists.marker(letters) != nil || children.contains(number) || run[MemoAttributes.Code.self] == true
                            || run[MemoAttributes.Table.self] != nil ? nil : run[MemoAttributes.Align.self]
                    }
                    // In a row, as the timeline lines are: a lone wrapping Text is measured a line short here.
                    HStack(alignment: .top, spacing: 0) {
                        Color.clear.frame(width: 0, height: MemoStyle.lineHeight)
                        Text(MemoStyle.rendered(AttributedString(text[range])))
                            .lineHeight(.exact(points: MemoStyle.lineHeight))
                            .multilineTextAlignment(align == .center ? .center : align == .right ? .trailing : .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: align == .center ? .center : align == .right ? .trailing : .leading)
                }
            }
        }
        .textStyle(.memo)
        .foregroundStyle(.ink)
    }
}

extension NSAttributedString {
    /// `range`'s letters and attributes as a string of its own. Not `attributedSubstring(from:)`:
    /// on the memo's text (SwiftUI's storage) that makes a substring tied to itself, never freed,
    /// and the memo makes one for each paragraph it draws again, on every key.
    func copiedPart(_ range: NSRange) -> NSMutableAttributedString {
        let part = NSMutableAttributedString(string: (string as NSString).substring(with: range))
        enumerateAttributes(in: range) { attributes, run, _ in
            part.setAttributes(attributes, range: NSRange(location: run.location - range.location, length: run.length))
        }
        return part
    }
}
