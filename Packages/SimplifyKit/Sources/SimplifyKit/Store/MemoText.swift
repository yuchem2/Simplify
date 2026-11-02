import Foundation

/// The formatting a memo keeps. The editor draws fonts and colours from these; only these reach
/// the store, so a paste from elsewhere loses its fonts, links and other styling.
public enum MemoAttributes {
    public enum Bold: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "simplify.memo.bold"
    }

    public enum Italic: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "simplify.memo.italic"
    }

    /// A code block: whole lines in a fixed-width face on a shaded ground.
    public enum Code: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "simplify.memo.code"
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

public extension AttributeScopes {
    struct MemoScope: AttributeScope {
        public let bold: MemoAttributes.Bold
        public let italic: MemoAttributes.Italic
        public let code: MemoAttributes.Code
        public let math: MemoAttributes.Math
        public let script: MemoAttributes.Script
        public let ink: MemoAttributes.Ink
        public let highlight: MemoAttributes.Highlight
        public let todo: MemoAttributes.Todo
        public let todoBox: MemoAttributes.TodoBox
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
public enum MemoText {
    static let version = 1

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
        return try? encoder.encode(Document(v: version, runs: runs))
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
        var k: Bool?
        var m: Bool?
        var s: String?
        var c: String?
        var h: String?
        var td: String?
        var tx: Bool?
        var tb: Bool?

        init(text: String, from run: AttributedString.Runs.Run) {
            t = text
            b = run[MemoAttributes.Bold.self] == true ? true : nil
            i = run[MemoAttributes.Italic.self] == true ? true : nil
            k = run[MemoAttributes.Code.self] == true ? true : nil
            m = run[MemoAttributes.Math.self] == true ? true : nil
            s = run[MemoAttributes.Script.self]?.rawValue
            c = run[MemoAttributes.Ink.self]?.rawValue
            // A code block has its own shaded ground.
            h = k == true ? nil : run[MemoAttributes.Highlight.self]?.rawValue
            let todo = run[MemoAttributes.Todo.self]
            td = todo?.id.uuidString
            tx = todo?.isDone == true ? true : nil
            tb = todo != nil && run[MemoAttributes.TodoBox.self] == true ? true : nil
        }

        func sameFormatting(as other: Run) -> Bool {
            b == other.b && i == other.i && k == other.k && m == other.m && s == other.s && c == other.c && h == other.h && td == other.td && tx == other.tx && tb == other.tb
        }

        var attributed: AttributedString {
            var container = AttributeContainer()
            if b == true { container[MemoAttributes.Bold.self] = true }
            if i == true { container[MemoAttributes.Italic.self] = true }
            if k == true { container[MemoAttributes.Code.self] = true }
            if m == true { container[MemoAttributes.Math.self] = true }
            container[MemoAttributes.Script.self] = s.flatMap(MemoScript.init(rawValue:))
            container[MemoAttributes.Ink.self] = c.flatMap(Palette.init(rawValue:))
            if k != true { container[MemoAttributes.Highlight.self] = h.flatMap(Palette.init(rawValue:)) }
            container[MemoAttributes.Todo.self] = td.flatMap(UUID.init(uuidString:)).map { MemoTodo(id: $0, isDone: tx == true) }
            if tb == true, container[MemoAttributes.Todo.self] != nil { container[MemoAttributes.TodoBox.self] = true }
            return AttributedString(t, attributes: container)
        }
    }
}
