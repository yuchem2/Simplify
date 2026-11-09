import Foundation

/// The formatting a memo keeps. The editor draws fonts and colours from these; only these reach
/// the store, so a paste from elsewhere loses its fonts and other styling (its links are turned
/// into `Link` when their address is one `MemoLinks` takes).
public enum MemoAttributes {
    public enum Bold: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "simplify.memo.bold"
    }

    public enum Italic: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "simplify.memo.italic"
    }

    public enum Underline: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "simplify.memo.underline"
    }

    /// Struck-through letters, set by hand; a done ToDo chip's line is its own and not this.
    public enum Strike: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "simplify.memo.strike"
    }

    /// A title, heading or subheading: whole lines, like a code block.
    public enum Paragraph: CodableAttributedStringKey {
        public typealias Value = MemoParagraph
        public static let name = "simplify.memo.paragraph"
    }

    /// A code block: whole lines in a fixed-width face on a shaded ground.
    public enum Code: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "simplify.memo.code"
    }

    /// Inline code: picked letters within a line in a fixed-width face on a shaded ground. Not a
    /// code block, so it is never widened to the whole line.
    public enum InlineCode: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "simplify.memo.inlinecode"
    }

    /// A line set in the middle or to the right: whole lines, like a paragraph style. Left, the
    /// usual, has none.
    public enum Align: CodableAttributedStringKey {
        public typealias Value = MemoAlign
        public static let name = "simplify.memo.align"
    }

    /// A table row: the line's cells split by tab letters, every row of one table under its id.
    /// Whole lines, like a paragraph style.
    public enum Table: CodableAttributedStringKey {
        public typealias Value = String
        public static let name = "simplify.memo.table"
    }

    /// An attached file: the one placeholder letter (`MemoAttachments.placeholder`) that stands
    /// for it, its value `<id>/<original name>`, the file's place under `Attachments/`.
    public enum Attachment: CodableAttributedStringKey {
        public typealias Value = String
        public static let name = "simplify.memo.attachment"
    }

    /// Formula lettering: an italic serif.
    public enum Math: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "simplify.memo.math"
    }

    /// Raised or lowered small letters.
    public enum Script: CodableAttributedStringKey {
        public typealias Value = MemoScript
        public static let name = "simplify.memo.script"
    }

    /// Text colour, by palette name so it is redrawn in the dark theme's value.
    public enum Ink: CodableAttributedStringKey {
        public typealias Value = Palette
        public static let name = "simplify.memo.ink"
    }

    /// Highlighter, by palette name.
    public enum Highlight: CodableAttributedStringKey {
        public typealias Value = Palette
        public static let name = "simplify.memo.highlight"
    }

    /// A ToDo chip: `□ 제목` letters that stand for the ToDo with this id (stage 6).
    public enum Todo: CodableAttributedStringKey {
        public typealias Value = MemoTodo
        public static let name = "simplify.memo.todo"
    }

    /// The box letter at the front of a chip, drawn larger so it is easy to click.
    public enum TodoBox: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "simplify.memo.todobox"
    }

    /// A link: the letters open this address on ⌘-click. Only http, https and mailto addresses
    /// (`MemoLinks.address`); never on line breaks or a table's cell-splitting tabs.
    public enum Link: CodableAttributedStringKey {
        public typealias Value = String
        public static let name = "simplify.memo.link"
    }
}

/// Which ToDo a chip stands for, and whether it was done when the chip was last drawn. The ToDo
/// itself is the truth; chips are brought up to date whenever the memo opens.
public struct MemoTodo: Codable, Hashable, Sendable {
    public var id: UUID
    public var isDone: Bool

    public init(id: UUID, isDone: Bool) {
        self.id = id
        self.isDone = isDone
    }
}

public enum MemoScript: String, Codable, Hashable, Sendable {
    case raised, lowered
}

/// A line set in the middle or to the right; left lines have none.
public enum MemoAlign: String, Codable, Hashable, Sendable, CaseIterable {
    case center, right
}

/// A line's paragraph style; plain body lines have none.
public enum MemoParagraph: String, Codable, Hashable, Sendable, CaseIterable {
    case title, heading, sub
}

public extension AttributeScopes {
    struct MemoScope: AttributeScope {
        public let bold: MemoAttributes.Bold
        public let italic: MemoAttributes.Italic
        public let underline: MemoAttributes.Underline
        public let strike: MemoAttributes.Strike
        public let paragraph: MemoAttributes.Paragraph
        public let code: MemoAttributes.Code
        public let inlineCode: MemoAttributes.InlineCode
        public let align: MemoAttributes.Align
        public let table: MemoAttributes.Table
        public let attachment: MemoAttributes.Attachment
        public let math: MemoAttributes.Math
        public let script: MemoAttributes.Script
        public let ink: MemoAttributes.Ink
        public let highlight: MemoAttributes.Highlight
        public let todo: MemoAttributes.Todo
        public let todoBox: MemoAttributes.TodoBox
        /// Not `link`, which Foundation's own scope holds.
        public let memoLink: MemoAttributes.Link
    }

