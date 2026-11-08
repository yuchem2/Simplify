#if os(macOS)
import AppKit
import SwiftUI

// Puts ink menus and anchored pops on screen: a borderless panel, a child of the window, so a
// menu can hang past the window's or a modal's edge without being cut off. The menu panel never
// takes the keyboard; the window's events are read before anything else while it is open, the
// way the system menu tracks them.

/// A borderless panel for a menu level or a pop. Only a pop takes the keyboard.
final class InkPanel: NSPanel {
    var takesKeys = false
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        // The frame draws its own flat shadow.
        hasShadow = false
        level = .popUpMenu
        isReleasedWhenClosed = false
        hidesOnDeactivate = true
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { takesKeys }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Shows the panel with its top left at `topLeft` (screen points), kept on the screen: past the
    /// right edge it moves left, past the bottom it goes up to `above` (the y its bottom may rest on), or is pushed up.
    func place(size: CGSize, topLeft: CGPoint, leftAlternative: CGFloat? = nil, above: CGFloat? = nil, screen: NSScreen?) {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        var x = topLeft.x
        var top = topLeft.y
        if x + size.width > visible.maxX { x = leftAlternative.map { $0 - size.width } ?? (visible.maxX - size.width) }
        x = max(visible.minX, x)
        if top - size.height < visible.minY {
            if let above, above + size.height <= visible.maxY { top = above + size.height } else { top = visible.minY + size.height }
        }
        top = min(top, visible.maxY)
        setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }
}

/// Converts a view's bounds to screen points.
@MainActor func screenRect(of view: NSView) -> NSRect? {
    guard let window = view.window else { return nil }
    return window.convertToScreen(view.convert(view.bounds, to: nil))
}

// MARK: - Menu

@MainActor @Observable
final class InkMenuModel {
    var cursor: InkMenuCursor
    /// How far each level's list is scrolled.
    var scrolls: [CGFloat] = [0]
    let minWidth: CGFloat
    let maxItems: Int?

    init(_ entries: [InkMenuEntry], minWidth: CGFloat, maxItems: Int?) {
        cursor = InkMenuCursor(entries)
        self.minWidth = minWidth
        self.maxItems = maxItems
    }

    func maxItems(at depth: Int) -> Int? { depth == 0 ? maxItems : nil }

    func scroll(at depth: Int) -> CGFloat { scrolls.indices.contains(depth) ? scrolls[depth] : 0 }

    /// Scrolls `depth` by `delta`, within its list.
    func scroll(_ depth: Int, by delta: CGFloat) {
        guard cursor.levels.indices.contains(depth) else { return }
        let entries = cursor.levels[depth].entries
        let room = InkMenuMetrics.contentHeight(entries) - InkMenuMetrics.viewportHeight(entries, maxItems: maxItems(at: depth))
        while scrolls.count <= depth { scrolls.append(0) }
        scrolls[depth] = min(max(0, scrolls[depth] + delta), max(0, room))
    }

    /// Scrolls so the cursor line is in view; `centred` puts it in the middle (a menu just opened).
    func reveal(_ depth: Int, centred: Bool = false) {
        guard cursor.levels.indices.contains(depth), let index = cursor.levels[depth].cursor else { return }
        let entries = cursor.levels[depth].entries
        let viewport = InkMenuMetrics.viewportHeight(entries, maxItems: maxItems(at: depth))
        let top = InkMenuMetrics.tops(entries)[index]
        let current = scroll(at: depth)
        let target: CGFloat
        if centred {
            target = top + InkMenuMetrics.itemHeight / 2 - viewport / 2
        } else if top < current {
            target = top
        } else if top + InkMenuMetrics.itemHeight > current + viewport {
            target = top + InkMenuMetrics.itemHeight - viewport
        } else {
            return
        }
        scroll(depth, by: target - current)
    }
}

/// One level of the open menu, read from the model.
private struct InkMenuLevelView: View {
    let model: InkMenuModel
    let depth: Int
    let showsPatterns: Bool

    var body: some View {
        if model.cursor.levels.indices.contains(depth) {
            let level = model.cursor.levels[depth]
            InkMenuView(entries: level.entries, cursor: level.cursor, minWidth: depth == 0 ? model.minWidth : 0,
                        maxItems: model.maxItems(at: depth), scroll: model.scroll(at: depth))
                // Room for the flat shadow inside the panel.
                .padding([.trailing, .bottom], Metrics.shadowOffset)
                .environment(\.showsPalettePatterns, showsPatterns)
                .fixedSize()
        }
    }
}

