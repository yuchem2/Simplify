import SwiftUI
import SimplifyKit

/// Stage 0 placeholder: proves the app launches and can see the shared App Group.
/// The month grid and day panel replace it in stage 1.
struct ContentView: View {
    private let container = AppGroup.containerURL()

    var body: some View {
        VStack(spacing: 12) {
            Text("Simplify")
                .font(.largeTitle.bold())
            Text(container.map { "공유 저장소: \($0.path)" } ?? "App Group 없음 · 서명 전 빌드")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
