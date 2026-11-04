import AppKit
import SwiftUI
import SimplifyKit

// Rules and timeline lines: how the memo draws `────` and `11.02 08:30 …` lines, and ⌃⌘T. Only the
// drawing changes; the letters stay as typed, so the store, the synced copy and the Notes mirror
// keep them (`MemoTimeline` finds the lines).

extension MemoDraft {
    /// ⌃⌘T, the format bar's 시각 and the right-click menu: `11.03 14:25 ` at the front of the
    /// caret's line, or on a new line under it when the line has words. A day memo names its own
    /// day; a week or month memo today, or the chosen day when today is outside it.
    func insertTime(now: Date = .now) {
        guard let period, !isUnreadable, let caret = selectedRanges.first?.lowerBound else {
            NSSound.beep()
            return
        }
        let calendar = period.calendar
        let day = MemoTimeline.stampDay(for: period, today: calendar.startOfDay(for: now), chosen: chosenDay ?? period.start)
        let stamp = MemoTimeline.stamp(day: day, now: now, calendar: calendar)
        let characters = text.characters
        let put = MemoTimeline.insertion(in: String(characters), caret: characters.distance(from: characters.startIndex, to: caret), stamp: stamp)
        text.transform(updating: &selection) { text in
            text.insert(AttributedString(put.text), at: text.characters.index(text.startIndex, offsetBy: put.offset))
        }
        let after = text.characters.index(text.startIndex, offsetBy: min(put.caretAfter, text.characters.count))
        selection = AttributedTextSelection(insertionPoint: after, typingAttributes: AttributeContainer())
        focusRequest += 1
    }
}

/// Draws the memo's rules, timeline lines, lists, quotes and titles in its text view, through
/// TextKit 2's own hooks: the content storage hands out each paragraph with display-only changes
/// (the time in figures and soft ink with a hanging indent; a rule's letters hidden; a list item's
/// marker by level with the words hanging after it; a quote's `>` hidden; a title's or heading's
/// line height), and the layout manager gives a rule paragraph a fragment that draws an ink line
/// across the memo instead, and a quote one that draws an ink line down its side. The storage (and
/// so the memo's text) is never touched. A rule shows its letters again while the caret is on it,
/// so it can be edited like any line.
@MainActor
final class MemoLineStyler: NSObject, NSTextContentStorageDelegate, NSTextLayoutManagerDelegate {
    /// The memo's text view, once attached.
    private(set) weak var textView: NSTextView?
    /// The rule paragraph the caret is on, shown as letters.
    private var openRule: NSRange?
    /// Whether some timeline line in the memo has a range (`08:30-09:15`), which widens the time column.
    private var hasRange = false

    /// The text view it draws for is still in a window.
    var isAttached: Bool { textView?.window != nil }

    /// Takes over the text view's paragraphs, if nothing else has.
    func attach(to textView: NSTextView) {
        guard let storage = textView.textContentStorage, let layout = textView.textLayoutManager else { return }
        if self.textView === textView, storage.delegate === self { return }
        guard storage.delegate == nil || storage.delegate === self, layout.delegate == nil || layout.delegate === self else { return }
        self.textView = textView
        storage.delegate = self
        layout.delegate = self
        update(force: true)
    }

    /// After the letters, the caret or the focus changed: paragraphs whose look changed are made again.
    func update(force: Bool = false) {
        guard let textView, let storage = textView.textContentStorage, let text = storage.textStorage else { return }
        let string = text.string
        let widened = Self.hasRange(in: string)
        var rule: NSRange?
        if textView.window?.firstResponder === textView, let caret = textView.selectedRanges.first?.rangeValue {
            let paragraph = (string as NSString).paragraphRange(for: NSRange(location: caret.location, length: 0))
            if MemoTimeline.isRule(Self.line(string, paragraph)) { rule = paragraph }
        }
        guard force || widened != hasRange || rule != openRule else { return }
        let changed: [NSRange] = force || widened != hasRange ? [NSRange(location: 0, length: text.length)] : [openRule, rule].compactMap { $0 }
        hasRange = widened
        openRule = rule
        for range in changed where NSMaxRange(range) <= text.length {
            storage.processEditing(for: text, edited: .editedAttributes, range: range, changeInLength: 0, invalidatedRange: range)
        }
    }

