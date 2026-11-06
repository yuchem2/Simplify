import Foundation
import Testing
@testable import SimplifyKit

/// Centred and right-set lines, and inline code: saved, read back, synced and sent to the 메모 app;
/// a list's inset stays the memo's own drawing.
struct MemoAlignCodeTests {
    private func styled(_ string: String, _ build: (inout AttributeContainer) -> Void = { _ in }) -> AttributedString {
        var container = AttributeContainer()
        build(&container)
        return AttributedString(string, attributes: container)
    }

    private func json(_ text: AttributedString) throws -> String {
        String(decoding: try #require(MemoText.encode(text)), as: UTF8.self)
    }

    @Test func alignmentIsSavedAndReadBackWithoutANewVersion() throws {
        var text = styled("가운데") { $0[MemoAttributes.Align.self] = .center }
        text += styled("\n")
        text += styled("오른쪽") { $0[MemoAttributes.Align.self] = .right }
        let saved = try json(text)
        #expect(saved.contains(#""al":"center""#) && saved.contains(#""al":"right""#))
        // Nothing an older build cannot read: still version 1.
        #expect(saved.contains(#""v":1"#))
        #expect(MemoText.decodeIfReadable(MemoText.encode(text)) == text)
    }

    @Test func inlineCodeIsSavedAndReadBackWithoutANewVersion() throws {
        var text = styled("설치는 ")
        text += styled("install.sh") { $0[MemoAttributes.InlineCode.self] = true }
        text += styled(" 로 해요")
        let saved = try json(text)
        #expect(saved.contains(#""kc":true"#) && saved.contains(#""v":1"#))
        #expect(MemoText.decodeIfReadable(MemoText.encode(text)) == text)
    }

    @Test func inlineCodeHasNoHighlighterAndGivesWayToACodeBlock() throws {
        let marked = styled("x") {
            $0[MemoAttributes.InlineCode.self] = true
            $0[MemoAttributes.Highlight.self] = .yellow
        }
        #expect(!(try json(marked)).contains(#""h""#))
        let both = styled("x") {
            $0[MemoAttributes.InlineCode.self] = true
            $0[MemoAttributes.Code.self] = true
        }
        let saved = try json(both)
        #expect(saved.contains(#""k":true"#) && !saved.contains(#""kc""#))
    }

    @Test func anOlderBuildSkipsTheNewKeys() throws {
        // A build that does not know `al` or `kc` reads the letters and its own keys.
        let data = Data(#"{"v":1,"runs":[{"t":"제목","al":"center","b":true},{"t":"코드","kc":true}]}"#.utf8)
        let text = try #require(MemoText.decodeIfReadable(data))
        #expect(String(text.characters) == "제목코드")
        // Values of another type under the new keys are left out, not the memo.
        let odd = Data(#"{"v":1,"runs":[{"t":"줄","al":3,"kc":"yes"}]}"#.utf8)
        #expect(String(try #require(MemoText.decodeIfReadable(odd)).characters) == "줄")
        let unknown = Data(#"{"v":1,"runs":[{"t":"줄","al":"justified"}]}"#.utf8)
        #expect(try #require(MemoText.decodeIfReadable(unknown)).runs.allSatisfy { $0[MemoAttributes.Align.self] == nil })
    }

    @Test func syncKeepsAlignmentAndInlineCodeWhenJoining() throws {
        var top = styled("위") { $0[MemoAttributes.Align.self] = .center }
        top += styled(" ")
        top += styled("코드") { $0[MemoAttributes.InlineCode.self] = true }
        let bottom = styled("아래") { $0[MemoAttributes.Align.self] = .right }
        let upper = try #require(MemoText.encode(top))
        let lower = try #require(MemoText.encode(bottom))
        let joined = try #require(SyncMerge.joined(upper, under: lower))
        let text = MemoText.decode(joined)
        #expect(text.runs.contains { $0[MemoAttributes.Align.self] == .center && String(text[$0.range].characters) == "위" })
        #expect(text.runs.contains { $0[MemoAttributes.Align.self] == .right && String(text[$0.range].characters) == "아래" })
        #expect(text.runs.contains { $0[MemoAttributes.InlineCode.self] == true && String(text[$0.range].characters) == "코드" })
    }

    @Test func notesGetTextAlignAndFixedWidthLetters() throws {
        var text = styled("가운데") { $0[MemoAttributes.Align.self] = .center }
        text += styled("\n")
        text += styled("제목") {
            $0[MemoAttributes.Align.self] = .right
            $0[MemoAttributes.Paragraph.self] = .title
        }
        text += styled("\n설치는 ")
        text += styled("install.sh") {
            $0[MemoAttributes.InlineCode.self] = true
            $0[MemoAttributes.Highlight.self] = .yellow
        }
        let html = try #require(NotesHTML.body(name: "이름", text: text))
        #expect(html.contains(#"<div style="text-align: center">가운데</div>"#))
        #expect(html.contains(#"<div style="text-align: right"><h2>제목</h2></div>"#))
        #expect(html.contains("<div>설치는 <tt>install.sh</tt></div>"))
        #expect(!html.contains("background-color"))
    }

    @Test func listLinesStayLeftAndCarryNoInsetToNotes() throws {
        // An aligned list item (from before it became one) is sent left, as the memo draws it.
        var text = styled("• 하나") { $0[MemoAttributes.Align.self] = .center }
        text += styled("\n\t• 둘\n위")
        let html = try #require(NotesHTML.body(name: "이름", text: text))
        #expect(!html.contains("text-align"))
        #expect(!html.contains("padding") && !html.contains("margin"))
        #expect(html.contains("<ul>\n<li>하나</li>\n<ul>\n<li>둘</li>\n</ul>\n</ul>"))
    }
}
