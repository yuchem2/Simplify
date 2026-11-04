import AppKit
import ObjectiveC
import SwiftUI
import UniformTypeIdentifiers
import SimplifyKit

// Attached files (stage 4 of memo formatting): put in by dragging from Finder, pasting a
// picture, 파일 첨부… (⌘⇧A) or the Aa bar's 첨부. In the memo each is one placeholder letter
// (`MemoAttachments`); `MemoLineStyler` draws a picture or a one-line card in its place.

/// This Mac's attached files and how each stands: here, on its way from another device, or
/// nowhere to be found. Opening, showing and copying them.
@MainActor
final class AttachmentShelf {
    static let shared = AttachmentShelf()
    /// Posted when a file arrived, went, or started or stopped waiting: cards are drawn again.
    static let didChange = Notification.Name("AttachmentShelf.didChange")

    /// `Attachments` in the App Group container, or the sandbox's own Application Support when the
    /// build has no group. The format check puts a test folder in its place.
    var store: AttachmentStore
    /// This run, for `MemoAttachments.sweep`'s grace.
    let launch = UUID().uuidString
    /// Ids another device has and this one is bringing down (`DeviceSync`).
    private(set) var waiting: Set<String> = []
    private var images: [String: NSImage] = [:]
    private var sizes: [String: Int64] = [:]

    private init() {
        store = AttachmentStore.shared() ?? AttachmentStore(root: URL.applicationSupportDirectory.appending(path: AttachmentStore.folderName, directoryHint: .isDirectory))
    }

    enum State: Equatable {
        case ready(size: Int64)
        case waiting
        case missing
    }

    func state(_ ref: MemoAttachments.Ref) -> State {
        if let size = sizes[ref.id] ?? store.size(ref) {
            sizes[ref.id] = size
            return .ready(size: size)
        }
        return waiting.contains(ref.id) ? .waiting : .missing
    }

    /// A picture, drawn as one: a file of an image type that can be read as one.
    func image(_ ref: MemoAttachments.Ref) -> NSImage? {
        guard UTType(filenameExtension: ref.fileExtension)?.conforms(to: .image) == true, case .ready = state(ref) else { return nil }
        if let image = images[ref.id] { return image }
        guard let image = NSImage(contentsOf: store.url(for: ref)), image.size.width > 0, image.size.height > 0 else { return nil }
        if images.count > 60 { images.removeAll() }
        images[ref.id] = image
        return image
    }

    /// `PDF 문서`, `Excel 통합 문서`: the file's kind in Korean (the app has no other language, so
    /// the system's names would come in English), by its broad kind past the common ones.
    func kindName(_ ref: MemoAttachments.Ref) -> String {
        if let known = Self.kinds[ref.fileExtension] { return known }
        guard let type = UTType(filenameExtension: ref.fileExtension) else { return "파일" }
        if type.conforms(to: .image) { return "이미지" }
        if type.conforms(to: .movie) { return "동영상" }
        if type.conforms(to: .audio) { return "오디오" }
        if type.conforms(to: .archive) { return "압축 파일" }
        if type.conforms(to: .text) { return "텍스트" }
        return ref.fileExtension.isEmpty ? "파일" : "\(ref.fileExtension.uppercased()) 파일"
    }

    private static let kinds: [String: String] = [
        "pdf": "PDF 문서", "xlsx": "Excel 통합 문서", "xls": "Excel 통합 문서", "docx": "Word 문서", "doc": "Word 문서",
        "pptx": "PowerPoint 프레젠테이션", "ppt": "PowerPoint 프레젠테이션", "key": "Keynote 프레젠테이션", "numbers": "Numbers 스프레드시트",
        "pages": "Pages 문서", "hwp": "한글 문서", "hwpx": "한글 문서", "csv": "CSV 문서", "txt": "텍스트", "md": "마크다운 문서",
        "rtf": "서식 있는 텍스트", "zip": "ZIP 압축 파일", "png": "PNG 이미지", "jpg": "JPEG 이미지", "jpeg": "JPEG 이미지",
        "heic": "HEIC 이미지", "gif": "GIF 이미지", "mov": "QuickTime 동영상", "mp4": "MP4 동영상", "mp3": "MP3 오디오", "m4a": "M4A 오디오",
    ]

