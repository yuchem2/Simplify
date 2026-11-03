import SwiftUI
import SimplifyKit

/// What the event popover shows and where it hangs.
struct EventPopoverState {
    enum Content {
        case detail(EventOccurrence)
        /// Editing an event on screen, or a new one (`occurrence` nil).
        case editor(EventEditorModel)
    }

    /// A question that takes over the popover until it is answered.
    enum Question: Equatable {
        case discard
        case delete
        case saveScope
    }

    var content: Content
    /// The `eventAnchor` of the row or day cell it points at.
    var anchor: String
    var question: Question?
    /// A delete is on its way; the popover stays until it is done.
    var isBusy = false

    /// The event the popover is about, if it is one already on the calendar.
    var occurrence: EventOccurrence? {
        switch content {
        case .detail(let occurrence): occurrence
        case .editor(let editor): editor.occurrence
        }
    }
}

// MARK: - Anchors

/// Where each event row and day cell sits, so the popover can point at the one it is about.
struct EventAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

enum EventAnchor {
    /// `week` is the panel's week list; `weekGrid` the week view.
    enum Place: String { case month, panel, week, weekGrid }

    static func cell(_ day: Date) -> String {
        "cell:\(Int(day.timeIntervalSinceReferenceDate))"
    }

    /// A band shows on several days, and an event in both the month and the panel, so the key
    /// names the place and the day too.
    static func row(_ occurrenceID: String, day: Date, in place: Place) -> String {
        "\(place.rawValue):\(Int(day.timeIntervalSinceReferenceDate)):\(occurrenceID)"
    }
}

extension View {
    /// Lets the event popover point at this view. Adds to the anchors inside it (a day cell's
    /// rows) instead of replacing them.
    func eventAnchor(_ id: String) -> some View {
        transformAnchorPreference(key: EventAnchorKey.self, value: .bounds) { $0[id] = $1 }
    }

    /// A dashed outline on an event whose change waits to be sent.
    func unsentOutline(_ isUnsent: Bool) -> some View {
        overlay {
            if isUnsent {
                Rectangle()
                    .strokeBorder(.ink, style: StrokeStyle(lineWidth: Metrics.lineMark, dash: [3, 2]))
                    .padding(-1.5)
                    .accessibilityLabel("보내기 대기")
            }
        }
    }

    /// One click picks the event and shows its details; a second click on it (or a double-click) edits it.
    func opensEvent(_ occurrence: EventOccurrence, day: Date, anchor: String, model: AppModel, calendars: CalendarController) -> some View {
        contentShape(Rectangle())
            .onTapGesture { model.openEvent(occurrence, day: day, anchor: anchor, calendars: calendars) }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.openEvent(occurrence, day: day, anchor: anchor, calendars: calendars) }
    }
}

// MARK: - Opening and closing

extension AppModel {
    /// Shows the event's details; when they are already showing, opens the editor instead.
    func openEvent(_ occurrence: EventOccurrence, day: Date, anchor: String, calendars: CalendarController) {
        if case .detail(let shown)? = popover?.content, shown.id == occurrence.id {
            edit(occurrence, calendars: calendars)
            return
        }
        select(day)
        selectedEventID = occurrence.id
        popover = EventPopoverState(content: .detail(occurrence), anchor: anchor)
    }

    /// Turns the open popover into the editor for `occurrence`, when its calendar can be written.
    @discardableResult
    func edit(_ occurrence: EventOccurrence, calendars: CalendarController) -> Bool {
        guard calendars.isWritable(occurrence.sourceID), let event = calendars.event(id: occurrence.eventID) else { return false }
        let editor = EventEditorModel(editing: occurrence, event: event, calendar: calendar)
        popover = EventPopoverState(content: .editor(editor), anchor: popover?.anchor ?? EventAnchor.cell(selectedDay))
        return true
    }

    /// A new event on `day`, from the next full hour for an hour, in the calendar used last.
    func newEvent(on day: Date, calendars: CalendarController) {
        guard !isModalOpen, let sourceID = calendars.defaultSourceForNewEvent else { return }
        select(day)
        let editor = EventEditorModel(newOn: selectedDay, sourceID: sourceID, calendar: calendar)
        popover = EventPopoverState(content: .editor(editor), anchor: EventAnchor.cell(selectedDay))
    }

