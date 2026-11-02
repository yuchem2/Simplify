import SwiftUI
#if os(macOS)
import AppKit
#endif

// The ink ledger: one sheet of paper, hairline edges, a single heavy spine, and nothing that casts a
// shadow except what floats above the paper. Every control answers the pointer (hover) and the
// keyboard (a paper gap, then an ink ring).

/// `isFocused` in a button style also answers for a focused container around the button (a page or
/// grid that takes the keys). A button only takes focus itself with full keyboard access on, so only
/// then is the ring its own.
@MainActor func ownsFocus(_ isFocused: Bool) -> Bool {
    #if os(macOS)
    isFocused && NSApplication.shared.isFullKeyboardAccessEnabled
    #else
    isFocused
    #endif
}

public extension View {
    /// The font of a step on the type scale.
    func textStyle(_ style: TextStyle) -> some View {
        font(style.font)
    }

    /// The main paper: no outline of its own, just a hairline where it meets the wall.
    func paperSheet() -> some View {
        background(.paper)
            .overlay(Rectangle().strokeBorder(.shade, lineWidth: Metrics.line))
    }

    /// What floats above the paper (popovers, menus, the settings modal): paper, an ink hairline and
    /// a flat offset shadow. Over a dimmed window pass a darker `shadow`, since the usual one is lighter than the dim.
    func floatingFrame(shadow: Color = Tokens.shadowFloat) -> some View {
        background(.paper)
            .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
            .background(Rectangle().fill(shadow).offset(x: Metrics.shadowOffset, y: Metrics.shadowOffset))
    }

    /// The keyboard focus mark: a paper gap, then an ink ring, outside the view's bounds.
    func focusRing(_ isShown: Bool) -> some View {
        overlay {
            if isShown {
                Rectangle()
                    .strokeBorder(.paper, lineWidth: Metrics.focusGap)
                    .overlay(Rectangle().inset(by: -Metrics.focusRing).strokeBorder(Tokens.focusRing, lineWidth: Metrics.focusRing))
                    .padding(-Metrics.focusGap)
                    .allowsHitTesting(false)
            }
        }
    }

    /// A list row that answers the pointer and shows how it is picked: ink when chosen from many,
    /// grey while it is being edited or its menu is open, a quiet step off the paper under the pointer.
    /// Text on a chosen row should be `onInk`; read `isChosen` where the row draws it.
    func selectableRow(chosen: Bool, active: Bool = false, inset: CGFloat = Metrics.spaceXs) -> some View {
        modifier(SelectableRow(chosen: chosen, active: active, inset: inset))
    }
}

private struct SelectableRow: ViewModifier {
    var chosen: Bool
    var active: Bool
    var inset: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, inset)
            .background(fill)
            .padding(.horizontal, -inset)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: Metrics.motionQuick), value: hovering)
    }

    private var fill: Color {
        if chosen { return Tokens.selection }
        if active { return .rowActive }
        return hovering ? .hover : .clear
    }
}

/// Square segments joined by ink lines; the chosen one is filled with ink.
public struct SegmentedTabs<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var disabled: Set<Value> = []
    /// Segments that get a `MemoMark` after their label.
    var marked: Set<Value> = []
    var fills = false

    public init(_ options: [(value: Value, label: String)], selection: Binding<Value>, disabled: Set<Value> = [], marked: Set<Value> = [], fillsWidth: Bool = false) {
        self.options = options
        _selection = selection
        self.disabled = disabled
        self.marked = marked
        fills = fillsWidth
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 { Rectangle().fill(.ink).frame(width: Metrics.line) }
                let isOn = option.value == selection
                Button { selection = option.value } label: {
                    HStack(spacing: 5) {
                        Text(option.label)
                        if marked.contains(option.value) { MemoMark(color: isOn ? .onInk : .inkSoft) }
                    }
                }
                .buttonStyle(SegmentStyle(isOn: isOn, fills: fills))
                .disabled(disabled.contains(option.value))
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityValue(marked.contains(option.value) ? Text("메모 있음") : Text(verbatim: ""))
            }
        }
        .fixedSize(horizontal: !fills, vertical: true)
        .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
    }
}

private struct SegmentStyle: ButtonStyle {
    var isOn: Bool
    var fills: Bool

