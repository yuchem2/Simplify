import SwiftUI

/// A vertical ScrollView, except while the debug snapshot renders: ImageRenderer cannot draw
/// AppKit-backed scroll views, so the content is laid out plainly there.
struct ScrollArea<Content: View>: View {
    @Environment(\.isRenderingSnapshot) private var isRenderingSnapshot
    @ViewBuilder var content: Content

    var body: some View {
        if isRenderingSnapshot {
            VStack(spacing: 0) { content; Spacer(minLength: 0) }
        } else {
            ScrollView { content }
        }
    }
}

extension EnvironmentValues {
    @Entry var isRenderingSnapshot = false
}