    /// Return on the month or week: the picked event's details.
    func openSelectedEvent(calendars: CalendarController) -> Bool {
        guard let occurrence = selectedOccurrence(calendars) else { return false }
        popover = EventPopoverState(content: .detail(occurrence), anchor: EventAnchor.row(occurrence.id, day: selectedDay, in: calendarPlace))
        return true
    }

    /// ⌫ on the month or week: asks before deleting the picked event. Read-only events stay as they are.
    func deleteSelectedEvent(calendars: CalendarController) -> Bool {
        guard let occurrence = selectedOccurrence(calendars), calendars.isWritable(occurrence.sourceID) else { return false }
        popover = EventPopoverState(content: .detail(occurrence), anchor: EventAnchor.row(occurrence.id, day: selectedDay, in: calendarPlace), question: .delete)
        return true
    }

    /// Tab / ⇧Tab on the month or week: the chosen day's next or previous event.
    func moveEventSelection(by step: Int, calendars: CalendarController) -> Bool {
        let slots = calendars.slots[selectedDay] ?? []
        guard !slots.isEmpty else { return false }
        let index = slots.firstIndex { $0.occurrence.id == selectedEventID }
        let next = index.map { ($0 + step + slots.count) % slots.count } ?? (step > 0 ? 0 : slots.count - 1)
        selectedEventID = slots[next].occurrence.id
        return true
    }

    /// Where the keys' popover points: the month sheet or the week grid on screen, or the small
    /// month's list beside a wide panel (which draws its rows as the panel's day list, or its week
    /// list for a week or month).
    private var calendarPlace: EventAnchor.Place {
        if isPanelWide, !isPanelHidden { return panelScope == .day ? .panel : .week }
        return calendarView == .week ? .weekGrid : .month
    }

    private func selectedOccurrence(_ calendars: CalendarController) -> EventOccurrence? {
        (calendars.slots[selectedDay] ?? []).first { $0.occurrence.id == selectedEventID }?.occurrence
    }

    /// Esc, or a click outside: an editor with changes asks first.
    func requestClosePopover() {
        guard var state = popover, !state.isBusy else { return }
        if state.question != nil {
            state.question = nil
            popover = state
        } else if case .editor(let editor) = state.content, editor.isDirty, editor.phase != .saving, editor.phase != .refreshing {
            state.question = .discard
            popover = state
        } else if case .editor(let editor) = state.content, editor.phase == .saving {
            return
        } else {
            popover = nil
        }
    }
}

// MARK: - The layer

/// Lies over the whole window while the popover is open: a click outside closes it, and the
/// popover hangs beside the row or day it is about, on whichever side has room.
struct EventPopoverLayer: View {
    let model: AppModel
    let calendars: CalendarController
    let anchors: [String: Anchor<CGRect>]
    @State private var size = CGSize(width: EventPopoverLayer.width, height: 220)

    static let width: CGFloat = 340
    /// From the target to the popover's edge: the arrow and a little air.
    private static let gap: CGFloat = PopoverArrow.depth + Metrics.spaceXxs
    private static let margin: CGFloat = Metrics.spaceL

