import SwiftUI

// The ink menu: the app's own right-click menus and dropdowns, drawn on paper like everything
// else instead of in the system's blue. One look for every menu: a floating frame, the cursor
// row filled with ink, the chosen value ticked, shortcuts and details in soft ink on the right,
// red only for what cannot be undone. The model and its keyboard walk are plain values here;
// `InkMenuPresenter` shows them in a panel over the window.

/// A swatch before a menu line: a calendar's or label's colour, in its shape when patterns are on.
public struct InkMenuSwatch {
    public var color: Color?
    public var shape: MarkShape?

    public init(_ color: Color?, shape: MarkShape? = nil) {
        self.color = color
        self.shape = shape
    }
}

/// One line that can be picked.
public struct InkMenuItem {
    public var title: String
    /// Soft ink on the right: a date (`11.4`), a period (`11월 1주차`) or a shortcut (`⌘X`).
    public var detail: String?
    public var swatch: InkMenuSwatch?
    /// nil for a line that is not one of several choices; true for the chosen one (✓).
    public var checked: Bool?
    public var isEnabled: Bool
    /// Cannot be undone (지우기, 연결 해제): red, and red under the cursor.
    public var isDanger: Bool
    public var submenu: [InkMenuEntry]?
    public var action: (@MainActor () -> Void)?

    public init(_ title: String, detail: String? = nil, swatch: InkMenuSwatch? = nil, checked: Bool? = nil, isEnabled: Bool = true,
                isDanger: Bool = false, submenu: [InkMenuEntry]? = nil, action: (@MainActor () -> Void)? = nil) {
        self.title = title
        self.detail = detail
        self.swatch = swatch
        self.checked = checked
        self.isEnabled = isEnabled
        self.isDanger = isDanger
        self.submenu = submenu
        self.action = action
    }

    /// Takes the cursor: enabled, and something happens when it is picked.
    var isPickable: Bool { isEnabled && (action != nil || submenu != nil) }
}

/// A line of a menu: something to pick, a small section title, or a rule.
public enum InkMenuEntry {
    case item(InkMenuItem)
    case section(String)
    case divider

    public static func item(_ title: String, detail: String? = nil, swatch: InkMenuSwatch? = nil, checked: Bool? = nil, isEnabled: Bool = true,
                            isDanger: Bool = false, action: @escaping @MainActor () -> Void) -> InkMenuEntry {
        .item(InkMenuItem(title, detail: detail, swatch: swatch, checked: checked, isEnabled: isEnabled, isDanger: isDanger, action: action))
    }

    public static func submenu(_ title: String, isEnabled: Bool = true, _ entries: [InkMenuEntry]) -> InkMenuEntry {
        .item(InkMenuItem(title, isEnabled: isEnabled, submenu: entries))
    }

    public var item: InkMenuItem? {
        if case .item(let item) = self { item } else { nil }
    }
}

/// Where the cursor is in an open menu and its open submenus, and what the keys do to it. The arrow
/// keys pass over section titles, rules and lines that cannot be used.
public struct InkMenuCursor {
    public struct Level {
        public var entries: [InkMenuEntry]
        /// The line under the cursor, an index into `entries`.
        public var cursor: Int?
    }

    public enum Key: Sendable { case up, down, right, left, enter, escape }

    public enum Outcome {
        case none
        /// Run this line's action and close the menu.
        case pick(InkMenuItem)
        /// Close the whole menu without a pick.
        case dismiss
    }

    /// The menu first, then each open submenu.
    public private(set) var levels: [Level]

    /// Opens on the chosen value, or the first line that can be used.
    public init(_ entries: [InkMenuEntry]) {
        levels = [Level(entries: entries, cursor: Self.initial(in: entries))]
    }

    public static func initial(in entries: [InkMenuEntry]) -> Int? {
        entries.indices.first { entries[$0].item?.checked == true && entries[$0].item?.isPickable == true }
            ?? entries.indices.first { entries[$0].item?.isPickable == true }
    }

    /// The next line that can be used, `step` lines on (±1), stopping at the ends.
    public static func move(from cursor: Int?, by step: Int, in entries: [InkMenuEntry]) -> Int? {
        let order = step > 0 ? Array(entries.indices) : entries.indices.reversed()
        guard let cursor else { return order.first { entries[$0].item?.isPickable == true } }
        return order.first { (step > 0 ? $0 > cursor : $0 < cursor) && entries[$0].item?.isPickable == true } ?? cursor
    }