    func url(_ ref: MemoAttachments.Ref) -> URL { store.url(for: ref) }

    /// After a sync pass: which ids are on their way, and which arrived or went.
    func synced(waiting: Set<String>, changed: Set<String>) {
        guard waiting != self.waiting || !changed.isEmpty else { return }
        self.waiting = waiting
        forget(changed)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Cached sizes and pictures of these ids are read again.
    func forget(_ ids: Set<String>) {
        for id in ids {
            sizes[id] = nil
            images[id] = nil
        }
    }

    /// Removes the attachments no memo uses once their wait is over.
    func sweep(referenced: Set<String>?) {
        let removed = store.sweep(referenced: referenced, launch: launch)
        guard !removed.isEmpty else { return }
        forget(removed)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    // MARK: Copies of files

    enum Added {
        case added([MemoAttachments.Ref])
        /// Some were over the limit (the rest are in `refs`).
        case tooLarge([MemoAttachments.Ref])
    }

    func add(_ urls: [URL]) -> Added {
        var refs: [MemoAttachments.Ref] = []
        var tooLarge = false
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                refs.append(try store.add(copying: url))
            } catch AttachmentStore.Failure.tooLarge {
                tooLarge = true
            } catch {
                NSSound.beep()
            }
        }
        return tooLarge ? .tooLarge(refs) : .added(refs)
    }

    func add(picture data: Data, now: Date = .now) -> Added {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        do {
            return .added([try store.add(data: data, name: "이미지 \(formatter.string(from: now)).png")])
        } catch AttachmentStore.Failure.tooLarge {
            return .tooLarge([])
        } catch {
            NSSound.beep()
            return .added([])
        }
    }

    /// The attachment a file URL on the clipboard points at, when it is one of this Mac's (a card
    /// copied with its menu's 복사).
    func ref(at url: URL) -> MemoAttachments.Ref? {
        let file = url.standardizedFileURL.path, root = store.root.standardizedFileURL.path
        guard file.hasPrefix(root + "/") else { return nil }
        return MemoAttachments.Ref(value: String(file.dropFirst(root.count + 1)))
    }

    // MARK: The card's menu

    func open(_ ref: MemoAttachments.Ref) {
        NSWorkspace.shared.open(url(ref))
    }

    func reveal(_ ref: MemoAttachments.Ref) {
        NSWorkspace.shared.activateFileViewerSelecting([url(ref)])
    }

    /// The file itself on the clipboard, for Finder or another app.
    func copy(_ ref: MemoAttachments.Ref) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url(ref) as NSURL])
    }

    func saveAs(_ ref: MemoAttachments.Ref, in window: NSWindow?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ref.name
        panel.canCreateDirectories = true
        let source = url(ref)
        let done: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let target = panel.url else { return }
            try? FileManager.default.removeItem(at: target)
            if (try? FileManager.default.copyItem(at: source, to: target)) == nil { NSSound.beep() }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: done) } else { panel.begin(completionHandler: done) }
    }
}

extension MemoDraft {
    /// The picked card: one clicked (the caret just after it), or selected on its own.
    var pickedAttachment: (range: Range<AttributedString.Index>, ref: MemoAttachments.Ref)? {
        guard text.characters.contains(MemoAttachments.placeholder) else { return nil }
        let range: Range<AttributedString.Index>
        if let location = pickedCard?(), let found = Range(NSRange(location: location, length: 1), in: text) {
            range = found
        } else if case .ranges(let ranges) = selection.indices(in: text), ranges.ranges.count == 1, let only = ranges.ranges.first,
                  text.characters.distance(from: only.lowerBound, to: only.upperBound) == 1 {
            range = only
        } else {
            return nil
        }
        return MemoAttachments.attachments(in: text).first { $0.range == range }
    }