/// The panel's content: the drawn level, and the pointer and VoiceOver on top of it. Lines have
/// fixed heights, so the line under the pointer comes from its height alone.
private final class InkMenuLevelHost: NSView {
    weak var presenter: InkMenuPresenter?
    let depth: Int
    let hosting: NSHostingView<InkMenuLevelView>
    private var tracking: NSTrackingArea?
    /// Held until the next ask: VoiceOver reads an element's attributes after it is handed over.
    private var elements: [NSAccessibilityElement] = []

    init(presenter: InkMenuPresenter, depth: Int, showsPatterns: Bool) {
        self.presenter = presenter
        self.depth = depth
        hosting = NSHostingView(rootView: InkMenuLevelView(model: presenter.model, depth: depth, showsPatterns: showsPatterns))
        super.init(frame: .zero)
        addSubview(hosting)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// Rounded up: a panel a fraction narrower than its lines would cut the widest one short.
    var contentSize: CGSize {
        let size = hosting.fittingSize
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    override func layout() {
        super.layout()
        hosting.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    /// The line under `event`, or nil off every line (the padding, the shadow).
    private func index(at event: NSEvent) -> Int? {
        guard let model = presenter?.model, model.cursor.levels.indices.contains(depth) else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let menuWidth = bounds.width - Metrics.shadowOffset
        let entries = model.cursor.levels[depth].entries
        let viewport = InkMenuMetrics.viewportHeight(entries, maxItems: model.maxItems(at: depth))
        let y = point.y - InkMenuMetrics.padding
        guard point.x >= 0, point.x < menuWidth, y >= 0, y < viewport else { return nil }
        return InkMenuMetrics.index(at: y + model.scroll(at: depth), in: entries)
    }

    override func mouseMoved(with event: NSEvent) { presenter?.hover(depth: depth, index: index(at: event)) }
    override func mouseEntered(with event: NSEvent) { presenter?.hover(depth: depth, index: index(at: event)) }
    override func mouseExited(with event: NSEvent) { presenter?.hover(depth: depth, index: nil) }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard let index = index(at: event) else { return }
        presenter?.click(depth: depth, index: index)
    }

    override func scrollWheel(with event: NSEvent) {
        presenter?.model.scroll(depth, by: -event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : InkMenuMetrics.itemHeight))
    }

    // MARK: VoiceOver

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .menu }

    override func accessibilityChildren() -> [Any]? {
        guard let presenter, presenter.model.cursor.levels.indices.contains(depth), let window else { return [] }
        let model = presenter.model
        let entries = model.cursor.levels[depth].entries
        let tops = InkMenuMetrics.tops(entries)
        let scroll = model.scroll(at: depth)
        elements = entries.indices.compactMap { index -> NSAccessibilityElement? in
            guard let item = entries[index].item else { return nil }
            let local = NSRect(x: 0, y: InkMenuMetrics.padding + tops[index] - scroll, width: bounds.width - Metrics.shadowOffset, height: InkMenuMetrics.itemHeight)
            let depth = depth
            let element = InkMenuItemElement { [weak presenter] in presenter?.click(depth: depth, index: index) }
            element.setAccessibilityRole(.menuItem)
            element.setAccessibilityLabel([item.title, item.detail].compactMap(\.self).joined(separator: ", "))
            element.setAccessibilityEnabled(item.isPickable)
            element.setAccessibilitySelected(model.cursor.levels[depth].cursor == index)
            if item.checked == true { element.setAccessibilityValue("선택됨") }
            element.setAccessibilityParent(self)
            element.setAccessibilityFrame(window.convertToScreen(convert(local, to: nil)))
            return element
        }
        return elements
    }
}

/// A menu line for VoiceOver; pressing it picks the line.
private final class InkMenuItemElement: NSAccessibilityElement {
    private let press: @MainActor @Sendable () -> Void

    init(press: @escaping @MainActor @Sendable () -> Void) {
        self.press = press
        super.init()
    }

    override func accessibilityPerformPress() -> Bool {
        let press = press
        MainActor.assumeIsolated { press() }
        return true
    }
}

/// An open ink menu: its panels, and the window's events while it is open. One at a time.
@MainActor
public final class InkMenuPresenter {
    private static var current: InkMenuPresenter?

    let model: InkMenuModel
    private weak var parent: NSWindow?
    private let showsPatterns: Bool
    private let typeahead: ((String) -> Int?)?
    private let onClose: (() -> Void)?
    private var panels: [InkPanel] = []
    /// For each submenu panel, the line of the level above that opened it.
    private var openers: [Int?] = []
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var typed = ""
    private var typedAt: TimeInterval = 0