    var body: some View {
        if let state = model.popover {
            GeometryReader { geo in
                // An event behind "+n개 더" has no row; point at its day instead.
                let target = (anchors[state.anchor] ?? anchors[EventAnchor.cell(model.selectedDay)]).map { geo[$0] }
                    ?? CGRect(x: geo.size.width / 2, y: geo.size.height / 3, width: 0, height: 0)
                let place = placement(for: target, in: geo.size, content: state)
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { tap in
                            // A second click on the event it shows is the double-click that edits it.
                            if target.contains(tap.location), case .detail(let occurrence) = state.content, state.question == nil {
                                model.edit(occurrence, calendars: calendars)
                            } else {
                                model.requestClosePopover()
                            }
                        })
                        .accessibilityHidden(true)
                    EventPopoverCard(model: model, calendars: calendars, state: state)
                        .frame(width: Self.width)
                        .floatingFrame()
                        .overlay(alignment: .topLeading) {
                            PopoverArrow(pointsLeft: place.arrowOnLeft)
                                .offset(x: arrowX(place), y: place.arrowY - PopoverArrow.depth)
                        }
                        // The arrow's own flat shadow, under the card like the card's.
                        .background(alignment: .topLeading) {
                            PopoverArrow.Outline(pointsLeft: place.arrowOnLeft)
                                .fill(Tokens.shadowFloat)
                                .frame(width: PopoverArrow.size.width, height: PopoverArrow.size.height)
                                .offset(x: arrowX(place) + Metrics.shadowOffset, y: place.arrowY - PopoverArrow.depth + Metrics.shadowOffset)
                                .accessibilityHidden(true)
                        }
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                        .offset(x: place.origin.x, y: place.origin.y)
                }
            }
        }
    }

    /// The arrow overlaps the card's ink edge so the edge opens where the arrow joins it.
    private func arrowX(_ place: Placement) -> CGFloat {
        place.arrowOnLeft ? -PopoverArrow.depth : Self.width - Metrics.line
    }

    private struct Placement {
        var origin: CGPoint
        var arrowOnLeft: Bool
        var arrowY: CGFloat
    }

    /// Right of the target when it fits, otherwise left; level with the target's middle, kept inside the window.
    private func placement(for target: CGRect, in bounds: CGSize, content state: EventPopoverState) -> Placement {
        // Until the popover has been measured, a likely height keeps a tall editor inside the window.
        var size = size
        if case .editor = state.content, state.question == nil { size.height = max(size.height, 470) }
        if let question = state.question, question != .discard { size.height = max(size.height, 400) }
        var x = target.maxX + Self.gap
        let fitsRight = x + size.width <= bounds.width - Self.margin
        if !fitsRight { x = max(Self.margin, target.minX - Self.gap - size.width) }
        let y = min(max(Self.margin, target.midY - 28), max(Self.margin, bounds.height - size.height - Self.margin))
        let arrowY = min(max(target.midY - y, 18), size.height - 18)
        return Placement(origin: CGPoint(x: x, y: y), arrowOnLeft: fitsRight, arrowY: arrowY)
    }
}

/// The little point on the popover's side, drawn like the popover: paper with a 1 pt ink edge. Its
/// base lies over the card's edge, so the paper runs through and the two slanted lines meet the
/// edge where it stops.
private struct PopoverArrow: View {
    let pointsLeft: Bool
    static let depth: CGFloat = 8
    /// The depth plus the width of the card's edge it covers.
    static let size = CGSize(width: depth + Metrics.line, height: depth * 2)

    var body: some View {
        let d = Self.depth, half = Metrics.line / 2
        // Mirrored for an arrow on the right; the base is at `d + line` on the left, at 0 on the right.
        let x = { (value: CGFloat) in pointsLeft ? value : Self.size.width - value }
        ZStack {
            Outline(pointsLeft: pointsLeft)
                .fill(.paper)
            Path { p in
                // Down the middle of the card's edge, out to the tip and back.
                p.move(to: CGPoint(x: x(d + half), y: 0))
                p.addLine(to: CGPoint(x: x(half), y: d))
                p.addLine(to: CGPoint(x: x(d + half), y: d * 2))
            }
            .stroke(.ink, style: StrokeStyle(lineWidth: Metrics.line, lineCap: .butt, lineJoin: .miter))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }

    /// The arrow's area, base included: filled with paper on the card, with the shadow under it.
    struct Outline: Shape {
        let pointsLeft: Bool

        func path(in rect: CGRect) -> Path {
            let x = { (value: CGFloat) in pointsLeft ? value : rect.width - value }
            return Path { p in
                p.move(to: CGPoint(x: x(rect.width), y: 0))
                p.addLine(to: CGPoint(x: x(0), y: rect.height / 2))
                p.addLine(to: CGPoint(x: x(rect.width), y: rect.height))
                p.closeSubpath()
            }
        }
    }
}

/// The popover's insides: details or the editor, or the question it is asking.
private struct EventPopoverCard: View {
    let model: AppModel
    let calendars: CalendarController
    let state: EventPopoverState
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if let question = state.question {
                EventQuestionView(model: model, calendars: calendars, state: state, question: question)
            } else {
                switch state.content {
                case .detail(let occurrence):
                    EventDetailView(model: model, calendars: calendars, occurrence: occurrence)
                case .editor(let editor):
                    EventEditorView(model: model, calendars: calendars, editor: editor)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onExitCommand { model.requestClosePopover() }
        .accessibilityAddTraits(.isModal)
    }
}
