import AppKit
import SwiftUI
import SimplifyKit

/// The memo being written in the panel: its text, the selection, and saving after a pause.
@MainActor
@Observable
final class MemoDraft {
    var text = AttributedString()
    var selection = AttributedTextSelection()
    private(set) var period: Period?
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
    /// The box has keyboard focus; ⌘⇧T is caught only then.
    @ObservationIgnored var hasFocus = false
    /// The part of the box the panel shows, in window coordinates (top-left origin), as SwiftUI
    /// lays it out. Right-clicks and clicks are judged against it.
    @ObservationIgnored var visibleBox: CGRect = .null
    /// Where the selection's first line sits in the box, top-left origin; set by `MemoMenuHost`,
    /// which can ask the text view. Nil when it cannot tell.
    @ObservationIgnored var selectionLineRect: (() -> CGRect?)?
    /// The same line in window coordinates, top-left origin, for placing pops beside it.
    @ObservationIgnored var selectionLineInWindow: (() -> CGRect?)?
    /// Gives the focused text view the ink caret and a grey selection.
    @ObservationIgnored var inkTextView: (() -> Void)?
    /// Opens the right-click menu under the selection, for VoiceOver's 메뉴 보기.
    @ObservationIgnored var showMenu: (() -> Void)?
    /// The next text change is `[[` being put back after a closed search; it opens nothing.
    @ObservationIgnored var skipsSearchTrigger = false
    /// Bumped to put keyboard focus back in the box after a pop closes.
    var focusRequest = 0
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored let book: MemoBook
    /// The highlighter ⌘⇧H puts on. Remembered across launches.
    var lastHighlight = Palette(rawValue: UserDefaults.standard.string(forKey: "memoLastHighlight") ?? "") ?? .yellow {
        didSet { UserDefaults.standard.set(lastHighlight.rawValue, forKey: "memoLastHighlight") }
    }

    init(book: MemoBook) {
        self.book = book
    }

    /// Saves what is open, then shows `period`'s memo. The same period under another calendar (the
    /// week's first day or the zone changed) opens again, so names worked out from it follow.
    func open(_ period: Period) {
        guard period != self.period || period.calendar != self.period?.calendar else { return }
        flush()
        self.period = period
        let stored = book.text(for: period)
        isUnreadable = stored == nil
        text = stored ?? AttributedString()
        saved = text
        selection = AttributedTextSelection()
        // Chips show their ToDo as it is now; a change found here is saved like any other edit.
        refreshChips()
    }

    /// After typing stops for half a second the memo is saved.
    func textChanged() {
        keepCodeBlocksWhole()
        keepChipsWhole()
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
        if book.save(text, for: period) { saved = text }
    }

