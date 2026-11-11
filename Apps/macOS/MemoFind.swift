import AppKit
import SwiftUI
import SimplifyKit

// ⌘F in the open memo: a box floating over the memo's top right (the format bar's frame and
// measures), the places found drawn over the letters (TextKit 2 rendering attributes, so the
// memo's own letters and attributes never change), replacing one or all, and the 찾기 menu.
// What is found, and where, is `MemoFind` in SimplifyKit.

/// The open memo's find: what is looked for, where it was found, and which place is shown.
@MainActor
@Observable
final class MemoFindState {
    enum Field: Hashable { case find, replace }

    /// The box is over the memo.
    private(set) var isOpen = false
    /// Its second row, 바꿀 글 and the replace buttons, is out.
    var showsReplace = false
    /// The words looked for; finding runs again on every letter.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            refresh(from: caretLocation)
            reveal()
        }
    }
    var replacement = ""
    /// The places found in the open memo, front to back (UTF-16), and the one shown.
    private(set) var matches: [NSRange] = []
    private(set) var current: Int?
    /// Which of the box's fields has keyboard focus, as the box reports it.
    var focusedField: Field?
    /// The field to give keyboard focus to, and a count bumped to ask for it again.
    private(set) var focusTarget: Field = .find
    private(set) var focusRequest = 0
    /// The box in the window content's coordinates (top-left origin): clicks there are the box's,
    /// not the memo's under it.
    @ObservationIgnored var frameInContent: CGRect = .null

    @ObservationIgnored weak var draft: MemoDraft?
    @ObservationIgnored private weak var paintedView: NSTextView?
    @ObservationIgnored private var lastAnnounced: String?
    /// After a replacement: the next place is the first after this, once the text has caught up.
    @ObservationIgnored private var resumeAt: Int?

    /// How far down the memo the box covers, its shadow included: the shown place is scrolled to
    /// below this when it can be (DESIGN.md › 찾기 상자).
    static let oneRowCover: CGFloat = 46
    static let twoRowCover: CGFloat = 74

    var canReplace: Bool { !(draft?.isUnreadable ?? true) }
    var showsReplaceRow: Bool { showsReplace && canReplace }
    var hasQuery: Bool { !query.isEmpty }
    var foundNothing: Bool { hasQuery && matches.isEmpty }

    /// `3/7`, `없음`, or nothing before a word is typed.
    var countText: String {
        guard hasQuery else { return "" }
        guard !matches.isEmpty else { return "없음" }
        return "\((current ?? 0) + 1)/\(matches.count)"
    }

    // MARK: Opening and closing

    /// ⌘F (`replacing` false) or ⌥⌘F: the box opens, or its field takes focus again. Picked letters
    /// within one line become the words looked for.
    func open(replacing: Bool) {
        guard let draft else { return }
        if draft.hasFocus, let picked = pickedWords(in: draft) { query = picked }
        let wantsReplace = replacing && canReplace
        if wantsReplace { showsReplace = true }
        if !isOpen {
            isOpen = true
            refresh(from: caretLocation)
        }
        reveal()
        focus(wantsReplace ? .replace : .find)
    }

    /// Esc or ✕: the box goes, its marks with it, and the memo takes focus again with the place
    /// that was shown picked.
    func close(focusingMemo: Bool = true) {
        guard isOpen else { return }
        isOpen = false
        focusedField = nil
        clearPaint()
        guard focusingMemo, let textView = memoTextView() else { return }
        if let range = currentRange, NSMaxRange(range) <= (textView.string as NSString).length {
            textView.setSelectedRange(range)
        }
        textView.window?.makeFirstResponder(textView)
        draft?.focusRequest += 1
    }

    /// ⇄: the replace row in or out.
    func toggleReplace() {
        guard canReplace else { return }
        showsReplace.toggle()
        focus(showsReplace ? .replace : .find)
    }

    func focus(_ field: Field) {
        focusTarget = field
        focusRequest += 1
    }

    /// ⌘E: the picked letters become the words looked for; the box does not open.
    func usePickedWords() {
        guard let draft, let picked = pickedWords(in: draft) else { return NSSound.beep() }
        query = picked
    }

    // MARK: Finding

    /// Finds again in the open memo's letters as they are now: the shown place stays where it was
    /// when it still stands there, else the first from `location`.
    @discardableResult
    func refresh(from location: Int? = nil, announcing: Bool = true) -> Bool {
        guard let draft else { return false }
        let previous = currentRange
        matches = MemoFind.matches(of: query, in: draft.text)
        let resumed = resumeAt != nil
        if let resume = resumeAt {
            resumeAt = nil
            current = MemoFind.firstIndex(from: resume, in: matches)
        } else if let previous, let same = matches.firstIndex(where: { $0.location == previous.location }) {
            current = same
        } else {
            current = MemoFind.firstIndex(from: location ?? previous?.location ?? 0, in: matches)
        }
        // With the box closed (⌘E), only the places are kept, for ⌘G.
        guard isOpen else { return resumed }
        repaint()
        if announcing { announce() }
        return resumed
    }

    /// The open memo's letters changed (typing, another memo or day): the places are found again.
    /// After a replacement, the next place is shown.
    func textChanged() {
        guard isOpen else { return }
        // Typing in the memo is not read out at every letter; a replacement's next place is.
        let pending = resumeAt != nil
        if refresh(announcing: pending) { reveal() }
    }

    /// Another memo or day: the first place there is shown, not one at the old place's offset.
    func memoChanged() {
        guard isOpen else { return }
        current = nil
        matches = []
        refresh(from: 0)
        reveal()
    }

    /// ⌘G / Return (1) or ⇧⌘G / ⇧Return (-1). With the box closed, from the caret with the words
    /// last looked for, picking the place found.
    func step(_ by: Int) {
        guard hasQuery else { return NSSound.beep() }
        if !isOpen {
            guard let draft, let textView = memoTextView() else { return }
            let found = MemoFind.matches(of: query, in: draft.text)
            guard !found.isEmpty else { return NSSound.beep() }
            let picked = textView.selectedRange()
            let index = by > 0
                ? found.firstIndex { $0.location >= NSMaxRange(picked) && $0 != picked } ?? 0
                : found.lastIndex { NSMaxRange($0) <= picked.location && $0 != picked } ?? found.count - 1
            textView.setSelectedRange(found[index])
            textView.scrollRangeToVisible(found[index])
            announce(index: index, count: found.count)
            return
        }
        guard !matches.isEmpty else { return NSSound.beep() }
        current = MemoFind.step(current, by: by, count: matches.count)
        repaint()
        reveal()
        announce()
    }

    private var currentRange: NSRange? {
        guard let current, matches.indices.contains(current) else { return nil }
        return matches[current]
    }

    /// Where finding starts: the memo's caret, or the start.
    private var caretLocation: Int {
        memoTextView()?.selectedRange().location ?? 0
    }

    /// The picked letters when they are within one line, for ⌘F and ⌘E.
    private func pickedWords(in draft: MemoDraft) -> String? {
        guard let range = draft.selectedRanges.first(where: { !$0.isEmpty }) else { return nil }
        let words = String(draft.text[range].characters)
        guard !words.contains(where: \.isNewline), !words.isEmpty else { return nil }
        return words
    }

    // MARK: Replacing

    /// 바꾸기: the shown place becomes the replacement, as typed there (the place's first letter's
    /// formatting), and the next place is shown. One undo step.
    func replaceCurrent() {
        guard isOpen, canReplace, let draft, let range = currentRange, let textView = memoTextView(),
              let storage = textView.textStorage, NSMaxRange(range) <= storage.length else { return NSSound.beep() }
        let letters = MemoFind.replacement(replacement, inTable: isInTable(range, in: draft))
        let piece = NSAttributedString(string: letters, attributes: storage.attributes(at: range.location, effectiveRange: nil))
        // As if typed over the place: picked first, so the undo step puts the selection back there.
        textView.setSelectedRange(range)
        let before = storage.length
        MemoTableClipboard.replace(range, with: piece, in: textView)
        // Refused (`shouldChangeText`): nothing changed, and the place stays shown.
        let now = storage.string as NSString
        guard storage.length != before
                || (range.location + piece.length <= now.length && now.substring(with: NSRange(location: range.location, length: piece.length)) == piece.string)
        else { return }
        resumeAt = range.location + piece.length
        textView.setSelectedRange(NSRange(location: range.location + piece.length, length: 0))
        // SwiftUI's copy of the letters follows the text view's (`textChanged`); if it already has
        // without telling, the places are found again here.
        Task { @MainActor [weak self] in
            guard let self, self.resumeAt != nil else { return }
            if self.refresh() { self.reveal() }
        }
    }

    /// 모두 N: every place at once, in one edit (one ⌘Z puts all of them back), back to front so
    /// each place is still where it was found.
    func replaceAll() {
        guard isOpen, canReplace, let draft, !matches.isEmpty, let textView = memoTextView(), let storage = textView.textStorage,
              matches.allSatisfy({ NSMaxRange($0) <= storage.length }) else { return NSSound.beep() }
        let ranges = matches
        let pieces = ranges.map { range in
            NSAttributedString(string: MemoFind.replacement(replacement, inTable: isInTable(range, in: draft)),
                               attributes: storage.attributes(at: range.location, effectiveRange: nil))
        }
        // Its own undo step, apart from letters typed just before.
        textView.breakUndoCoalescing()
        textView.setSelectedRange(ranges[0])
        guard textView.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: pieces.map(\.string)) else { return }
        let byRange = Dictionary(uniqueKeysWithValues: zip(ranges.map(\.location), pieces))
        storage.beginEditing()
        for range in MemoFind.replaceAllOrder(ranges) {
            if let piece = byRange[range.location] { storage.replaceCharacters(in: range, with: piece) }
        }
        storage.endEditing()
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: ranges[0].location + pieces[0].length, length: 0))
        let count = ranges.count
        Task { @MainActor [weak self] in
            self?.refresh(announcing: false)
            self?.post("\(count)곳을 바꿨어요")
        }
    }

    private func isInTable(_ range: NSRange, in draft: MemoDraft) -> Bool {
        guard let found = Range(range, in: draft.text) else { return false }
        return draft.text.runs[found.lowerBound][MemoAttributes.Table.self] != nil
    }

    // MARK: The memo's text view

    /// The memo being written's text view: the one the memo's styler draws (not a read-only memo of
    /// 모아 보기), under the memo's place in the window.
    func memoTextView() -> NSTextView? {
        if let paintedView, paintedView.window != nil, paintedView.window === window { return paintedView }
        guard let draft, let content = window?.contentView else { return nil }
        let found = Self.memoTextView(in: content, box: draft.visibleBox)
        paintedView = found
        return found
    }

    /// The window the memo's editor is in, set by the editor (`MemoFindLayer`).
    @ObservationIgnored weak var window: NSWindow?

    private static func memoTextView(in view: NSView, box: CGRect) -> NSTextView? {
        if let textView = view as? NSTextView, !textView.isFieldEditor, !MemoTextViews.readOnly.contains(textView),
           textView.textLayoutManager?.delegate is MemoLineStyler {
            guard let content = textView.window?.contentView else { return nil }
            let outer = textView.enclosingScrollView ?? textView
            let frame = content.convert(outer.bounds, from: outer)
            let top = content.isFlipped ? frame : CGRect(x: frame.minX, y: content.bounds.height - frame.maxY, width: frame.width, height: frame.height)
            return top.intersects(box) ? textView : nil
        }
        for subview in view.subviews {
            if let found = memoTextView(in: subview, box: box) { return found }
        }
        return nil
    }

    /// The memo's text view went (the editor left): it is looked for again next time.
    func forgetTextView() {
        clearPaint()
        paintedView = nil
    }

    // MARK: Drawing the places

    /// The places drawn under the letters by a layer of their own (`FindMarksView`), nothing
    /// written into the memo: every place a grey (`shade`) ground, the shown one also in an ink edge.
    func repaint() {
        guard let textView = memoTextView() else { return }
        marksView(on: textView)?.needsDisplay = true
    }

    /// The layer under the memo's letters that draws the places.
    private func marksView(on textView: NSTextView) -> FindMarksView? {
        guard isOpen else { return nil }
        if let marks, marks.superview === textView { return marks }
        marks?.removeFromSuperview()
        let view = FindMarksView(frame: textView.bounds)
        view.autoresizingMask = [.width, .height]
        view.places = { [weak self, weak textView] in
            guard let self, let textView else { return [] }
            return self.placeFrames(in: textView)
        }
        // Over the selection's layer, under the letters'; without it, under everything.
        if let selection = textView.subviews.first(where: { String(describing: type(of: $0)).contains("Selection") }) {
            textView.addSubview(view, positioned: .above, relativeTo: selection)
        } else {
            textView.addSubview(view, positioned: .below, relativeTo: nil)
        }
        marks = view
        return view
    }

    @ObservationIgnored private var marks: FindMarksView?

    /// Every place, line by line, in the text view, and whether it is the shown one: from the
    /// letters' left edge to their right, and from their font's ascender to its descender around
    /// the line's baseline, as the line is drawn (a list's hung words, a table cell, code). Only
    /// lines laid out are measured; the others are out of sight.
    func placeFrames(in textView: NSTextView) -> [(frame: CGRect, isShown: Bool)] {
        guard isOpen, let manager = textView.textLayoutManager, let content = manager.textContentManager else { return [] }
        let length = (textView.string as NSString).length
        let origin = textView.textContainerOrigin
        let documentStart = content.documentRange.location
        var frames: [(CGRect, Bool)] = []
        for (index, match) in matches.enumerated() where NSMaxRange(match) <= length {
            guard let start = content.location(documentStart, offsetBy: match.location) else { continue }
            manager.enumerateTextLayoutFragments(from: start, options: []) { fragment in
                let paragraph = content.offset(from: documentStart, to: fragment.rangeInElement.location)
                guard paragraph < NSMaxRange(match) else { return false }
                let box = fragment.layoutFragmentFrame
                for line in fragment.textLineFragments {
                    let letters = NSRange(location: paragraph + line.characterRange.location, length: line.characterRange.length)
                    let part = NSIntersectionRange(letters, match)
                    guard part.length > 0 else { continue }
                    let local = part.location - paragraph
                    let x0 = line.locationForCharacter(at: local).x, x1 = line.locationForCharacter(at: local + part.length).x
                    let font = (local < line.attributedString.length ? line.attributedString.attribute(.font, at: local, effectiveRange: nil) as? NSFont : nil)
                        ?? NSFont.systemFont(ofSize: MemoStyle.size)
                    let baseline = box.minY + line.typographicBounds.minY + line.glyphOrigin.y
                    let top = baseline - font.ascender - Metrics.spaceXxs
                    frames.append((CGRect(x: box.minX + line.typographicBounds.minX + min(x0, x1) + origin.x, y: top + origin.y,
                                          width: abs(x1 - x0), height: font.ascender - font.descender + 2 * Metrics.spaceXxs), index == current))
                }
                // On to the next paragraph only when the place runs past this one.
                return content.offset(from: documentStart, to: fragment.rangeInElement.endLocation) < NSMaxRange(match)
            }
        }
        return frames
    }

    private func clearPaint() {
        marks?.removeFromSuperview()
        marks = nil
    }

    /// The shown place scrolled into sight under the box, a line to spare above it. It is not
    /// picked while the box is open (an unfocused selection's grey band would show under the ink);
    /// closing the box picks it, and VoiceOver hears its line (`announce`).
    func reveal() {
        guard isOpen, let range = currentRange, let textView = memoTextView(), let scrollView = textView.enclosingScrollView,
              NSMaxRange(range) <= (textView.string as NSString).length else { return }
        guard let rect = frame(of: range, in: textView) else { return }
        let clip = scrollView.contentView
        // The box covers the memo's top this far.
        let covered = showsReplaceRow ? Self.twoRowCover : Self.oneRowCover
        let room = MemoStyle.lineHeight
        let shown = clip.convert(rect, from: textView)
        var y = clip.bounds.minY
        if shown.minY < clip.bounds.minY + covered {
            y = shown.minY - covered - room
        } else if shown.maxY > clip.bounds.maxY - Metrics.spaceXs {
            y = shown.maxY - clip.bounds.height + room
        } else {
            return
        }
        let height = scrollView.documentView?.frame.height ?? 0
        y = min(max(0, y), max(0, height - clip.bounds.height))
        let target = CGPoint(x: clip.bounds.minX, y: y)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            clip.scroll(to: target)
            scrollView.reflectScrolledClipView(clip)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Metrics.motionQuick
                clip.animator().setBoundsOrigin(target)
            } completionHandler: {
                MainActor.assumeIsolated { scrollView.reflectScrolledClipView(clip) }
            }
        }
    }

    /// Where the letters sit in the text view, all their lines together.
    func frame(of range: NSRange, in textView: NSTextView) -> CGRect? {
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return nil }
        manager.ensureLayout(for: textRange)
        var found = CGRect.null
        manager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            found = found.union(frame)
            return true
        }
        guard !found.isNull else { return nil }
        return found.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
    }

    /// The shown place's letters in the memo's text view, for the check.
    var currentFrame: CGRect? {
        guard let range = currentRange, let textView = memoTextView() else { return nil }
        return frame(of: range, in: textView)
    }

    // MARK: VoiceOver

    private func announce() {
        guard isOpen, hasQuery else { return }
        announce(index: current, count: matches.count)
    }

    /// `7개 중 3번째`, then the shown place's line, so VoiceOver reads where it is.
    private func announce(index: Int?, count: Int) {
        var words = count == 0 ? "찾은 곳 없음" : "\(count)개 중 \((index ?? 0) + 1)번째"
        if isOpen, let range = currentRange, let draft {
            let letters = String(draft.text.characters) as NSString
            if NSMaxRange(range) <= letters.length {
                let line = letters.substring(with: letters.lineRange(for: range)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { words += ", " + line }
            }
        }
        guard words != lastAnnounced else { return }
        lastAnnounced = words
        post(words)
    }

    private func post(_ words: String) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: words, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// The places found: a grey (`shade`) ground around each line of their letters, and an ink edge
/// around the shown one. Under the letters, so they draw over it; it takes no clicks.
private final class FindMarksView: NSView {
    var places: () -> [(frame: CGRect, isShown: Bool)] = { [] }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            let ground = NSColor(Color.shade), edge = NSColor(Color.ink)
            for place in places() where place.frame.intersects(dirtyRect) {
                // Kept inside the text view, so a title's tall first line keeps its top edge.
                let box = place.frame.integral.insetBy(dx: -1, dy: 0).intersection(bounds)
                guard !box.isEmpty else { continue }
                ground.setFill()
                box.fill()
                guard place.isShown else { continue }
                edge.setStroke()
                let path = NSBezierPath(rect: box.insetBy(dx: Metrics.lineBox / 2, dy: Metrics.lineBox / 2))
                path.lineWidth = Metrics.lineBox
                path.stroke()
            }
        }
    }
}

