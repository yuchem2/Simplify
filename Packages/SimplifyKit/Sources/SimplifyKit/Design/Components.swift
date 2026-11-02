import SwiftUI

// The drawn look: crisp ink outlines, an inner moulding line, a flat offset shadow.

public extension View {
    /// Paper with a heavy outline, an optional inner moulding line, and the drawn shadow.
    /// Over a dimmed window pass a darker `shadow`, since the usual shade is lighter than the dim.
    func mouldedFrame(moulding: Bool = true, shadow: Color = Tokens.shadowDrawn) -> some View {
        background(.paper)
            .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.lineOuter))
            .overlay {
                if moulding {
                    Rectangle().inset(by: Metrics.mouldingInset).strokeBorder(.ink, lineWidth: Metrics.line)
                }
            }
            .drawnShadow(shadow)
    }

    /// A flat shade offset down and right, with no blur.
    func drawnShadow(_ color: Color = Tokens.shadowDrawn) -> some View {
        background(Rectangle().fill(color).offset(x: 5, y: 5))
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
                    .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Color.onInk : disabled.contains(option.value) ? Color.inkFaint : Color.ink)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: fills ? .infinity : nil)
                    .frame(height: 28)
                    .background(isOn ? Color.ink : Color.paper)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled.contains(option.value))
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityValue(marked.contains(option.value) ? Text("메모 있음") : Text(verbatim: ""))
            }
        }
        .fixedSize(horizontal: !fills, vertical: true)
        .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
    }
}

/// Buttons drawn as outlined boxes; `.primary` is filled with ink (one per screen), `.toggled` is a
/// plain button shown switched on, `.text` is an underlined word.
public struct DrawnButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case plain, primary, toggled, text }
    var kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    public init(_ kind: Kind = .plain) { self.kind = kind }

    public func makeBody(configuration: Configuration) -> some View {
        switch kind {
        case .text:
            configuration.label
                .font(.system(size: 12))
                .underline()
                .foregroundStyle(isEnabled ? Color.ink : Color.inkFaint)
                .opacity(configuration.isPressed ? 0.6 : 1)
                // A taller target around the small word without changing the layout.
                .contentShape(Rectangle().inset(by: -4))
        case .plain, .primary, .toggled:
            configuration.label
                .font(.system(size: 13, weight: kind == .primary ? .semibold : .regular))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .frame(minWidth: 28, minHeight: 28)
                .background(background(pressed: configuration.isPressed))
                .overlay(Rectangle().strokeBorder(isEnabled ? Color.ink : Color.inkFaint, lineWidth: Metrics.line))
                .contentShape(Rectangle())
        }
    }

    private var foreground: Color {
        guard isEnabled else { return .inkFaint }
        return kind == .primary ? .onInk : .ink
    }

    private func background(pressed: Bool) -> Color {
        if kind == .primary && isEnabled { return .ink }
        if kind == .toggled { return pressed ? .shade : .shadeSoft }
        return pressed ? .shadeSoft : .paper
    }
}

/// A 16 pt square: empty when off, filled with ink and a check when on.
public struct DrawnCheckboxStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                ZStack {
                    Rectangle().fill(configuration.isOn ? Color.ink : Color.paper)
                    Rectangle().strokeBorder(.ink, lineWidth: 1.5)
                    if configuration.isOn {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.onInk)
                    }
                }
                .frame(width: 16, height: 16)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "완료" : "미완료")
    }
}

/// A small square in a calendar's or label's colour, outlined in ink. `nil` draws an empty box.
public struct Mark: View {
    var color: Color?
    var size: CGFloat

    public init(_ color: Color?, size: CGFloat = 10) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        Rectangle()
            .fill(color ?? .clear)
            // A thinner edge on small marks leaves more of the colour showing.
            .overlay(Rectangle().strokeBorder(.ink, lineWidth: size <= 9 ? Metrics.line : 1.2))
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
                Circle().strokeBorder(tint, lineWidth: size <= 9 ? 1.4 : 1.6)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A small pencil: this day, week or month has a memo.
public struct MemoMark: View {
    var color: Color

    public init(color: Color = .inkSoft) {
        self.color = color
    }

    public var body: some View {
        Image(systemName: "pencil")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// A panel section name followed by a rule that runs to the trailing edge.
public struct SectionRule<Trailing: View>: View {
    var title: String
    var trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.7)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(.ink).frame(height: Metrics.line)
            trailing
        }
    }
}