    /// 파일 첨부… (⌘⇧A), the Aa bar's 첨부 and the right-click menu: files picked in a panel.
    func askToAttach() {
        guard !isUnreadable else { return NSSound.beep() }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "첨부"
        panel.message = "메모에 붙일 파일을 골라 주세요. 25MB까지 붙일 수 있어요."
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK else { return }
            self?.attach(panel.urls)
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: done) } else { panel.begin(completionHandler: done) }
    }

    /// Copies the files in and puts them at `offset` (letters), or the caret. Over 25 MB a file is
    /// left out, and the memo says so.
    func attach(_ urls: [URL], at offset: Int? = nil) {
        guard !isUnreadable, !urls.isEmpty else { return }
        put(AttachmentShelf.shared.add(urls), at: offset)
    }

    /// A pasted picture.
    func attach(picture data: Data) {
        guard !isUnreadable else { return }
        put(AttachmentShelf.shared.add(picture: data), at: nil)
    }

    private func put(_ added: AttachmentShelf.Added, at offset: Int?) {
        switch added {
        case .added(let refs):
            insertAttachments(refs, at: offset)
        case .tooLarge(let refs):
            insertAttachments(refs, at: offset)
            NSSound.beep()
            notify?(MemoAttachments.limitMessage)
        }
    }

    /// Each attachment on a line of its own at `offset` (or the caret), the caret on the line
    /// after. In a table they go under it: a cell holds words only.
    func insertAttachments(_ refs: [MemoAttachments.Ref], at offset: Int? = nil) {
        guard !refs.isEmpty, !isUnreadable else { return }
        let characters = text.characters
        var at = min(offset ?? selectedRanges.first.map { characters.distance(from: characters.startIndex, to: $0.lowerBound) } ?? characters.count,
                     characters.count)
        // Out of a table: past the end of its last row.
        var index = characters.index(characters.startIndex, offsetBy: at)
        if let table = tableID(atLineOf: index) {
            while index < characters.endIndex {
                while index < characters.endIndex, !characters[index].isNewline { index = characters.index(after: index) }
                guard index < characters.endIndex else { break }
                let next = characters.index(after: index)
                guard tableID(atLineOf: next) == table, next < characters.endIndex, !characters[next].isNewline else { break }
                index = next
            }
            at = characters.distance(from: characters.startIndex, to: index)
        }
        index = characters.index(characters.startIndex, offsetBy: at)
        var piece = AttributedString()
        if index > characters.startIndex, !characters[characters.index(before: index)].isNewline { piece += AttributedString("\n") }
        for (number, ref) in refs.enumerated() {
            if number > 0 { piece += AttributedString("\n") }
            var mark = AttributeContainer()
            mark[MemoAttributes.Attachment.self] = ref.value
            piece += AttributedString(String(MemoAttachments.placeholder), attributes: mark)
        }
        // A line break after, so the caret starts a plain line under the last one: one added, or
        // the one already there.
        let breakFollows = index < characters.endIndex && characters[index].isNewline
        if !breakFollows { piece += AttributedString("\n") }
        let length = piece.characters.count + (breakFollows ? 1 : 0)
        text.transform(updating: &selection) { $0.insert(piece, at: $0.characters.index($0.startIndex, offsetBy: at)) }
        let caret = text.characters.index(text.startIndex, offsetBy: min(at + length, text.characters.count))
        selection = AttributedTextSelection(insertionPoint: caret, typingAttributes: AttributeContainer())
        focusRequest += 1
    }

    private func tableID(atLineOf index: AttributedString.Index) -> String? {
        let characters = text.characters
        var line = index
        while line > characters.startIndex, !characters[characters.index(before: line)].isNewline { line = characters.index(before: line) }
        guard line < characters.endIndex, !characters[line].isNewline else { return nil }
        return text.runs[line][MemoAttributes.Table.self]
    }

    /// 첨부 지우기: the attachment's letter goes, with its line when nothing else is on it. The
    /// file is cleared away later, once no memo uses it (undo can bring the letter back).
    func removeAttachment(_ range: Range<AttributedString.Index>) {
        let characters = text.characters
        var range = range
        let startsLine = range.lowerBound == characters.startIndex || characters[characters.index(before: range.lowerBound)].isNewline
        if startsLine, range.upperBound < characters.endIndex, characters[range.upperBound].isNewline {
            range = range.lowerBound..<characters.index(after: range.upperBound)
        }
        let start = characters.distance(from: characters.startIndex, to: range.lowerBound)
        text.transform(updating: &selection) { $0.removeSubrange(range) }
        selection = AttributedTextSelection(insertionPoint: text.characters.index(text.startIndex, offsetBy: min(start, text.characters.count)),
                                            typingAttributes: AttributeContainer())
        focusRequest += 1
    }

    /// Letters typed against an attachment do not become one, and a placeholder letter that
    /// stands for nothing goes.
    func keepAttachmentsWhole() {
        if isComposing { return }
        // Most memos have none: no walk over every letter on each keystroke.
        guard text.characters.contains(MemoAttachments.placeholder) || !text.runs[MemoAttributes.Attachment.self].allSatisfy({ $0.0 == nil }) else { return }
        let strays = MemoAttachments.strays(in: text)
        let loose = MemoAttachments.loosePlaceholders(in: text)
        guard !strays.isEmpty || !loose.isEmpty else { return }
        text.transform(updating: &selection) { text in
            text[strays][MemoAttributes.Attachment.self] = nil
            for range in loose.ranges.reversed() { text.removeSubrange(range) }
        }
    }

    /// Opens Quick Look on the attachment, when its file is here.
    func preview(_ ref: MemoAttachments.Ref) {
        guard case .ready = AttachmentShelf.shared.state(ref) else { return NSSound.beep() }
        previewURL = AttachmentShelf.shared.url(ref)
    }

    /// The card's right-click menu, as the mockup's.
    func cardMenu(_ ref: MemoAttachments.Ref, range: Range<AttributedString.Index>, window: NSWindow?) -> [InkMenuEntry] {
        let shelf = AttachmentShelf.shared
        let offset = text.characters.distance(from: text.startIndex, to: range.lowerBound)
        let here = if case .ready = shelf.state(ref) { true } else { false }
        return [
            .item("훑어보기", detail: "Space", isEnabled: here) { [weak self] in self?.preview(ref) },
            .item("기본 앱으로 열기", isEnabled: here) { shelf.open(ref) },
            .item("Finder에서 보기", isEnabled: here) { shelf.reveal(ref) },
            .divider,
            .item("복사", isEnabled: here) { shelf.copy(ref) },
            .item("다른 이름으로 저장…", isEnabled: here) { shelf.saveAs(ref, in: window) },
            .divider,
            // Found again when picked: the letters may have changed while the menu was open.
            .item("첨부 지우기", isDanger: true) { [weak self] in
                guard let self else { return }
                let cards = MemoAttachments.attachments(in: self.text).filter { $0.ref == ref }
                let card = cards.first { self.text.characters.distance(from: self.text.startIndex, to: $0.range.lowerBound) == offset } ?? cards.first
                if let card { self.removeAttachment(card.range) }
            },
        ]
    }
}