    func makeBody(configuration: Configuration) -> some View {
        SegmentBody(configuration: configuration, isOn: isOn, fills: fills)
    }

    private struct SegmentBody: View {
        let configuration: Configuration
        var isOn: Bool
        var fills: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            configuration.label
                .textStyle(.body)
                .fontWeight(isOn ? .semibold : .regular)
                .foregroundStyle(isOn ? Color.onInk : isEnabled ? Color.ink : Color.inkFaint)
                .padding(.horizontal, Metrics.spaceL)
                .frame(maxWidth: fills ? .infinity : nil)
                .frame(height: 28)
                .background(isOn ? Tokens.selection : (hovering || configuration.isPressed) && isEnabled ? Color.hover : Color.paper)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .focusRing(ownsFocus(isFocused))
                .zIndex(ownsFocus(isFocused) ? 1 : 0)
        }
    }
}

/// Buttons drawn as outlined boxes. `.primary` is filled with ink (one per screen), `.toggled` is a
/// plain button shown switched on, `.text` is an underlined word. `.danger` and `.dangerText` (a red
/// underlined word) do what cannot be undone: delete, drop edits, disconnect.
public struct DrawnButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case plain, primary, toggled, text, dangerText, danger, icon }
    var kind: Kind

    public init(_ kind: Kind = .plain) { self.kind = kind }

    public func makeBody(configuration: Configuration) -> some View {
        DrawnButtonBody(configuration: configuration, kind: kind)
    }
}

private struct DrawnButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: DrawnButtonStyle.Kind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var hovering = false

    var body: some View {
        Group {
            switch kind {
            case .text, .dangerText:
                configuration.label
                    .textStyle(.small)
                    .underline()
                    .foregroundStyle(!isEnabled ? Color.inkFaint : kind == .dangerText ? Color.danger : Color.ink)
                    .padding(.horizontal, Metrics.spaceXxs)
                    .background(hovering && isEnabled ? Color.hover : Color.clear)
                    .opacity(configuration.isPressed ? 0.6 : 1)
                    // A taller target around the small word without changing the layout.
                    .contentShape(Rectangle().inset(by: -4))
            case .icon:
                // A bare glyph (×, ‹ ›) in a 28 pt square: no outline, hover fill only.
                configuration.label
                    .foregroundStyle(isEnabled ? Color.ink : Color.inkFaint)
                    .frame(width: 28, height: 28)
                    .background(configuration.isPressed ? Color.rowActive : hovering && isEnabled ? Color.hover : Color.clear)
                    .contentShape(Rectangle())
            case .plain, .primary, .toggled, .danger:
                configuration.label
                    .textStyle(.body)
                    .fontWeight(kind == .primary ? .semibold : .regular)
                    .foregroundStyle(foreground)
                    .padding(.horizontal, Metrics.spaceL)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(background(pressed: configuration.isPressed))
                    // Switched on reads by its heavier edge as well as its fill, so it never looks like hover.
                    .overlay(Rectangle().strokeBorder(outline, lineWidth: kind == .toggled && isEnabled ? Metrics.lineBox : Metrics.line))
                    .contentShape(Rectangle())
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Metrics.motionQuick), value: hovering)
        .focusRing(ownsFocus(isFocused))
        .zIndex(ownsFocus(isFocused) ? 1 : 0)
    }

    private var foreground: Color {
        guard isEnabled else { return .inkFaint }
        switch kind {
        case .primary: return .onInk
        case .danger: return .danger
        default: return .ink
        }
    }

    private var outline: Color {
        guard isEnabled else { return .inkFaint }
        return kind == .danger ? .danger : .ink
    }

    private func background(pressed: Bool) -> Color {
        if kind == .primary && isEnabled { return pressed || hovering ? Color.ink.opacity(Metrics.opacityPrimaryHover) : .ink }
        guard isEnabled else { return .paper }
        if kind == .toggled { return .rowActive }
        if pressed { return .rowActive }
        return hovering ? .hover : .paper
    }
}

/// A square box, empty when off and filled with ink and a check when on. 16 pt in lists, smaller in
/// pickers and memos. The one checkbox drawing in the app: ToDos, settings and the event editor.
public struct CheckBox: View {
    var isOn: Bool
    var size: CGFloat
    /// Pointer over it: the empty box takes the hover fill.
    var isHovered: Bool
    /// On a chosen (ink) row: drawn in on-ink so it still reads.
    var onInk: Bool