// MARK: The box

/// The find box over the memo's top right, under its tabs: the format bar's frame, 8 pt inside,
/// 4 pt between its 26×24 buttons. ⇄ brings out the replace row. A read-only memo has no ⇄.
struct MemoFindBox: View {
    @Bindable var find: MemoFindState
    @FocusState private var field: MemoFindState.Field?
    static let width: CGFloat = 248

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceXs) {
            HStack(spacing: Metrics.spaceXs) {
                if find.canReplace {
                    FindIconButton(glyph: .swap, name: find.showsReplace ? "바꾸기 닫기" : "바꾸기", help: "바꾸기 (⌥⌘F)",
                                   toggled: find.showsReplace) { find.toggleReplace() }
                        .accessibilityValue(find.showsReplace ? "펼침" : "접힘")
                }
                findField
                FindIconButton(glyph: .up, name: "이전", help: "이전 (⇧⌘G)") { find.step(-1) }
                    .disabled(find.matches.isEmpty)
                FindIconButton(glyph: .down, name: "다음", help: "다음 (⌘G)") { find.step(1) }
                    .disabled(find.matches.isEmpty)
                FindIconButton(glyph: .close, name: "닫기", help: "닫기 (Esc)") { find.close() }
            }
            if find.showsReplaceRow {
                HStack(spacing: Metrics.spaceXs) {
                    Color.clear.frame(width: 26, height: 24)
                    FindFieldFrame(isFocused: field == .replace) {
                        TextField("바꿀 글", text: $find.replacement)
                            .textFieldStyle(.plain)
                            .textStyle(.body)
                            .focused($field, equals: .replace)
                            .accessibilityLabel("바꿀 글")
                    }
                    FindTextButton(help: "지금 찾은 곳을 바꾸고 다음으로 (Return)") { find.replaceCurrent() } label: { Text("바꾸기") }
                        .disabled(find.matches.isEmpty)
                    FindTextButton(help: "모두 바꾸기 (⌥⌘Return)") { find.replaceAll() } label: {
                        HStack(spacing: Metrics.spaceXs) {
                            Text("모두")
                            Text("\(find.matches.count)").textStyle(.meta).monospacedDigit().foregroundStyle(.inkSoft)
                        }
                    }
                    .disabled(find.matches.isEmpty)
                    .accessibilityLabel("모두 바꾸기, \(find.matches.count)곳")
                }
            }
        }
        .padding(Metrics.spaceM)
        .frame(width: Self.width, alignment: .leading)
        .floatingFrame()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("메모에서 찾기")
        .onChange(of: field) { find.focusedField = field }
        .onChange(of: find.focusRequest, initial: true) {
            // Once the field is in the window.
            Task { @MainActor in field = find.focusTarget == .replace && find.showsReplaceRow ? .replace : .find }
        }
    }

    private var findField: some View {
        FindFieldFrame(isFocused: field == .find, isEmpty: find.foundNothing) {
            HStack(spacing: Metrics.spaceS) {
                FindGlyph.find.shape.stroke(.inkSoft, style: FindGlyph.stroke)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                TextField("찾을 글", text: $find.query)
                    .textFieldStyle(.plain)
                    .textStyle(.body)
                    .focused($field, equals: .find)
                    .accessibilityLabel("찾을 글")
                if find.hasQuery {
                    Text(find.countText)
                        .textStyle(.meta)
                        .monospacedDigit()
                        .foregroundStyle(.inkSoft)
                        .fixedSize()
                        .accessibilityLabel(find.foundNothing ? "찾은 곳 없음" : "\(find.matches.count)개 중 \((find.current ?? 0) + 1)번째")
                }
            }
        }
    }
}

