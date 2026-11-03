#if os(macOS)
import AppKit
import SwiftUI

// A box that hangs from the button that opened it, in the menus' place and frame: right under the
// button with no arrow, paper and an ink hairline. It takes the keyboard (Tab moves inside it) and
// closes on a click outside or Esc. The event popover keeps its arrow: it points at a day, not a button.

@MainActor
final class AnchoredPopPresenter {
    private static var current: AnchoredPopPresenter?

    private let panel = InkPanel()
    private let hosting: NSHostingView<AnyView>
    private weak var parent: NSWindow?
    private let anchor: NSRect
    private let onClose: () -> Void
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []

    private init(parent: NSWindow, anchor: NSRect, onClose: @escaping () -> Void) {
        self.parent = parent
        self.anchor = anchor
        self.onClose = onClose
        hosting = NSHostingView(rootView: AnyView(EmptyView()))
    }

    static func show(_ content: AnyView, below anchor: NSRect, in window: NSWindow, onClose: @escaping () -> Void) -> AnchoredPopPresenter {
        current?.close()
        InkMenuPresenter.dismiss()
        let presenter = AnchoredPopPresenter(parent: window, anchor: anchor, onClose: onClose)
        current = presenter
        presenter.present(content)
        return presenter
    }

    private func present(_ content: AnyView) {
        panel.takesKeys = true
        // Under the colour wheel that StylePop's 다른 색… opens, which floats at this level too.
        panel.level = .floating
        panel.onCancel = { [weak self] in self?.close() }
        panel.appearance = parent?.effectiveAppearance
        panel.contentView = hosting
        update(content)
        place(hosting.fittingSize)
        parent?.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        watch()
    }

    var isOpen: Bool { Self.current === self }

    /// New content from SwiftUI, framed; a change of size moves the bottom, never the top.
    func update(_ content: AnyView) {
        hosting.rootView = AnyView(
            content
                .floatingFrame()
                .padding([.trailing, .bottom], Metrics.shadowOffset)
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in self?.resize(size) }
        )
    }

    private func resize(_ size: CGSize) {
        guard isOpen, size != panel.frame.size, size.width > 0 else { return }
        place(size)
    }

    private func place(_ size: CGSize) {
        // Over the button's bottom edge, so the two hairlines are one.
        panel.place(size: size, topLeft: CGPoint(x: anchor.minX, y: anchor.minY + Metrics.line),
                    above: anchor.maxY - Metrics.line - Metrics.shadowOffset, screen: parent?.screen)
    }

    private func watch() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            let swallowed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isOpen else { return false }
                let window = event.window
                // Inside the box, a menu it opened, or the colour wheel a calendar's colour pop opens.
                if window === self.panel || window?.parent === self.panel || window is NSColorPanel { return false }
                let point = window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? NSEvent.mouseLocation
                self.close()
                // A click on the button that opened it only closes it, rather than opening it again.
                return window === self.parent && self.anchor.contains(point)
            }
            return swallowed ? nil : event
        }
        let center = NotificationCenter.default
        let close: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.close() } }
        observers = [
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: close),
            center.addObserver(forName: NSWindow.didResizeNotification, object: parent, queue: .main, using: close),
            center.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main, using: close),
        ]
    }

    func close() {
        guard isOpen else { return }
        Self.current = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        let wasKey = panel.isKeyWindow
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if wasKey { parent?.makeKey() }
        onClose()
    }
}

@MainActor final class PopBox {
    var presenter: AnchoredPopPresenter?
}

private struct PopAnchor<PopContent: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let showsPatterns: Bool
    let content: () -> PopContent
    let box: PopBox

    func makeNSView(context: Context) -> NSView {
        AnchorView()
    }

    /// Opens, closes or refreshes the box to match `isPresented` and the latest content.
    func updateNSView(_ view: NSView, context: Context) {
        if let presenter = box.presenter, presenter.isOpen {
            if isPresented { presenter.update(shown) } else { presenter.close() }
            return
        }
        box.presenter = nil
        guard isPresented else { return }
        let shown = shown
        let binding = $isPresented
        // After this update: the window and the view's place are settled, and the binding may change.
        Task { @MainActor in
            guard binding.wrappedValue, box.presenter == nil else { return }
            guard let window = view.window, let anchor = screenRect(of: view) else {
                binding.wrappedValue = false
                return
            }
            box.presenter = AnchoredPopPresenter.show(shown, below: anchor, in: window) {
                box.presenter = nil
                binding.wrappedValue = false
            }
        }
    }

    /// Built only while the box is open or opening.
    private var shown: AnyView {
        AnyView(content().environment(\.showsPalettePatterns, showsPatterns))
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {}

    private final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct AnchoredPopModifier<PopContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let content: () -> PopContent
    @State private var box = PopBox()
    @Environment(\.showsPalettePatterns) private var showsPatterns

    func body(content view: Content) -> some View {
        view
            .background(PopAnchor(isPresented: $isPresented, showsPatterns: showsPatterns, content: content, box: box))
            .onDisappear { box.presenter?.close() }
    }
}

public extension View {
    /// A box under this view while `isPresented` is true, in the menus' frame (A안: no arrow). It
    /// closes on a click outside or Esc and sets `isPresented` back to false. The content brings its
    /// own padding.
    func anchoredPop<PopContent: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> PopContent) -> some View {
        modifier(AnchoredPopModifier(isPresented: isPresented, content: content))
    }
}
#endif