    // MARK: NSTextContentStorageDelegate

    // TextKit asks on the main thread, the text view's own.
    nonisolated func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        nonisolated(unsafe) let storage = textContentStorage
        nonisolated(unsafe) var made: NSTextParagraph?
        MainActor.assumeIsolated { made = paragraph(storage, range) }
        return made
    }

    private func paragraph(_ storage: NSTextContentStorage, _ range: NSRange) -> NSTextParagraph? {
        guard let text = storage.textStorage, NSMaxRange(range) <= text.length, range.length > 0 else { return nil }
        let line = Self.line(text.string, range)
        // A code block keeps its own face.
        if text.attribute(.font, at: range.location, effectiveRange: nil).map({ ($0 as? NSFont)?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true }) == true {
            return nil
        }
        // The caret as it is now: during an edit the rule's range has already moved.
        if MemoTimeline.isRule(line), !caretIsIn(range) {
            let shown = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
            let letters = NSRange(location: 0, length: (line as NSString).length)
            // Tiny and clear, so a long run of dashes never wraps; the fragment draws the line.
            shown.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 1), .backgroundColor: NSColor.clear], range: letters)
            shown.addAttribute(.memoRule, value: true, range: NSRange(location: 0, length: shown.length))
            return NSTextParagraph(attributedString: shown)
        }
        if let length = MemoTimeline.stampLength(line) {
            let shown = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
            let stamp = NSRange(location: 0, length: (String(line.prefix(length)) as NSString).length)
            let size = (text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)?.pointSize ?? MemoStyle.size
            let figures = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
            shown.addAttributes([.font: figures, .foregroundColor: NSColor(Color.inkSoft)], range: stamp)
            let width = Self.width(of: String(line.prefix(length)), font: figures)
            let column = Self.width(of: Self.hasRange(in: text.string) ? "00.00 00:00-00:00 " : "00.00 00:00 ", font: figures)
            // The space after the time stretches to the column, so every line's words start together.
            if stamp.length < (line as NSString).length {
                let space = Self.width(of: " ", font: figures)
                shown.addAttribute(.kern, value: max(0, column - width - space), range: NSRange(location: stamp.length, length: 1))
            }
            let style = ((shown.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.headIndent = column
            shown.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: shown.length))
            return NSTextParagraph(attributedString: shown)
        }
        return blockParagraph(text, range, line)
    }

    /// A list item, a quote, or a title, heading or subheading line as drawn; nil for any other.
    private func blockParagraph(_ text: NSTextStorage, _ range: NSRange, _ line: String) -> NSTextParagraph? {
        let marker = MemoLists.marker(line)
        let paragraph = Self.paragraph(text.attribute(Self.paragraphKey, at: range.location, effectiveRange: nil))
        guard marker != nil || paragraph != nil else { return nil }
        let shown = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
        let whole = NSRange(location: 0, length: shown.length)
        let style = ((shown.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        switch paragraph {
        case .title?, .heading?:
            // The title and heading tokens' own line heights, and a little room above.
            let height = paragraph == .title ? TextStyle.title.lineHeight : TextStyle.heading.lineHeight
            style.minimumLineHeight = height
            style.maximumLineHeight = height
            style.paragraphSpacingBefore = paragraph == .title ? Metrics.spaceXs : Metrics.spaceM
        case .sub?:
            style.paragraphSpacingBefore = Metrics.spaceS
        case nil:
            break
        }
        // A quote's `> ` hidden; what follows starts past the ink line, wrapped lines too.
        let quoteIndent = marker?.isQuoted == true ? Metrics.lineSpine + Metrics.spaceL : 0
        if let marker, marker.isQuoted {
            // In the memo's own face, so a heading's larger letters do not push its words out.
            let font = NSFont.systemFont(ofSize: MemoStyle.size)
            shown.addAttribute(.font, value: font, range: NSRange(location: 0, length: 2))
            shown.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(location: 0, length: 1))
            shown.addAttribute(.kern, value: max(0, quoteIndent - Self.width(of: "> ", font: font)), range: NSRange(location: 1, length: 1))
            // Soft ink, except letters given a colour of their own.
            if shown.length > 2 {
                shown.enumerateAttribute(Self.inkKey, in: NSRange(location: 2, length: shown.length - 2)) { value, part, _ in
                    if value == nil { shown.addAttribute(.foregroundColor, value: NSColor(Color.inkSoft), range: part) }
                }
            }
            style.headIndent = quoteIndent
            shown.addAttribute(.memoQuote, value: true, range: whole)
        }
        if let marker, marker.kind != .quote {
            // A tab a level; the marker, then the words from a column after it, wrapped lines too.
            style.tabStops = (1...MemoLists.maxLevel).map { NSTextTab(textAlignment: .left, location: quoteIndent + CGFloat($0) * MemoLists.levelIndent) }
            style.defaultTabInterval = MemoLists.levelIndent
            let label = NSRange(location: marker.labelOffset, length: (marker.label as NSString).length)
            let drawn = MemoLists.shownLabel(marker)
            if drawn != marker.label { shown.replaceCharacters(in: label, with: drawn) }
            let size = (shown.attribute(.font, at: label.location, effectiveRange: nil) as? NSFont)?.pointSize ?? MemoStyle.size
            let font: NSFont = switch marker.kind {
            case .number: .monospacedDigitSystemFont(ofSize: size, weight: .regular)
            // A geometric dot about half the letters' size, raised to their middle.
            case .bullet: .systemFont(ofSize: (size * Self.bulletScale).rounded())
            default: .systemFont(ofSize: size)
            }
            shown.addAttributes([.font: font, .foregroundColor: marker.quoted ? NSColor(Color.inkSoft) : NSColor(Color.ink)], range: label)
            if marker.kind == .bullet { shown.addAttribute(.baselineOffset, value: (size * Self.bulletRise).rounded(), range: label) }
            let space = NSRange(location: NSMaxRange(label), length: 1)
            // In the marker's face, so the measured column is the drawn one on a title line too.
            shown.addAttribute(.font, value: font, range: space)
            let width = Self.width(of: drawn, font: font) + Self.width(of: " ", font: font)
            let column = marker.kind == .number ? Self.numberColumn : MemoLists.levelIndent
            shown.addAttribute(.kern, value: max(0, column - width), range: space)
            style.headIndent = quoteIndent + CGFloat(marker.level) * MemoLists.levelIndent + max(column, width)
        }
        shown.addAttribute(.paragraphStyle, value: style, range: whole)
        return NSTextParagraph(attributedString: shown)
    }

    // MARK: NSTextLayoutManagerDelegate

    nonisolated func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                                       in textElement: NSTextElement) -> NSTextLayoutFragment {
        let range = textElement.elementRange
        if let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 {
            if paragraph.attributedString.attribute(.memoRule, at: 0, effectiveRange: nil) != nil {
                return RuleFragment(textElement: textElement, range: range)
            }
            if paragraph.attributedString.attribute(.memoQuote, at: 0, effectiveRange: nil) != nil {
                return QuoteFragment(textElement: textElement, range: range)
            }
        }
        return NSTextLayoutFragment(textElement: textElement, range: range)
    }

    // MARK: Helpers

    /// The focused memo's caret is inside `range` (a whole paragraph, its line break included).
    private func caretIsIn(_ range: NSRange) -> Bool {
        guard let textView, textView.window?.firstResponder === textView,
              let caret = textView.selectedRanges.first?.rangeValue else { return false }
        // The caret's own paragraph, as `update` finds it: at the end after a rule's line break it
        // is on the empty line below.
        return (textView.string as NSString).paragraphRange(for: NSRange(location: caret.location, length: 0)) == range
    }

    /// The paragraph's letters without its line break.
    private static func line(_ string: String, _ range: NSRange) -> String {
        let paragraph = (string as NSString).substring(with: range)
        return paragraph.trimmingCharacters(in: .newlines)
    }

    private static func hasRange(in string: String) -> Bool {
        string.split(separator: "\n", omittingEmptySubsequences: true).contains { MemoTimeline.stampLength($0) == 17 }
    }

    private static func width(of letters: String, font: NSFont) -> CGFloat {
        (letters as NSString).size(withAttributes: [.font: font]).width
    }

    /// A number item's marker column, a little wider than a bullet's for two figures.
    private static let numberColumn: CGFloat = 26
    /// A bullet's size and lift against its line's letters.
    private static let bulletScale: CGFloat = 0.5
    private static let bulletRise: CGFloat = 0.15

    private static let paragraphKey = NSAttributedString.Key(MemoAttributes.Paragraph.name)
    private static let inkKey = NSAttributedString.Key(MemoAttributes.Ink.name)

    /// A paragraph style as the text view keeps it.
    private static func paragraph(_ value: Any?) -> MemoParagraph? {
        if let paragraph = value as? MemoParagraph { return paragraph }
        return (value as? String).flatMap(MemoParagraph.init(rawValue:))
    }
}