    private init(entries: [InkMenuEntry], parent: NSWindow, minWidth: CGFloat, maxItems: Int?, showsPatterns: Bool,
                 typeahead: ((String) -> Int?)?, onClose: (() -> Void)?) {
        model = InkMenuModel(entries, minWidth: minWidth, maxItems: maxItems)
        self.parent = parent
        self.showsPatterns = showsPatterns
        self.typeahead = typeahead
        self.onClose = onClose
    }

    /// Whether a menu is open, for views that would otherwise answer the same keys.
    public static var isOpen: Bool { current != nil }

    /// A right-click menu with its top left at `point` (screen points).
    @discardableResult
    public static func popUp(_ entries: [InkMenuEntry], at point: CGPoint, in window: NSWindow, showsPatterns: Bool = false,
                             onClose: (() -> Void)? = nil) -> InkMenuPresenter {
        let presenter = open(entries, in: window, minWidth: 0, maxItems: nil, showsPatterns: showsPatterns, typeahead: nil, onClose: onClose)
        presenter.showRoot { panel, size in
            panel.place(size: size, topLeft: point, leftAlternative: point.x, above: point.y, screen: window.screen)
        }
        return presenter
    }

    /// A dropdown under `anchor` (screen points), at least as wide as it, or over it where the
    /// screen has no room below. Long lists show `maxItems` lines and scroll, the chosen one in the middle.
    @discardableResult
    public static func dropDown(_ entries: [InkMenuEntry], below anchor: NSRect, in window: NSWindow, maxItems: Int? = nil,
                                showsPatterns: Bool = false, typeahead: ((String) -> Int?)? = nil, onClose: (() -> Void)? = nil) -> InkMenuPresenter {
        let presenter = open(entries, in: window, minWidth: anchor.width, maxItems: maxItems, showsPatterns: showsPatterns,
                             typeahead: typeahead, onClose: onClose)
        presenter.model.reveal(0, centred: true)
        presenter.showRoot { panel, size in
            // Over the field's bottom edge, so the two hairlines are one.
            panel.place(size: size, topLeft: CGPoint(x: anchor.minX, y: anchor.minY + Metrics.line),
                        above: anchor.maxY - Metrics.line - Metrics.shadowOffset, screen: window.screen)
        }
        return presenter
    }

    /// Closes the open menu, if any, without a pick.
    public static func dismiss() {
        current?.close()
    }

    /// Closes this menu if it is still open.
    public func dismiss() {
        close()
    }

    private static func open(_ entries: [InkMenuEntry], in window: NSWindow, minWidth: CGFloat, maxItems: Int?, showsPatterns: Bool,
                             typeahead: ((String) -> Int?)?, onClose: (() -> Void)?) -> InkMenuPresenter {
        current?.close()
        let presenter = InkMenuPresenter(entries: entries, parent: window, minWidth: minWidth, maxItems: maxItems,
                                         showsPatterns: showsPatterns, typeahead: typeahead, onClose: onClose)
        current = presenter
        presenter.watch()
        return presenter
    }

    private func makePanel(depth: Int) -> (InkPanel, CGSize) {
        let panel = InkPanel()
        let host = InkMenuLevelHost(presenter: self, depth: depth, showsPatterns: showsPatterns)
        panel.contentView = host
        panel.appearance = parent?.effectiveAppearance
        let size = host.contentSize
        return (panel, size)
    }

    private func showRoot(place: (InkPanel, CGSize) -> Void) {
        let (panel, size) = makePanel(depth: 0)
        place(panel, size)
        parent?.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        panels = [panel]
        openers = [nil]
        NSAccessibility.post(element: panel.contentView as Any, notification: .created)
    }

