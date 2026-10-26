import SwiftUI
import SimplifyKit

/// The month as a ruled grid on a moulded sheet, Monday first.
struct MonthSheet: View {
    let model: AppModel
    /// The sheet holds keyboard focus so the arrow keys move the chosen day.
    @FocusState private var focused: Bool

    private static let weekdays = ["월", "화", "수", "목", "금", "토", "일"]
    /// Smallest day cell; with six rows this sets the sheet's (and the window's) minimum size.
    static let minCellSize = CGSize(width: 100, height: 80)
    /// Where a date number starts inside its cell; the weekday labels share the same edge.
    static let dateInset = EdgeInsets(top: 8, leading: 14, bottom: 4, trailing: 7)

    var body: some View {
        let grid = model.grid
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(name == "일" ? Color.holiday : Color.inkSoft)
                        .padding(.leading, Self.dateInset.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GeometryReader { geo in
                let width = geo.size.width / 7
                let height = geo.size.height / CGFloat(grid.weeks.count)
                VStack(spacing: 0) {
                    ForEach(grid.weeks, id: \.first) { week in
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { day in
                                DayCell(day: day, model: model, inMonth: grid.isInMonth(day)) {
                                    model.select(day)
                                    focused = true
                                }
                                .frame(width: width, height: height)
                            }
                        }
                    }
                }
                .overlay { GridLines(columns: 7, rows: grid.weeks.count).stroke(.ink, lineWidth: Metrics.line) }
            }
            .frame(minWidth: Self.minCellSize.width * 7, minHeight: Self.minCellSize.height * 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .mouldedFrame()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            // Arrow events carry the numeric-pad and function flags, and Caps Lock may be on,
            // so only real modifiers count. ⌘← / ⌘→ belong to the 이동 menu.
            guard press.modifiers.isDisjoint(with: [.command, .option, .control, .shift]) else { return .ignored }
            switch press.key {
            case .leftArrow: model.moveSelection(byDays: -1)
            case .rightArrow: model.moveSelection(byDays: 1)
            case .upArrow: model.moveSelection(byDays: -7)
            default: model.moveSelection(byDays: 7)
            }
            return .handled
        }
    }
}

/// Every row and column edge of an evenly divided rectangle.
private struct GridLines: Shape {
    var columns: Int
    var rows: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for c in 0...columns {
            let x = rect.minX + rect.width * CGFloat(c) / CGFloat(columns)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for r in 0...rows {
            let y = rect.minY + rect.height * CGFloat(r) / CGFloat(rows)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private struct DayCell: View {
    let day: Date
    let model: AppModel
    let inMonth: Bool
    let onSelect: () -> Void

    var body: some View {
        let isToday = model.isToday(day)
        let number = model.calendar.component(.day, from: day)
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3) {
                // Numbers start on the same line as the weekday labels; today's disc grows
                // around its number without moving it.
                Text("\(number)")
                    .font(.display(16))
                    .foregroundStyle(numberColor(isToday: isToday))
                    .padding(.horizontal, isToday ? 4 : 0)
                    .frame(minWidth: isToday ? 24 : nil, minHeight: 24)
                    .background { if isToday { Capsule().fill(.ink) } }
                    // The disc's left edge sits 4 pt before the date line, well inside the selection.
                    .padding(.leading, isToday ? -4 : 0)
                // Events and the ToDo count fill in here from stage 2 on.
            }
            .padding(MonthSheet.dateInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // The selection moulding sits behind the date so today's disc stays whole.
            .background {
                if model.isSelected(day) {
                    Rectangle().inset(by: 4).strokeBorder(.ink, lineWidth: Metrics.line)
                }
            }
            .background(inMonth ? Color.clear : Color.shadeSoft)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Period(containing: day, scope: .day, calendar: model.calendar).title + (isToday ? ", 오늘" : ""))
        .accessibilityAddTraits(model.isSelected(day) ? .isSelected : [])
    }

    private func numberColor(isToday: Bool) -> Color {
        if isToday { return .onInk }
        if !inMonth { return .inkFaint }
        return model.isRedDay(day) ? .holiday : .ink
    }
}