// MARK: Drawing

/// How a card is drawn: which file, how it stands, and whether it is picked.
struct CardLook: Equatable {
    var ref: MemoAttachments.Ref
    var state: AttachmentShelf.State
    var isPicked: Bool
    /// The picture's own size, for a picture drawn as one.
    var pictureSize: CGSize?
}

/// An attachment in the memo's text view: a picture across the memo (at most 240 pt high), or a
/// one-line card. Square corners and ink lines, like the rest of the memo.
final class AttachmentCard: NSTextAttachment {
    let look: CardLook

    /// Room around the drawing for the picked outline, and the mockup's 6 pt above and below.
    static let margin: CGFloat = 4
    static let pictureMaxHeight: CGFloat = 240
    static let cardMaxWidth: CGFloat = 340
    static let cardHeight: CGFloat = 44

    init(look: CardLook) {
        self.look = look
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { nil }

    /// The drawing's size in a memo line `width` wide, the margins left out.
    static func size(of look: CardLook, width: CGFloat) -> CGSize {
        let room = max(40, width - 2 * margin)
        if let picture = look.pictureSize {
            var size = CGSize(width: room, height: room * picture.height / picture.width)
            if size.height > pictureMaxHeight { size = CGSize(width: pictureMaxHeight * picture.width / picture.height, height: pictureMaxHeight) }
            return CGSize(width: max(1, size.width.rounded()), height: max(1, size.height.rounded()))
        }
        return CGSize(width: min(cardMaxWidth, room), height: cardHeight)
    }

    private func bounds(in container: NSTextContainer?) -> CGRect {
        let width = container.map { $0.size.width - $0.lineFragmentPadding * 2 } ?? Self.cardMaxWidth
        let size = Self.size(of: look, width: width)
        // Its foot a little under the baseline, like a letter's descent, so it sits in its line.
        return CGRect(x: 0, y: -Self.margin, width: size.width + 2 * Self.margin, height: size.height + 2 * Self.margin)
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?,
                                   proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        bounds(in: textContainer)
    }

    // TextKit 2 lays an attachment out only when it offers a view; it then draws `image(for:)`.
    override func viewProvider(for parentView: NSView?, location: any NSTextLocation, textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        AttachmentCardProvider(textAttachment: self, parentView: parentView, textLayoutManager: textContainer?.textLayoutManager, location: location)
    }

    override func image(for bounds: CGRect, attributes: [NSAttributedString.Key: Any], location: any NSTextLocation,
                        textContainer: NSTextContainer?) -> NSImage? {
        guard Thread.isMainThread else { return nil }
        let view = textContainer?.textView
        let look = look, size = bounds.size
        return MainActor.assumeIsolated {
            CardArt.image(look, size: size, appearance: view?.window?.effectiveAppearance ?? NSApp.effectiveAppearance)
        }
    }
}

final class AttachmentCardProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let card = textAttachment as? AttachmentCard else { return }
        nonisolated(unsafe) let attachment = card
        nonisolated(unsafe) let provider = self
        MainActor.assumeIsolated { provider.view = AttachmentCardView(card: attachment) }
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?,
                                   proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        textAttachment?.attachmentBounds(for: attributes, location: location, textContainer: textContainer,
                                         proposedLineFragment: proposedLineFragment, position: position) ?? .zero
    }
}

