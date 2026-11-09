import Foundation

/// Files attached to memos (stage 4 of memo formatting). In the memo an attachment is one
/// placeholder letter carrying `MemoAttributes.Attachment`, whose value `<id>/<original name>`
/// is also the file's place in the attachment folder (`AttachmentStore`).
public enum MemoAttachments {
    /// The letter that stands for an attachment in a memo's text.
    public static let placeholder: Character = "\u{FFFC}"
    /// The largest file that can be attached: 25 MB, as Finder counts.
    public static let limit: Int64 = 25_000_000
    public static let limitMessage = "25MB까지 붙일 수 있어요"

    /// One attachment as a memo names it.
    public struct Ref: Hashable, Sendable {
        /// A UUID string, the attachment's own folder.
        public var id: String
        /// The file's original name, which it keeps inside that folder.
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }

        /// From a stored `<id>/<name>`; nil when the id is not a UUID or the name is empty or
        /// holds a slash (it must stay one file inside the folder).
        public init?(value: String) {
            guard let slash = value.firstIndex(of: "/") else { return nil }
            let id = String(value[..<slash]), name = String(value[value.index(after: slash)...])
            guard UUID(uuidString: id) != nil, !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return nil }
            self.id = id
            self.name = name
        }

        public var value: String { "\(id)/\(name)" }

        /// The name's extension, lower case, or "" without one.
        public var fileExtension: String { (name as NSString).pathExtension.lowercased() }
    }

    /// Every attachment in the text, each placeholder letter on its own.
    public static func attachments(in text: AttributedString) -> [(range: Range<AttributedString.Index>, ref: Ref)] {
        var found: [(range: Range<AttributedString.Index>, ref: Ref)] = []
        for (value, range) in text.runs[MemoAttributes.Attachment.self] {
            guard let value, let ref = Ref(value: value) else { continue }
            var index = range.lowerBound
            while index < range.upperBound {
                let next = text.characters.index(after: index)
                if text.characters[index] == placeholder { found.append((index..<next, ref)) }
                index = next
            }
        }
        return found
    }

    public static func ids(in text: AttributedString) -> Set<String> {
        Set(attachments(in: text).map(\.ref.id))
    }

    /// Letters that carry the attachment mark but are not its placeholder (typed against it), or
    /// whose mark cannot be read: they lose the mark.
    public static func strays(in text: AttributedString) -> RangeSet<AttributedString.Index> {
        var strays = RangeSet<AttributedString.Index>()
        for (value, range) in text.runs[MemoAttributes.Attachment.self] {
            guard let value else { continue }
            guard Ref(value: value) != nil else {
                strays.insert(contentsOf: range)
                continue
            }
            var index = range.lowerBound
            while index < range.upperBound {
                let next = text.characters.index(after: index)
                if text.characters[index] != placeholder { strays.insert(contentsOf: index..<next) }
                index = next
            }
        }
        return strays
    }

    /// Placeholder letters with no attachment (pasted from elsewhere, or left after one was
    /// unmarked): they stand for nothing and go.
    public static func loosePlaceholders(in text: AttributedString) -> RangeSet<AttributedString.Index> {
        var loose = RangeSet<AttributedString.Index>()
        for (value, range) in text.runs[MemoAttributes.Attachment.self] where value == nil {
            var index = range.lowerBound
            while index < range.upperBound {
                let next = text.characters.index(after: index)
                if text.characters[index] == placeholder { loose.insert(contentsOf: index..<next) }
                index = next
            }
        }
        return loose
    }

    /// What an attachment reads as outside the memo: in the 메모 app's copy and on the clipboard.
    public static func label(_ ref: Ref) -> String { "📎 \(ref.name)" }

    /// The memo as plain text: attachments as `📎 name`, formulas in `$…$` (`MemoMath.plainText`).
    public static func plainText(_ text: AttributedString) -> String {
        let found = attachments(in: text)
        // Without the invisible marks that keep lines plain (`MemoLists.plainMark`).
        guard !found.isEmpty else { return MemoLists.withoutPlainMarks(MemoMath.plainText(text)) }
        var text = text
        for item in found.reversed() {
            text.replaceSubrange(item.range, with: AttributedString(label(item.ref)))
        }
        return MemoLists.withoutPlainMarks(MemoMath.plainText(text))
    }

    /// The ids the stored memos use, or nil when one cannot be read: it may use any, so nothing
    /// is cleared away.
    public static func referenced(byBodies bodies: [Data?]) -> Set<String>? {
        var ids: Set<String> = []
        for body in bodies {
            guard let text = MemoText.decodeIfReadable(body) else { return nil }
            ids.formUnion(self.ids(in: text))
        }
        return ids
    }

    /// `248KB`, `1.4MB`: a file's size as the card shows it.
    public static func sizeText(_ bytes: Int64) -> String {
        if bytes < 1000 { return "\(bytes)B" }
        if bytes < 1_000_000 { return "\(Int((Double(bytes) / 1000).rounded()))KB" }
        let units = ["MB", "GB", "TB"]
        var value = Double(bytes) / 1_000_000
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let rounded = (value * 10).rounded() / 10
        return (rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)) + units[unit]
    }

    /// The few letters on a card's file mark: `PDF`, `XLS`, `ZIP`.
    public static func badge(_ ref: Ref) -> String {
        let ext = ref.fileExtension
        if ext.isEmpty { return "FILE" }
        return badges[ext] ?? String(ext.uppercased().prefix(4))
    }

    private static let badges: [String: String] = [
        "xlsx": "XLS", "xlsm": "XLS", "docx": "DOC", "pptx": "PPT", "numbers": "NUM", "pages": "PAGE", "jpeg": "JPG", "markdown": "MD",
    ]

    // MARK: Clearing away

    /// An attachment no memo uses, waiting to be removed.
    public struct Pending: Codable, Hashable, Sendable {
        /// When it was first found unused.
        public var since: Date
        /// The run of the app that found it.
        public var launch: String

        public init(since: Date, launch: String) {
            self.since = since
            self.launch = launch
        }
    }

    /// How long an unused attachment waits within the run that found it: undo can still bring
    /// back the letter that used it. The next run removes it at once (undo starts afresh).
    public static let grace: TimeInterval = 30 * 60

    /// Which stored attachments to remove now, and which wait. One in use again stops waiting.
    public static func sweep(stored: Set<String>, referenced: Set<String>, pending: [String: Pending],
                             launch: String, now: Date) -> (remove: Set<String>, pending: [String: Pending]) {
        var remove: Set<String> = []
        var waiting: [String: Pending] = [:]
        for id in stored where !referenced.contains(id) {
            if let found = pending[id] {
                if found.launch != launch || now.timeIntervalSince(found.since) >= grace { remove.insert(id) } else { waiting[id] = found }
            } else {
                waiting[id] = Pending(since: now, launch: launch)
            }
        }
        return (remove, waiting)
    }
}