    /// Opens or closes submenu panels to match the cursor's levels.
    private func syncPanels() {
        var count = model.cursor.levels.count
        // A submenu opened from another line (색 라벨 → 넘기기) is built again, beside its own line.
        if let changed = (1..<max(1, min(panels.count, count))).first(where: { openers[$0] != model.cursor.levels[$0 - 1].cursor }) {
            count = changed
        }
        while panels.count > count {
            let panel = panels.removeLast()
            openers.removeLast()
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        while panels.count < model.cursor.levels.count, let above = panels.last {
            let depth = panels.count
            guard let row = model.cursor.levels[depth - 1].cursor else { break }
            let (panel, size) = makePanel(depth: depth)
            // The submenu's first line beside the line that opened it, overlapping the menu's edge a little.
            let entries = model.cursor.levels[depth - 1].entries
            let rowTop = above.frame.maxY - InkMenuMetrics.padding - InkMenuMetrics.tops(entries)[row] + model.scroll(at: depth - 1)
            let menuRight = above.frame.maxX - Metrics.shadowOffset
            panel.place(size: size, topLeft: CGPoint(x: menuRight - Metrics.spaceS, y: rowTop + InkMenuMetrics.padding),
                        leftAlternative: above.frame.minX + Metrics.spaceS, screen: parent?.screen)
            parent?.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            panels.append(panel)
            openers.append(row)
        }
    }

    // MARK: Pointer

    func hover(depth: Int, index: Int?) {
        // Off the lines of a menu whose submenu is open: the submenu stays.
        model.cursor.hover(depth: depth, index: index)
        syncPanels()
    }

    func click(depth: Int, index: Int) {
        guard let item = model.cursor.item(depth: depth, index: index) else { return }
        if item.submenu != nil {
            model.cursor.hover(depth: depth, index: index)
            syncPanels()
            return
        }
        pick(item)
    }

    private func pick(_ item: InkMenuItem) {
        close()
        item.action?()
    }

    // MARK: Keys and closing

    private func key(_ event: NSEvent) -> Bool {
        // A shortcut closes the menu and goes on to the window.
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            close()
            return false
        }
        let key: InkMenuCursor.Key? = switch event.keyCode {
        case 126: .up
        case 125: .down
        case 124: .right
        case 123: .left
        case 36, 76, 49: .enter   // Return, Enter, Space
        case 53: .escape
        default: nil
        }
        if let key {
            let before = model.cursor.levels.count
            switch model.cursor.handle(key) {
            case .pick(let item): pick(item)
            case .dismiss: close()
            case .none:
                syncPanels()
                model.reveal(model.cursor.levels.count - 1)
                if model.cursor.levels.count != before { typed = "" }
            }
            return true
        }
        if let typeahead, let letters = event.charactersIgnoringModifiers, !letters.isEmpty, letters.allSatisfy(\.isASCII), letters.allSatisfy(\.isNumber) {
            let now = event.timestamp
            if now - typedAt > 1 { typed = "" }
            typed += letters
            typedAt = now
            if let index = typeahead(typed) {
                model.cursor.place(at: index)
                model.reveal(model.cursor.levels.count - 1, centred: true)
            }
        }
        return true
    }

    private func isOurs(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return panels.contains { $0 === window }
    }

    private func watch() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            let swallowed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                switch event.type {
                case .keyDown:
                    return self.key(event)
                case .scrollWheel:
                    if !self.isOurs(event.window) { self.close() }
                    return false
                default:
                    if self.isOurs(event.window) { return false }
                    // A click outside closes the menu and goes no further, as with the system's menus.
                    self.close()
                    return true
                }
            }
            return swallowed ? nil : event
        }
        let center = NotificationCenter.default
        let close: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.close() } }
        observers = [
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: close),
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: parent, queue: .main, using: close),
            center.addObserver(forName: NSWindow.didMoveNotification, object: parent, queue: .main, using: close),
            center.addObserver(forName: NSWindow.didResizeNotification, object: parent, queue: .main, using: close),
            center.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main, using: close),
        ]
    }

    private func close() {
        guard Self.current === self else { return }
        Self.current = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        for panel in panels {
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panels = []
        openers = []
        onClose?()
    }
}

// MARK: - SwiftUI

/// Hands the representable's view to the modifier, for its window and place on screen.
@MainActor final class AnchorBox {
    weak var view: NSView?
    weak var menu: InkMenuPresenter?
}

struct AnchorReader: NSViewRepresentable {
    let box: AnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }

    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct InkDropdown: ViewModifier {
    @Binding var isPresented: Bool
    let maxItems: Int?
    let typeahead: ((String) -> Int?)?
    let entries: () -> [InkMenuEntry]
    @State private var box = AnchorBox()
    @Environment(\.showsPalettePatterns) private var showsPatterns

    func body(content: Content) -> some View {
        content
            .background(AnchorReader(box: box))
            .onChange(of: isPresented) { _, open in
                // Only this dropdown's own menu: another may have replaced it.
                guard open else {
                    box.menu?.dismiss()
                    return
                }
                guard let view = box.view, let window = view.window, let anchor = screenRect(of: view) else {
                    isPresented = false
                    return
                }
                box.menu = InkMenuPresenter.dropDown(entries(), below: anchor, in: window, maxItems: maxItems, showsPatterns: showsPatterns,
                                                     typeahead: typeahead) { isPresented = false }
            }
            .onDisappear { box.menu?.dismiss() }
    }
}

