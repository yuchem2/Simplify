import AppKit
import SwiftUI
import SimplifyKit

// Tables as the memo draws them: each row's cells start at its table's column edges (tab stops
// measured over every row of that table), and the row's fragment draws the grid. A table never
// grows past the memo's width: its columns share the width, and a cell's letters past its column
// are drawn cut with `…`. The letters stay tabs and line breaks, so the store, the synced copy and
// ⌘C keep them whole.

/// How one row is drawn: its table's column edges from the text's left edge, whether it is the
/// first row (bold, with the grid's top line), the cell the caret is in, and where a cut cell's
/// `…` stands.
final class TableRowLook: NSObject {
    let edges: [CGFloat]
    let isFirst: Bool
    let caretColumn: Int?
    let ellipses: [CGFloat]
    let ellipsisFont: NSFont

    init(edges: [CGFloat], isFirst: Bool, caretColumn: Int?, ellipses: [CGFloat], ellipsisFont: NSFont) {
        self.edges = edges
        self.isFirst = isFirst
        self.caretColumn = caretColumn
        self.ellipses = ellipses
        self.ellipsisFont = ellipsisFont
    }

    var width: CGFloat { edges.last ?? 0 }
}

/// The caret in a table: its row's letters, its column, and where it is.
struct TableCaret: Equatable {
    var row: NSRange
    var column: Int
    var location: Int
}

extension MemoLineStyler {
    static let tableKey = NSAttributedString.Key(MemoAttributes.Table.name)
    /// Room on either side of a cell's letters, as in the mockup.
    nonisolated static let cellPadding: CGFloat = 10
    /// An empty column's width, so a new table has cells to click into.
    static let leastCellWidth: CGFloat = 64
    nonisolated static let ellipsis = "…"

    /// The table the line at `location` is a row of: its id and its rows (lines without breaks).
    static func table(in text: NSAttributedString, at location: Int) -> (id: String, rows: [NSRange])? {
        let string = text.string as NSString
        guard location <= string.length else { return nil }
        let line = string.lineRange(for: NSRange(location: location, length: 0))
        guard let id = rowID(text, line) else { return nil }
        var rows = [line]
        while rows[0].location > 0 {
            let above = string.lineRange(for: NSRange(location: rows[0].location - 1, length: 0))
            guard rowID(text, above) == id else { break }
            rows.insert(above, at: 0)
        }
        while let last = rows.last, NSMaxRange(last) < string.length, string.character(at: NSMaxRange(last) - 1) == 0x0A {
            let below = string.lineRange(for: NSRange(location: NSMaxRange(last), length: 0))
            guard rowID(text, below) == id else { break }
            rows.append(below)
        }
        return (id, rows.map { MemoLists.lineContent(of: $0, in: string) })
    }

    /// The table id on a line's first letter; nil for an empty line or one outside a table.
    static func rowID(_ text: NSAttributedString, _ line: NSRange) -> String? {
        guard line.length > 0, line.location < text.length, (text.string as NSString).character(at: line.location) != 0x0A else { return nil }
        return text.attribute(tableKey, at: line.location, effectiveRange: nil) as? String
    }

    /// Every table's letters in the memo, first row to last.
    static func tableSpans(in text: NSAttributedString) -> [NSRange] {
        var spans: [NSRange] = []
        var location = 0
        while location < text.length {
            if let table = table(in: text, at: location), let last = table.rows.last {
                spans.append(MemoTables.span(of: table.rows))
                location = NSMaxRange(last) + 1
            } else {
                location = NSMaxRange((text.string as NSString).lineRange(for: NSRange(location: location, length: 0)))
            }
        }
        return spans
    }

    /// How wide a table may be: the memo's line width.
    var tableWidth: CGFloat? {
        guard let container = textView?.textContainer, container.size.width > 0, container.size.width < 100_000 else { return nil }
        return container.size.width - container.lineFragmentPadding * 2
    }

