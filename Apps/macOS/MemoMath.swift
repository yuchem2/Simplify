import AppKit
import SwiftUI
import SwiftMath
import SimplifyKit

// Formulas: a memo's `m` letters and `$$ ` lines read as LaTeX and drawn by SwiftMath (CoreText,
// in the app). `MemoLineStyler` puts the drawing in place of the letters while the caret is
// elsewhere; the letters themselves are never changed.

/// A formula typeset from its LaTeX, or why it cannot be.
@MainActor
enum FormulaPicture {
    struct Shape {
        var width: CGFloat
        var ascent: CGFloat
        var descent: CGFloat
        var height: CGFloat { ascent + descent }
    }

    /// What the LaTeX typesets to at `size`, or the reason it cannot, in words for the memo.
    static func shape(_ latex: String, size: CGFloat, display: Bool) -> Result<Shape, Unreadable> {
        label(latex, size: size, display: display).map { label in
            let descent = label.displayList?.descent ?? 0
            return Shape(width: label.frame.width, ascent: label.frame.height - descent, descent: descent)
        }
    }

    /// The formula drawn in `color`, its baseline `shape.descent` above the image's foot.
    static func image(_ latex: String, size: CGFloat, display: Bool, color: NSColor) -> NSImage? {
        let rgba = color.usingColorSpace(.sRGB).map { "\($0.redComponent),\($0.greenComponent),\($0.blueComponent),\($0.alphaComponent)" } ?? "\(color)"
        let key = "\(display ? "D" : "T")\(size)|\(rgba)|\(latex)"
        if let image = images[key] { return image }
        guard case .success(let label) = label(latex, size: size, display: display) else { return nil }
        let image = NSImage(size: label.frame.size, flipped: false) { _ in
            // The label is shared by every colour of the formula.
            label.textColor = color
            label.draw(label.bounds)
            return true
        }
        if images.count > 400 { images.removeAll() }
        images[key] = image
        return image
    }

    /// Why the LaTeX cannot be read, or nil when it can; at any size.
    static func unreadableReason(_ latex: String) -> String? {
        if let known = reasons[latex] { return known.isEmpty ? nil : known }
        let reason = if case .failure(let unreadable) = typeset(latex, size: 16, display: false) { unreadable.reason } else { "" }
        if reasons.count > 400 { reasons.removeAll() }
        reasons[latex] = reason
        return reason.isEmpty ? nil : reason
    }

    /// Each LaTeX's reason, empty when it reads.
    private static var reasons: [String: String] = [:]

    struct Unreadable: Error {
        var reason: String
    }

    private static var labels: [String: Result<MTMathUILabel, Unreadable>] = [:]
    private static var images: [String: NSImage] = [:]

    private static func label(_ latex: String, size: CGFloat, display: Bool) -> Result<MTMathUILabel, Unreadable> {
        let key = "\(display ? "D" : "T")\(size)|\(latex)"
        if let made = labels[key] { return made }
        let made = typeset(latex, size: size, display: display)
        if labels.count > 400 { labels.removeAll() }
        labels[key] = made
        return made
    }

    private static func typeset(_ latex: String, size: CGFloat, display: Bool) -> Result<MTMathUILabel, Unreadable> {
        // SwiftMath drops letters its fonts lack (Korean among them, `\text{원}` too) without a
        // word. Each stands in as a Cyrillic letter, which it keeps as an ordinary symbol, and is
        // put back once read; CoreText then draws it in a face that has it.
        var stand: [Character: Character] = [:]
        var back: [String: String] = [:]
        var spare = standIns.filter { !latex.contains($0) }.makeIterator()
        var read = ""
        for character in latex {
            if character.isASCII || MTMathAtomFactory.atom(forCharacter: character) != nil {
                read.append(character)
            } else if let known = stand[character] {
                read.append(known)
            } else if let next = spare.next() {
                stand[character] = next
                back[String(next)] = String(character)
                read.append(next)
            } else {
                return .failure(Unreadable(reason: "글자가 너무 여러 가지예요"))
            }
        }
        var error: NSError?
        guard let list = MTMathListBuilder.build(fromString: read, error: &error), error == nil else {
            return .failure(Unreadable(reason: reason(error)))
        }
        if !back.isEmpty { visit(list) { atom in if let letter = back[atom.nucleus] { atom.nucleus = letter } } }
        let label = MTMathUILabel()
        label.labelMode = display ? .display : .text
        label.textAlignment = .left
        label.fontSize = size
        label.mathList = list
        // Laid out against a wide frame once to measure, then against its own size, which puts
        // its baseline `descent` up from the foot.
        label.frame = CGRect(x: 0, y: 0, width: 4000, height: 400)
        label.layout()
        guard let measured = label.displayList else { return .failure(Unreadable(reason: "그릴 수 없는 수식이에요")) }
        // SwiftMath centres anything shorter than half the size in that much height, so the frame
        // is at least that tall and the baseline stays `descent` up from its foot.
        label.frame = CGRect(x: 0, y: 0, width: max(1, ceil(measured.width)), height: max(1, ceil(max(measured.ascent + measured.descent, size / 2))))
        label.layout()
        return .success(label)
    }