    var memo: MemoScope.Type { MemoScope.self }
}

public extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.MemoScope, T>) -> T {
        self[T.self]
    }
}

/// How a memo is written into `DiaryNote.body`: JSON runs of text with the formatting above.
///
/// `{"v":1,"runs":[{"t":"견적서","b":true,"c":"red","h":"yellow"},{"t":" 보내기"}]}`
/// Colours are palette names; a name this version does not know is dropped, as is any other
/// attribute. Neighbouring runs with the same formatting are joined. A ToDo chip's run carries
/// `"td"` (the ToDo's id) and `"tx":true` once done, and its box letter `"tb":true`; older
/// versions ignore these and keep the text.
///
/// Version 2 adds `"u":true` (underline), `"x":true` (struck through) and `"p"` (`title`,
/// `heading` or `sub`). A memo using none of them is still written as version 1, so a Mac with an
/// older version keeps reading it; one that does is version 2, which older versions leave unread.
/// A table row's letters carry `"tl"` (its table's id), which makes the memo version 2; its cells
/// are split by tab letters, so a version 2 build that does not know the key shows the rows as
/// lines of tab-split words.
/// An attached file is one placeholder letter carrying `"fa"` (`<id>/<original name>`), which
/// makes the memo version 2 too; a build that does not know the key shows the bare letter.
/// Lists and quotes are letters (`• `, `- `, `1. `, `> `) and need no key.
/// A centred or right-set line carries `"al"` (`center` or `right`) and inline code `"kc":true`.
/// Neither raises the version: a build that does not know them skips the key, as unknown keys
/// always were, and shows the letters left-set and plain.
/// A link's letters carry `"ln"` (its address), which does not raise the version either: an
/// older build shows them as plain letters (and drops the link if it saves the memo). An address
/// `MemoLinks` would not take (`javascript:`, `file:` …) is dropped on reading and writing.
public enum MemoText {
    static let version = 2