/// A field of the box: 24 pt, a 1 pt ink edge that thickens to 1.5 pt with focus (no ring: box
/// edge, ring and field edge would crowd into 6 pt), `error-tint` when nothing is found.
private struct FindFieldFrame<Content: View>: View {
    var isFocused: Bool
    var isEmpty = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, Metrics.spaceS)
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
            .background(isEmpty ? Color.errorTint : Color.paper)
            .overlay(Rectangle().strokeBorder(.ink, lineWidth: isFocused ? Metrics.lineBox : Metrics.line))
    }
}

/// The box's glyphs, 14 pt, drawn with 1.5 pt ink lines.
enum FindGlyph {
    case find, swap, up, down, close

    static let stroke = StrokeStyle(lineWidth: Metrics.lineBox, lineCap: .square)

    var shape: Path {
        // In a 14 pt square.
        var p = Path()
        switch self {
        case .find:
            p.addEllipse(in: CGRect(x: 1.8, y: 1.8, width: 8.4, height: 8.4))
            p.move(to: CGPoint(x: 9.2, y: 9.2)); p.addLine(to: CGPoint(x: 12.6, y: 12.6))
        case .swap:
            p.move(to: CGPoint(x: 2, y: 4.5)); p.addLine(to: CGPoint(x: 11.5, y: 4.5))
            p.move(to: CGPoint(x: 9, y: 2)); p.addLine(to: CGPoint(x: 11.5, y: 4.5)); p.addLine(to: CGPoint(x: 9, y: 7))
            p.move(to: CGPoint(x: 12, y: 9.5)); p.addLine(to: CGPoint(x: 2.5, y: 9.5))
            p.move(to: CGPoint(x: 5, y: 7)); p.addLine(to: CGPoint(x: 2.5, y: 9.5)); p.addLine(to: CGPoint(x: 5, y: 12))
        case .up:
            p.move(to: CGPoint(x: 7, y: 11.5)); p.addLine(to: CGPoint(x: 7, y: 3))
            p.move(to: CGPoint(x: 3.5, y: 6.5)); p.addLine(to: CGPoint(x: 7, y: 3)); p.addLine(to: CGPoint(x: 10.5, y: 6.5))
        case .down:
            p.move(to: CGPoint(x: 7, y: 2.5)); p.addLine(to: CGPoint(x: 7, y: 11))
            p.move(to: CGPoint(x: 3.5, y: 7.5)); p.addLine(to: CGPoint(x: 7, y: 11)); p.addLine(to: CGPoint(x: 10.5, y: 7.5))
        case .close:
            p.move(to: CGPoint(x: 3.5, y: 3.5)); p.addLine(to: CGPoint(x: 10.5, y: 10.5))
            p.move(to: CGPoint(x: 10.5, y: 3.5)); p.addLine(to: CGPoint(x: 3.5, y: 10.5))
        }
        return p
    }
}

