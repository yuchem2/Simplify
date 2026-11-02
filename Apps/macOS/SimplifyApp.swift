import SwiftData
import SwiftUI
import SimplifyKit

@main
struct SimplifyApp: App {
    @State private var model: AppModel
    @State private var calendars: CalendarController
    @State private var memos: MemoBook
    private let container: ModelContainer

    init() {
        SimplifyFonts.register()
        var isSaved = true
        do {
            container = try SimplifyStore.makeContainer()
        } catch {
            // Keep the app usable if the shared store cannot open; nothing is saved this session,
            // and the panel says so.
            container = try! SimplifyStore.makeContainer(inMemory: true)
            isSaved = false
        }
        _memos = State(initialValue: MemoBook(container: container, isSaved: isSaved))
        let cache = SimplifyStore.openCache()
        let model = AppModel()
        _model = State(initialValue: model)
        _calendars = State(initialValue: CalendarController(container: cache, calendar: model.calendar))
    }

    var body: some Scene {
        // One window: the app has a single month view and a single sync loop.
        Window("Simplify", id: "main") {
            MainView(model: model, calendars: calendars, memos: memos)
                // Seven 100 pt day cells beside the 360 pt panel, plus margins.
                .frame(minWidth: 1180, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        // Open the window on every launch, even when restoration finds nothing to bring back.
        .defaultLaunchBehavior(.presented)
        .modelContainer(container)
        .commands {
            MemoCommands()
            CommandGroup(replacing: .appSettings) {
                Button("설정…") { model.isSettingsOpen = true }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(model.popover != nil)
            }
            CommandGroup(replacing: .newItem) {
                Button("새 일정") { model.newEvent(on: model.selectedDay, calendars: calendars) }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(model.isModalOpen || calendars.writableSources.isEmpty)
            }
            CommandGroup(after: .toolbar) {
                Button(model.isPanelHidden ? "패널 보기" : "패널 숨기기") { model.isPanelHidden.toggle() }
                    .keyboardShortcut("\\", modifiers: .command)
                    .disabled(model.isModalOpen)
            }
            MoveCommands(model: model)
        }
    }
}

/// The 이동 menu. Off under the settings modal or an event popover, and while a memo is being
/// written, so ⌘← and ⌘→ move the caret instead of the page.
private struct MoveCommands: Commands {
    let model: AppModel
    @FocusedValue(\.memoDraft) private var focusedMemo

    var body: some Commands {
        CommandMenu("이동") {
            Group {
                Button("오늘") { model.goToToday() }
                    .keyboardShortcut("t", modifiers: .command)
                let unit = model.calendarView == .week ? "주" : "달"
                Button("이전 \(unit)") { model.turnPage(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("다음 \(unit)") { model.turnPage(by: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            .disabled(model.isModalOpen || focusedMemo != nil)
        }
    }
}