/// The drawn card, in its own appearance. Clicks are taken by the memo's event watch, not here.
final class AttachmentCardView: NSView {
    let card: AttachmentCard

    init(card: AttachmentCard) {
        self.card = card
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        CardArt.image(card.look, size: bounds.size, appearance: effectiveAppearance).draw(in: bounds)
    }
}

/// The card's drawing, its colours taken from `appearance` (the window's: the text view's own can
/// lag behind a theme change).
@MainActor
enum CardArt {
    static func image(_ look: CardLook, size: CGSize, appearance: NSAppearance) -> NSImage {
        var colors = Colors()
        appearance.performAsCurrentDrawingAppearance { colors = Colors.current() }
        let shelf = AttachmentShelf.shared
        let picture = look.pictureSize != nil ? shelf.image(look.ref) : nil
        let kind = shelf.kindName(look.ref)
        return NSImage(size: size, flipped: true) { _ in
            let m = AttachmentCard.margin
            let box = CGRect(x: m, y: m, width: max(1, size.width - 2 * m), height: max(1, size.height - 2 * m))
            if let picture {
                drawPicture(picture, look: look, in: box, colors: colors)
            } else {
                drawCard(look, kind: kind, in: box, colors: colors)
            }
            if look.isPicked {
                // The mockup's 2 pt ink outline, 2 pt outside the drawing.
                let outline = NSBezierPath(rect: box.insetBy(dx: -3, dy: -3))
                outline.lineWidth = 2
                colors.ink.setStroke()
                outline.stroke()
            }
            return true
        }
    }

