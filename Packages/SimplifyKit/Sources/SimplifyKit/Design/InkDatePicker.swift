import SwiftUI

/// What the date picker's keys do to the picked day, apart from the view.
public enum DatePickerKeys {
    public enum Key: Sendable { case previousDay, nextDay, previousWeek, nextWeek, previousMonth, nextMonth, today }

    /// The day `key` moves `day` to. A month on keeps the day of the month where it can
    /// (31 January → 28 February).
    public static func move(_ day: Date, _ key: Key, today: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        let moved: Date? = switch key {
        case .previousDay: calendar.date(byAdding: .day, value: -1, to: start)
        case .nextDay: calendar.date(byAdding: .day, value: 1, to: start)
        case .previousWeek: calendar.date(byAdding: .day, value: -7, to: start)
        case .nextWeek: calendar.date(byAdding: .day, value: 7, to: start)
        case .previousMonth: calendar.date(byAdding: .month, value: -1, to: start)
        case .nextMonth: calendar.date(byAdding: .month, value: 1, to: start)
        case .today: calendar.startOfDay(for: today)
        }
        return moved ?? start
    }
}

/// A small ledger month to pick a day from, drawn like the main calendar: an ink rule under the
/// weekday letters, a hairline under each week, today under a short ink bar, Sundays and holidays
/// red, the picked day filled with ink. It follows the calendar's first weekday.
///
/// Keys: arrows move a day or a week, Page Up and Page Down a month, T goes to today, Return
/// calls `onCommit`. A click picks the day, and with `commitsOnClick` calls `onCommit` too.
public struct InkDatePicker: View {
    @Binding var selection: Date
    let calendar: Calendar
    let today: Date
    let isHoliday: (Date) -> Bool
    let takesFocus: Bool
    let commitsOnClick: Bool
    let onCommit: (() -> Void)?
    @State private var shown: Date
    @FocusState private var focused: Bool

    private static let cell = CGSize(width: 32, height: 28)

    public init(selection: Binding<Date>, calendar: Calendar, today: Date = .now, takesFocus: Bool = true, commitsOnClick: Bool = true,
                isHoliday: @escaping (Date) -> Bool = { _ in false }, onCommit: (() -> Void)? = nil) {
        self.commitsOnClick = commitsOnClick
        _selection = selection
        self.calendar = calendar
        self.today = today
        self.takesFocus = takesFocus
        self.isHoliday = isHoliday
        self.onCommit = onCommit
        _shown = State(initialValue: selection.wrappedValue)
    }

    public var body: some View {
        let grid = MonthGrid(month: shown, calendar: calendar)
        VStack(alignment: .leading, spacing: Metrics.spaceS) {
            header(grid.month)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(calendar.weekdaysInOrder, id: \.self) { weekday in
                        Text(Calendar.weekdayName(weekday))
                            .textStyle(.meta)
                            .foregroundStyle(weekday == 1 ? Color.holiday : Color.inkSoft)
                            .frame(width: Self.cell.width)
                            .padding(.bottom, Metrics.spaceXxs)
                    }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(.ink).frame(height: Metrics.lineSpine) }
                .accessibilityHidden(true)
                ForEach(grid.weeks, id: \.first) { week in
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { day in
                            dayCell(day, inMonth: grid.isInMonth(day))
                        }
                    }
                }
            }
            Text("고른 날 · \(Self.longDay(selection, calendar: calendar))")
                .textStyle(.small)
                .foregroundStyle(.inkSoft)
                .accessibilityHidden(true)
        }
        .fixedSize()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { if takesFocus { focused = true } }
        .onChange(of: selection) { _, day in
            // The month follows the picked day across its edge.
            if !calendar.isDate(day, equalTo: shown, toGranularity: .month) { shown = day }
        }
        .onKeyPress(.leftArrow) { move(.previousDay) }
        .onKeyPress(.rightArrow) { move(.nextDay) }
        .onKeyPress(.upArrow) { move(.previousWeek) }
        .onKeyPress(.downArrow) { move(.nextWeek) }
        .onKeyPress(.pageUp) { move(.previousMonth) }
        .onKeyPress(.pageDown) { move(.nextMonth) }
        // By letter and by the Korean key in its place, so T works with either input source.
        .onKeyPress(characters: CharacterSet(charactersIn: "tTㅅ")) { _ in move(.today) }
        .onKeyPress(.return) {
            onCommit?()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("날짜 고르기, \(Self.longDay(selection, calendar: calendar))")
    }

    private func header(_ month: Period) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceM) {
            Text(month.title)
                .font(.display(15))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Metrics.spaceM)
            HStack(spacing: Metrics.spaceXxs) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)).frame(width: 22) }
                    .accessibilityLabel("이전 달")
                Button { _ = move(.today) } label: { Text("오늘").textStyle(.small).padding(.horizontal, Metrics.spaceXs) }
                Button { shift(1) } label: { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).frame(width: 22) }
                    .accessibilityLabel("다음 달")
            }
            .buttonStyle(NavStyle())
        }
    }

    private func dayCell(_ day: Date, inMonth: Bool) -> some View {
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let isPicked = calendar.isDate(day, inSameDayAs: selection)
        let red = calendar.component(.weekday, from: day) == 1 || isHoliday(day)
        let color: Color = isPicked ? .onInk : !inMonth ? .inkFaint : red ? .holiday : .ink
        return DayCell(number: calendar.component(.day, from: day), color: color, isToday: isToday, isPicked: isPicked)
            .frame(width: Self.cell.width, height: Self.cell.height)
            .onTapGesture {
                selection = day
                if commitsOnClick { onCommit?() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.longDay(day, calendar: calendar) + (isToday ? ", 오늘" : ""))
            .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction {
                selection = day
                if commitsOnClick { onCommit?() }
            }
    }

    private func move(_ key: DatePickerKeys.Key) -> KeyPress.Result {
        selection = DatePickerKeys.move(selection, key, today: today, calendar: calendar)
        shown = selection
        return .handled
    }

    /// Shows the month before or after, leaving the picked day as it is.
    private func shift(_ months: Int) {
        shown = calendar.date(byAdding: .month, value: months, to: Period(containing: shown, scope: .month, calendar: calendar).start) ?? shown
    }

    /// `11월 12일 목요일`.
    static func longDay(_ day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day, .weekday], from: day)
        return "\(c.month!)월 \(c.day!)일 \(Calendar.weekdayName(c.weekday!))요일"
    }
}

/// One date: the number, today's bar over it, ink when picked, the week's grey rule under it.
private struct DayCell: View {
    let number: Int
    let color: Color
    let isToday: Bool
    let isPicked: Bool
    @State private var hovering = false

    var body: some View {
        Text("\(number)")
            .textStyle(.small)
            .fontWeight(isToday || isPicked ? .bold : .medium)
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isPicked ? Tokens.selection : hovering ? Color.hover : Color.clear)
            .overlay(alignment: .top) {
                if isToday {
                    Rectangle().fill(isPicked ? Color.onInk : Color.ink).frame(height: 3).padding(.horizontal, 5)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(.shade).frame(height: Metrics.line)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// ‹ 오늘 ›: bare words and arrows, a hover fill under the pointer.
private struct NavStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NavBody(configuration: configuration)
    }

    private struct NavBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.ink)
                .frame(height: 22)
                .background(configuration.isPressed ? Color.rowActive : hovering ? Color.hover : Color.clear)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .focusRing(ownsFocus(isFocused))
        }
    }
}