    public init(isOn: Bool, size: CGFloat = 16, isHovered: Bool = false, onInk: Bool = false) {
        self.isOn = isOn
        self.size = size
        self.isHovered = isHovered
        self.onInk = onInk
    }

    public var body: some View {
        let line: Color = onInk ? .onInk : .ink
        ZStack {
            Rectangle().fill(isOn ? line : onInk ? Color.clear : isHovered ? Color.hover : Color.paper)
            Rectangle().strokeBorder(line, lineWidth: size < 14 ? Metrics.lineMark : Metrics.lineBox)
            if isOn {
                Glyph(.check, size: size * 0.62, weight: size < 14 ? Metrics.lineBox : 1.8)
                    .foregroundStyle(onInk ? Color.ink : Color.onInk)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A button drawn as a `CheckBox`; its label is not shown, so pass `EmptyView()` and name it for VoiceOver.
/// Hover fills the empty box, focus rings it.
public struct CheckBoxButtonStyle: ButtonStyle {
    var isOn: Bool
    var size: CGFloat
    var onInk: Bool

    public init(isOn: Bool, size: CGFloat = 16, onInk: Bool = false) {
        self.isOn = isOn
        self.size = size
        self.onInk = onInk
    }

    public func makeBody(configuration: Configuration) -> some View {
        CheckBoxButtonBody(isOn: isOn, size: size, onInk: onInk, isPressed: configuration.isPressed)
    }

    private struct CheckBoxButtonBody: View {
        var isOn: Bool
        var size: CGFloat
        var onInk: Bool
        var isPressed: Bool
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            CheckBox(isOn: isOn, size: size, isHovered: hovering, onInk: onInk)
                .opacity(isPressed ? 0.7 : 1)
                .focusRing(ownsFocus(isFocused))
                .padding(3)
                .contentShape(Rectangle())
                .padding(-3)
                .onHover { hovering = $0 }
        }
    }
}

/// A toggle drawn as a `CheckBox` before its label.
public struct DrawnCheckboxStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        CheckboxToggle(configuration: configuration)
    }

    private struct CheckboxToggle: View {
        let configuration: ToggleStyleConfiguration
        @State private var hovering = false

        var body: some View {
            Button { configuration.isOn.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceM) {
                    CheckBox(isOn: configuration.isOn, isHovered: hovering)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                    configuration.label
                }
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
            }
            .buttonStyle(FocusOnlyStyle())
            .accessibilityValue(configuration.isOn ? "완료" : "미완료")
        }
    }
}

/// A plain button that only adds the focus ring. For rows and labels that draw their own look.
public struct FocusOnlyStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        FocusOnlyBody(configuration: configuration)
    }

    private struct FocusOnlyBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.7 : 1)
                .focusRing(ownsFocus(isFocused))
        }
    }
}

/// How a text field is drawn: `.box` in forms, `.inline` inside a list row, `.title` for the big name
/// at the top of an editor.
public enum FieldKind: Sendable { case box, inline, title }

public extension View {
    /// The one input look. Put it on a `.plain` TextField; pass whether it has keyboard focus and
    /// whether its value is wrong. Disabled comes from the environment.
    func drawnField(_ kind: FieldKind = .box, focused: Bool, error: Bool = false) -> some View {
        modifier(DrawnField(kind: kind, focused: focused, error: error))
    }
}

private struct DrawnField: ViewModifier {
    var kind: FieldKind
    var focused: Bool
    var error: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        switch kind {
        case .box:
            content
                .textFieldStyle(.plain)
                .textStyle(.body)
                .foregroundStyle(isEnabled ? Color.ink : Color.inkFaint)
                .padding(.horizontal, Metrics.spaceM)
                .frame(minHeight: 28)
                .background(error ? Color.errorTint : !isEnabled ? Color.shadeSoft : hovering && !focused ? Color.hover : Color.paper)
                .overlay(Rectangle().strokeBorder(isEnabled ? Color.ink : Color.inkFaint, lineWidth: error ? Metrics.lineBox : Metrics.line))
                .focusRing(focused)
                .onHover { hovering = $0 }
        case .inline:
            content
                .textFieldStyle(.plain)
                .foregroundStyle(isEnabled ? Color.ink : Color.inkFaint)
                .padding(.horizontal, Metrics.spaceXs)
                .background(error ? Color.errorTint : focused ? Color.rowActive : hovering ? Color.hover : Color.clear)
                .overlay(alignment: .bottom) {
                    if focused { Rectangle().fill(.ink).frame(height: Metrics.line) }
                }
                .onHover { hovering = $0 }
        case .title:
            content
                .textFieldStyle(.plain)
                .textStyle(.subheading)
                .foregroundStyle(isEnabled ? Color.ink : Color.inkFaint)
                .padding(.bottom, Metrics.spaceXs)
                .background(error ? Color.errorTint : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(focused || error ? Color.ink : hovering ? Color.inkFaint : Color.shade)
                        .frame(height: focused ? Metrics.lineBox : Metrics.line)
                }
                .onHover { hovering = $0 }
        }
    }
}

