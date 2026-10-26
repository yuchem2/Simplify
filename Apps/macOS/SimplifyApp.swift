import SwiftData
import SwiftUI
import SimplifyKit

@main
struct SimplifyApp: App {
    @State private var model = AppModel()
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
    }

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
                // Seven 100 pt day cells beside the 360 pt panel, plus margins.
                .frame(minWidth: 1180, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(container)
        .commands {
            CommandMenu("이동") {
                Button("오늘") { model.goToToday() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("이전 달") { model.turnMonth(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("다음 달") { model.turnMonth(by: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
        }
    }
}
