import SwiftData
import SwiftUI
import SimplifyKit

@main
struct SimplifyApp: App {
    @State private var model: AppModel
    @State private var calendars: CalendarController
    private let container: ModelContainer

    init() {
        SimplifyFonts.register()
        do {
            container = try SimplifyStore.makeContainer()
        } catch {
            // Keep the app usable if the shared store cannot open; nothing is saved this session.
            assertionFailure("Diary store failed to open: \(error)")
            container = try! SimplifyStore.makeContainer(inMemory: true)
        }
        let cache = SimplifyStore.openCache()
        let model = AppModel()
        _model = State(initialValue: model)
        _calendars = State(initialValue: CalendarController(container: cache, calendar: model.calendar))
    }

    var body: some Scene {
        // One window: the app has a single month view and a single sync loop.
        Window("Simplify", id: "main") {
            MainView(model: model, calendars: calendars)
                // Seven 100 pt day cells beside the 360 pt panel, plus margins.
                .frame(minWidth: 1180, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        // Open the window on every launch, even when restoration finds nothing to bring back.
        .defaultLaunchBehavior(.presented)
        .modelContainer(container)
        .commands {
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
            CommandMenu("이동") {
                Group {
                    Button("오늘") { model.goToToday() }
                        .keyboardShortcut("t", modifiers: .command)
                    Button("이전 달") { model.turnMonth(by: -1) }
                        .keyboardShortcut(.leftArrow, modifiers: .command)
                    Button("다음 달") { model.turnMonth(by: 1) }
                        .keyboardShortcut(.rightArrow, modifiers: .command)
                }
                // The month under the settings modal or an event popover stays put.
                .disabled(model.isModalOpen)
            }
        }
    }
}
