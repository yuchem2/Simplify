import SwiftUI
import SimplifyKit

/// The drawn pop over the panel: 가져오기, the memo's `[[` search, ⌘⇧T's periods, and a day to
/// pass to. A click outside or Esc closes it.
struct PanelPopLayer: View {
    let model: AppModel
    let calendars: CalendarController
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
                        .padding(Metrics.spaceS)
                        .frame(width: 316, alignment: .topLeading)
                        .floatingFrame()
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
        case .search, .makeTodos, .pickDay(.makeTodos), .link: break
        }
        guard let line = memos.todos.popAnchor else { return fallback }
        let frame = geo.frame(in: .global)
        let below = line.maxY - frame.minY + Metrics.spaceS
        if below + height <= geo.size.height - Metrics.spaceL { return below }
        return max(Metrics.spaceL, line.minY - frame.minY - height - Metrics.spaceS)
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
            DayPop(purpose: purpose, model: model, calendars: calendars, memos: memos, close: close)
        case .link(let location, let length, let address):
            LinkPop(draft: memos.draft, location: location, length: length, address: address, close: close)
        }
    }

    /// Closed without a pick: a typed `[[` comes back.
    private func close() {
        if case .search(let offset, let typed) = memos.todos.pop {
            memos.todos.pop = nil
            memos.draft.cancelSearch(at: offset, typed: typed)
        } else if case .link = memos.todos.pop {
            // Back to the letters it was about.
            memos.todos.pop = nil
            memos.draft.focusRequest += 1
        } else {
            memos.todos.pop = nil
        }
    }
}

// MARK: - Pieces

private struct PopGroup: View {
    let title: String
    var body: some View {
        SectionRule(title)
            .padding(.horizontal, Metrics.spaceM)
            .padding(.top, Metrics.spaceS)
            .padding(.bottom, Metrics.spaceXs)
    }
}

