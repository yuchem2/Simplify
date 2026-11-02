import SwiftUI
import SimplifyKit

/// The drawn pop over the panel: 가져오기, the memo's `[[` search, ⌘⇧T's periods, and a day to
/// pass to. A click outside or Esc closes it.
struct PanelPopLayer: View {
    let model: AppModel
    let memos: MemoBook
    @State private var height: CGFloat = 0

    var body: some View {
        if let pop = memos.todos.pop {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                        .accessibilityHidden(true)
                    content(pop)
                        .padding(6)
                        .frame(width: 316, alignment: .topLeading)
                        .background(.paper)
                        .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.lineOuter))
                        .drawnShadow()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                        .padding(.top, top(for: pop, in: geo))
                        .onExitCommand { close() }
                }
            }
        }
    }

    /// Under the memo line a memo pop is about, or over it where the panel has no room below;
    /// other pops sit near the top of the panel.
    private func top(for pop: PanelPop, in geo: GeometryProxy) -> CGFloat {
        let fallback: CGFloat = 118
        switch pop {
        case .importer, .pickDay(.pass): return fallback
        case .search, .makeTodos, .pickDay(.makeTodos): break
        }
        guard let line = memos.todos.popAnchor else { return fallback }
        let frame = geo.frame(in: .global)
        let below = line.maxY - frame.minY + 6
        if below + height <= geo.size.height - 12 { return below }
        return max(12, line.minY - frame.minY - height - 6)
    }

    @ViewBuilder
    private func content(_ pop: PanelPop) -> some View {
        switch pop {
        case .importer(let period):
            ImportPop(period: period, model: model, memos: memos, close: close)
        case .search(let offset, _):
            SearchPop(offset: offset, memos: memos)
        case .makeTodos(let lines):
            if let memo = memos.draft.period {
                TargetPop(choices: TodoTargets.choices(for: memo)) { target in
                    close()
                    memos.draft.makeTodos(fromLines: lines, in: target.period)
                } other: {
                    // Stays beside the same memo line.
                    memos.todos.pop = .pickDay(.makeTodos(lines: lines))
                }
            }
        case .pickDay(let purpose):
            DayPop(purpose: purpose, model: model, memos: memos, close: close)
        }
    }

    /// Closed without a pick: a typed `[[` comes back.
    private func close() {
        if case .search(let offset, let typed) = memos.todos.pop {
            memos.todos.pop = nil
            memos.draft.cancelSearch(at: offset, typed: typed)
        } else {
            memos.todos.pop = nil
        }
    }
}

// MARK: - Pieces

private struct PopGroup: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.inkSoft)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A row in a pick list: the title and a small line under it.
private struct PickRow<Leading: View>: View {
    let title: String
    let detail: String
    let isOn: Bool
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            leading.padding(.top, 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 14)).lineLimit(2)
                Text(detail).font(.system(size: 11)).foregroundStyle(.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background { if isOn { Rectangle().fill(.shadeSoft) } }
        .overlay { if isOn { Rectangle().strokeBorder(.ink, lineWidth: Metrics.line) } }
        .contentShape(Rectangle())
    }
}

/// A list that takes its own height up to `maxHeight` and scrolls only past it.
private struct PopScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.isRenderingSnapshot) private var isRenderingSnapshot

    var body: some View {
        // ImageRenderer draws no scroll views.
        if isRenderingSnapshot {
            content.frame(maxHeight: maxHeight, alignment: .top).fixedSize(horizontal: false, vertical: true).clipped()
        } else {
            fitted
        }
    }

    private var fitted: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PopFoot<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.ink).frame(height: Metrics.line)
            HStack(spacing: 8) { content }
                .padding(.horizontal, 4)
                .padding(.top, 8)
                .padding(.bottom, 2)
        }
        .padding(.top, 6)
    }
}

// MARK: - 가져오기

/// Unfinished ToDos from other periods and ToDo lines in memos, picked several at a time.
/// 잇기 shows each here too; 넘기기 moves a ToDo's own period here. A memo line becomes a new
/// ToDo here either way, and turns into a chip in its memo.
private struct ImportPop: View {
    let period: Period
    let model: AppModel
    let memos: MemoBook
    let close: () -> Void
    @State private var todos: [TodoItem]
    @State private var lines: [(period: Period, line: MemoTodoLine)]
    @State private var picked: Set<String> = []

