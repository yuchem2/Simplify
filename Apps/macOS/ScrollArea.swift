import SwiftUI

/// A vertical ScrollView, except while the debug snapshot renders: ImageRenderer cannot draw
/// AppKit-backed scroll views, so the content is laid out plainly there, its top in view and the
/// rest cut off as a scrolled-to-top view would show it.
struct ScrollArea<Content: View>: View {
    @Environment(\.isRenderingSnapshot) private var isRenderingSnapshot
    /// Where it is scrolled, for a view that moves it (the panel following the memo's caret).
    var position: Binding<ScrollPosition>?
    @ViewBuilder var content: Content

    init(position: Binding<ScrollPosition>? = nil, @ViewBuilder content: () -> Content) {
        self.position = position
        self.content = content()
    }

    var body: some View {
        if isRenderingSnapshot {
            Color.clear.overlay(alignment: .top) { content.fixedSize(horizontal: false, vertical: true) }.clipped()
        } else if let position {
            ScrollView { content }.scrollPosition(position)
        } else {
            ScrollView { content }
        }
    }
}

extension EnvironmentValues {
    @Entry var isRenderingSnapshot = false
}