    /// The column edges of a table, from 0: each column as wide as its widest cell (the first
    /// row's in bold) and its padding. Past `width` the columns share it: narrow ones keep their
    /// width and the rest split what is left evenly.
    static func tableEdges(_ text: NSAttributedString, rows: [NSRange], width: CGFloat?) -> [CGFloat] {
        let string = text.string as NSString
        var widths: [CGFloat] = []
        for (index, row) in rows.enumerated() {
            for (column, cell) in MemoTables.cellRanges(of: row, in: string).enumerated() {
                let letters = text.copiedPart(cell)
                if index == 0 { embolden(letters) }
                let width = max(leastCellWidth, ceil(letters.size().width) + 2 * cellPadding)
                if column < widths.count { widths[column] = max(widths[column], width) } else { widths.append(width) }
            }
        }
        while widths.count < MemoTables.leastColumns { widths.append(leastCellWidth) }
        if let width, widths.reduce(0, +) > width {
            widths = shared(widths, width: width)
        }
        var edges: [CGFloat] = [0]
        for width in widths { edges.append(edges[edges.count - 1] + width) }
        return edges
    }

    /// Columns fitted into `width`: those narrower than an even share keep their width, and the
    /// others split the rest evenly, in whole points.
    static func shared(_ widths: [CGFloat], width: CGFloat) -> [CGFloat] {
        var result = widths
        var open = Array(widths.indices)
        var left = width
        while !open.isEmpty {
            let share = left / CGFloat(open.count)
            let narrow = open.filter { widths[$0] <= share }
            guard !narrow.isEmpty else {
                for index in open { result[index] = floor(share) }
                break
            }
            for index in narrow { left -= widths[index] }
            open.removeAll { narrow.contains($0) }
        }
        return result
    }

    /// A table's edges, measured again only when its letters or the memo's width changed.
    func edges(of table: (id: String, rows: [NSRange]), in text: NSAttributedString) -> [CGFloat] {
        let letters = text.copiedPart(MemoTables.span(of: table.rows))
        let width = tableWidth
        if let measured = measuredTables[table.id], measured.width == width, measured.letters.isEqual(to: letters) { return measured.edges }
        let edges = Self.tableEdges(text, rows: table.rows, width: width)
        measuredTables[table.id] = (letters, width, edges)
        return edges
    }