    struct Colors {
        var ink = NSColor.labelColor, inkSoft = NSColor.secondaryLabelColor, inkFaint = NSColor.tertiaryLabelColor
        var paper = NSColor.textBackgroundColor, shade = NSColor.separatorColor

        static func current() -> Colors {
            func c(_ color: Color) -> NSColor { NSColor(color).usingColorSpace(.sRGB) ?? .labelColor }
            return Colors(ink: c(.ink), inkSoft: c(.inkSoft), inkFaint: c(.inkFaint), paper: c(.paper), shade: c(.shade))
        }
    }

    private static func drawPicture(_ picture: NSImage, look: CardLook, in box: CGRect, colors: Colors) {
        picture.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        let frame = NSBezierPath(rect: box.insetBy(dx: Metrics.line / 2, dy: Metrics.line / 2))
        frame.lineWidth = Metrics.line
        colors.shade.setStroke()
        frame.stroke()
        // Its name and size on a paper tag at the foot.
        guard box.width > 80, box.height > 30 else { return }
        var words = look.ref.name
        if case .ready(let size) = look.state { words += " · " + MemoAttachments.sizeText(size) }
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colors.inkSoft]
        let textWidth = min((words as NSString).size(withAttributes: attributes).width, box.width - 30)
        let tag = CGRect(x: box.minX + 8, y: box.maxY - 6 - 16, width: textWidth + 12, height: 16)
        colors.paper.setFill()
        tag.fill()
        let edge = NSBezierPath(rect: tag.insetBy(dx: 0.5, dy: 0.5))
        edge.lineWidth = Metrics.line
        colors.shade.setStroke()
        edge.stroke()
        drawLine(words, in: CGRect(x: tag.minX + 6, y: tag.minY + 1, width: textWidth, height: 14), attributes: attributes)
    }

    private static func drawCard(_ look: CardLook, kind: String, in box: CGRect, colors: Colors) {
        let waiting = look.state == .waiting, missing = look.state == .missing
        colors.paper.setFill()
        box.fill()
        let edge = NSBezierPath(rect: box.insetBy(dx: Metrics.line / 2, dy: Metrics.line / 2))
        edge.lineWidth = Metrics.line
        if waiting { edge.setLineDash([4, 3], count: 2, phase: 0) }
        (waiting ? colors.inkSoft : colors.ink).setStroke()
        edge.stroke()

        // The file mark: a page with its corner folded, its kind's letters at the foot.
        let mark = CGRect(x: box.minX + 10, y: box.midY - 14, width: 22, height: 28)
        let fold: CGFloat = 7
        let page = NSBezierPath()
        page.move(to: CGPoint(x: mark.minX + 0.5, y: mark.minY + 0.5))
        page.line(to: CGPoint(x: mark.maxX - fold, y: mark.minY + 0.5))
        page.line(to: CGPoint(x: mark.maxX - 0.5, y: mark.minY + fold))
        page.line(to: CGPoint(x: mark.maxX - 0.5, y: mark.maxY - 0.5))
        page.line(to: CGPoint(x: mark.minX + 0.5, y: mark.maxY - 0.5))
        page.close()
        page.move(to: CGPoint(x: mark.maxX - fold, y: mark.minY + 0.5))
        page.line(to: CGPoint(x: mark.maxX - fold, y: mark.minY + fold))
        page.line(to: CGPoint(x: mark.maxX - 0.5, y: mark.minY + fold))
        page.lineWidth = Metrics.line
        if waiting { page.setLineDash([3, 2], count: 2, phase: 0) }
        (missing ? colors.inkFaint : waiting ? colors.inkSoft : colors.ink).setStroke()
        page.stroke()
        let badge = missing ? "?" : MemoAttachments.badge(look.ref)
        let badgeAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: badge.count > 3 ? 6.5 : 8, weight: .bold),
                                                              .foregroundColor: missing ? colors.inkFaint : waiting ? colors.inkSoft : colors.ink]
        let badgeSize = (badge as NSString).size(withAttributes: badgeAttributes)
        (badge as NSString).draw(at: CGPoint(x: mark.midX - badgeSize.width / 2, y: mark.maxY - 3 - badgeSize.height), withAttributes: badgeAttributes)

        // The name, and its kind and size (or how it stands).
        let left = mark.maxX + 10, width = max(10, box.maxX - 10 - left)
        let small: String = switch look.state {
        case .ready(let size): "\(kind) · \(MemoAttachments.sizeText(size))"
        case .waiting: "다른 기기에서 받는 중…"
        case .missing: "파일을 찾을 수 없어요 · 다른 기기에서 다시 맞춰 주세요"
        }
        drawLine(look.ref.name, in: CGRect(x: left, y: box.midY - 16, width: width, height: 18),
                 attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: waiting ? colors.inkSoft : colors.ink])
        drawLine(small, in: CGRect(x: left, y: box.midY + 2, width: width, height: 14),
                 attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: colors.inkSoft])
    }

    /// One line, cut short with … when it does not fit.
    private static func drawLine(_ words: String, in rect: CGRect, attributes: [NSAttributedString.Key: Any]) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        var attributes = attributes
        attributes[.paragraphStyle] = style
        (words as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }
}