/// A short word in an ink box: 오늘, 읽기 전용. A warning (다시 연결 필요) passes `fill: .errorTint`.
public struct Tag: View {
    var text: String
    var color: Color
    var fill: Color

    public init(_ text: String, color: Color = .ink, fill: Color = .clear) {
        self.text = text
        self.color = color
        self.fill = fill
    }

    public var body: some View {
        Text(text)
            .textStyle(.meta)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, Metrics.spaceS)
            .padding(.vertical, 1)
            .background(fill)
            .overlay(Rectangle().strokeBorder(color, lineWidth: Metrics.line))
            .fixedSize()
    }
}

/// A notice across the top of a panel or popover. `.warning` is for something that went wrong:
/// the error tint and a warning sign, never red.
public struct NoticeBar: View {
    public enum Tone: Sendable { case info, warning }
    var title: String?
    var message: String
    var tone: Tone
    var icon: String?

    public init(_ message: String, title: String? = nil, tone: Tone = .warning, icon: String? = nil) {
        self.title = title
        self.message = message
        self.tone = tone
        self.icon = icon
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceM) {
            Image(systemName: icon ?? (tone == .warning ? "exclamationmark.triangle" : "info.circle"))
                .textStyle(.small)
                .accessibilityHidden(true)
            Text("\(Text(title.map { $0 + " " } ?? "").fontWeight(.semibold))\(message)")
                .textStyle(.small)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Tokens.error)
        .padding(.horizontal, Metrics.spaceM)
        .padding(.vertical, Metrics.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone == .warning ? Color.errorTint : Color.raised)
        .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
        .accessibilityElement(children: .combine)
    }
}

/// A small square in a calendar's or label's colour, outlined in ink. `nil` draws an empty box.
/// Widgets pass `outlined: false`: there the colour stands alone.
public struct Mark: View {
    var color: Color?
    var size: CGFloat
    var outlined: Bool

    public init(_ color: Color?, size: CGFloat = 10, outlined: Bool = true) {
        self.color = color
        self.size = size
        self.outlined = outlined
    }