/// A 26×24 glyph button with its own 1 pt ink edge, as the format bar's; `toggled` (⇄ while the
/// replace row is out) is the grey of a switched-on control with a 1.5 pt edge. Off: faint, dashed.
private struct FindIconButton: View {
    let glyph: FindGlyph
    let name: String
    let help: String
    var toggled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FindGlyphLabel(glyph: glyph)
        }
        .buttonStyle(FindButtonStyle(toggled: toggled, width: 26))
        .help(help)
        .accessibilityLabel(name)
    }
}

private struct FindGlyphLabel: View {
    let glyph: FindGlyph
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        glyph.shape.stroke(isEnabled ? Color.ink : Color.inkFaint, style: FindGlyph.stroke)
            .frame(width: 14, height: 14)
    }
}

/// A word button of the box: 24 pt high, 8 pt either side, body letters.
private struct FindTextButton<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) { label.textStyle(.body) }
            .buttonStyle(FindButtonStyle(toggled: false, width: nil))
            .help(help)
    }
}

private struct FindButtonStyle: ButtonStyle {
    var toggled: Bool
    var width: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        FindButtonBody(configuration: configuration, toggled: toggled, width: width)
    }

    private struct FindButtonBody: View {
        let configuration: Configuration
        let toggled: Bool
        let width: CGFloat?
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? Color.ink : Color.inkFaint)
                .padding(.horizontal, width == nil ? Metrics.spaceM : 0)
                .frame(width: width, height: 24)
                .background(toggled || configuration.isPressed ? Color.rowActive : hovering && isEnabled ? Color.hover : Color.paper)
                .overlay {
                    if isEnabled {
                        Rectangle().strokeBorder(.ink, lineWidth: toggled ? Metrics.lineBox : Metrics.line)
                    } else {
                        Rectangle().strokeBorder(Color.inkFaint, style: StrokeStyle(lineWidth: Metrics.line, dash: [3, 2]))
                    }
                }
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                // Full keyboard access: the buttons take focus in turn and show the ring.
                .focusRing(isFocused && NSApp.isFullKeyboardAccessEnabled)
        }
    }
}

