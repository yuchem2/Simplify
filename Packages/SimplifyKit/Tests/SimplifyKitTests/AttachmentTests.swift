import Foundation
import Testing
@testable import SimplifyKit

/// Attached files: how a memo stores them, clearing away the unused, and keeping them in step
/// between devices (`AttachmentSync`).
struct AttachmentTests {
    private let id = "0E5B7C2A-1111-4222-8333-944455556666"
    private let other = "1F6C8D3B-2222-4333-9444-A55566667777"

    private func attachment(_ value: String) -> AttributedString {
        var container = AttributeContainer()
        container[MemoAttributes.Attachment.self] = value
        return AttributedString(String(MemoAttachments.placeholder), attributes: container)
    }

    // MARK: Stored

    @Test func anAttachmentIsSavedAsFaOnItsPlaceholderAndReadBack() throws {
        let text = AttributedString("자료\n") + attachment("\(id)/견적서_v3.pdf") + AttributedString("\n끝")
        let data = try #require(MemoText.encode(text))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""fa":"\#(id)\/견적서_v3.pdf""#) || json.contains(#""fa":"\#(id)/견적서_v3.pdf""#))
        #expect(json.contains(#""v":2"#))
        let back = MemoText.decode(data)
        #expect(back == text)
        let found = MemoAttachments.attachments(in: back)
        #expect(found.map(\.ref) == [MemoAttachments.Ref(id: id, name: "견적서_v3.pdf")])
        #expect(MemoAttachments.ids(in: back) == [id])
    }

    @Test func faStaysApartFromTheTodoBoxAndTableKeys() throws {
        var row = AttributeContainer()
        row[MemoAttributes.Table.self] = "t1"
        var chip = AttributeContainer()
        chip[MemoAttributes.Todo.self] = MemoTodo(id: UUID(), isDone: false)
        chip[MemoAttributes.TodoBox.self] = true
        let text = AttributedString("가\t나", attributes: row) + AttributedString("\n") + AttributedString("□", attributes: chip)
            + AttributedString("\n") + attachment("\(id)/a.png")
        let back = MemoText.decode(MemoText.encode(text))
        #expect(back == text)
        #expect(back.runs.filter { $0[MemoAttributes.Attachment.self] != nil }.count == 1)
    }