    /// SwiftMath's parse errors in the memo's words; the command itself where it names one.
    private static func reason(_ error: NSError?) -> String {
        let message = error?.localizedDescription ?? ""
        switch error?.code {
        case 1: return "{ }의 짝이 맞지 않아요"
        case 2:
            let command = message.split(separator: " ").last.map(String.init) ?? ""
            return command.hasPrefix("\\") ? "\(command)는 모르는 명령이에요" : "모르는 명령이 있어요"
        case 3: return message.contains("{") || message.contains("}") ? "{ }가 빠졌어요" : "쓸 수 없는 글자가 있어요"
        case 4, 5: return "괄호 명령 뒤에 괄호가 없거나 맞지 않아요"
        case 6: return "\\left에 짝이 되는 \\right가 없어요"
        case 7: return "\\right 앞에 \\left가 없어요"
        case 8, 9, 10, 11: return "\\begin과 \\end가 맞지 않아요"
        case 12: return "표의 칸 수가 맞지 않아요"
        case 14: return "\\limits는 합·적분 같은 기호 뒤에만 써요"
        default: return "LaTeX로 읽을 수 없어요"
        }
    }

    /// Letters SwiftMath keeps as they are: Cyrillic.
    private static let standIns = Array("абвгдежзийклмнопрстуфхцчшщъыьэюяАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ")

    private static func visit(_ list: MTMathList?, _ body: (MTMathAtom) -> Void) {
        guard let list else { return }
        for atom in list.atoms {
            body(atom)
            visit(atom.subScript, body)
            visit(atom.superScript, body)
            switch atom {
            case let atom as MTFraction: visit(atom.numerator, body); visit(atom.denominator, body)
            case let atom as MTRadical: visit(atom.radicand, body); visit(atom.degree, body)
            case let atom as MTInner: visit(atom.innerList, body)
            case let atom as MTOverLine: visit(atom.innerList, body)
            case let atom as MTUnderLine: visit(atom.innerList, body)
            case let atom as MTAccent: visit(atom.innerList, body)
            case let atom as MTMathColor: visit(atom.innerList, body)
            case let atom as MTMathTextColor: visit(atom.innerList, body)
            case let atom as MTMathColorbox: visit(atom.innerList, body)
            case let atom as MTMathTable: atom.cells.forEach { $0.forEach { visit($0, body) } }
            default: break
            }
        }
    }
}

/// A formula in the memo's text view: stands for its first letter while its LaTeX is hidden. It
/// is drawn in the text view's appearance each time, so a theme change recolours it.
final class FormulaAttachment: NSTextAttachment {
    let latex: String
    let size: CGFloat
    let isDisplay: Bool
    let shape: FormulaPicture.Shape
    /// Its letters' colour, by palette name; nil for ink.
    let ink: Palette?

    init(latex: String, size: CGFloat, isDisplay: Bool, shape: FormulaPicture.Shape, ink: Palette?) {
        self.latex = latex
        self.size = size
        self.isDisplay = isDisplay
        self.shape = shape
        self.ink = ink
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?,
                                   proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        CGRect(x: 0, y: -shape.descent, width: shape.width, height: shape.height)
    }

    // TextKit 2 lays an attachment out only when it offers a view; it then draws `image(for:)`.
    override func viewProvider(for parentView: NSView?, location: any NSTextLocation, textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        FormulaViewProvider(textAttachment: self, parentView: parentView, textLayoutManager: textContainer?.textLayoutManager, location: location)
    }

    override func image(for bounds: CGRect, attributes: [NSAttributedString.Key: Any], location: any NSTextLocation,
                        textContainer: NSTextContainer?) -> NSImage? {
        // TextKit keeps the image; the memo's paragraphs are made again when the appearance changes.
        // Drawn for the text view only; never off the main thread (where SwiftMath's views cannot be).
        guard Thread.isMainThread else { return nil }
        let view = textContainer?.textView
        let latex = latex, size = size, display = isDisplay, ink = ink
        return MainActor.assumeIsolated {
            var color = NSColor.labelColor
            // The window's: the text view's own can lag behind a theme change.
            (view?.window?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
                color = (ink.map { NSColor($0.ink) } ?? NSColor(Color.ink)).usingColorSpace(.sRGB) ?? .labelColor
            }
            return FormulaPicture.image(latex, size: size, display: display, color: color)
        }
    }
}