// MARK: Putting it on the memo

/// The find box on the memo editor, its keys and its room at the memo's top. Added once to
/// `MemoEditor`.
struct MemoFindLayer: ViewModifier {
    let draft: MemoDraft
    @Environment(\.colorScheme) private var colorScheme
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        let find = draft.find
        content
            .overlay(alignment: .topTrailing) {
                if find.isOpen {
                    MemoFindBox(find: find)
                        // 6 pt under the tabs, which stand a section step above the memo.
                        .offset(y: Metrics.spaceS - Metrics.spaceM)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                            find.frameInContent = draft.inContent(frame)
                        }
                        .onDisappear { find.frameInContent = .null }
                }
            }
            .background(FindWindowProbe(find: find))
            .focusedValue(\.memoFind, draft)
            .onAppear {
                find.draft = draft
                install()
            }
            .onDisappear {
                // The panel folded, or 모아 보기 moved the editor: the box goes with it.
                find.close(focusingMemo: false)
                find.forgetTextView()
                remove()
            }
            .onChange(of: draft.text) { find.textChanged() }
            .onChange(of: draft.noteID) { find.memoChanged() }
            .onChange(of: colorScheme) { find.repaint() }
    }

    /// ⌘F, ⌥⌘F, ⌘E, ⌘G and ⇧⌘G while the memo or the box has keyboard focus; Return, ⌥⌘Return
    /// and Esc in the box. By the key's place, so a Korean input source does not change them.
    private func install() {
        guard monitor == nil else { return }
        let draft = draft
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated { MemoFindKeys.handle(event, draft: draft) }
            return handled ? nil : event
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Tells the find which window the memo is in: the app's window, or a check's.
private struct FindWindowProbe: NSViewRepresentable {
    let find: MemoFindState

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.find = find
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.find = find
    }

    final class ProbeView: NSView {
        weak var find: MemoFindState?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { find?.window = window }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

@MainActor
enum MemoFindKeys {
    /// `kVK_ANSI_F`, `kVK_ANSI_G`, `kVK_ANSI_E`, `kVK_Return`, `kVK_ANSI_KeypadEnter`, `kVK_Escape`.
    static let keyF: UInt16 = 3
    static let keyG: UInt16 = 5
    static let keyE: UInt16 = 14
    static let keyReturn: UInt16 = 36
    static let keyEnter: UInt16 = 76
    static let keyEscape: UInt16 = 53

    static func handle(_ event: NSEvent, draft: MemoDraft) -> Bool {
        let find = draft.find
        guard draft.book.todos.pop == nil, event.window === find.window else { return false }
        let inBox = find.isOpen && find.focusedField != nil
        guard draft.hasFocus || inBox else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        // A Korean syllable still being composed in a field: Return and Esc finish it there first.
        let composing = (event.window?.firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
        switch (event.keyCode, modifiers) {
        case (keyF, [.command]):
            find.open(replacing: false)
        case (keyF, [.command, .option]):
            find.open(replacing: true)
        case (keyE, [.command]):
            guard draft.hasFocus else { return false }
            find.usePickedWords()
        case (keyG, [.command]):
            find.step(1)
        case (keyG, [.command, .shift]):
            find.step(-1)
        case (keyReturn, [.command, .option]), (keyEnter, [.command, .option]):
            guard inBox, !composing else { return false }
            find.replaceAll()
        case (keyReturn, []), (keyEnter, []):
            guard inBox, !composing else { return false }
            if find.focusedField == .replace { find.replaceCurrent() } else { find.step(1) }
        case (keyReturn, [.shift]), (keyEnter, [.shift]):
            guard inBox, !composing, find.focusedField == .find else { return false }
            find.step(-1)
        case (keyEscape, []):
            guard inBox, !composing else { return false }
            find.close()
        default:
            return false
        }
        return true
    }
}

extension FocusedValues {
    /// The memo the 찾기 menu works on: while it or its find box has keyboard focus.
    @Entry var memoFind: MemoDraft?
}

/// 편집 › 찾기: the find box's keys, for the memo or its box with keyboard focus.
struct MemoFindCommands: Commands {
    @FocusedValue(\.memoFind) private var draft

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Menu("찾기") {
                Button("찾기…") { draft?.find.open(replacing: false) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("찾아서 바꾸기…") { draft?.find.open(replacing: true) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(draft?.isUnreadable ?? true)
                Divider()
                Button("다음 찾기") { draft?.find.step(1) }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(draft?.find.hasQuery != true)
                Button("이전 찾기") { draft?.find.step(-1) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(draft?.find.hasQuery != true)
                Divider()
                Button("선택 항목으로 찾기") { draft?.find.usePickedWords() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(draft?.hasSelectedText != true)
            }
            .disabled(draft == nil)
        }
    }
}
