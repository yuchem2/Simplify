import AppKit
import SwiftUI
import SimplifyKit

// A period's several memos in the panel: the tabs under the "메모" rule (하나씩), or the memos one
// under another (모아 보기), with names changed in place and 메모 지우기 asked in the panel.

/// The tabs of the period's memos in the order they were made, then `+ 새 메모`. The open memo's
/// name is ink with a line under it; double-click or 이름 바꾸기 changes a name in place.
struct MemoTabsRow: View {
    @Bindable var draft: MemoDraft
    let tabs: [MemoBook.Tab]

    var body: some View {
        FlowRow(spacing: Metrics.spaceL, lineSpacing: Metrics.spaceXs) {
            ForEach(tabs, id: \.id) { tab in
                MemoTabLabel(draft: draft, tab: tab, isOn: tab.id == draft.noteID, font: TextStyle.item.font,
                             nsFont: .systemFont(ofSize: TextStyle.item.size))
            }
            Button("+ 새 메모") { draft.newMemo() }
                .buttonStyle(.plain)
                .textStyle(.item)
                .foregroundStyle(.inkFaint)
                .padding(.bottom, Metrics.spaceXs + Metrics.lineSpine)
                .help("이 기간에 새 메모를 만들어요")
                .disabled(draft.isUnreadable && draft.noteID == nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("메모 목록")
    }
}

/// One memo's name: a tab in 하나씩, a header in 모아 보기. While renamed it is a field with only a
/// caret at the end of the name: no box, no highlight.
struct MemoTabLabel: View {
    @Bindable var draft: MemoDraft
    let tab: MemoBook.Tab
    let isOn: Bool
    let font: Font
    let nsFont: NSFont
    /// 모아 보기's header: the name is its title, and the line under it runs across the memo.
    var isHeader = false
    @State private var menuOpen = false

    var body: some View {
        let renaming = tab.id != nil && draft.renaming == tab.id
        Group {
            if renaming {
                // The name as the tab shows it holds the place, so the field's letters and the line
                // under them stand where the tab's do, level with the other tabs.
                Text(draft.renameText.isEmpty ? " " : draft.renameText)
                    .font(font)
                    .fontWeight(isHeader ? nil : .semibold)
                    .lineLimit(1)
                    .hidden()
                    .overlay(alignment: .leading) {
                        InlineNameField(text: $draft.renameText, font: fieldFont) { toBody in
                            draft.commitRename(toBody: toBody)
                        } cancel: {
                            draft.cancelRename()
                        }
                        .fixedSize()
                        .accessibilityLabel("메모 이름")
                    }
            } else {
                Text(tab.name)
                    .font(font)
                    .fontWeight(isOn && !isHeader ? .semibold : nil)
                    .foregroundStyle(isOn || isHeader ? Color.ink : Color.inkSoft)
                    .lineLimit(1)
            }
        }
        // Room under the letters for the line: with less, letters that reach lower (`(1)`, `g`) come
        // nearer to it than the rest, and the line reads as sloping.
        .padding(.bottom, Metrics.spaceXs + (isHeader ? 0 : Metrics.lineSpine))
        .frame(maxWidth: isHeader ? .infinity : nil, alignment: .leading)
        .overlay(alignment: .bottom) {
            if isHeader {
                Rectangle().fill(isOn ? Color.ink : Color.shade).frame(height: isOn ? Metrics.lineSpine : Metrics.line)
            } else if isOn || renaming || menuOpen {
                Rectangle().fill(isOn || renaming ? Color.ink : Color.shade).frame(height: Metrics.lineSpine)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !renaming { draft.select(tab.id) } }
        // Not exclusive: the first click opens the memo at once, the second starts the rename.
        .simultaneousGesture(TapGesture(count: 2).onEnded { if !renaming { draft.startRenaming(tab.id) } })
        .inkContextMenu(isEnabled: draft.book.todos.pop == nil && !renaming, isOpen: $menuOpen) { menu }
        .accessibilityElement(children: renaming ? .contain : .ignore)
        .accessibilityLabel(tab.name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { draft.select(tab.id) }
        .accessibilityAction(named: "이름 바꾸기") { draft.startRenaming(tab.id) }
    }

    /// The tab's own face: semibold, as the open tab is drawn.
    private var fieldFont: NSFont {
        isHeader ? nsFont : NSFont.systemFont(ofSize: nsFont.pointSize, weight: .semibold)
    }

    private var menu: [InkMenuEntry] {
        var entries: [InkMenuEntry] = [.item("이름 바꾸기") { draft.startRenaming(tab.id) }]
        if let id = tab.id {
            entries += [.divider, .item("메모 지우기", isDanger: true) { draft.askToDelete(id) }]
        }
        return entries
    }
}

/// 메모 지우기 on a memo with words: asked once more, in the panel under the tabs.
struct MemoDeleteQuestion: View {
    let draft: MemoDraft
    let id: UUID
    let name: String

    var body: some View {
        HStack(spacing: Metrics.spaceM) {
            Text("‘\(name)’ 메모를 지우면 쓴 글도 함께 지워져요.")
                .textStyle(.item)
                .foregroundStyle(.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Metrics.spaceS)
            Button("취소") { draft.confirmingDelete = nil }
                .buttonStyle(DrawnButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button("지우기") { draft.delete(id) }
                .buttonStyle(DrawnButtonStyle(.danger))
        }
        .padding(.vertical, Metrics.spaceXs)
        .accessibilityElement(children: .contain)
    }
}

/// `하나씩 | 모아 보기` on the "메모" rule.
struct MemoLayoutSwitch: View {
    @Binding var layout: AppModel.MemoLayout
    let draft: MemoDraft

    var body: some View {
        HStack(spacing: 0) {
            segment(.one, "하나씩")
            Rectangle().fill(.ink).frame(width: Metrics.line)
            segment(.all, "모아 보기")
        }
        .fixedSize()
        .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("메모 보기")
    }

    private func segment(_ value: AppModel.MemoLayout, _ label: String) -> some View {
        let isOn = layout == value
        return Button {
            guard layout != value else { return }
            // The editor moves to another place in the panel.
            draft.resignEditor?()
            layout = value
        } label: {
            Text(label)
                .textStyle(.meta)
                .foregroundStyle(isOn ? Color.onInk : Color.ink)
                .padding(.horizontal, Metrics.spaceS)
                .frame(height: 18)
        }
        .buttonStyle(FormatButtonStyle(isOn: isOn))
        .focusable(false)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 모아 보기's `+`: a new memo, named in its header.
struct MemoAddButton: View {
    let draft: MemoDraft

    var body: some View {
        Button { draft.newMemo() } label: {
            Text("+")
                .textStyle(.meta)
                .foregroundStyle(.ink)
                .frame(width: 20, height: 18)
                .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
        }
        .buttonStyle(FormatButtonStyle(isOn: false))
        .focusable(false)
        .help("새 메모")
        .accessibilityLabel("새 메모")
    }
}

/// A memo of 모아 보기 that is not being written: drawn read-only as the editor draws it (the same
/// formatting and `MemoLineStyler`), as tall as its text. A click moves the writing to it.
struct MemoReadOnly: View {
    let text: AttributedString
    let label: String
    /// Nothing open over the panel (a pop, a modal), so a click on the memo is for it.
    let canPick: () -> Bool
    let pick: () -> Void
    @State private var height: CGFloat = MemoStyle.lineHeight + 2 * MemoStyle.textViewInset.height
    @State private var place = MemoReadPlace()
    @Environment(\.isRenderingSnapshot) private var isRenderingSnapshot

    var body: some View {
        let tapped: some View = content.contentShape(Rectangle()).onTapGesture { pick() }
        let words = String(text.characters)
        return tapped
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(words))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("눌러서 이 메모를 써요"))
            .accessibilityAction { pick() }
    }

    @ViewBuilder
    private var content: some View {
        if isRenderingSnapshot {
            MemoPrint(text: text)
                .padding(.vertical, MemoStyle.textViewInset.height)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            drawn
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
                .background { MemoReadHost(place: place, text: text, pick: pick, canPick: canPick) { height = $0 } }
                .onGeometryChange(for: CGRect.self) { proxy in proxy.frame(in: .global) } action: { place.frame = $0 }
        }
    }

    private var drawn: some View {
        let letters: Binding<AttributedString> = .constant(text)
        let selection: Binding<AttributedTextSelection> = .constant(AttributedTextSelection())
        return TextEditor(text: letters, selection: selection)
            .attributedTextFormattingDefinition(MemoFormatting())
            .textStyle(.memo)
            .lineHeight(.exact(points: TextStyle.memo.lineHeight))
            .foregroundStyle(.ink)
            .scrollContentBackground(.hidden)
            .disabled(true)
            .allowsHitTesting(false)
            .padding(.leading, -MemoStyle.textViewInset.width)
    }
}

/// Where a read-only memo sits in the window (top-left origin), as SwiftUI lays it out.
final class MemoReadPlace {
    var frame: CGRect = .null {
        didSet { if frame != oldValue { moved?() } }
    }
    /// The host looks for its text view again: it may have looked before the memo had a place.
    var moved: (() -> Void)?
}

/// Finds the read-only memo's text view by its place, has a `MemoLineStyler` draw it, and reports
/// how tall its text is.
private struct MemoReadHost: NSViewRepresentable {
    let place: MemoReadPlace
    let text: AttributedString
    let pick: () -> Void
    let canPick: () -> Bool
    let measured: (CGFloat) -> Void

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.place = place
        view.measured = measured
        view.pick = pick
        view.canPick = canPick
        // Moved only (scrolled): found again if need be, not drawn again.
        place.moved = { [weak view] in Task { @MainActor in view?.redraw(force: false) } }
        return view
    }

    static func dismantleNSView(_ view: HostView, coordinator: ()) {
        view.release()
    }

    func updateNSView(_ view: HostView, context: Context) {
        view.measured = measured
        view.pick = pick
        view.canPick = canPick
        // Drawn again in full only for new letters: the panel is laid out again on every key
        // typed in the memo being written, and this memo has not changed.
        let changed = view.text != text
        view.text = text
        // After the text view has taken the letters.
        Task { @MainActor in view.redraw(force: changed) }
    }

    final class HostView: NSView {
        var place: MemoReadPlace?
        var measured: ((CGFloat) -> Void)?
        var pick: (() -> Void)?
        var canPick: (() -> Bool)?
        /// The letters last drawn.
        var text: AttributedString?
        private let styler = MemoLineStyler()
        private var last: CGFloat?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            Task { @MainActor [weak self] in self?.redraw() }
            // The text view under the click is AppKit's and takes the click before SwiftUI could:
            // a click that lands on it is caught here and moves the writing to this memo.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let window = self.window, event.window === window, let textView = self.styler.textView,
                          self.canPick?() == true else { return false }
                    let outer = textView.enclosingScrollView ?? textView
                    guard outer.convert(outer.visibleRect, to: nil).contains(event.locationInWindow) else { return false }
                    self.pick?()
                    return true
                }
                return handled ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// The memo went: its text view and paragraphs are let go.
        func release() {
            stop()
            if let textView = styler.textView { MemoTextViews.readOnly.remove(textView) }
            styler.detach()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            Task { @MainActor [weak self] in
                guard let self, self.styler.isAttached else { return }
                self.styler.update(force: true)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// `force` false: only found again if it moved, and measured; its paragraphs stay as made.
        @MainActor
        func redraw(force: Bool = true) {
            guard let window, let content = window.contentView, let here = place?.frame, !here.isNull else { return }
            // While the memos are laid out again a text view may first be taken for another memo's:
            // one that is no longer where this memo is goes back.
            // Looser than finding it: SwiftUI's place and AppKit's can be a frame apart while scrolling.
            if styler.isAttached, let textView = styler.textView, !MemoTextViews.isAt(textView, here, slack: 12) {
                MemoTextViews.readOnly.remove(textView)
                styler.detach()
                last = nil
            }
            var force = force
            if !styler.isAttached {
                guard let textView = MemoTextViews.find(in: content, at: here) else { return }
                styler.attach(to: textView)
                // Passed over by the editor looking for its own text view.
                if styler.textView === textView { MemoTextViews.readOnly.add(textView) }
                force = true
            }
            styler.update(force: force)
            guard let textView = styler.textView, let height = MemoTextViews.contentHeight(of: textView), height != last else { return }
            last = height
            measured?(height)
        }
    }
}

enum MemoTextViews {
    /// The text views drawing 모아 보기's read-only memos.
    @MainActor static let readOnly = NSHashTable<NSTextView>.weakObjects()

    /// The read-only text view whose top-left corner is at `box`'s (SwiftUI's global frame of the
    /// memo): not the memo being written (drawn by its own styler, and editable).
    @MainActor
    static func find(in view: NSView, at box: CGRect) -> NSTextView? {
        if let textView = view as? NSTextView, !textView.isFieldEditor,
           readOnly.contains(textView) || (textView.textContentStorage?.delegate == nil && textView.window?.firstResponder !== textView) {
            return isAt(textView, box) ? textView : nil
        }
        for subview in view.subviews {
            if let found = find(in: subview, at: box) { return found }
        }
        return nil
    }

    /// The text view (its scroll view) starts where `box` starts, within `slack` points. SwiftUI's
    /// global frame was seen measured from the window's top edge, title bar included; where the
    /// content fills the window that is the content's top too, so either is taken.
    @MainActor
    static func isAt(_ textView: NSTextView, _ box: CGRect, slack: CGFloat = 2) -> Bool {
        guard let window = textView.window, let content = window.contentView else { return false }
        let outer = textView.enclosingScrollView ?? textView
        let frame = outer.convert(outer.bounds, to: nil)
        let fromWindowTop = window.frame.height - frame.maxY
        let inContent = content.convert(outer.bounds, from: outer)
        let fromContentTop = content.isFlipped ? inContent.minY : content.bounds.height - inContent.maxY
        let top = abs(fromWindowTop - box.minY) < abs(fromContentTop - box.minY) ? fromWindowTop : fromContentTop
        return abs(top - box.minY) < slack && abs(frame.minX - box.minX) < 8
    }

    /// How tall the text view's letters are laid out, with its insets: a memo of 모아 보기 is that tall.
    @MainActor
    static func contentHeight(of textView: NSTextView) -> CGFloat? {
        guard let manager = textView.textLayoutManager else { return nil }
        manager.ensureLayout(for: manager.documentRange)
        let used = manager.usageBoundsForTextContainer.height
        let lines = max(used, MemoStyle.lineHeight)
        return (lines + 2 * MemoStyle.textViewInset.height).rounded(.up)
    }
}

/// A field for a memo's name inside its tab: the name's own width, no border, no focus ring, the
/// caret put at the end of the name with nothing picked (an AppKit field, so the name is never
/// shown picked, not even for a moment). Return and Tab keep the name and go on to the memo, Esc
/// puts it back; losing focus keeps it.
struct InlineNameField: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let commit: (_ toBody: Bool) -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NameField {
        let field = NameField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = NSColor(Color.ink)
        field.stringValue = text
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        // Once it is in the window, and after the memo has let its focus go (`blurRequest`).
        func focus(_ tries: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let window = field.window { window.makeFirstResponder(field) } else if tries > 0 { focus(tries - 1) }
            }
        }
        focus(4)
        return field
    }

    func updateNSView(_ field: NameField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
            field.invalidateIntrinsicContentSize()
        }
    }

    static func dismantleNSView(_ field: NameField, coordinator: Coordinator) {
        coordinator.isDone = true
        if field.currentEditor() != nil { field.abortEditing() }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineNameField
        /// Committed or put back already: the end of editing that follows does nothing more.
        var isDone = false

        init(_ parent: InlineNameField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            field.invalidateIntrinsicContentSize()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                finish(control) { parent.commit(true) }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finish(control) { parent.cancel() }
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            finish { parent.commit(false) }
        }

        /// `control` given: its editing ends here first, before the field goes away.
        private func finish(_ control: NSControl? = nil, _ action: () -> Void) {
            guard !isDone else { return }
            isDone = true
            if let control, control.currentEditor() != nil { control.window?.makeFirstResponder(nil) }
            action()
        }
    }

    final class NameField: NSTextField {
        override var intrinsicContentSize: NSSize {
            let width = (stringValue as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13)]).width
            return NSSize(width: ceil(width) + 3, height: super.intrinsicContentSize.height)
        }

        /// The caret at the end of the name, in ink, with nothing picked (a field picks all of
        /// itself on focus).
        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became, let editor = currentEditor() as? NSTextView {
                editor.selectedRange = NSRange(location: (stringValue as NSString).length, length: 0)
                editor.insertionPointColor = NSColor(Color.ink)
                editor.selectedTextAttributes = [.backgroundColor: NSColor(Color.rowActive)]
            }
            return became
        }
    }
}

/// Lays its views out left to right, starting a new line when the next one does not fit.
struct FlowRow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + row.height - size.height), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let added = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if added > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row(items: [index], width: size.width, height: size.height))
            } else {
                rows[rows.count - 1].items.append(index)
                rows[rows.count - 1].width = added
                rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            }
        }
        return rows
    }
}
