import AppIntents
import SimplifyKit

/// A ToDo's checkbox in the medium and large widgets: ticks or unticks it in the shared diary store
/// without opening the app. WidgetKit reloads the widgets afterwards; the app reads the store again
/// when it next comes to the front.
struct ToggleTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "할 일 체크"
    static let isDiscoverable = false

    @Parameter(title: "할 일") var todoID: String
    @Parameter(title: "완료") var isDone: Bool

    init() {}

    init(todoID: UUID, isDone: Bool) {
        self.todoID = todoID.uuidString
        self.isDone = isDone
    }

    /// The box flips the row's current state.
    static let make: TodoIntentMaker = { entry in ToggleTodoIntent(todoID: entry.todoID, isDone: !entry.isDone) }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: todoID) else { return .result() }
        try WidgetStore.setTodo(id, done: isDone, in: try SimplifyStore.makeContainer(), defaults: SharedSettings.defaults)
        SharedSettings.postDiaryChanged()
        return .result()
    }
}
