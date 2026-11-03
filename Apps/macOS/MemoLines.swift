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

/// Draws the memo's rules and timeline lines in its text view, through TextKit 2's own hooks: the
/// content storage hands out each paragraph with display-only changes (the time in figures and
/// soft ink with a hanging indent; a rule's letters hidden), and the layout manager gives a rule
/// paragraph a fragment that draws an ink line across the memo instead. The storage (and so the
/// memo's text) is never touched. A rule shows its letters again while the caret is on it, so it
/// can be edited like any line.
@MainActor
final class MemoLineStyler: NSObject, NSTextContentStorageDelegate, NSTextLayoutManagerDelegate {
    private weak var textView: NSTextView?
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
        return nil
    }

    // MARK: NSTextLayoutManagerDelegate

    nonisolated func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                                       in textElement: NSTextElement) -> NSTextLayoutFragment {
        let range = textElement.elementRange
        if let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0,
           paragraph.attributedString.attribute(.memoRule, at: 0, effectiveRange: nil) != nil {
            return RuleFragment(textElement: textElement, range: range)
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
}

extension NSAttributedString.Key {
    /// A rule paragraph, as `MemoLineStyler` hands it out; never in the memo's own text.
    static let memoRule = NSAttributedString.Key("simplify.memo.rule")
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