public extension View {
    /// A dropdown ink menu under this view while `isPresented` is true; it sets it back to false
    /// when it closes. Long lists pass `maxItems`; `typeahead` turns typed letters into a line index.
    func inkMenu(isPresented: Binding<Bool>, maxItems: Int? = nil, typeahead: ((String) -> Int?)? = nil,
                 entries: @escaping () -> [InkMenuEntry]) -> some View {
        modifier(InkDropdown(isPresented: isPresented, maxItems: maxItems, typeahead: typeahead, entries: entries))
    }

    /// An ink menu at the pointer on a right-click (or a control-click) inside this view, while
    /// `isEnabled`. `isOpen` follows the menu, for the row to show it is the one the menu is about.
    func inkContextMenu(isEnabled: Bool = true, isOpen: Binding<Bool>? = nil, entries: @escaping () -> [InkMenuEntry]) -> some View {
        modifier(InkContextMenu(isEnabled: isEnabled, isOpen: isOpen, entries: entries))
    }
}

private struct InkContextMenu: ViewModifier {
    let isEnabled: Bool
    let isOpen: Binding<Bool>?
    let entries: () -> [InkMenuEntry]
    @Environment(\.showsPalettePatterns) private var showsPatterns
    @State private var box = ClickBox()

    func body(content: Content) -> some View {
        content
            .background {
                ContextClickReader(box: box, isEnabled: isEnabled, isOpen: isOpen, showsPatterns: showsPatterns, entries: entries)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        let local = CGRect(origin: .zero, size: proxy.size)
                        let shown = proxy.bounds(of: .scrollView).map { local.intersection($0) } ?? local
                        let frame = proxy.frame(in: .global)
                        return shown.offsetBy(dx: frame.minX, dy: frame.minY)
                    } action: { box.visible = $0 }
            }
            // VoiceOver's 메뉴 보기 (VO-Shift-M) opens the same menu, under the view.
            .accessibilityAction(.showMenu) { box.openUnderView() }
            .onDisappear { box.menu?.dismiss() }
    }
}

/// What a right-click needs when it comes: where the view is (from SwiftUI's layout of it: its own
/// AppKit frame does not follow a SwiftUI scroll view), whether it may open, and the latest menu.
@MainActor final class ClickBox {
    /// In the window's content, top-left origin.
    var visible: CGRect = .zero
    var isEnabled = true
    var showsPatterns = false
    var entries: (() -> [InkMenuEntry])?
    var isOpen: Binding<Bool>?
    weak var view: NSView?
    weak var menu: InkMenuPresenter?

    func open(at point: CGPoint, in window: NSWindow) {
        guard isEnabled, let entries else { return }
        let isOpen = isOpen
        // After the menu it replaces has closed, so that one's closing cannot clear this one.
        menu = InkMenuPresenter.popUp(entries(), at: point, in: window, showsPatterns: showsPatterns) {
            isOpen?.wrappedValue = false
        }
        isOpen?.wrappedValue = true
    }

    /// Opens at the view's bottom-left corner, for the keyboard and VoiceOver.
    func openUnderView() {
        guard let window = view?.window, let content = window.contentView else { return }
        let corner = CGPoint(x: visible.minX, y: content.isFlipped ? visible.maxY : content.bounds.height - visible.maxY)
        open(at: window.convertPoint(toScreen: content.convert(corner, to: nil)), in: window)
    }
}

private struct ContextClickReader: NSViewRepresentable {
    let box: ClickBox
    let isEnabled: Bool
    let isOpen: Binding<Bool>?
    let showsPatterns: Bool
    let entries: () -> [InkMenuEntry]

    func makeNSView(context: Context) -> WatchView {
        let view = WatchView()
        updateNSView(view, context: context)
        return view
    }

    /// The latest menu and state, read when the click comes.
    func updateNSView(_ view: WatchView, context: Context) {
        view.box = box
        box.view = view
        box.isEnabled = isEnabled
        box.isOpen = isOpen
        box.showsPatterns = showsPatterns
        box.entries = entries
    }

    static func dismantleNSView(_ view: WatchView, coordinator: ()) {
        view.stop()
    }

    final class WatchView: NSView {
        var box: ClickBox?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                let opened = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let window = self.window, event.window === window, let box = self.box, box.isEnabled,
                          !self.isHiddenOrHasHiddenAncestor else { return false }
                    if event.type == .leftMouseDown && !event.modifierFlags.contains(.control) { return false }
                    guard let content = window.contentView else { return false }
                    let point = content.convert(event.locationInWindow, from: nil)
                    let top = content.isFlipped ? point : CGPoint(x: point.x, y: content.bounds.height - point.y)
                    guard box.visible.contains(top) else { return false }
                    box.open(at: window.convertPoint(toScreen: event.locationInWindow), in: window)
                    return true
                }
                return opened ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif
