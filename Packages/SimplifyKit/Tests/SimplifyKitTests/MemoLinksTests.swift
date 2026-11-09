import Foundation
import Testing
@testable import SimplifyKit

/// Links in a memo: which addresses are taken, how they are stored, and where they go out.
struct MemoLinksTests {
    private func linked(_ letters: String, _ address: String) -> AttributedString {
        var text = AttributedString(letters)
        text[MemoAttributes.Link.self] = address
        return text
    }

    @Test func onlyWebAndMailAddressesAreTaken() {
        #expect(MemoLinks.address("https://figma.com/file/simplify-ds") == "https://figma.com/file/simplify-ds")
        #expect(MemoLinks.address("  http://example.com/a?b=c#d \n") == "http://example.com/a?b=c#d")
        #expect(MemoLinks.address("mailto:yoom@example.com") == "mailto:yoom@example.com")
        // A bare www. gets https.
        #expect(MemoLinks.address("www.apple.com/kr") == "https://www.apple.com/kr")
        // Never something that runs or opens a file, nor words.
        #expect(MemoLinks.address("javascript:alert(1)") == nil)
        #expect(MemoLinks.address("file:///etc/passwd") == nil)
        #expect(MemoLinks.address("figma.com/file") == nil)
        #expect(MemoLinks.address("https://a.com https://b.com") == nil)
        #expect(MemoLinks.address("다음 분기 계획") == nil)
        #expect(MemoLinks.address("https://") == nil)
        #expect(MemoLinks.address("mailto:") == nil)
        #expect(MemoLinks.stored("HTTPS://Example.com") == "HTTPS://Example.com")
        #expect(MemoLinks.stored("www.apple.com") == nil)
    }

    @Test func aTypedAddressLeavesTheSentencesPunctuationOut() {
        #expect(MemoLinks.typedAddress("https://developer.apple.com/documentation")?.address == "https://developer.apple.com/documentation")
        let closed = MemoLinks.typedAddress("https://apple.com).")
        #expect(closed?.address == "https://apple.com" && closed?.length == 17)
        #expect(MemoLinks.typedAddress("https://en.wikipedia.org/wiki/Swift_(language)")?.address == "https://en.wikipedia.org/wiki/Swift_(language)")
        #expect(MemoLinks.typedAddress("www.naver.com,")?.address == "https://www.naver.com")
        #expect(MemoLinks.typedAddress("www.") == nil)
        #expect(MemoLinks.typedAddress("https://") == nil)
        #expect(MemoLinks.typedAddress("apple.com") == nil)
        #expect(MemoLinks.typedAddress("ftp://files.example.com") == nil)
    }

    @Test func aLinkIsStoredWithoutRaisingTheVersion() throws {
        var text = AttributedString("발표 자료는 ")
        text += linked("디자인 시스템 문서", "https://figma.com/file/simplify-ds")
        text += AttributedString("에 있어요.")
        let data = try #require(MemoText.encode(text))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""v":1"#))
        #expect(json.contains(#""ln":"https:\/\/figma.com\/file\/simplify-ds""#))
        let back = MemoText.decode(data)
        #expect(back == text)
        let run = try #require(back.runs.first { $0[MemoAttributes.Link.self] != nil })
        #expect(String(back[run.range].characters) == "디자인 시스템 문서")
        // A link and bold over part of it: two runs, one link.
        var bold = text
        let start = bold.characters.index(bold.startIndex, offsetBy: 7)
        bold[start..<bold.characters.index(start, offsetBy: 3)][MemoAttributes.Bold.self] = true
        #expect(MemoText.decode(MemoText.encode(bold)) == bold)
    }

    @Test func anAddressNoLinkMayHoldIsDropped() throws {
        let data = Data(#"{"v":1,"runs":[{"t":"눌러","ln":"javascript:alert(1)"},{"t":" 파일","ln":"file:///etc"},{"t":" 웹","ln":"https://a.com"},{"t":" 이상","ln":42}]}"#.utf8)
        let text = MemoText.decode(data)
        #expect(String(text.characters) == "눌러 파일 웹 이상")
        #expect(text.runs.compactMap { $0[MemoAttributes.Link.self] } == ["https://a.com"])
        // And it is not written either.
        let written = String(decoding: try #require(MemoText.encode(linked("x", "javascript:alert(1)"))), as: UTF8.self)
        #expect(!written.contains("ln"))
    }

    @Test func aLinkStaysOffLineBreaksAndTableTabs() {
        let data = Data(#"{"v":1,"runs":[{"t":"한 줄\n둘\t셋","ln":"https://a.com"}]}"#.utf8)
        let text = MemoText.decode(data)
        let linkedLetters = text.runs.filter { $0[MemoAttributes.Link.self] != nil }.map { String(text[$0.range].characters) }
        #expect(linkedLetters == ["한 줄", "둘", "셋"])
    }

    @Test func theNotesCopyAndHTMLCarryAnchors() throws {
        var text = AttributedString("자료: ")
        text += linked("시안 \"최종\"", "https://figma.com/a?b=1&c=2")
        let html = try #require(NotesHTML.body(name: "11월 9일", text: text))
        #expect(html.contains(#"<a href="https://figma.com/a?b=1&amp;c=2">시안 &quot;최종&quot;</a>"#))
        var bold = linked("굵은 링크", "mailto:a@b.com")
        bold[MemoAttributes.Bold.self] = true
        #expect(NotesHTML.fragment(bold)?.contains(#"<a href="mailto:a@b.com"><b>굵은 링크</b></a>"#) == true)
    }

    @Test func aPastedTableKeepsItsCellsLinks() {
        let cell = MemoTablePaste.Cell("Figma 시안 · 패널", links: [.init(letters: "Figma 시안", address: "https://figma.com/x"),
                                                                    .init(letters: "패널", address: "javascript:void(0)")])
        let text = MemoTablePaste.table([[MemoTablePaste.Cell("자료"), cell]], id: "t1")
        let linkedLetters = text.runs.filter { $0[MemoAttributes.Link.self] != nil }.map { String(text[$0.range].characters) }
        #expect(linkedLetters == ["Figma 시안"])
        #expect(text.runs.allSatisfy { $0[MemoAttributes.Table.self] == "t1" })
        // The memo's own copy keeps `ln` through the clipboard.
        let back = MemoTablePaste.unclip(MemoTablePaste.clip(text)!, newID: { "t2" })
        #expect(back?.runs.compactMap { $0[MemoAttributes.Link.self] } == ["https://figma.com/x"])
    }
}