    @Test func aMarkThatCannotBeReadOrOnOtherLettersIsDropped() {
        // Not a UUID, a name with a slash, or another type: the letter stays, the mark goes.
        for bad in [#""fa":"abc/x.pdf""#, #""fa":"\#(id)/a/b""#, #""fa":3"#, #""fa":"\#(id)/""#] {
            let text = MemoText.decode(Data(#"{"v":2,"runs":[{"t":"\#(MemoAttachments.placeholder)",\#(bad)}]}"#.utf8))
            #expect(String(text.characters) == String(MemoAttachments.placeholder))
            #expect(MemoAttachments.attachments(in: text).isEmpty, "\(bad)")
        }
        // Read on its placeholder only, not on letters that shared the run.
        let mixed = MemoText.decode(Data(#"{"v":2,"runs":[{"t":"가\#(MemoAttachments.placeholder)나","fa":"\#(id)/a.pdf"}]}"#.utf8))
        #expect(mixed.runs.compactMap { $0[MemoAttributes.Attachment.self] != nil ? String(mixed[$0.range].characters) : nil } == [String(MemoAttachments.placeholder)])
    }

    @Test func namesNeverLeaveTheAttachmentFolder() throws {
        // Stored values that would climb out are not attachments at all.
        for bad in ["\(id)/../x", "\(id)/..", "\(id)/.", "../\(id)/x", "\(id)//x"] {
            #expect(MemoAttachments.Ref(value: bad) == nil, "\(bad)")
        }
        // A file's own name is made one plain file name when it comes in.
        let root = FileManager.default.temporaryDirectory.appending(path: "attach-names-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AttachmentStore(root: root.appending(path: "Attachments"))
        for name in ["../../etc/passwd", "..", ".hidden", "a:b.txt", ""] {
            let ref = try store.add(data: Data("x".utf8), name: name)
            let url = store.url(for: ref).standardizedFileURL.path
            #expect(url.hasPrefix(store.root.standardizedFileURL.path + "/\(ref.id)/"), "\(name) → \(url)")
            #expect(!ref.name.contains("/") && !ref.name.hasPrefix(".") && MemoAttachments.Ref(value: ref.value) == ref, "\(name) → \(ref.name)")
        }
    }

    @Test func lettersTypedAgainstAnAttachmentAreStrays() {
        var text = attachment("\(id)/a.pdf")
        var typed = AttributeContainer()
        typed[MemoAttributes.Attachment.self] = "\(id)/a.pdf"
        text += AttributedString("글", attributes: typed)
        let strays = MemoAttachments.strays(in: text)
        #expect(String(text[strays].characters) == "글")
        let loose = AttributedString("앞\(MemoAttachments.placeholder)뒤")
        #expect(String(loose[MemoAttachments.loosePlaceholders(in: loose)].characters) == String(MemoAttachments.placeholder))
    }

    @Test func plainTextNamesTheFileAfterAClip() {
        var math = AttributeContainer()
        math[MemoAttributes.Math.self] = true
        let text = AttributedString("보기 ") + attachment("\(id)/견적서_v3.pdf") + AttributedString(" 그리고 ") + AttributedString("x^2", attributes: math)
        #expect(MemoAttachments.plainText(text) == "보기 📎 견적서_v3.pdf 그리고 $x^2$")
    }

    @Test func sizesAndBadgesReadAsTheCardShowsThem() {
        #expect(MemoAttachments.sizeText(512) == "512B")
        #expect(MemoAttachments.sizeText(248_000) == "248KB")
        #expect(MemoAttachments.sizeText(1_400_000) == "1.4MB")
        #expect(MemoAttachments.sizeText(25_000_000) == "25MB")
        #expect(MemoAttachments.badge(.init(id: id, name: "예산_2026Q4.xlsx")) == "XLS")
        #expect(MemoAttachments.badge(.init(id: id, name: "견적서_v3.pdf")) == "PDF")
        #expect(MemoAttachments.badge(.init(id: id, name: "README")) == "FILE")
    }

    // MARK: Clearing away

    @Test func unusedAttachmentsWaitWithinTheRunAndGoAfter() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        // First found unused: it waits.
        var result = MemoAttachments.sweep(stored: [id, other], referenced: [other], pending: [:], launch: "A", now: now)
        #expect(result.remove.isEmpty && Set(result.pending.keys) == [id])
        // Still within the grace, same run: still waits.
        result = MemoAttachments.sweep(stored: [id, other], referenced: [other], pending: result.pending, launch: "A", now: now + 60)
        #expect(result.remove.isEmpty)
        // Undo brought it back: it stops waiting.
        let back = MemoAttachments.sweep(stored: [id, other], referenced: [id, other], pending: result.pending, launch: "A", now: now + 120)
        #expect(back.remove.isEmpty && back.pending.isEmpty)
        // After the grace, or in the next run: removed.
        #expect(MemoAttachments.sweep(stored: [id], referenced: [], pending: result.pending, launch: "A", now: now + MemoAttachments.grace).remove == [id])
        #expect(MemoAttachments.sweep(stored: [id], referenced: [], pending: result.pending, launch: "B", now: now + 1).remove == [id])
    }

    @Test func unreadableMemosKeepEveryAttachment() {
        let good = MemoText.encode(attachment("\(id)/a.pdf"))
        #expect(MemoAttachments.referenced(byBodies: [good, nil]) == [id])
        #expect(MemoAttachments.referenced(byBodies: [good, Data(#"{"v":9,"runs":[]}"#.utf8)]) == nil)
    }

    @Test func theStoreCopiesRefusesTooLargeAndClearsWithAMark() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "attach-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AttachmentStore(root: root.appending(path: "Attachments"))
        let source = root.appending(path: "견적서_v3.pdf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2048).write(to: source)
        let ref = try store.add(copying: source)
        #expect(ref.name == "견적서_v3.pdf" && store.exists(ref) && store.size(ref) == 2048)
        #expect(store.ids() == [ref.id])

        let big = root.appending(path: "큰파일.bin")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(MemoAttachments.limit + 1))
        try handle.close()
        #expect(throws: AttachmentStore.Failure.tooLarge) { try store.add(copying: big) }

        // Unused: waits in this run, then goes and leaves its mark.
        let now = Date()
        #expect(store.sweep(referenced: [], launch: "A", now: now).isEmpty)
        #expect(store.exists(ref))
        #expect(store.sweep(referenced: [], launch: "B", now: now) == [ref.id])
        #expect(!store.exists(ref) && store.marks() == [ref.id] && store.ids().isEmpty)
        // A memo that cannot be read keeps everything.
        let kept = try store.add(data: Data("x".utf8), name: "붙여넣은 이미지.png")
        #expect(store.sweep(referenced: nil, launch: "C", now: now).isEmpty && store.exists(kept))
    }

    // MARK: Between devices

    @Test func usedFilesGoUpAndComeDown() {
        let plan = AttachmentSync.plan(referenced: [id, other], local: [id], localMarks: [], remote: [other], remoteMarks: [])
        #expect(plan.upload == [id] && plan.download == [other])
        #expect(plan.removeLocal.isEmpty && plan.removeRemote.isEmpty && plan.markLocal.isEmpty && plan.markRemote.isEmpty)
    }

    @Test func aMarkClearsTheFileEverywhereNoMemoUsesIt() {
        // Cleared here: the sync folder's copy goes and is marked.
        var plan = AttachmentSync.plan(referenced: [], local: [], localMarks: [id], remote: [id], remoteMarks: [])
        #expect(plan.removeRemote == [id] && plan.markRemote == [id] && plan.download.isEmpty)
        // Cleared on another device: this one's goes too and takes the mark.
        plan = AttachmentSync.plan(referenced: [], local: [id], localMarks: [], remote: [], remoteMarks: [id])
        #expect(plan.removeLocal == [id] && plan.markLocal == [id] && plan.upload.isEmpty)
        // Unused and unmarked here (still waiting to be cleared): left alone.
        plan = AttachmentSync.plan(referenced: [], local: [id], localMarks: [], remote: [id], remoteMarks: [])
        #expect(plan == AttachmentSync.Plan())
    }

    @Test func aMemoThatStillUsesAMarkedFileKeepsIt() {
        // Another device cleared it, but a memo here (written apart, or undone) uses it: the marks
        // go and the file goes up again.
        let plan = AttachmentSync.plan(referenced: [id], local: [id], localMarks: [], remote: [], remoteMarks: [id])
        #expect(plan.removeLocal.isEmpty && plan.unmarkRemote == [id] && plan.upload == [id])
    }

    @Test func aPassCopiesBothWaysAndCarriesMarks() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "attach-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sync = root.appending(path: "Simplify Sync")
        let mac = AttachmentStore(root: root.appending(path: "mac/Attachments"))
        let pad = AttachmentStore(root: root.appending(path: "pad/Attachments"))
        let a = try mac.add(data: Data("견적".utf8), name: "견적서.pdf")

        // This Mac's memo uses it: it goes up; the other device's memo uses it too: it comes down.
        _ = try AttachmentSync.pass(store: mac, syncFolder: sync, referenced: [a.id: a])
        #expect(FileManager.default.fileExists(atPath: sync.appending(path: "Attachments/\(a.id)/견적서.pdf").path))
        let report = try AttachmentSync.pass(store: pad, syncFolder: sync, referenced: [a.id: a])
        #expect(report.changed == [a.id] && (try? Data(contentsOf: pad.url(for: a))) == Data("견적".utf8))

        // Cleared away on the Mac: the next passes take it off the folder and the other device.
        #expect(mac.sweep(referenced: [], launch: "next", now: .now).isEmpty)
        #expect(mac.sweep(referenced: [], launch: "later", now: .now) == [a.id])
        _ = try AttachmentSync.pass(store: mac, syncFolder: sync, referenced: [:])
        #expect(!FileManager.default.fileExists(atPath: sync.appending(path: "Attachments/\(a.id)").path))
        #expect(FileManager.default.fileExists(atPath: sync.appending(path: "Attachments/\(a.id).deleted").path))
        _ = try AttachmentSync.pass(store: pad, syncFolder: sync, referenced: [:])
        #expect(!pad.exists(a) && pad.marks() == [a.id])

        // Before the other devices' memos are read, a pass only sends files up: a mark there
        // does not take this device's copy, and this device's mark does not take theirs.
        let b = try mac.add(data: Data("다시".utf8), name: "b.pdf")
        pad.mark(b.id)
        let early = try AttachmentSync.pass(store: pad, syncFolder: sync, referenced: [:], uploadsOnly: true)
        #expect(early == AttachmentSync.Report() && !FileManager.default.fileExists(atPath: sync.appending(path: "Attachments/\(b.id).deleted").path))
        _ = try AttachmentSync.pass(store: mac, syncFolder: sync, referenced: [b.id: b], uploadsOnly: true)
        #expect(FileManager.default.fileExists(atPath: sync.appending(path: "Attachments/\(b.id)/b.pdf").path))

        // Used but nowhere: neither waiting nor changed (the card says it cannot be found).
        let gone = MemoAttachments.Ref(id: other, name: "계약서.docx")
        let missing = try AttachmentSync.pass(store: pad, syncFolder: sync, referenced: [other: gone])
        #expect(missing.waiting.isEmpty && missing.changed.isEmpty)
    }
}