    /// The first row's letters in the same faces' bold.
    static func embolden(_ letters: NSMutableAttributedString) {
        letters.enumerateAttribute(.font, in: NSRange(location: 0, length: letters.length)) { value, range, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: MemoStyle.size)
            letters.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: range)
        }
    }

    /// A table row as drawn: cells from the column edges (a number against its cell's right edge),
    /// never wrapped; the first row in bold; a cell too long for its column cut with `…` (the
    /// caret's cell around the caret). Nil for a line outside a table.
    func tableParagraph(_ text: NSTextStorage, _ range: NSRange, caret: TableCaret?) -> NSMutableAttributedString? {
        guard let table = Self.table(in: text, at: range.location) else { return nil }
        let string = text.string as NSString
        let row = MemoLists.lineContent(of: range, in: string)
        guard let index = table.rows.firstIndex(of: row) else { return nil }
        let edges = edges(of: table, in: text)
        // Before the cells are cut, so letters past a cell's edge lose the link's line with the rest.
        let shown = Self.dressLinks(text.copiedPart(range))
        let whole = NSRange(location: 0, length: shown.length)
        if index == 0 { Self.embolden(shown) }
        let style = ((shown.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.firstLineHeadIndent = Self.cellPadding
        style.headIndent = Self.cellPadding
        style.lineBreakMode = .byClipping
        let font = (shown.length > 0 ? shown.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil) ?? NSFont.systemFont(ofSize: MemoStyle.size)
        let ellipsisFont = index == 0 ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
        let ellipsisWidth = ceil((Self.ellipsis as NSString).size(withAttributes: [.font: ellipsisFont]).width)
        var stops: [NSTextTab] = []
        var ellipses: [CGFloat] = []
        let caretHere = caret?.row == row ? caret : nil
        for (column, cell) in MemoTables.cellRanges(of: row, in: string).enumerated() {
            let left = column < edges.count - 1 ? edges[column] : edges[edges.count - 1]
            let right = column + 1 < edges.count ? edges[column + 1] : left
            let local = NSRange(location: cell.location - range.location, length: cell.length)
            let room = max(0, right - left - 2 * Self.cellPadding)
            let cut = Self.cut(shown, local, room: room, ellipsis: ellipsisWidth,
                               caret: caretHere?.column == column ? caretHere.map { $0.location - range.location } : nil)
            if let lead = cut.lead { ellipses.append(left + Self.cellPadding + lead) }
            if let tail = cut.tail { ellipses.append(left + Self.cellPadding + tail) }
            guard column > 0 else { continue }
            if cut.lead == nil, cut.tail == nil, column + 1 < edges.count, MemoTables.isNumber(string.substring(with: cell)) {
                stops.append(NSTextTab(textAlignment: .right, location: right - Self.cellPadding))
            } else {
                stops.append(NSTextTab(textAlignment: .left, location: left + Self.cellPadding))
            }
        }
        style.tabStops = stops
        style.defaultTabInterval = Self.leastCellWidth
        shown.addAttribute(.paragraphStyle, value: style, range: whole)
        shown.addAttribute(.memoTable, value: TableRowLook(edges: edges, isFirst: index == 0, caretColumn: caretHere?.column,
                                                           ellipses: ellipses, ellipsisFont: ellipsisFont), range: whole)
        return shown
    }

    /// A cell's letters cut to `room`: those that do not fit take no room and do not show. Kept from
    /// the front, or, when the caret is past what fits, the letters just before the caret. Gives
    /// where a `…` goes before and after the shown letters, from the cell's text start.
    private static func cut(_ shown: NSMutableAttributedString, _ cell: NSRange, room: CGFloat, ellipsis: CGFloat,
                            caret: Int?) -> (lead: CGFloat?, tail: CGFloat?) {
        func width(_ from: Int, _ to: Int) -> CGFloat {
            to > from ? shown.attributedSubstring(from: NSRange(location: from, length: to - from)).size().width : 0
        }
        guard cell.length > 0, width(cell.location, NSMaxRange(cell)) > room + 0.5 else { return (nil, nil) }
        // The places between whole letters.
        var places = [cell.location]
        let letters = shown.string as NSString
        while let last = places.last, last < NSMaxRange(cell) {
            places.append(NSMaxRange(letters.rangeOfComposedCharacterSequence(at: last)))
        }
        // The most letters from `from` on that fit in `limit`.
        func fitting(from: Int, limit: CGFloat) -> Int {
            var low = places.firstIndex(of: from) ?? 0, high = places.count - 1
            while low < high {
                let middle = (low + high + 1) / 2
                if width(from, places[middle]) <= limit { low = middle } else { high = middle - 1 }
            }
            return places[low]
        }
        var start = cell.location
        var end = fitting(from: start, limit: room - ellipsis)
        if let caret, caret > end {
            // The letters before the caret, with a `…` before them and one after when more follow.
            let tail = caret < NSMaxRange(cell) ? ellipsis : 0
            let limit = room - ellipsis - tail
            var low = 0, high = places.firstIndex(of: caret) ?? places.count - 1
            while low < high {
                let middle = (low + high) / 2
                if width(places[middle], caret) <= limit { high = middle } else { low = middle + 1 }
            }
            start = places[low]
            end = caret
        }
        let gone: [NSAttributedString.Key: Any] = [.font: hiddenTableFont, .foregroundColor: NSColor.clear, .backgroundColor: NSColor.clear,
                                                    .underlineStyle: 0, .strikethroughStyle: 0]
        if start > cell.location {
            let front = NSRange(location: cell.location, length: start - cell.location)
            shown.addAttributes(gone, range: front)
            // The shown letters start after the `…`.
            shown.addAttribute(.kern, value: ellipsis, range: letters.rangeOfComposedCharacterSequence(at: start - 1))
        }
        if end < NSMaxRange(cell) { shown.addAttributes(gone, range: NSRange(location: end, length: NSMaxRange(cell) - end)) }
        let lead: CGFloat? = start > cell.location ? 0 : nil
        let shownWidth = width(start, end)
        let tail: CGFloat? = end < NSMaxRange(cell) ? (lead == nil ? 0 : ellipsis) + shownWidth : nil
        return (lead, tail)
    }

    /// Letters past a cell's edge: no room, no ink.
    private static let hiddenTableFont = NSFont.systemFont(ofSize: 0.01)
}

extension NSAttributedString.Key {
    /// A table row, as `MemoLineStyler` hands it out (`TableRowLook`); never in the memo's own text.
    static let memoTable = NSAttributedString.Key("simplify.memo.tablerow")
}

/// A table row: its letters, the 1 pt ink grid around its cells (the top line on the first row
/// only, so rows one under another share their lines), a cut cell's `…`, and a 2 pt ink box in
/// the caret's cell.
final class TableFragment: NSTextLayoutFragment {
    private var look: TableRowLook? {
        guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 else { return nil }
        return paragraph.attributedString.attribute(.memoTable, at: 0, effectiveRange: nil) as? TableRowLook
    }

    override var renderingSurfaceBounds: CGRect {
        let bounds = super.renderingSurfaceBounds
        guard let look else { return bounds }
        return bounds.union(CGRect(x: 0, y: 0, width: look.width + Metrics.line, height: layoutFragmentFrame.height))
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard let look, let first = textLineFragments.first, let last = textLineFragments.last else { return }
        // The row's left edge: its first letter stands a cell's padding in from it.
        let left = point.x + first.typographicBounds.minX + first.locationForCharacter(at: 0).x - MemoLineStyler.cellPadding
        let top = point.y + first.typographicBounds.minY
        let height = last.typographicBounds.maxY - first.typographicBounds.minY
        let line = Metrics.line
        func colors(in appearance: NSAppearance) -> (ink: CGColor, soft: CGColor) {
            var colors = (ink: NSColor.black.cgColor, soft: NSColor.gray.cgColor)
            appearance.performAsCurrentDrawingAppearance {
                colors = (NSColor(Color.ink).cgColor, NSColor(Color.inkSoft).cgColor)
            }
            return colors
        }
        // In the window's appearance: the text view's own can stay light in the dark theme.
        // The window is read on the main thread only; elsewhere the grid takes the current drawing appearance.
        let view = textLayoutManager?.textContainer?.textView
        let (ink, softInk) = Thread.isMainThread
            ? MainActor.assumeIsolated { colors(in: view?.window?.effectiveAppearance ?? NSAppearance.currentDrawing()) }
            : colors(in: NSAppearance.currentDrawing())
        let soft = NSColor(cgColor: softInk) ?? .gray
        context.setFillColor(ink)
        for (index, edge) in look.edges.enumerated() {
            let x = left + edge - (index == look.edges.count - 1 ? line : 0)
            context.fill(CGRect(x: x, y: top, width: line, height: height))
        }
        if look.isFirst { context.fill(CGRect(x: left, y: top, width: look.width, height: line)) }
        context.fill(CGRect(x: left, y: top + height - line, width: look.width, height: line))
        if let column = look.caretColumn, column + 1 < look.edges.count {
            let box = CGRect(x: left + look.edges[column], y: top, width: look.edges[column + 1] - look.edges[column], height: height)
            let ring: CGFloat = 2
            context.setStrokeColor(ink)
            context.setLineWidth(ring)
            context.stroke(box.insetBy(dx: ring / 2, dy: ring / 2))
        }
        guard !look.ellipses.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        let attributes: [NSAttributedString.Key: Any] = [.font: look.ellipsisFont, .foregroundColor: soft]
        let baseline = top + first.glyphOrigin.y
        for x in look.ellipses {
            (MemoLineStyler.ellipsis as NSString).draw(at: CGPoint(x: left + x, y: baseline - look.ellipsisFont.ascender), withAttributes: attributes)
        }
    }
}