extension NSAttributedString.Key {
    /// A rule paragraph, as `MemoLineStyler` hands it out; never in the memo's own text.
    static let memoRule = NSAttributedString.Key("simplify.memo.rule")
    /// A quote paragraph, likewise.
    static let memoQuote = NSAttributedString.Key("simplify.memo.quote")
}

/// A quote paragraph: its words, and a spine-weight ink line down its left side. Quote lines one
/// under another make one line.
final class QuoteFragment: NSTextLayoutFragment {
    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard let first = textLineFragments.first, let last = textLineFragments.last else { return }
        context.setFillColor(NSColor(Color.ink).cgColor)
        let top = first.typographicBounds.minY
        context.fill(CGRect(x: point.x + first.typographicBounds.minX, y: point.y + top, width: Metrics.lineSpine,
                            height: last.typographicBounds.maxY - top))
    }
}

/// A rule paragraph: a 1 pt ink line across the memo's width, in the middle of its line.
final class RuleFragment: NSTextLayoutFragment {
    private var lineWidth: CGFloat {
        guard let container = textLayoutManager?.textContainer else { return layoutFragmentFrame.width }
        return container.size.width - container.lineFragmentPadding * 2
    }

    override var renderingSurfaceBounds: CGRect {
        CGRect(x: 0, y: 0, width: max(lineWidth, layoutFragmentFrame.width), height: layoutFragmentFrame.height)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let height = textLineFragments.first?.typographicBounds.height ?? MemoStyle.lineHeight
        // Resolved in the text view's appearance, which is the current drawing one here.
        context.setFillColor(NSColor(Color.ink).cgColor)
        let y = (point.y + height / 2).rounded(.down)
        context.fill(CGRect(x: point.x, y: y, width: lineWidth, height: Metrics.line))
    }
}