    public static func encode(_ text: AttributedString) -> Data? {
        guard !isBlank(text) else { return nil }
        var runs: [Run] = []
        for run in text.runs {
            var item = Run(text: String(text[run.range].characters), from: run)
            if let last = runs.last, last.sameFormatting(as: item) {
                item.t = last.t + item.t
                runs.removeLast()
            }
            runs.append(item)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let needsTwo = runs.contains { $0.u != nil || $0.x != nil || $0.p != nil || $0.tl != nil || $0.fa != nil }
        return try? encoder.encode(Document(v: needsTwo ? version : 1, runs: runs))
    }

    /// An empty memo for missing or unreadable data.
    public static func decode(_ data: Data?) -> AttributedString {
        guard let data, let document = try? JSONDecoder().decode(Document.self, from: data) else { return AttributedString() }
        var text = AttributedString()
        for run in document.runs {
            text.append(run.attributed)
        }
        return text
    }

    /// Like `decode`, but nil for data that is there and cannot be read (a newer format, or
    /// damage), so callers can leave it untouched instead of saving over it.
    public static func decodeIfReadable(_ data: Data?) -> AttributedString? {
        guard let data else { return AttributedString() }
        guard let document = try? JSONDecoder().decode(Document.self, from: data), document.v <= version else { return nil }
        return decode(data)
    }

    /// Nothing but spaces and line breaks: the memo is deleted rather than kept.
    public static func isBlank(_ text: AttributedString) -> Bool {
        text.characters.allSatisfy(\.isWhitespace)
    }

    private struct Document: Codable {
        var v: Int
        var runs: [Run]
    }

    private struct Run: Codable {
        var t: String
        var b: Bool?
        var i: Bool?
        var u: Bool?
        var x: Bool?
        var p: String?
        var tl: String?
        var fa: String?
        var k: Bool?
        var kc: Bool?
        var al: String?
        var m: Bool?
        var s: String?
        var c: String?
        var h: String?
        var td: String?
        var tx: Bool?
        var tb: Bool?
        var ln: String?

        private enum CodingKeys: String, CodingKey {
            case t, b, i, u, x, p, tl, fa, k, kc, al, m, s, c, h, td, tx, tb, ln
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            t = try c.decode(String.self, forKey: .t)
            b = try c.decodeIfPresent(Bool.self, forKey: .b)
            i = try c.decodeIfPresent(Bool.self, forKey: .i)
            // Keys version 1 did not know: a value of another type under them is left out rather
            // than making the memo unreadable, as unknown keys always were.
            u = (try? c.decodeIfPresent(Bool.self, forKey: .u)) ?? nil
            x = (try? c.decodeIfPresent(Bool.self, forKey: .x)) ?? nil
            p = (try? c.decodeIfPresent(String.self, forKey: .p)) ?? nil
            tl = (try? c.decodeIfPresent(String.self, forKey: .tl)) ?? nil
            fa = (try? c.decodeIfPresent(String.self, forKey: .fa)) ?? nil
            k = try c.decodeIfPresent(Bool.self, forKey: .k)
            kc = (try? c.decodeIfPresent(Bool.self, forKey: .kc)) ?? nil
            al = (try? c.decodeIfPresent(String.self, forKey: .al)) ?? nil
            m = try c.decodeIfPresent(Bool.self, forKey: .m)
            s = try c.decodeIfPresent(String.self, forKey: .s)
            self.c = try c.decodeIfPresent(String.self, forKey: .c)
            h = try c.decodeIfPresent(String.self, forKey: .h)
            td = try c.decodeIfPresent(String.self, forKey: .td)
            tx = try c.decodeIfPresent(Bool.self, forKey: .tx)
            tb = try c.decodeIfPresent(Bool.self, forKey: .tb)
            ln = ((try? c.decodeIfPresent(String.self, forKey: .ln)) ?? nil).flatMap(MemoLinks.stored)
        }

        init(text: String, from run: AttributedString.Runs.Run) {
            t = text
            b = run[MemoAttributes.Bold.self] == true ? true : nil
            i = run[MemoAttributes.Italic.self] == true ? true : nil
            u = run[MemoAttributes.Underline.self] == true ? true : nil
            x = run[MemoAttributes.Strike.self] == true ? true : nil
            p = run[MemoAttributes.Paragraph.self]?.rawValue
            tl = run[MemoAttributes.Table.self]
            fa = run[MemoAttributes.Attachment.self]
            k = run[MemoAttributes.Code.self] == true ? true : nil
            // Inside a code block it is the block.
            kc = k == nil && run[MemoAttributes.InlineCode.self] == true ? true : nil
            al = run[MemoAttributes.Align.self]?.rawValue
            m = run[MemoAttributes.Math.self] == true ? true : nil
            s = run[MemoAttributes.Script.self]?.rawValue
            c = run[MemoAttributes.Ink.self]?.rawValue
            // A code block has its own shaded ground.
            h = k == true || kc == true ? nil : run[MemoAttributes.Highlight.self]?.rawValue
            let todo = run[MemoAttributes.Todo.self]
            td = todo?.id.uuidString
            tx = todo?.isDone == true ? true : nil
            tb = todo != nil && run[MemoAttributes.TodoBox.self] == true ? true : nil
            ln = run[MemoAttributes.Link.self].flatMap(MemoLinks.stored)
        }

        func sameFormatting(as other: Run) -> Bool {
            b == other.b && i == other.i && u == other.u && x == other.x && p == other.p && tl == other.tl && fa == other.fa && k == other.k && kc == other.kc && al == other.al && m == other.m && s == other.s && c == other.c && h == other.h && td == other.td && tx == other.tx && tb == other.tb && ln == other.ln
        }

        var attributed: AttributedString {
            var container = AttributeContainer()
            if b == true { container[MemoAttributes.Bold.self] = true }
            if i == true { container[MemoAttributes.Italic.self] = true }
            if u == true { container[MemoAttributes.Underline.self] = true }
            if x == true { container[MemoAttributes.Strike.self] = true }
            container[MemoAttributes.Paragraph.self] = p.flatMap(MemoParagraph.init(rawValue:))
            if let tl, !tl.isEmpty { container[MemoAttributes.Table.self] = tl }
            // Only a well-formed value on the placeholder letter, below.
            let attachment = fa.flatMap(MemoAttachments.Ref.init(value:))
            if k == true { container[MemoAttributes.Code.self] = true }
            if kc == true, k != true { container[MemoAttributes.InlineCode.self] = true }
            container[MemoAttributes.Align.self] = al.flatMap(MemoAlign.init(rawValue:))
            if m == true { container[MemoAttributes.Math.self] = true }
            container[MemoAttributes.Script.self] = s.flatMap(MemoScript.init(rawValue:))
            container[MemoAttributes.Ink.self] = c.flatMap(Palette.init(rawValue:))
            if k != true, kc != true { container[MemoAttributes.Highlight.self] = h.flatMap(Palette.init(rawValue:)) }
            container[MemoAttributes.Todo.self] = td.flatMap(UUID.init(uuidString:)).map { MemoTodo(id: $0, isDone: tx == true) }
            if tb == true, container[MemoAttributes.Todo.self] != nil { container[MemoAttributes.TodoBox.self] = true }
            container[MemoAttributes.Link.self] = ln
            var text = AttributedString(t, attributes: container)
            // A table's mark stays off line breaks, which belong to no row.
            if container[MemoAttributes.Table.self] != nil {
                for index in text.characters.indices where text.characters[index].isNewline {
                    text[index..<text.characters.index(after: index)][MemoAttributes.Table.self] = nil
                }
            }
            if let ln {
                // Off line breaks and a table's cell-splitting tabs, which belong to no link.
                for index in text.characters.indices where !MemoLinks.canCarry(text.characters[index]) {
                    text[index..<text.characters.index(after: index)][MemoAttributes.Link.self] = nil
                }
            }
            if let attachment {
                for index in text.characters.indices where text.characters[index] == MemoAttachments.placeholder {
                    text[index..<text.characters.index(after: index)][MemoAttributes.Attachment.self] = attachment.value
                }
            }
            return text
        }
    }
}