    public mutating func handle(_ key: Key) -> Outcome {
        let depth = levels.count - 1
        let level = levels[depth]
        switch key {
        case .up, .down:
            // The deepest open level takes the keys, also a submenu the pointer opened without a cursor.
            levels[depth].cursor = Self.move(from: level.cursor, by: key == .down ? 1 : -1, in: level.entries)
            return .none
        case .right:
            openSubmenu()
            return .none
        case .left:
            if depth > 0 { levels.removeLast() }
            return .none
        case .enter:
            guard let cursor = level.cursor, let item = level.entries[cursor].item, item.isPickable else { return .none }
            if item.submenu != nil {
                openSubmenu()
                return .none
            }
            return .pick(item)
        case .escape:
            return .dismiss
        }
    }

    /// The pointer is over `index` of `depth` (nil: over no line). Deeper submenus close unless the
    /// pointer is on the line that opened them; a line with a submenu opens it without a cursor in it.
    public mutating func hover(depth: Int, index: Int?) {
        guard levels.indices.contains(depth) else { return }
        let entries = levels[depth].entries
        guard let index, entries.indices.contains(index), let item = entries[index].item, item.isPickable else {
            // Off every line: keep the line whose submenu is open.
            if levels.count == depth + 1 { levels[depth].cursor = nil }
            return
        }
        if levels[depth].cursor == index, levels.count > depth + 1 { return }
        levels[depth].cursor = index
        levels.removeSubrange((depth + 1)...)
        if let submenu = item.submenu {
            levels.append(Level(entries: submenu, cursor: nil))
        }
    }

    /// Puts the cursor on `index` of the deepest level, for typing a value.
    public mutating func place(at index: Int) {
        let depth = levels.count - 1
        guard levels[depth].entries.indices.contains(index), levels[depth].entries[index].item?.isPickable == true else { return }
        levels[depth].cursor = index
    }

    /// The item at `index` of `depth`, for a click.
    public func item(depth: Int, index: Int) -> InkMenuItem? {
        guard levels.indices.contains(depth), levels[depth].entries.indices.contains(index),
              let item = levels[depth].entries[index].item, item.isPickable else { return nil }
        return item
    }

    private mutating func openSubmenu() {
        let depth = levels.count - 1
        guard let cursor = levels[depth].cursor, let submenu = levels[depth].entries[cursor].item?.submenu, submenu.contains(where: { $0.item?.isPickable == true }) else { return }
        levels.append(Level(entries: submenu, cursor: Self.initial(in: submenu)))
    }
}

/// Typing a time into a list of times: `9`, `14`, `230`, `1415` put the cursor on the nearest
/// time in the list. An hour that could be morning or afternoon (`2`, `230`) is read as the one
/// nearer `near`, the time already chosen.
public enum TimeTypeahead {
    /// Minutes after midnight for the typed digits, or nil when they are not a time.
    public static func minutes(_ typed: String, near: Int?) -> Int? {
        guard !typed.isEmpty, typed.count <= 4, typed.allSatisfy(\.isASCII), let number = Int(typed) else { return nil }
        let hour: Int, minute: Int
        switch typed.count {
        case 1, 2: (hour, minute) = (number, 0)
        default: (hour, minute) = (number / 100, number % 100)
        }
        guard hour <= 24, minute < 60 else { return nil }
        let morning = hour % 24 * 60 + minute
        guard (1...11).contains(hour), let near else { return morning }
        let afternoon = morning + 12 * 60
        return abs(afternoon - near) < abs(morning - near) ? afternoon : morning
    }

    /// The index of the time in `options` (minutes after midnight) nearest what was typed.
    public static func nearest(_ typed: String, in options: [Int], near: Int?) -> Int? {
        guard let target = minutes(typed, near: near), !options.isEmpty else { return nil }
        return options.indices.min { abs(options[$0] - target) < abs(options[$1] - target) }
    }
}

// MARK: - Drawing

/// Fixed line heights, so the panel can tell which line the pointer is on without asking SwiftUI.
public enum InkMenuMetrics {
    public static let itemHeight: CGFloat = 26
    static let sectionHeight: CGFloat = 22
    static let dividerHeight: CGFloat = 9
    /// Above the first line and below the last.
    static let padding: CGFloat = Metrics.spaceXs
    static let minWidth: CGFloat = 128

    static func height(of entry: InkMenuEntry) -> CGFloat {
        switch entry {
        case .item: itemHeight
        case .section: sectionHeight
        case .divider: dividerHeight
        }
    }

    /// Each line's top, from the top of the list (under the padding).
    static func tops(_ entries: [InkMenuEntry]) -> [CGFloat] {
        var top: CGFloat = 0
        return entries.map { entry in
            defer { top += height(of: entry) }
            return top
        }
    }

    static func contentHeight(_ entries: [InkMenuEntry]) -> CGFloat {
        entries.reduce(0) { $0 + height(of: $1) }
    }

