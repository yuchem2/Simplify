import Foundation

/// The addresses a memo's links may hold, and finding one in typed or pasted letters.
///
/// Only http, https and mailto: a link is opened on ⌘-click, so an address that would run
/// something (`javascript:`) or open a file on this Mac (`file:`) is never made a link, and one
/// read from a memo or a paste is dropped.
public enum MemoLinks {
    public static let schemes: Set<String> = ["http", "https", "mailto"]

    /// `typed` as a link's address: trimmed, `https://` put before a bare `www.…`, and nil for
    /// anything else that is not one whole http, https or mailto address (spaces inside, another
    /// scheme, no host).
    public static func address(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
        let lower = trimmed.lowercased()
        let full = lower.hasPrefix("www.") ? "https://" + trimmed : trimmed
        return stored(full)
    }

    /// `value` if it is an address a link may keep, else nil. For addresses already made (stored,
    /// pasted from a web page), so nothing is added in front.
    public static func stored(_ value: String) -> String? {
        guard !value.contains(where: { $0.isWhitespace || $0.isNewline }),
              let url = URL(string: value), let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else { return nil }
        if scheme == "mailto" {
            let rest = value.dropFirst("mailto:".count)
            return rest.isEmpty ? nil : value
        }
        // http and https need a host past `//`.
        guard let host = url.host(), !host.isEmpty, value.lowercased().hasPrefix(scheme + "://") else { return nil }
        return value
    }

    /// A letter a link may be on: not a line break, nor a table's cell-splitting tab.
    public static func canCarry(_ letter: Character) -> Bool {
        !letter.isNewline && letter != "\t"
    }

    /// The address a typed word stands for, for links made as the word is finished (a space or
    /// Return after it): one starting `http://`, `https://`, `mailto:` or `www.`, without the
    /// closing punctuation that usually follows an address in a sentence (`.`, `,`, `)` …). The
    /// address and how many letters (UTF-16) of the word it covers, from the word's start.
    public static func typedAddress(_ word: String) -> (address: String, length: Int)? {
        let lower = word.lowercased()
        guard ["http://", "https://", "mailto:", "www."].contains(where: { lower.hasPrefix($0) }) else { return nil }
        var letters = Substring(word)
        let closing: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}", "'", "\"", "’", "”", "。", "、"]
        while let last = letters.last, closing.contains(last) {
            // A `)` that closes one opened inside the address stays (`wiki/Swift_(language)`).
            if last == ")", letters.filter({ $0 == "(" }).count >= letters.filter({ $0 == ")" }).count { break }
            letters = letters.dropLast()
        }
        guard let address = address(String(letters)), address != "https://www." else { return nil }
        // Something after `www.` or the scheme.
        guard letters.count > (lower.hasPrefix("www.") ? 4 : lower.hasPrefix("mailto:") ? 7 : lower.hasPrefix("https://") ? 8 : 7) else { return nil }
        return (address, (String(letters) as NSString).length)
    }
}
