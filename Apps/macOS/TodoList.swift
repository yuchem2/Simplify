import AppKit
import SwiftUI
import SimplifyKit

/// A period's ToDos in the panel: tick with the box, double-click or Return to rename, ⌫ to
/// delete (or, for a linked row, to leave this period), drag to reorder, right-click for the
/// colour label and 넘기기. The last row takes a new ToDo on Return.
///
/// A click picks a row and the keys act on it through `TodoKeyHost`: SwiftUI focus on a plain
/// row does not take the keyboard from the calendar beside it.
struct TodoList: View {
    let period: Period
    let model: AppModel
    let memos: MemoBook
    @State private var newTitle = ""
    @State private var editing: UUID?
    @State private var editTitle = ""
    @State private var dropTarget: UUID?
    /// The row whose right-click menu is open: grey while it is.
    @State private var menuRow: UUID?
    @FocusState private var focus: Field?
    @Environment(\.isRenderingSnapshot) private var isRenderingSnapshot

    private enum Field: Hashable { case edit, add }
    /// The add row's drop slot.
    private static let endSlot = UUID()

    private var todos: TodoBook { memos.todos }

    var body: some View {
        let rows = todos.entries(for: period)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                // ImageRenderer cannot draw drag sources, drop targets or menus.
                if isRenderingSnapshot {
                    rowContent(entry)
                } else {
                    row(entry)
                    .overlay(alignment: .top) { if dropTarget == entry.id { DropLine() } }
                    .draggable(entry.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        drop(items, at: index, rows: rows)
                    } isTargeted: { dropTarget = $0 ? entry.id : (dropTarget == entry.id ? nil : dropTarget) }
                }
            }
            if isRenderingSnapshot {
                addRow
            } else {
                addRow
                    .overlay(alignment: .top) { if dropTarget == Self.endSlot { DropLine() } }
                    .dropDestination(for: String.self) { items, _ in
                        drop(items, at: rows.count, rows: rows)
                    } isTargeted: { dropTarget = $0 ? Self.endSlot : (dropTarget == Self.endSlot ? nil : dropTarget) }
            }
        }
        .background {
            if !isRenderingSnapshot {
                TodoKeyHost(book: todos) { key in handleKey(key, rows: rows) }
            }
        }
        .onChange(of: period) {
            editing = nil
            todos.selectedRow = nil
        }
    }

    /// ⌫ deletes the picked row, Return renames it, Space ticks it, Esc lets it go.
    private func handleKey(_ key: TodoKeyHost.Key, rows: [TodoEntry]) -> Bool {
        guard editing == nil, let id = todos.selectedRow, let entry = rows.first(where: { $0.id == id }) else { return false }
        switch key {
        case .delete: todos.remove(entry)
        case .rename: startEditing(entry)
        case .tick: todos.setDone(entry.todoID, !entry.isDone)
        case .release: todos.selectedRow = nil
        }
        return true
    }

    // MARK: Rows

    private func row(_ entry: TodoEntry) -> some View {
        rowContent(entry)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { startEditing(entry) }
            .onTapGesture {
                // The add field lets go, so the keys come to the row.
                focus = nil
                todos.selectedRow = entry.id
            }
            .inkContextMenu(isEnabled: !model.isModalOpen && todos.pop == nil,
                            isOpen: Binding(get: { menuRow == entry.id }, set: { if $0 { menuRow = entry.id } else if menuRow == entry.id { menuRow = nil } })) { menu(entry) }
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: entry.isLink ? "이 칸에서 빼기" : "지우기") { todos.remove(entry) }
    }

    private func rowContent(_ entry: TodoEntry) -> some View {
        let isEditing = editing == entry.id
        // Picked from the list: ink; being renamed: grey.
        let isChosen = todos.selectedRow == entry.id && !isEditing
        return HStack(alignment: .top, spacing: Metrics.spaceM) {
            Button { todos.setDone(entry.todoID, !entry.isDone) } label: { EmptyView() }
                .buttonStyle(CheckBoxButtonStyle(isOn: entry.isDone, onInk: isChosen))
                .padding(.top, Metrics.spaceXxs)
                .accessibilityLabel(entry.title)
                .accessibilityValue(entry.isDone ? "완료" : "미완료")
                .accessibilityAddTraits(.isToggle)
            VStack(alignment: .leading, spacing: 0) {
                if isEditing {
                    TextField("할 일", text: $editTitle)
                        .textStyle(.item)
                        .drawnField(.inline, focused: focus == .edit)
                        .focused($focus, equals: .edit)
                        .onSubmit { finishEditing(entry) }
                        .onExitCommand { editing = nil; focus = nil }
                        .onChange(of: focus) { _, now in if now != .edit, editing == entry.id { finishEditing(entry) } }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceS) {
                        if let label = entry.label {
                            Mark(label.ink, size: 8).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        }
                        let color = isChosen ? Color.onInk : entry.isDone ? Color.inkSoft : Color.ink
                        Text(entry.title)
                            .textStyle(.item)
                            .foregroundStyle(color)
                            .ledgerStrikethrough(entry.isDone, color: color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                meta(entry, onInk: isChosen)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Metrics.spaceXs)
        .selectableRow(chosen: isChosen, active: isEditing || menuRow == entry.id)
    }

    /// Where else the ToDo shows, and the memo it came from.
    @ViewBuilder
    private func meta(_ entry: TodoEntry, onInk: Bool) -> some View {
        let places = entry.elsewhere.compactMap { $0.period(calendar: model.calendar) }
        let source = entry.sourceNoteID.flatMap { id in memos.period(ofNote: id, calendar: model.calendar).map { (id: id, period: $0) } }
        if !places.isEmpty || source != nil {
            HStack(spacing: Metrics.spaceM) {
                if let source {
                    Button { show(source.period, note: source.id) } label: {
                        HStack(spacing: Metrics.spaceXxs) {
                            Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                            Text(memos.label(ofNote: source.id, calendar: model.calendar).map { "\(TodoNames.short(source.period, now: model.today)) · \($0)" }
                                ?? "\(TodoNames.short(source.period, now: model.today)) 메모").underline()
                        }
                    }
                    .buttonStyle(FocusOnlyStyle())
                    .help("메모 열기")
                }
                if !places.isEmpty {
                    HStack(spacing: Metrics.spaceXxs) {
                        Image(systemName: "link").font(.system(size: 9, weight: .medium))
                        Text(places.map { TodoNames.short($0, now: model.today) }.joined(separator: " · ") + "에 연결됨")
                    }
                    .foregroundStyle(onInk ? Color.onInk : Color.inkSoft)
                }
            }
            .textStyle(.meta)
            .foregroundStyle(onInk ? Color.onInk : Color.ink)
            .lineLimit(1)
        }
    }

    /// 고치기 · 색 라벨 › · 넘기기 › · 지우기 (or, for a linked row, 이 칸에서 빼기).
    private func menu(_ entry: TodoEntry) -> [InkMenuEntry] {
        let labels: [InkMenuEntry] = [.item("없음", checked: entry.label == nil) { todos.setLabel(entry.todoID, nil) }]
            + Palette.allCases.map { palette in
                .item(palette.name, swatch: InkMenuSwatch(palette.ink, shape: palette.markShape), checked: entry.label == palette) {
                    todos.setLabel(entry.todoID, palette)
                }
            }
        var targets: [InkMenuEntry] = []
        for group in TodoNames.passTargets(from: period) {
            targets += group.map { target in .item(target.name, detail: TodoNames.menuDetail(target.period)) { todos.pass(entry, to: target.period) } }
            targets.append(.divider)
        }
        targets.append(.item("다른 날짜…") { todos.pop = .pickDay(.pass(entry, from: period)) })
        return [
            .item("고치기") { startEditing(entry) },
            .submenu("색 라벨", labels),
            .submenu("넘기기", targets),
            .divider,
            .item(entry.isLink ? "이 칸에서 빼기" : "지우기", isDanger: true) { todos.remove(entry) },
        ]
    }

    // MARK: Adding and editing

    private var addRow: some View {
        HStack(spacing: Metrics.spaceM) {
            Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(.inkFaint).frame(width: 16)
            if isRenderingSnapshot {
                Text("할 일 추가").textStyle(.item).foregroundStyle(.inkFaint)
            } else {
                addField
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Metrics.spaceXs)
        .selectableRow(chosen: false)
    }

    private var addField: some View {
            TextField("할 일 추가", text: $newTitle)
                .textFieldStyle(.plain)
                .textStyle(.item)
                .focused($focus, equals: .add)
                .onSubmit {
                    todos.add(newTitle, to: period)
                    newTitle = ""
                    // Stays in the field for the next one.
                    focus = .add
                }
                .accessibilityLabel("할 일 추가")
    }

    private func startEditing(_ entry: TodoEntry) {
        editTitle = entry.title
        editing = entry.id
        focus = .edit
    }

    private func finishEditing(_ entry: TodoEntry) {
        guard editing == entry.id else { return }
        todos.rename(entry.todoID, to: editTitle)
        editing = nil
        if focus == .edit { focus = nil }
        todos.selectedRow = entry.id
    }

    private func drop(_ items: [String], at index: Int, rows: [TodoEntry]) -> Bool {
        dropTarget = nil
        guard let id = items.first.flatMap(UUID.init(uuidString:)), let entry = rows.first(where: { $0.id == id }) else { return false }
        todos.move(entry, to: index, in: period)
        return true
    }

    /// Opens the memo a ToDo was made from: its period, and that memo among the period's.
    private func show(_ period: Period, note: UUID) {
        memos.choose(note, in: period)
        if memos.draft.period == period { memos.draft.select(note) }
        model.select(period.start)
        model.panelScope = period.scope
    }
}

/// Where a dragged row will land.
private struct DropLine: View {
    var body: some View {
        Rectangle().fill(.ink).frame(height: 2).offset(y: -1).allowsHitTesting(false)
    }
}

/// Short names for periods under ToDos and in 넘기기.
enum TodoNames {
    /// `11/2`, `11월 1주차`, `11월`; today's day reads `11/6 오늘`.
    static func short(_ period: Period, now: Date = .now) -> String {
        let c = period.calendar.dateComponents([.month, .day], from: period.start)
        switch period.scope {
        case .day: return "\(c.month!)/\(c.day!)" + (period.contains(now) ? " 오늘" : "")
        case .week: return period.title
        case .month: return "\(c.month!)월"
        }
    }

    /// `11월 2일`, `11월 1주차`, `2026년 11월`, for lists that mix periods; the period holding
    /// today says so after it (`11월 6일 · 오늘`, `11월 1주차 · 이번 주`, `2026년 11월 · 이번 달`).
    static func long(_ period: Period, now: Date = .now) -> String {
        let c = period.calendar.dateComponents([.month, .day], from: period.start)
        let name = switch period.scope {
        case .day: "\(c.month!)월 \(c.day!)일"
        case .week, .month: period.title
        }
        guard period.contains(now) else { return name }
        let current = switch period.scope {
        case .day: "오늘"
        case .week: "이번 주"
        case .month: "이번 달"
        }
        return "\(name) · \(current)"
    }

    /// The right column of a menu line: `11.4`, `11월 2주차`, `12월`.
    static func menuDetail(_ period: Period) -> String {
        let c = period.calendar.dateComponents([.month, .day], from: period.start)
        switch period.scope {
        case .day: return "\(c.month!).\(c.day!)"
        case .week: return period.title
        case .month: return "\(c.month!)월"
        }
    }

    /// 넘기기's quick choices, in groups: the next period of each size, then this row's own week
    /// and month. The period the row is in is left out.
    static func passTargets(from period: Period) -> [[TodoTargets.Target]] {
        let calendar = period.calendar
        func target(_ name: String, _ p: Period) -> TodoTargets.Target {
            let detail: String = switch p.scope {
            case .day: "\(calendar.component(.month, from: p.start))월 \(calendar.component(.day, from: p.start))일"
            case .week: p.title
            case .month: "\(calendar.component(.month, from: p.start))월"
            }
            return TodoTargets.Target(name: name, detail: detail, period: p)
        }
        let week = Period(containing: period.start, scope: .week, calendar: calendar)
        let month = Period(containing: period.start, scope: .month, calendar: calendar)
        switch period.scope {
        case .day:
            return [[target("내일", period.advanced(by: 1)), target("다음 주", week.advanced(by: 1)), target("다음 달", month.advanced(by: 1))],
                    [target("이번 주로", week), target("이번 달로", month)]]
        case .week:
            return [[target("다음 주", period.advanced(by: 1)), target("다음 달", month.advanced(by: 1))], [target("이번 달로", month)]]
        case .month:
            return [[target("다음 달", period.advanced(by: 1))]]
        }
    }
}

/// The ToDo list's keys, read from the window's events before anything else gets them, the way
/// the memo box reads ⌘⇧T. Only while a row is picked and no text is being typed.
struct TodoKeyHost: NSViewRepresentable {
    enum Key { case delete, rename, tick, release }

    let book: TodoBook
    let handle: (Key) -> Bool

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.book = book
        view.handle = handle
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        view.book = book
        view.handle = handle
    }

    static func dismantleNSView(_ view: HostView, coordinator: ()) {
        view.stop()
    }

    final class HostView: NSView {
        var book: TodoBook?
        var handle: ((Key) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let window = self.window, event.window === window, let book = self.book,
                          book.selectedRow != nil, book.pop == nil else { return false }
                    if event.type == .leftMouseDown {
                        // A click outside the list lets the row go; a click on a row picks it again.
                        if !self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) { book.selectedRow = nil }
                        return false
                    }
                    // Typing goes to the field or memo that has it.
                    if window.firstResponder is NSText || (window.firstResponder as? NSTextInputClient)?.hasMarkedText() == true { return false }
                    guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
                    let key: Key? = switch event.keyCode {
                    case 51, 117: .delete   // ⌫, ⌦
                    case 36, 76: .rename    // Return, Enter
                    case 49: .tick          // Space
                    case 53: .release       // Esc
                    default: nil
                    }
                    guard let key else { return false }
                    return self.handle?(key) ?? false
                }
                return handled ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