/// The view TextKit asks a `FormulaAttachment` for.
final class FormulaViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? FormulaAttachment else { return }
        nonisolated(unsafe) let formula = attachment
        nonisolated(unsafe) let provider = self
        MainActor.assumeIsolated {
            provider.view = FormulaView(attachment: formula)
        }
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?,
                                   proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        guard let attachment = textAttachment as? FormulaAttachment else { return .zero }
        return CGRect(x: 0, y: -attachment.shape.descent, width: attachment.shape.width, height: attachment.shape.height)
    }
}

/// A drawn formula in its letters' colour, as its own appearance has it. Clicks go to the text.
final class FormulaView: NSView {
    let attachment: FormulaAttachment

    init(attachment: FormulaAttachment) {
        self.attachment = attachment
        super.init(frame: CGRect(x: 0, y: 0, width: attachment.shape.width, height: attachment.shape.height))
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        var color = NSColor.labelColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = (attachment.ink.map { NSColor($0.ink) } ?? NSColor(Color.ink)).usingColorSpace(.sRGB) ?? .labelColor
        }
        FormulaPicture.image(attachment.latex, size: attachment.size, display: attachment.isDisplay, color: color)?.draw(in: bounds)
    }
}

/// A hover tip's words.
final class FormulaTip: NSObject, NSViewToolTipOwner {
    let text: String

    init(text: String) {
        self.text = text
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        text
    }
}

/// Under the formula being written: the formula as it will be drawn, why it cannot be, or a hint
/// while it is empty. It only shows; clicks go through to the text.
final class FormulaPeekView: NSHostingView<FormulaPeek> {
    convenience init() {
        self.init(rootView: FormulaPeek(latex: "", isDisplay: false, ink: nil))
    }

    func show(latex: String, isDisplay: Bool, ink: Palette?) {
        rootView = FormulaPeek(latex: latex, isDisplay: isDisplay, ink: ink)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct FormulaPeek: View {
    let latex: String
    let isDisplay: Bool
    let ink: Palette?

    var body: some View {
        Group {
            if latex.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("LaTeX로 수식을 써요 · Esc로 끝내요")
                    .textStyle(.small)
                    .foregroundStyle(.inkSoft)
            } else {
                switch FormulaPicture.shape(latex, size: isDisplay ? 19 : 16, display: isDisplay) {
                case .success:
                    // Drawn black and tinted here, so the theme's ink applies.
                    if let image = FormulaPicture.image(latex, size: isDisplay ? 19 : 16, display: isDisplay, color: .black) {
                        Image(nsImage: image)
                            .renderingMode(.template)
                            .foregroundStyle(ink?.ink ?? Tokens.ink)
                    }
                case .failure(let unreadable):
                    VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
                        Text("수식을 읽을 수 없어요").textStyle(.small).foregroundStyle(.ink)
                        Text(unreadable.reason).textStyle(.small).foregroundStyle(.inkSoft)
                    }
                }
            }
        }
        .padding(.horizontal, Metrics.spaceM)
        .padding(.vertical, Metrics.spaceS)
        .floatingFrame()
        .accessibilityHidden(true)
    }
}

extension MemoDraft {
    /// ⌥⌘E and the format bar's fx. Picked letters become a formula, or plain letters again when
    /// they all are one. With only a caret: the formula being written turns back into its letters;
    /// right after a drawn one, that one opens; anywhere else an empty formula starts and what is
    /// typed next is its LaTeX.
    func toggleFormula() {
        guard !isUnreadable else { return }
        if hasSelectedText {
            toggle(MemoAttributes.Math.self)
            return
        }
        guard case .insertionPoint(let caret) = selection.indices(in: text) else { return }
        if let open = openFormula?(), let range = Range(open, in: text), !range.isEmpty {
            // A formula line is its `$$ `, which is taken off by hand.
            if String(text[range].characters).hasPrefix(MemoMath.displayMark) {
                NSSound.beep()
                return
            }
            text.transform(updating: &selection) { $0[range][MemoAttributes.Math.self] = nil }
            dropFormulaTyping()
            return
        }
        change { $0[MemoAttributes.Math.self] = true }
        startFormula?(String(text[text.startIndex..<caret].characters).utf16.count)
        focusRequest += 1
    }

    /// The caret types plain letters, not more of the formula before it.
    func dropFormulaTyping() {
        guard case .insertionPoint(let caret) = selection.indices(in: text) else { return }
        var typing = selection.typingAttributes(in: text)
        guard typing[MemoAttributes.Math.self] == true else { return }
        typing[MemoAttributes.Math.self] = nil
        selection = AttributedTextSelection(insertionPoint: caret, typingAttributes: typing)
    }
}