/// The memo for pictures (ImageRenderer cannot draw the text view): each line as `Text`, a rule as
/// an ink line and a timeline line with its time in a figure column, as the text view draws them.
struct MemoPrint: View {
    let text: AttributedString

    var body: some View {
        let lines = MemoTodoLines.lines(in: text)
        let plain = lines.map { String(text[$0].characters) }
        let wide = plain.contains { MemoTimeline.stampLength($0) == 17 }
        let figures = Font.system(size: MemoStyle.size).monospacedDigit()
        let column = (NSString(string: wide ? "00.00 00:00-00:00 " : "00.00 00:00 ")
            .size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: MemoStyle.size, weight: .regular)]).width).rounded(.up)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { number, range in
                let letters = plain[number]
                if MemoTimeline.isRule(letters) {
                    Rectangle().fill(.ink).frame(height: Metrics.line).frame(height: MemoStyle.lineHeight)
                } else if let length = MemoTimeline.stampLength(letters) {
                    let stamp = text.characters.index(range.lowerBound, offsetBy: length)
                    let rest = stamp < range.upperBound ? text.characters.index(after: stamp) : stamp
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(String(letters.prefix(length))).font(figures).foregroundStyle(.inkSoft)
                            .frame(width: column, alignment: .leading)
                        Text(MemoStyle.rendered(AttributedString(text[rest..<range.upperBound])))
                            .lineHeight(.exact(points: MemoStyle.lineHeight))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // In a row, as the timeline lines are: a lone wrapping Text is measured a line short here.
                    HStack(alignment: .top, spacing: 0) {
                        Color.clear.frame(width: 0, height: MemoStyle.lineHeight)
                        Text(MemoStyle.rendered(AttributedString(text[range])))
                            .lineHeight(.exact(points: MemoStyle.lineHeight))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .textStyle(.memo)
        .foregroundStyle(.ink)
    }
}
