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
        // Before the first frame, so a chosen theme never flashes the system one; MainView keeps it in step after.
        model.theme.apply()
        _calendars = State(initialValue: CalendarController(container: cache, calendar: model.calendar))
    }

    var body: some Scene {
        // One window: the app has a single month view and a single sync loop.
        Window("Simplify", id: "main") {
            MainView(model: model, calendars: calendars, memos: memos)
                // Seven 64 pt day cells beside the narrow 300 pt panel, plus margins: an 11-inch iPad's width.
                .frame(minWidth: MainView.minWidth, minHeight: 600)
        }
        // A real title bar (the window's controls live in it), drawn without its own title or glass.
        .windowToolbarStyle(.unified(showsTitle: false))
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
            CommandGroup(before: .toolbar) {
                // The title bar's view switch, also from the keyboard (and with the toolbar hidden).
                ForEach(Array(AppModel.CalendarView.allCases.enumerated()), id: \.element) { index, view in
                    Button("\(view.label) 보기") { model.calendarView = view }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                        .disabled(model.isModalOpen)
                }
                Divider()
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
                let unit = model.calendarView.unit
                Button("이전 \(unit)") { model.turnPage(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("다음 \(unit)") { model.turnPage(by: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            .disabled(model.isModalOpen || focusedMemo != nil)
        }
    }
}
