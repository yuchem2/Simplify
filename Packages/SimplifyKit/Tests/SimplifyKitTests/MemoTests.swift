import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import SimplifyKit

@MainActor
struct MemoTests {
    let cal = PeriodTests.calendar()

    private func styled(_ string: String, _ build: (inout AttributeContainer) -> Void) -> AttributedString {
        var container = AttributeContainer()
        build(&container)
        return AttributedString(string, attributes: container)
    }

    @Test func formattingSurvivesTheRoundTrip() throws {
        var text = AttributedString("다음 주까지 ")
        text += styled("견적서") { $0[MemoAttributes.Bold.self] = true; $0[MemoAttributes.Ink.self] = .red; $0[MemoAttributes.Highlight.self] = .yellow }
        text += styled(" 최종본") { $0[MemoAttributes.Italic.self] = true }
        text += AttributedString(" 보내기\n")
        text += styled("brew upgrade") { $0[MemoAttributes.Code.self] = true }
        text += AttributedString("\n")
        text += styled("w = 0.9w") { $0[MemoAttributes.Math.self] = true }
        text += styled("0") { $0[MemoAttributes.Math.self] = true; $0[MemoAttributes.Script.self] = .lowered }

        let back = MemoText.decode(try #require(MemoText.encode(text)))
        #expect(back == text)
        let bold = try #require(back.runs.first { $0[MemoAttributes.Bold.self] == true })
        #expect(String(back[bold.range].characters) == "견적서")
        #expect(bold[MemoAttributes.Ink.self] == .red)
        #expect(bold[MemoAttributes.Highlight.self] == .yellow)
    }

    @Test func otherAttributesAreDropped() throws {
        var text = AttributedString("링크와 글꼴")
        text.link = URL(string: "https://example.com")
        text.font = .system(size: 30)
        text.foregroundColor = .green
        text[MemoAttributes.Bold.self] = true

        let back = MemoText.decode(try #require(MemoText.encode(text)))
        #expect(back.runs.count == 1)
        let run = try #require(back.runs.first)
        #expect(run.link == nil)
        #expect(run.font == nil)
        #expect(run.foregroundColor == nil)
        #expect(run[MemoAttributes.Bold.self] == true)
    }

    @Test func codeBlocksKeepNoHighlight() throws {
        let text = styled("let x = 1") { $0[MemoAttributes.Code.self] = true; $0[MemoAttributes.Highlight.self] = .pink }
        let back = MemoText.decode(try #require(MemoText.encode(text)))
        #expect(back.runs.first?[MemoAttributes.Highlight.self] == nil)
        #expect(back.runs.first?[MemoAttributes.Code.self] == true)
    }

    @Test func unknownColourNamesAndBadDataAreIgnored() {
        let json = #"{"v":1,"runs":[{"t":"가","c":"gold","h":"blue","x":1},{"t":"나"}]}"#
        let text = MemoText.decode(Data(json.utf8))
        #expect(String(text.characters) == "가나")
        #expect(text.runs.first?[MemoAttributes.Ink.self] == nil)
        #expect(text.runs.first?[MemoAttributes.Highlight.self] == .blue)
        #expect(MemoText.decode(Data("not json".utf8)) == AttributedString())
        #expect(MemoText.decode(nil) == AttributedString())
    }

    @Test func unreadableBodiesAreToldApart() {
        #expect(MemoText.decodeIfReadable(nil) == AttributedString())
        #expect(MemoText.decodeIfReadable(Data("not json".utf8)) == nil)
        #expect(MemoText.decodeIfReadable(Data(#"{"v":3,"runs":[{"t":"새 형식"}]}"#.utf8)) == nil)
        #expect(MemoText.decodeIfReadable(MemoText.encode(AttributedString("가"))).map { String($0.characters) } == "가")
    }

    @Test func underlineStrikeAndParagraphsSurviveTheRoundTrip() throws {
        var text = styled("11월 정리") { $0[MemoAttributes.Paragraph.self] = .title }
        text += AttributedString("\n")
        text += styled("밑줄") { $0[MemoAttributes.Underline.self] = true }
        text += styled(" 지운 말") { $0[MemoAttributes.Strike.self] = true }
        text += AttributedString("\n")
        text += styled("회의") { $0[MemoAttributes.Paragraph.self] = .heading }
        text += AttributedString("\n")
        text += styled("결정") { $0[MemoAttributes.Paragraph.self] = .sub; $0[MemoAttributes.Bold.self] = true }
        let data = try #require(MemoText.encode(text))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""p":"title""#) && json.contains(#""p":"heading""#) && json.contains(#""p":"sub""#))
        #expect(json.contains(#""u":true"#) && json.contains(#""x":true"#))
        #expect(MemoText.decode(data) == text)
        #expect(MemoText.decodeIfReadable(data) == text)
    }

    /// Version 2 is written only for the new keys: older builds keep reading every other memo,
    /// and leave a version 2 memo unread (they read only `v` up to 1).
    @Test func versionTwoOnlyForTheNewKeys() throws {
        func version(_ text: AttributedString) throws -> Int {
            let data = try #require(MemoText.encode(text))
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            return try #require(object["v"] as? Int)
        }
        // Lists and quotes are letters.
        #expect(try version(AttributedString("• 하나\n1. 둘\n> 셋")) == 1)
        #expect(try version(styled("굵게") { $0[MemoAttributes.Bold.self] = true }) == 1)
        #expect(try version(styled("밑줄") { $0[MemoAttributes.Underline.self] = true }) == 2)
        #expect(try version(styled("취소") { $0[MemoAttributes.Strike.self] = true }) == 2)
        #expect(try version(styled("제목") { $0[MemoAttributes.Paragraph.self] = .heading }) == 2)
    }

    @Test func versionOneMemosStillRead() {
        let json = #"{"v":1,"runs":[{"t":"예전 ","b":true},{"t":"메모","c":"blue"}]}"#
        let text = MemoText.decodeIfReadable(Data(json.utf8))
        #expect(text.map { String($0.characters) } == "예전 메모")
        #expect(text?.runs.first?[MemoAttributes.Bold.self] == true)
    }

    @Test func badValuesUnderTheNewKeysAreDropped() {
        let json = #"{"v":2,"runs":[{"t":"가","u":"yes","p":"poster"},{"t":"나","x":true}]}"#
        let text = MemoText.decode(Data(json.utf8))
        #expect(String(text.characters) == "가나")
        #expect(text.runs.first?[MemoAttributes.Underline.self] == nil)
        #expect(text.runs.first?[MemoAttributes.Paragraph.self] == nil)
        #expect(text.runs.last?[MemoAttributes.Strike.self] == true)
    }

    @Test func neighbouringRunsWithTheSameFormattingJoin() throws {
        let text = AttributedString("하나") + AttributedString("둘")
        let data = try #require(MemoText.encode(text))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json == #"{"runs":[{"t":"하나둘"}],"v":1}"#)
    }

    @Test func blankTextEncodesToNothing() {
        #expect(MemoText.encode(AttributedString()) == nil)
        #expect(MemoText.encode(AttributedString(" \n\t")) == nil)
    }

    @Test func saveMakesUpdatesAndDeletesTheNote() throws {
        let container = try SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let day = Period(containing: PeriodTests.date(2026, 10, 26, in: cal), scope: .day, calendar: cal)
        let first = Date(timeIntervalSince1970: 1_000)

        #expect(try Memos.save(AttributedString(""), for: day, in: context) == false)
        #expect(try context.fetch(FetchDescriptor<DiaryNote>()).isEmpty)

        #expect(try Memos.save(AttributedString("워크숍 준비"), for: day, in: context, now: first))
        #expect(String(try Memos.text(for: day, in: context).characters) == "워크숍 준비")

        // Saving the same text keeps the old time.
        try Memos.save(AttributedString("워크숍 준비"), for: day, in: context, now: first.addingTimeInterval(60))
        #expect(try Memos.note(for: day, in: context)?.updatedAt == first)

        try Memos.save(AttributedString("워크숍 준비 끝"), for: day, in: context, now: first.addingTimeInterval(120))
        #expect(try Memos.note(for: day, in: context)?.updatedAt == first.addingTimeInterval(120))

        #expect(try Memos.save(AttributedString("  \n"), for: day, in: context) == false)
        #expect(try context.fetch(FetchDescriptor<DiaryNote>()).isEmpty)
    }

    @Test func duplicateNotesFoldIntoTheNewest() throws {
        let container = try SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let day = Period(containing: PeriodTests.date(2026, 10, 26, in: cal), scope: .day, calendar: cal)
        for (offset, body) in ["옛 메모", "새 메모"].enumerated() {
            let note = DiaryNote(period: day)
            note.body = MemoText.encode(AttributedString(body))
            note.updatedAt = Date(timeIntervalSince1970: Double(offset) * 100)
            context.insert(note)
        }
        try context.save()

        #expect(String(try Memos.text(for: day, in: context).characters) == "새 메모")
        try Memos.save(AttributedString("새 메모 고침"), for: day, in: context)
        #expect(try context.fetch(FetchDescriptor<DiaryNote>()).count == 1)
    }

    @Test func dayWeekAndMonthMemosAreKeptApart() throws {
        let container = try SimplifyStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let date = PeriodTests.date(2026, 10, 26, in: cal)
        let day = Period(containing: date, scope: .day, calendar: cal)
        let week = Period(containing: date, scope: .week, calendar: cal)
        let month = Period(containing: date, scope: .month, calendar: cal)
        try Memos.save(AttributedString("하루"), for: day, in: context)
        try Memos.save(AttributedString("한 주"), for: week, in: context)
        try Memos.save(AttributedString("한 달"), for: month, in: context)

        #expect(try Memos.keys(in: context) == ["2026-10-26", "2026-W44", "2026-10"])
        #expect(String(try Memos.text(for: week, in: context).characters) == "한 주")
        #expect(String(try Memos.text(for: month, in: context).characters) == "한 달")
        #expect(try Memos.text(for: day.advanced(by: 1), in: context) == AttributedString())

        try Memos.save(AttributedString(), for: week, in: context)
        #expect(try Memos.keys(in: context) == ["2026-10-26", "2026-10"])
    }
}
