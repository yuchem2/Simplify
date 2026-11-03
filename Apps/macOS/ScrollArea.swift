import SwiftUI

/// A vertical ScrollView, except while the debug snapshot renders: ImageRenderer cannot draw
/// AppKit-backed scroll views, so the content is laid out plainly there, its top in view and the
/// rest cut off as a scrolled-to-top view would show it.
struct ScrollArea<Content: View>: View {
    @Environment(\.isRenderingSnapshot) private var isRenderingSnapshot
    @ViewBuilder var content: Content

    var body: some View {
        if isRenderingSnapshot {
            Color.clear.overlay(alignment: .top) { content.fixedSize(horizontal: false, vertical: true) }.clipped()
        } else {
            ScrollView { content }
        }
    }
}

extension EnvironmentValues {
    @Entry var isRenderingSnapshot = false
}