    /// The stored memo changed underneath (another device's text arrived after this box was
    /// saved): show what is stored. Text added at the end keeps the caret where it was.
    func storedChanged() {
        guard let period else { return }
        let stored = book.text(for: period)
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

    /// The caret's or selection's lines are a code block. Judged by the lines, since a caret at the
    /// start of a code line types with the plain line break before it.
    var isCode: Bool {
        let lines = lineRanges(of: selectedRanges)
        guard lines.ranges.contains(where: { !$0.isEmpty }) else { return isOn(MemoAttributes.Code.self) }
        return text[lines].runs[MemoAttributes.Code.self].allSatisfy { $0.0 == true }
    }

    func toggle<K: AttributedStringKey>(_ key: K.Type) where K.Value == Bool {
        let on = !isOn(key)
        change { $0[key] = on ? true : nil }
    }

    func toggleScript(_ script: MemoScript) {
        let on = shared(MemoAttributes.Script.self) != script
        change { $0[MemoAttributes.Script.self] = on ? script : nil }
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

    /// A code block takes whole lines: every line the selection touches.
    func toggleCode() {
        let on = !isCode
        var lines = lineRanges(of: selectedRanges)
        // Off takes the line breaks around the lines too, so no code is left for a later edit to
        // spread back over them.
        if !on {
            let characters = text.characters
            for line in lines.ranges {
                if line.lowerBound > characters.startIndex { lines.insert(characters.index(before: line.lowerBound), within: characters) }
                if line.upperBound < characters.endIndex { lines.insert(line.upperBound, within: characters) }
            }
        }
        text.transform(updating: &selection) { text in
            text[lines][MemoAttributes.Code.self] = on ? true : nil
            if on { text[lines][MemoAttributes.Highlight.self] = nil }
        }
        // Also the caret's typing style, so an empty line starts the block. Not for a selection,
        // which may hold a line break that would carry code into the next line.
        if !hasSelectedText { change { $0[MemoAttributes.Code.self] = on ? true : nil } }
    }

    /// 지우기: back to plain text. A code block goes whole lines at a time, as it came.
    func clearFormatting() {
        let lines = lineRanges(of: selectedRanges)
        text.transform(updating: &selection) { text in
            text[lines][MemoAttributes.Code.self] = nil
        }
        change { container in
            container[MemoAttributes.Bold.self] = nil
            container[MemoAttributes.Italic.self] = nil
            container[MemoAttributes.Code.self] = nil
            container[MemoAttributes.Math.self] = nil
            container[MemoAttributes.Script.self] = nil
            container[MemoAttributes.Ink.self] = nil
            container[MemoAttributes.Highlight.self] = nil
        }
    }

    /// The editor's onChange picks up the new text and schedules the save.
    private func change(_ body: (inout AttributeContainer) -> Void) {
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
    static let boxHeight: CGFloat = 170
    /// Where the text view draws its first letter inside its own frame; the placeholder and the
    /// snapshot's text sit that much further in, so they line up with typed text.
    static let textViewInset = CGSize(width: 5, height: 4)

    /// A chip's box letter: larger than the text, so it is easy to hit.
    static let boxSize: CGFloat = 20

    static func font(bold: Bool, italic: Bool, code: Bool, math: Bool, script: MemoScript?, box: Bool = false) -> Font {
        // In the memo's own face, only larger.
        if box { return .system(size: boxSize) }
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

    /// A chip's letters once its ToDo is done: soft and struck through.
    static func ink(_ palette: Palette?, todo: MemoTodo?) -> Color? {
        todo?.isDone == true ? Tokens.inkSoft : palette?.ink
    }

    /// The title only: the box letter shows its tick unstruck.
    static func strike(_ todo: MemoTodo?, box: Bool = false) -> Text.LineStyle? {
        todo?.isDone == true && !box ? .single : nil
    }

    /// The memo with SwiftUI's own attributes filled in, for drawing it as plain `Text`.
    static func rendered(_ text: AttributedString) -> AttributedString {
        var text = text
        for run in text.runs {
            let code = run[MemoAttributes.Code.self] == true
            let script = run[MemoAttributes.Script.self]
            let box = run[MemoAttributes.TodoBox.self] == true
            text[run.range].font = font(bold: run[MemoAttributes.Bold.self] == true, italic: run[MemoAttributes.Italic.self] == true,
                                        code: code, math: run[MemoAttributes.Math.self] == true, script: script, box: box)
            let todo = run[MemoAttributes.Todo.self]
            text[run.range].foregroundColor = ink(run[MemoAttributes.Ink.self], todo: todo)
            text[run.range].backgroundColor = ground(code: code, highlight: run[MemoAttributes.Highlight.self], todo: todo)
            text[run.range].strikethroughStyle = strike(todo, box: box)
            text[run.range].baselineOffset = baselineOffset(script)
        }
        return text
    }
}

/// What the memo editor accepts: the memo's own formatting, drawn through SwiftUI's font, colour
/// and baseline attributes. Anything else (pasted fonts, links, underlines) is dropped.
struct MemoFormatting: AttributedTextFormattingDefinition {
    struct Scope: AttributeScope {
        let font: AttributeScopes.SwiftUIAttributes.FontAttribute
        let foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        let backgroundColor: AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
        let baselineOffset: AttributeScopes.SwiftUIAttributes.BaselineOffsetAttribute
        let strikethroughStyle: AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute
        let memo: AttributeScopes.MemoScope
    }

    var body: some AttributedTextFormattingDefinition<Scope> {
        FontFromFormatting()
        InkFromFormatting()
        GroundFromFormatting()
        BaselineFromFormatting()
        StrikeFromFormatting()
    }

    private struct FontFromFormatting: AttributedTextValueConstraint {
        typealias Scope = MemoFormatting.Scope
        typealias AttributeKey = AttributeScopes.SwiftUIAttributes.FontAttribute

        func constrain(_ container: inout Attributes) {
            container[AttributeKey.self] = MemoStyle.font(
                bold: container[MemoAttributes.Bold.self] == true, italic: container[MemoAttributes.Italic.self] == true,
                code: container[MemoAttributes.Code.self] == true, math: container[MemoAttributes.Math.self] == true,
                script: container[MemoAttributes.Script.self], box: container[MemoAttributes.TodoBox.self] == true)
        }
    }

    private struct InkFromFormatting: AttributedTextValueConstraint {
        typealias Scope = MemoFormatting.Scope
        typealias AttributeKey = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute

        func constrain(_ container: inout Attributes) {
            container[AttributeKey.self] = MemoStyle.ink(container[MemoAttributes.Ink.self], todo: container[MemoAttributes.Todo.self])
        }
    }

    private struct GroundFromFormatting: AttributedTextValueConstraint {
        typealias Scope = MemoFormatting.Scope
        typealias AttributeKey = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute

        func constrain(_ container: inout Attributes) {
            container[AttributeKey.self] = MemoStyle.ground(code: container[MemoAttributes.Code.self] == true, highlight: container[MemoAttributes.Highlight.self],
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
            container[AttributeKey.self] = MemoStyle.strike(container[MemoAttributes.Todo.self], box: container[MemoAttributes.TodoBox.self] == true)
        }
    }
}

/// The memo box: a fixed 170 pt box that scrolls inside itself, with the format bar over or
/// under it while letters are picked.
struct MemoEditor: View {
    @Bindable var draft: MemoDraft
    let period: Period
    /// The section name, for VoiceOver.
    let title: String
    let placeholder: String
    @FocusState private var focused: Bool
    @Environment(\.isRenderingSnapshot) private var isRenderingSnapshot
    @Environment(\.undoManager) private var undoManager
    /// The box's top within the panel's scroll view, to put the bar where it fits.
    @State private var top: CGFloat = 0
    /// The selected line in the box, for putting the bar beside it.
    @State private var line: CGRect?
    @State private var hovering = false

    private var textInset: EdgeInsets {
        EdgeInsets(top: Metrics.spaceS + MemoStyle.textViewInset.height, leading: Metrics.spaceM + MemoStyle.textViewInset.width,
                   bottom: Metrics.spaceS + MemoStyle.textViewInset.height, trailing: Metrics.spaceM + MemoStyle.textViewInset.width)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isRenderingSnapshot {
                // ImageRenderer cannot draw the AppKit text view.
                Text(MemoStyle.rendered(draft.text))
                    .lineHeight(.exact(points: MemoStyle.lineHeight))
                    .padding(textInset)
            } else {
                TextEditor(text: $draft.text, selection: $draft.selection)
                    .attributedTextFormattingDefinition(MemoFormatting())
                    .textStyle(.memo)
                    .lineHeight(.exact(points: TextStyle.memo.lineHeight))
                    .foregroundStyle(.ink)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .disabled(draft.isUnreadable)
                    .padding(.horizontal, Metrics.spaceM)
                    .padding(.vertical, Metrics.spaceS)
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
        .frame(maxWidth: .infinity, minHeight: MemoStyle.boxHeight, maxHeight: MemoStyle.boxHeight, alignment: .topLeading)
        .clipped()
        .background { if !isRenderingSnapshot { MemoMenuHost(draft: draft) } }
        .background(hovering && !focused && !draft.isUnreadable ? Color.hover : Color.paper)
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGRect.self) { proxy in
            let local = CGRect(origin: .zero, size: proxy.size)
            let shown = proxy.bounds(of: .scrollView).map { local.intersection($0) } ?? local
            let frame = proxy.frame(in: .global)
            return shown.offsetBy(dx: frame.minX, dy: frame.minY)
        } action: { draft.visibleBox = $0 }
        .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
        .focusRing(focused)
        .overlay(alignment: .topLeading) {
            if showsBar {
                MemoFormatBar(draft: draft).offset(y: barY)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { top = $0 }
        // Under the box the bar would hang past the end of the scroll content, where clicks do not
        // reach it; the room is made inside the content instead.
        .padding(.bottom, showsBar ? max(0, barY + MemoFormatBar.height - MemoStyle.boxHeight) : 0)
        .focusedValue(\.memoDraft, focused ? draft : nil)
        .onChange(of: focused, initial: true) {
            draft.hasFocus = focused
            // Once the text view has become first responder.
            if focused { Task { @MainActor in draft.inkTextView?() } }
        }
        // The week's first day counts too: periods equal across calendars still open again under the new one.
        .onChange(of: [period.key, "\(period.start.timeIntervalSinceReferenceDate)", "\(period.calendar.firstWeekday)"], initial: true) {
            draft.open(period)
            // The text view stays the same across days; its undo steps belong to the memo it left.
            // After the text view has taken the new text, so that swap is not left as a step either.
            Task { @MainActor in undoManager?.removeAllActions() }
        }
        .onChange(of: draft.text) { draft.textChanged() }
        .onChange(of: draft.selection) {
            draft.selectionChanged()
            // After the text view has laid the new selection out.
            Task { @MainActor in line = draft.selectionLineRect?() }
        }
        .onChange(of: draft.focusRequest) { focused = true }
        .onDisappear { draft.flush() }
    }

    private var showsBar: Bool { focused && draft.hasSelectedText }

    /// The bar's top within the box. Beside the selected line: over it where the panel shows
    /// enough room, otherwise under it. Without the line's place, over or under the whole box.
    private var barY: CGFloat {
        let height = MemoFormatBar.height
        guard let line, line.maxY > 0, line.minY < MemoStyle.boxHeight else {
            return top > height + Metrics.spaceL ? -height - Metrics.spaceS : MemoStyle.boxHeight + Metrics.spaceS
        }
        return top + line.minY > height + Metrics.spaceL ? line.minY - height - Metrics.spaceS : line.maxY + Metrics.spaceS
    }
}

/// Bold, italic, code block, formula and raised/lowered letters, then text colour and
/// highlighter from the palette. Shortcuts show on hover and live in the 서식 menu too.
struct MemoFormatBar: View {
    let draft: MemoDraft
    static let height: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceS) {
            HStack(spacing: Metrics.spaceXs) {
                style("B", "굵게", "⌘B", isOn: draft.isOn(MemoAttributes.Bold.self), font: TextStyle.body.font.bold()) { draft.toggle(MemoAttributes.Bold.self) }
                style("I", "기울임", "⌘I", isOn: draft.isOn(MemoAttributes.Italic.self), font: TextStyle.body.font.italic(), design: .serif) { draft.toggle(MemoAttributes.Italic.self) }
                style("{ }", "코드 블록", "⌘⇧C", isOn: draft.isCode, font: TextStyle.cell.font.weight(.semibold), design: .monospaced) { draft.toggleCode() }
                Rectangle().fill(.ink).frame(width: Metrics.line, height: 18).padding(.horizontal, Metrics.spaceXxs)
                style("fx", "수식", "⌥⌘E", isOn: draft.isOn(MemoAttributes.Math.self), font: TextStyle.item.font.italic(), design: .serif) { draft.toggle(MemoAttributes.Math.self) }
                style("x²", "위첨자", "⌃⌘=", isOn: draft.shared(MemoAttributes.Script.self) == .raised, font: TextStyle.small.font) { draft.toggleScript(.raised) }
                style("x₂", "아래첨자", "⌃⌘-", isOn: draft.shared(MemoAttributes.Script.self) == .lowered, font: TextStyle.small.font) { draft.toggleScript(.lowered) }
                Spacer(minLength: Metrics.spaceM)
                Button("지우기") { draft.clearFormatting() }
                    .buttonStyle(DrawnButtonStyle(.text))
                    .focusable(false)
                    .help("서식 지우기")
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

    private func style(_ title: String, _ name: String, _ shortcut: String, isOn: Bool, font: Font, design: Font.Design? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .fontDesign(design)
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
private struct FormatButtonStyle: ButtonStyle {
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
                Button("코드 블록") { draft?.toggleCode() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Divider()
                Button("수식") { draft?.toggle(MemoAttributes.Math.self) }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                Button("위첨자") { draft?.toggleScript(.raised) }
                    .keyboardShortcut("=", modifiers: [.command, .control])
                Button("아래첨자") { draft?.toggleScript(.lowered) }
                    .keyboardShortcut("-", modifiers: [.command, .control])
                Divider()
                Button("형광펜 (\((draft?.lastHighlight ?? .yellow).name))") { draft?.repeatHighlight() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("서식 지우기") { draft?.clearFormatting() }
                Divider()
                Button("할 일로 만들기…") { draft?.askToMakeTodos() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("할 일 가져오기…") { draft?.askToLinkTodo() }
                Button("할 일 체크") { draft?.toggleChipAtCaret() }
            }
            .disabled(draft == nil)
        }
    }
}