    init(period: Period, model: AppModel, memos: MemoBook, close: @escaping () -> Void) {
        self.period = period
        self.model = model
        self.memos = memos
        self.close = close
        // Read once, when the pop opens; picking does not move rows around.
        _todos = State(initialValue: memos.todos.open(notIn: period))
        _lines = State(initialValue: memos.todoLines(calendar: model.calendar))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopScroll(maxHeight: 320) {
                VStack(alignment: .leading, spacing: 0) {
                    PopGroup(title: "아직 못 한 할 일")
                    if todos.isEmpty { empty("다른 날·주·달에 남은 할 일이 없어요.") }
                    ForEach(todos, id: \.id) { item in
                        let key = item.id.uuidString
                        let home = Period(key: item.periodKey, scope: item.scope, calendar: model.calendar)
                        pick(key, title: item.title, detail: home.map(TodoNames.long) ?? "")
                    }
                    PopGroup(title: "메모 속 할 일 줄")
                    if lines.isEmpty { empty("[ ] 나 TODO: 로 시작하는 줄이 없어요.") }
                    ForEach(lines.indices, id: \.self) { index in
                        let found = lines[index]
                        pick(lineKey(found), title: found.line.text, detail: "\(TodoNames.long(found.period).components(separatedBy: " · ")[0]) 메모")
                    }
                }
            }
            PopFoot {
                Button { finish(passing: true) } label: { Label("넘기기", systemImage: "arrow.turn.down.right") }
                    .buttonStyle(DrawnButtonStyle())
                    .disabled(picked.isEmpty)
                    .help("고른 할 일을 이 칸으로 옮겨요")
                Spacer()
                Button("취소", action: close).buttonStyle(DrawnButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(picked.isEmpty ? "잇기" : "\(picked.count)개 잇기") { finish(passing: false) }
                    .buttonStyle(DrawnButtonStyle(.primary))
                    .disabled(picked.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.inkFaint).padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func lineKey(_ found: (period: Period, line: MemoTodoLine)) -> String {
        "\(found.period.scope.rawValue):\(found.period.key):\(found.line.line)"
    }

    private func pick(_ key: String, title: String, detail: String) -> some View {
        let isOn = picked.contains(key)
        return Button {
            if isOn { picked.remove(key) } else { picked.insert(key) }
        } label: {
            PickRow(title: title, detail: detail, isOn: isOn) { TodoBox(isOn: isOn, size: 14) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func finish(passing: Bool) {
        let book = memos.todos
        for item in todos where picked.contains(item.id.uuidString) {
            if passing {
                book.pass(Todos.homeEntry(item), to: period)
            } else {
                book.link(item.id, to: period)
            }
        }
        // Lines of one memo go in one rewrite, bottom first, so line numbers stay put.
        let chosen = lines.filter { picked.contains(lineKey($0)) }
        for (memo, group) in Dictionary(grouping: chosen, by: { $0.period }) {
            let noteID = memos.noteID(for: memo)
            let made = group.compactMap { found in
                book.add(found.line.title, to: period, sourceNoteID: noteID).map { (found.line.line, $0) }
            }
            memos.rewrite(memo) { text in
                for (line, item) in made.sorted(by: { $0.0 > $1.0 }) {
                    MemoTodoLines.replaceLine(line, in: &text, with: MemoChips.chip(id: item.id, title: item.title, isDone: false))
                }
            }
        }
        close()
    }
}

// MARK: - [[

/// Finds a ToDo to put in the memo as a chip. ↵ puts the highlighted one; ⌘↵ makes a new ToDo
/// from the words typed, filed under the memo's own period.
private struct SearchPop: View {
    let offset: Int
    let memos: MemoBook
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool
    @Environment(\.isRenderingSnapshot) private var isRenderingSnapshot

    var body: some View {
        let found = memos.todos.search(query)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12))
                if isRenderingSnapshot {
                    Text("할 일 찾기").font(.system(size: 14)).foregroundStyle(.inkFaint)
                    Spacer()
                } else {
                    field(found)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 3)
            .padding(.bottom, 5)
            .overlay(alignment: .bottom) { Rectangle().fill(.ink).frame(height: Metrics.line) }
            .padding(.horizontal, 2)
            .padding(.bottom, 4)
            list(found)
        }
        .onAppear { focused = true }
    }

    private func field(_ found: [TodoItem]) -> some View {
                TextField("할 일 찾기", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit { pick(found) }
                    .onKeyPress(.upArrow) { highlighted = max(0, highlighted - 1); return .handled }
                    .onKeyPress(.downArrow) { highlighted = min(max(found.count - 1, 0), highlighted + 1); return .handled }
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        makeNew()
                        return .handled
                    }
                    .onChange(of: query) { highlighted = 0 }
    }

    private func list(_ found: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PopScroll(maxHeight: 260) {
                VStack(alignment: .leading, spacing: 0) {
                    if found.isEmpty {
                        Text(query.isEmpty ? "할 일이 아직 없어요." : "찾는 할 일이 없어요. ⌘↵로 새로 만들어요.")
                            .font(.system(size: 12)).foregroundStyle(.inkFaint).padding(8)
                    }
                    ForEach(Array(found.enumerated()), id: \.element.id) { index, item in
                        Button { highlighted = index; pick(found) } label: {
                            PickRow(title: item.title, detail: detail(item), isOn: index == highlighted) {
                                Mark(item.isDone ? Color.ink : nil, size: 10)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            PopFoot {
                Text("↵ 잇기 · ⌘↵ 새 할 일로 만들기").font(.system(size: 11)).foregroundStyle(.inkSoft)
                Spacer()
            }
        }
    }

    private func detail(_ item: TodoItem) -> String {
        let state = item.isDone ? "끝냄" : "아직"
        guard let home = Period(key: item.periodKey, scope: item.scope, calendar: memos.draft.period?.calendar ?? .simplify) else { return state }
        return "\(state) · \(TodoNames.long(home))"
    }

    private func pick(_ found: [TodoItem]) {
        guard found.indices.contains(highlighted) else { makeNew(); return }
        memos.todos.pop = nil
        memos.draft.insertChip(found[highlighted].id, at: offset)
    }

    private func makeNew() {
        guard let period = memos.draft.period, let item = memos.todos.add(query, to: period, sourceNoteID: memos.noteID(for: period)) else { return }
        memos.todos.pop = nil
        memos.draft.insertChip(item.id, at: offset)
    }
}

// MARK: - ⌘⇧T

/// Which period the picked memo lines become ToDos in.
private struct TargetPop: View {
    let choices: [TodoTargets.Target]
    let pick: (TodoTargets.Target) -> Void
    let other: () -> Void
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopGroup(title: "할 일로 만들기")
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                Button { pick(choice) } label: { item(choice.name, detail: choice.detail, isOn: index == highlighted) }
                    .buttonStyle(.plain)
            }
            Rectangle().fill(.ink).frame(height: Metrics.line).padding(.horizontal, 8).padding(.vertical, 5)
            Button(action: other) { item("다른 날짜…", detail: "", isOn: highlighted == choices.count) }
                .buttonStyle(.plain)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.upArrow) { highlighted = max(0, highlighted - 1); return .handled }
        .onKeyPress(.downArrow) { highlighted = min(choices.count, highlighted + 1); return .handled }
        .onKeyPress(.return) {
            if choices.indices.contains(highlighted) { pick(choices[highlighted]) } else { other() }
            return .handled
        }
    }

    private func item(_ name: String, detail: String, isOn: Bool) -> some View {
        HStack {
            Text(name).font(.system(size: 13))
            Spacer()
            Text(detail).font(.system(size: 11)).foregroundStyle(isOn ? Color.onInk : Color.inkSoft)
        }
        .foregroundStyle(isOn ? Color.onInk : Color.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isOn ? Color.ink : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - 다른 날짜…

/// A day from a small calendar; 그 주로 and 그 달로 take its week or month instead.
private struct DayPop: View {
    let purpose: PanelPop.DayPurpose
    let model: AppModel
    let memos: MemoBook
    let close: () -> Void
    @State private var day = Date.now

    var body: some View {
        let calendar = model.calendar
        VStack(alignment: .leading, spacing: 0) {
            PopGroup(title: title)
            DatePicker("날짜", selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.calendar, calendar)
                .environment(\.locale, Locale(identifier: "ko_KR"))
                .padding(.horizontal, 4)
            PopFoot {
                Button("그 주로") { finish(Period(containing: day, scope: .week, calendar: calendar)) }.buttonStyle(DrawnButtonStyle())
                Button("그 달로") { finish(Period(containing: day, scope: .month, calendar: calendar)) }.buttonStyle(DrawnButtonStyle())
                Spacer()
                Button("\(calendar.component(.day, from: day))일로") { finish(Period(containing: day, scope: .day, calendar: calendar)) }
                    .buttonStyle(DrawnButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            if case .pass(_, let from) = purpose { day = from.calendar.date(byAdding: .day, value: 1, to: from.start) ?? from.start }
            else { day = model.selectedDay }
        }
    }

    private var title: String {
        switch purpose {
        case .pass: "넘기기"
        case .makeTodos: "할 일로 만들기"
        }
    }

    private func finish(_ target: Period) {
        close()
        switch purpose {
        case .pass(let entry, _): memos.todos.pass(entry, to: target)
        case .makeTodos(let lines): memos.draft.makeTodos(fromLines: lines, in: target)
        }
    }
}