    /// The list's visible height: everything, or `maxItems` lines when the list is longer.
    static func viewportHeight(_ entries: [InkMenuEntry], maxItems: Int?) -> CGFloat {
        let full = contentHeight(entries)
        guard let maxItems else { return full }
        return min(full, CGFloat(maxItems) * itemHeight)
    }

    /// The line at `y` (from the top of the list, scrolled), if any.
    static func index(at y: CGFloat, in entries: [InkMenuEntry]) -> Int? {
        let tops = tops(entries)
        return entries.indices.last { tops[$0] <= y && y < tops[$0] + height(of: entries[$0]) }
    }
}

/// One level of an ink menu, as drawn. The panel puts it on screen; a snapshot can draw it alone.
public struct InkMenuView: View {
    let entries: [InkMenuEntry]
    let cursor: Int?
    let minWidth: CGFloat
    let maxItems: Int?
    let scroll: CGFloat

    public init(entries: [InkMenuEntry], cursor: Int?, minWidth: CGFloat = 0, maxItems: Int? = nil, scroll: CGFloat = 0) {
        self.entries = entries
        self.cursor = cursor
        self.minWidth = minWidth
        self.maxItems = maxItems
        self.scroll = scroll
    }

    public var body: some View {
        let hasChecks = entries.contains { $0.item?.checked != nil }
        let viewport = InkMenuMetrics.viewportHeight(entries, maxItems: maxItems)
        let full = InkMenuMetrics.contentHeight(entries)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries.indices, id: \.self) { index in
                line(entries[index], isCursor: cursor == index, hasChecks: hasChecks)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: max(minWidth, InkMenuMetrics.minWidth), alignment: .leading)
        .offset(y: -scroll)
        .frame(height: viewport, alignment: .top)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if full > viewport {
                // A thin bar where the visible part of a long list sits.
                Rectangle().fill(.inkFaint)
                    .frame(width: 3, height: max(viewport * viewport / full, 16))
                    .offset(x: -3, y: (viewport - max(viewport * viewport / full, 16)) * scroll / (full - viewport))
            }
        }
        .padding(.vertical, InkMenuMetrics.padding)
        .fixedSize()
        .floatingFrame()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func line(_ entry: InkMenuEntry, isCursor: Bool, hasChecks: Bool) -> some View {
        switch entry {
        case .divider:
            Rectangle().fill(.shade).frame(height: Metrics.line)
                .padding(.vertical, Metrics.spaceXs)
                .frame(height: InkMenuMetrics.dividerHeight)
        case .section(let title):
            Text(title)
                .textStyle(.cell)
                .fontWeight(.semibold)
                .foregroundStyle(.inkSoft)
                .lineLimit(1)
                .padding(.leading, Metrics.spaceS + Metrics.spaceXs)
                .padding(.trailing, Metrics.spaceL)
                .padding(.top, Metrics.spaceS)
                .padding(.bottom, Metrics.spaceXxs)
                .frame(height: InkMenuMetrics.sectionHeight, alignment: .bottomLeading)
        case .item(let item):
            row(item, isCursor: isCursor && item.isPickable, hasChecks: hasChecks)
        }
    }

    private func row(_ item: InkMenuItem, isCursor: Bool, hasChecks: Bool) -> some View {
        let text: Color = isCursor ? .onInk : !item.isEnabled ? .inkFaint : item.isDanger ? .danger : .ink
        let soft: Color = isCursor ? .onInk : !item.isEnabled ? .inkFaint : .inkSoft
        return HStack(spacing: Metrics.spaceM) {
            if hasChecks {
                // The column keeps its width on unticked lines, so every title starts at the same place.
                Color.clear
                    .frame(width: 12, height: 12)
                    .overlay { if item.checked == true { Glyph(.check, size: 11, weight: Metrics.lineBox) } }
            }
            if let swatch = item.swatch {
                Mark(swatch.color, size: 10, shape: swatch.shape)
                    .opacity(item.isEnabled ? 1 : 0.5)
            }
            // Both at their full width: the menu sizes to its widest line, and a shortcut must
            // never be cut to "⌥…" by a rounding of that width.
            Text(item.title).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            if let detail = item.detail {
                Text(detail)
                    .monospacedDigit()
                    .fixedSize()
                    .foregroundStyle(soft)
                    .padding(.leading, Metrics.spaceXxl)
            }
            if item.submenu != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.leading, Metrics.spaceXxl)
            }
        }
        .textStyle(.body)
        .foregroundStyle(text)
        .padding(.leading, Metrics.spaceS + Metrics.spaceXs)
        .padding(.trailing, Metrics.spaceL)
        .frame(height: InkMenuMetrics.itemHeight)
        .background(isCursor ? (item.isDanger ? Color.danger : Tokens.selection) : Color.clear)
    }
}
