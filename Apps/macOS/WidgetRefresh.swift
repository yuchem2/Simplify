import Foundation
import WidgetKit

/// Asks the widgets for new timelines after the app changes what they show. Requests within a
/// second are folded into one, so a sync that touches many events reloads the widgets once.
@MainActor
enum WidgetRefresh {
    private static var pending: Task<Void, Never>?

    static func request() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            pending = nil
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The app is quitting: a request still waiting goes out now.
    static func flush() {
        guard let task = pending, !task.isCancelled else { return }
        task.cancel()
        pending = nil
        WidgetCenter.shared.reloadAllTimelines()
    }
}