    public var body: some View {
        Rectangle()
            .fill(color ?? .clear)
            // A thinner edge on small marks leaves more of the colour showing.
            .overlay { if outlined { Rectangle().strokeBorder(.ink, lineWidth: size <= 9 ? Metrics.line : Metrics.lineMark) } }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The mark of a reminder: a ring in its list's colour, filled and ticked once completed. Round
/// where event marks are square, so reminders read apart from events at a glance.
public struct ReminderMark: View {
    var color: Color?
    var size: CGFloat
    var isCompleted: Bool

    public init(_ color: Color?, size: CGFloat = 10, isCompleted: Bool = false) {
        self.color = color
        self.size = size
        self.isCompleted = isCompleted
    }

    public var body: some View {
        let tint = color ?? .ink
        ZStack {
            if isCompleted {
                Circle().fill(tint)
                Path { path in
                    path.move(to: CGPoint(x: size * 0.28, y: size * 0.52))
                    path.addLine(to: CGPoint(x: size * 0.44, y: size * 0.68))
                    path.addLine(to: CGPoint(x: size * 0.72, y: size * 0.34))
                }
                .stroke(.onInk, style: StrokeStyle(lineWidth: max(1, size * 0.14), lineCap: .round, lineJoin: .round))
            } else {
                Circle().strokeBorder(tint, lineWidth: size <= 9 ? 1.4 : Metrics.lineBox)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Unfinished ToDos left on a day: a small check mark and the count, beside the date.
public struct TodoCount: View {
    var count: Int

    public init(_ count: Int) {
        self.count = count
    }

    public var body: some View {
        HStack(spacing: 2) {
            Glyph(.check, size: 9, weight: Metrics.lineBox)
            Text("\(count)").textStyle(.meta)
        }
        .foregroundStyle(.inkSoft)
        // Never squeezed: the date and weekday beside it give way first.
        .fixedSize()
        .layoutPriority(1)
        .accessibilityHidden(true)
    }
}

/// The app's own small glyphs, drawn with the same crisp ink lines as everything else (SF Symbols
/// read heavier and rounder than the ledger). Coloured by the foreground style.
public struct Glyph: View {
    public enum Kind: Sendable { case pencil, check }
    var kind: Kind
    var size: CGFloat
    var weight: CGFloat

    public init(_ kind: Kind, size: CGFloat = 12, weight: CGFloat = Metrics.lineMark) {
        self.kind = kind
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        GlyphShape(kind: kind)
            .stroke(style: StrokeStyle(lineWidth: weight, lineCap: kind == .check ? .square : .butt, lineJoin: .miter))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// Drawn on a 12 × 12 grid and scaled to the frame.
    private struct GlyphShape: Shape {
        var kind: Kind

        func path(in rect: CGRect) -> Path {
            let u = rect.width / 12
            let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: rect.minX + x * u, y: rect.minY + y * u) }
            var path = Path()
            switch kind {
            case .pencil:
                // A straight pencil from bottom left to top right, with the line where the tip begins.
                path.addLines([p(2, 10), p(2.6, 7.4), p(8.4, 1.6), p(10.4, 3.6), p(4.6, 9.4)])
                path.closeSubpath()
                path.move(to: p(2.6, 7.4))
                path.addLine(to: p(4.6, 9.4))
            case .check:
                path.addLines([p(2, 6.4), p(4.8, 9.2), p(10, 3.2)])
            }
            return path
        }
    }
}

/// A small pencil: this day, week or month has a memo.
public struct MemoMark: View {
    var color: Color

    public init(color: Color = .inkSoft) {
        self.color = color
    }

    public var body: some View {
        Glyph(.pencil, size: 11)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// A section name followed by an ink rule that runs to the trailing edge.
public struct SectionRule<Trailing: View>: View {
    var title: String
    var trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Metrics.spaceM) {
            Text(title)
                .textStyle(.section)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(.ink).frame(height: Metrics.line)
            trailing
        }
    }
}

/// The day strip: 9 to 24 o'clock on one line, events as blocks in their calendar's tint with an
/// ink edge and a stripe of their colour, reminders as rings, and an ink line at the current time.
/// It shows at a glance where the free hours are.
public struct DayStrip: View {
    public struct Item: Identifiable, Sendable {
        public var id: String
        /// Minutes after midnight.
        public var start: Int
        public var end: Int
        public var palette: Palette
        public var isReminder: Bool

        public init(id: String, start: Int, end: Int, palette: Palette, isReminder: Bool = false) {
            self.id = id
            self.start = start
            self.end = end
            self.palette = palette
            self.isReminder = isReminder
        }
    }

    public static let hours = 9...24
    var items: [Item]
    /// Minutes after midnight; nil on days other than today.
    var now: Int?
    var height: CGFloat
    var showsLabels: Bool

    public init(items: [Item], now: Int?, height: CGFloat = 34, showsLabels: Bool = true) {
        self.items = items
        self.now = now
        self.height = height
        self.showsLabels = showsLabels
    }

    public var body: some View {
        VStack(spacing: Metrics.spaceXs) {
            Canvas { context, size in
                let first = CGFloat(Self.hours.lowerBound * 60), last = CGFloat(Self.hours.upperBound * 60)
                let x = { (minutes: Int) in (CGFloat(minutes) - first) / (last - first) * size.width }
                let mid = size.height / 2
                context.fill(Path(CGRect(x: 0, y: mid - 1, width: size.width, height: 2)), with: .color(.shade))
                for item in shown {
                    let start = max(x(item.start), 0)
                    if item.isReminder {
                        let ring = CGRect(x: min(max(x(item.start) - 4.5, 0), size.width - 9), y: mid - 4.5, width: 9, height: 9)
                        context.fill(Path(ellipseIn: ring), with: .color(.paper))
                        context.stroke(Path(ellipseIn: ring.insetBy(dx: 0.75, dy: 0.75)), with: .color(item.palette.ink), lineWidth: Metrics.lineBox)
                    } else {
                        let width = max(min(x(item.end), size.width) - start, 6)
                        let block = CGRect(x: min(start, size.width - width), y: mid - 9, width: width, height: 18)
                        context.fill(Path(block), with: .color(item.palette.tint))
                        context.stroke(Path(block.insetBy(dx: 0.5, dy: 0.5)), with: .color(.ink), lineWidth: Metrics.line)
                        context.fill(Path(CGRect(x: block.minX, y: mid - 9, width: 3, height: 18)), with: .color(item.palette.ink))
                    }
                }
                if let now, now >= Int(first), now <= Int(last) {
                    context.fill(Path(CGRect(x: x(now) - 1, y: 0, width: 2, height: size.height)), with: .color(Tokens.now))
                }
            }
            .frame(height: height)
            if showsLabels {
                // Each hour's label centred on its place on the line; the two ends hug the edges.
                GeometryReader { geo in
                    let span = CGFloat(Self.hours.upperBound - Self.hours.lowerBound)
                    ForEach(Array(stride(from: Self.hours.lowerBound, through: Self.hours.upperBound, by: 3)), id: \.self) { hour in
                        let fraction = CGFloat(hour - Self.hours.lowerBound) / span
                        Text("\(hour)시")
                            .fixedSize()
                            .frame(width: 40, alignment: fraction == 0 ? .leading : fraction == 1 ? .trailing : .center)
                            .position(x: min(max(fraction * geo.size.width, 20), geo.size.width - 20), y: geo.size.height / 2)
                    }
                }
                .frame(height: TextStyle.meta.lineHeight)
                .textStyle(.meta)
                .foregroundStyle(.inkSoft)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Events that touch 9–24 o'clock; a reminder only when it falls inside, so none is drawn at the wrong hour.
    private var shown: [Item] {
        let first = Self.hours.lowerBound * 60, last = Self.hours.upperBound * 60
        return items.filter { $0.isReminder ? $0.start >= first && $0.start <= last : $0.end > first && $0.start < last }
    }

    private var accessibilityText: String {
        let busy = shown.filter { !$0.isReminder }.count
        let reminders = shown.count - busy
        var text = "9시부터 24시까지 일정 \(busy)개"
        if reminders > 0 { text += ", 미리알림 \(reminders)개" }
        return text
    }
}

public extension View {
    /// The desktop widget's surface (C · lights off): no outline, a tone step off the desktop and a
    /// rounded mask. Widgets that use the system container background pass this colour there instead.
    func widgetSurface() -> some View {
        background(.widgetSurface, in: RoundedRectangle(cornerRadius: Metrics.radiusWidget, style: .continuous))
    }
}

/// The small widget's date: a filled oval in the nest tone with today's number in the display face.
public struct DateOval: View {
    var day: Int

    public init(day: Int) {
        self.day = day
    }

    public var body: some View {
        ZStack {
            Ellipse().fill(.widgetNest).frame(width: 76, height: 62)
            Text("\(day)").textStyle(.bigDate)
        }
        .frame(width: 84, height: 72)
    }
}

public extension View {
    /// A strikethrough through the middle of Hangul. The system line sits at half the Latin
    /// x-height, which runs through the lower part of Korean letters; this one sits at half the
    /// cap height, through the middle of both. Put it on a Text, with the colour the text is drawn in.
    func ledgerStrikethrough(_ isOn: Bool, color: Color) -> some View {
        textRenderer(LedgerStrikethrough(isOn: isOn, color: color))
    }
}

private struct LedgerStrikethrough: TextRenderer {
    var isOn: Bool
    var color: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            context.draw(line)
            guard isOn else { continue }
            for run in line {
                let bounds = run.typographicBounds
                // Cap height is about 0.73 of the ascent in SF Pro and Apple SD Gothic Neo; half of it.
                let y = bounds.origin.y - bounds.ascent * 0.365
                context.fill(Path(CGRect(x: bounds.rect.minX, y: y - Metrics.line / 2, width: bounds.width, height: Metrics.line)), with: .color(color))
            }
        }
    }
}