/// A short note under the caret, gone after a moment: `25MB까지 붙일 수 있어요`.
final class MemoNoticeView: NSHostingView<MemoNotice> {
    convenience init(_ words: String) {
        self.init(rootView: MemoNotice(words: words))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct MemoNotice: View {
    let words: String

    var body: some View {
        Text(words)
            .textStyle(.small)
            .foregroundStyle(.ink)
            .padding(.horizontal, Metrics.spaceM)
            .padding(.vertical, Metrics.spaceS)
            .floatingFrame()
            .accessibilityLabel(words)
    }
}

// MARK: Dropping files

/// Files dragged from Finder onto the memo become attachments where they are let go. SwiftUI's
/// text view takes file drags itself (as their paths), so the memo's one view is given a subclass
/// of its own, made at run time as key-value observing does, that catches file drags and passes
/// every other drag on.
@MainActor
enum MemoFileDrop {
    /// What to do with files let go at a point in the text view's coordinates; nil point asks only
    /// whether they would be taken.
    private static let drops = NSMapTable<NSTextView, DropBox>.weakToStrongObjects()

    final class DropBox {
        /// False when the memo cannot take them (it could not be read).
        let take: ([URL], CGPoint) -> Bool
        init(_ take: @escaping ([URL], CGPoint) -> Bool) { self.take = take }
    }

    /// The class is swapped once per text view, and again only when something (key-value
    /// observing letting go) put it back; the handler is the latest, as the memo's host can be made anew.
    static func install(on textView: NSTextView, take: @escaping ([URL], CGPoint) -> Bool) {
        drops.setObject(DropBox(take), forKey: textView)
        let original: AnyClass = object_getClass(textView)!
        if NSStringFromClass(original).hasSuffix(suffix) { return }
        guard let subclass = subclass(of: original) else { return }
        object_setClass(textView, subclass)
    }

    private static let suffix = "_SimplifyMemoDrop"

    static func files(in info: any NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    /// Takes the drag's files; false when it carries none, so the text view handles it as usual.
    static func take(_ info: any NSDraggingInfo, in view: NSTextView) -> Bool {
        let urls = files(in: info)
        guard !urls.isEmpty, let box = drops.object(forKey: view) else { return false }
        return box.take(urls, view.convert(info.draggingLocation, from: nil))
    }

    /// The drag carries files and the memo can take them.
    static func accepts(_ info: any NSDraggingInfo, in view: NSTextView) -> Bool {
        !files(in: info).isEmpty && view.isEditable
    }

    private static func subclass(of original: AnyClass) -> AnyClass? {
        let name = NSStringFromClass(original) + suffix
        if let made = NSClassFromString(name) { return made }
        guard let made = objc_allocateClassPair(original, name, 0) else { return nil }
        typealias Operation = @convention(c) (AnyObject, Selector, AnyObject) -> NSDragOperation
        typealias Decision = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        typealias Conclusion = @convention(c) (AnyObject, Selector, AnyObject) -> Void

        func override<T>(_ selector: Selector, _ type: T.Type, _ make: (T) -> Any) {
            guard let method = class_getInstanceMethod(original, selector) else { return }
            let inherited = unsafeBitCast(method_getImplementation(method), to: type)
            class_addMethod(made, selector, imp_implementationWithBlock(make(inherited)), method_getTypeEncoding(method))
        }
        for selector in [#selector(NSView.draggingEntered(_:)), #selector(NSView.draggingUpdated(_:))] {
            override(selector, Operation.self) { inherited in
                { (view: AnyObject, info: AnyObject) -> NSDragOperation in
                    guard let info = info as? any NSDraggingInfo, !MemoFileDrop.files(in: info).isEmpty else { return inherited(view, selector, info) }
                    // Files go in as attachments, or nowhere: a memo that could not be read takes none.
                    let takes = (view as? NSTextView).map { textView in MainActor.assumeIsolated { MemoFileDrop.accepts(info, in: textView) } } ?? false
                    return takes ? .copy : []
                } as @convention(block) (AnyObject, AnyObject) -> NSDragOperation
            }
        }
        let prepare = #selector(NSView.prepareForDragOperation(_:))
        override(prepare, Decision.self) { inherited in
            { (view: AnyObject, info: AnyObject) -> Bool in
                guard let info = info as? any NSDraggingInfo, !MemoFileDrop.files(in: info).isEmpty else { return inherited(view, prepare, info) }
                return (view as? NSTextView).map { textView in MainActor.assumeIsolated { MemoFileDrop.accepts(info, in: textView) } } ?? false
            } as @convention(block) (AnyObject, AnyObject) -> Bool
        }
        let perform = #selector(NSView.performDragOperation(_:))
        override(perform, Decision.self) { inherited in
            { (view: AnyObject, info: AnyObject) -> Bool in
                guard let info = info as? any NSDraggingInfo, let textView = view as? NSTextView else { return inherited(view, perform, info) }
                // Files never reach the text view, which would put in their paths.
                guard MemoFileDrop.files(in: info).isEmpty else { return MainActor.assumeIsolated { MemoFileDrop.take(info, in: textView) } }
                return inherited(view, perform, info)
            } as @convention(block) (AnyObject, AnyObject) -> Bool
        }
        let conclude = #selector(NSView.concludeDragOperation(_:))
        override(conclude, Conclusion.self) { inherited in
            { (view: AnyObject, info: AnyObject) in
                if let info = info as? any NSDraggingInfo, !MemoFileDrop.files(in: info).isEmpty { return }
                inherited(view, conclude, info)
            } as @convention(block) (AnyObject, AnyObject) -> Void
        }
        objc_registerClassPair(made)
        return made
    }
}
