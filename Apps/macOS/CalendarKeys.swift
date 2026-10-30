import SwiftUI

extension View {
    /// The month sheet's and week grid's keys: the arrows move the chosen day, Tab picks its events,
    /// Return opens the picked event (or a folded panel), ⌫ deletes it. The view holds keyboard
    /// focus, taking it back when the settings modal or the event popover closes.
    func calendarKeys(model: AppModel, calendars: CalendarController, focused: FocusState<Bool>.Binding) -> some View {
        focusable()
            .focusEffectDisabled()
            .focused(focused)
            .onAppear { focused.wrappedValue = true }
            .onChange(of: model.isModalOpen) { _, open in if !open { focused.wrappedValue = true } }
            .onKeyPress(.return) {
                guard !model.isModalOpen else { return .ignored }
                if model.openSelectedEvent(calendars: calendars) { return .handled }
                // With the panel folded, Return opens it on the chosen day.
                guard model.isPanelHidden else { return .ignored }
                model.isPanelHidden = false
                return .handled
            }
            .onKeyPress(.delete) {
                guard !model.isModalOpen else { return .ignored }
                return model.deleteSelectedEvent(calendars: calendars) ? .handled : .ignored
            }
            .onKeyPress(keys: [.tab]) { press in
                guard !model.isModalOpen else { return .ignored }
                return model.moveEventSelection(by: press.modifiers.contains(.shift) ? -1 : 1, calendars: calendars) ? .handled : .ignored
            }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                guard !model.isModalOpen else { return .ignored }
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