/// A row in a pick list: the title and a small line under it. Picked or under the keyboard
/// cursor, it is filled with ink.
private struct PickRow<Leading: View>: View {
    let title: String
    let detail: String
    let isOn: Bool
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.spaceM) {
            leading.padding(.top, Metrics.spaceXxs)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).textStyle(.item).lineLimit(2)
                Text(detail).textStyle(.cell).foregroundStyle(isOn ? Color.onInk : Color.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(isOn ? Color.onInk : Color.ink)
        .padding(.horizontal, Metrics.spaceM)
        .padding(.vertical, Metrics.spaceXs)
        .selectableRow(chosen: isOn, inset: 0)
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
            HStack(spacing: Metrics.spaceM) { content }
                .padding(.horizontal, Metrics.spaceXs)
                .padding(.top, Metrics.spaceM)
                .padding(.bottom, Metrics.spaceXxs)
        }
        .padding(.top, Metrics.spaceS)
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
    @State private var lines: [MemoBook.FoundLine]
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
                        pick(key, title: item.title, detail: home.map { TodoNames.long($0, now: model.today) } ?? "")
                    }
                    PopGroup(title: "메모 속 할 일 줄")
                    if lines.isEmpty { empty("[ ] 나 TODO: 로 시작하는 줄이 없어요.") }
                    ForEach(lines.indices, id: \.self) { index in
                        let found = lines[index]
                        let place = TodoNames.long(found.period, now: model.today).components(separatedBy: " · ")[0]
                        pick(lineKey(found), title: found.line.text, detail: found.name.map { "\(place) · \($0)" } ?? "\(place) 메모")
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
        Text(text).textStyle(.small).foregroundStyle(.inkSoft).padding(.horizontal, Metrics.spaceM).padding(.vertical, Metrics.spaceXs)
    }

    private func lineKey(_ found: MemoBook.FoundLine) -> String {
        "\(found.note.uuidString):\(found.line.line)"
    }

    private func pick(_ key: String, title: String, detail: String) -> some View {
        let isOn = picked.contains(key)
        return Button {
            if isOn { picked.remove(key) } else { picked.insert(key) }
        } label: {
            PickRow(title: title, detail: detail, isOn: isOn) { CheckBox(isOn: isOn, size: 14, onInk: isOn) }
        }
        .buttonStyle(FocusOnlyStyle())
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
        for (noteID, group) in Dictionary(grouping: chosen, by: \.note) {
            let made = group.compactMap { found in
                book.add(found.line.title, to: period, sourceNoteID: noteID).map { (found.line.line, $0) }
            }
            memos.rewrite(note: noteID) { text in
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
            // The box look goes on the whole line, so the magnifier sits inside the field.
            HStack(spacing: Metrics.spaceS) {
                Image(systemName: "magnifyingglass").foregroundStyle(.inkSoft)
                if isRenderingSnapshot {
                    Text("할 일 찾기").foregroundStyle(.inkFaint)
                    Spacer()
                } else {
                    field(found)
                }
            }
            .drawnField(.box, focused: focused)
            .padding(.horizontal, Metrics.spaceXxs)
            .padding(.top, Metrics.spaceXxs)
            .padding(.bottom, Metrics.spaceS)
            list(found)
        }
        .onAppear { focused = true }
    }

    private func field(_ found: [TodoItem]) -> some View {
                TextField("할 일 찾기", text: $query)
                    .textFieldStyle(.plain)
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
                            .textStyle(.small).foregroundStyle(.inkSoft).padding(Metrics.spaceM)
                    }
                    ForEach(Array(found.enumerated()), id: \.element.id) { index, item in
                        Button { highlighted = index; pick(found) } label: {
                            PickRow(title: item.title, detail: detail(item), isOn: index == highlighted) {
                                Mark(item.isDone ? Color.ink : nil, size: 10)
                            }
                        }
                        .buttonStyle(FocusOnlyStyle())
                    }
                }
            }
            PopFoot {
                Text("↵ 잇기 · ⌘↵ 새 할 일로 만들기").textStyle(.cell).foregroundStyle(.inkSoft)
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
        guard let period = memos.draft.period else { return }
        // Saved first, so a period's first memo has an id for the ToDo to name.
        memos.draft.flush()
        guard let item = memos.todos.add(query, to: period, sourceNoteID: memos.draft.noteID) else { return }
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
    @Environment(\.isRenderingSnapshot) private var isRenderingSnapshot

    /// The keys move an ink cursor; it shows only while the list has them.
    private var showsCursor: Bool { focused || isRenderingSnapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopGroup(title: "할 일로 만들기")
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                Button { pick(choice) } label: { item(choice.name, detail: choice.detail, isOn: showsCursor && index == highlighted) }
                    .buttonStyle(.plain)
            }
            Rectangle().fill(.ink).frame(height: Metrics.line).padding(.horizontal, Metrics.spaceM).padding(.vertical, Metrics.spaceXs)
            Button(action: other) { item("다른 날짜…", detail: "", isOn: showsCursor && highlighted == choices.count) }
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
            Text(name).textStyle(.body)
            Spacer()
            Text(detail).textStyle(.cell).foregroundStyle(isOn ? Color.onInk : Color.inkSoft)
        }
        .foregroundStyle(isOn ? Color.onInk : Color.ink)
        .padding(.horizontal, Metrics.spaceM)
        .padding(.vertical, Metrics.spaceXs)
        .selectableRow(chosen: isOn, inset: 0)
    }
}

// MARK: - 다른 날짜…

/// A day from a small calendar; 그 주로 and 그 달로 take its week or month instead.
private struct DayPop: View {
    let purpose: PanelPop.DayPurpose
    let model: AppModel
    let calendars: CalendarController
    let memos: MemoBook
    let close: () -> Void
    @State private var day = Date.now

    var body: some View {
        let calendar = model.calendar
        VStack(alignment: .leading, spacing: 0) {
            PopGroup(title: title)
            // A click only picks the day: 그 주로 and 그 달로 below still take its week or month.
            InkDatePicker(selection: $day, calendar: calendar, today: model.today, commitsOnClick: false, isHoliday: { calendars.holidayDays.contains($0) }) {
                finish(Period(containing: day, scope: .day, calendar: calendar))
            }
            .padding(.horizontal, Metrics.spaceM)
            .padding(.vertical, Metrics.spaceXs)
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
