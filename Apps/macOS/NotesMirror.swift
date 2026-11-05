import AppKit
import CoreServices
import Observation
import SimplifyKit

/// Copies memos into the 메모 app's "Simplify" folder as they are saved: one note per memo, named
/// after its period and its name (`NotesHTML`). One way only; the 메모 app's copy is written over
/// on the next send (renamed with it, found by the note id saved here), and deleted (to its 최근
/// 삭제된 항목) once the memo is blank or gone.
///
/// A saved memo waits a few seconds so a burst of saves goes as one, opening the 메모 app behind
/// Simplify when it is closed. Copies that cannot go (not allowed, or a failure) wait in a list
/// kept in the shared defaults and go when Simplify comes to the front or the next memo is saved.
@MainActor
@Observable
final class NotesMirror {
    static let shared = NotesMirror()

    enum Status: Equatable {
        case idle, sending, denied, failed
    }

    /// 설정 › 일반 › Apple 메모에도 쓰기.
    var isOn = SharedSettings.defaults.bool(forKey: SharedSettings.mirrorsToNotes) {
        didSet {
            SharedSettings.defaults.set(isOn, forKey: SharedSettings.mirrorsToNotes)
            if isOn {
                Task { await askAndSend(all: false) }
            } else {
                // Changes made while off are not tracked; 지금 모두 보내기 catches up.
                debounce?.cancel()
                pending = []
                status = .idle
            }
        }
    }

    private(set) var status: Status = .idle
    /// Memo ids whose copy has not gone yet (and period keys from before a period could have
    /// several, until `adoptPeriodKeys` moves them).
    private(set) var pending = SharedSettings.notesPending(in: SharedSettings.defaults) {
        didSet { SharedSettings.setNotesPending(pending, in: SharedSettings.defaults) }
    }

    /// The memos to copy; the app's one book. Unset in snapshots, which copy nothing.
    @ObservationIgnored weak var book: MemoBook?
    @ObservationIgnored private var ids = SharedSettings.notesNoteIDs(in: SharedSettings.defaults) {
        didSet { SharedSettings.setNotesNoteIDs(ids, in: SharedSettings.defaults) }
    }
    @ObservationIgnored private var names = SharedSettings.notesNoteNames(in: SharedSettings.defaults) {
        didSet { SharedSettings.setNotesNoteNames(names, in: SharedSettings.defaults) }
    }
    /// The body last sent for each key this run, so saving an unchanged memo sends nothing.
    @ObservationIgnored private var sent: [String: String] = [:]
    /// Keys saved again while their copy was on its way: they stay waiting for the next pause.
    @ObservationIgnored private var savedWhileSending: Set<String> = []
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var isSending = false
    @ObservationIgnored private let script = NotesScript()
    @ObservationIgnored private var observer: NSObjectProtocol?

    nonisolated static let notesBundleID = "com.apple.Notes"
    /// How long a saved memo waits for more saves before it goes.
    static let delay: Duration = .seconds(3)

    private init() {
        // Back from 시스템 설정, where it may have been allowed.
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotesMirror.shared.retry() }
        }
    }

    /// A memo was saved, renamed or deleted: its copy goes after a pause.
    func memoSaved(_ id: UUID) {
        guard isOn, book != nil else { return }
        let key = id.uuidString
        pending.insert(key)
        // Not allowed: it waits for 시스템 설정 rather than opening the 메모 app on every save.
        guard status != .denied else { return }
        if isSending { savedWhileSending.insert(key) }
        scheduleSend()
    }

    /// Before a period could have several memos, copies were kept by period key. Each such note
    /// becomes the copy of the period's memo from then (its oldest without a name), so it is
    /// written over rather than made again; a period with no memo left keeps its key until its
    /// note is deleted.
    func adoptPeriodKeys() {
        guard let book else { return }
        for key in Set(ids.keys).union(pending) where UUID(uuidString: key) == nil {
            guard let note = book.legacyNote(periodKey: key)?.uuidString else { continue }
            if let id = ids.removeValue(forKey: key), ids[note] == nil { ids[note] = id }
            if pending.remove(key) != nil { pending.insert(note) }
        }
    }

    private func scheduleSend() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            await send()
        }
    }

    /// 지금 모두 보내기: every memo, and the copies of memos that are gone, opening the 메모 app if needed.
    func sendAll() {
        guard isOn else { return }
        Task { await askAndSend(all: true) }
    }

    /// Simplify came to the front: try what is waiting.
    private func retry() {
        guard isOn else { return }
        if status == .denied {
            // Asking without a prompt only reads the answer given in 시스템 설정, and needs the
            // 메모 app open; a closed one is not opened just to ask.
            Task {
                guard Self.isNotesRunning, await script.permission(ask: false) == noErr else { return }
                status = .idle
                await send()
            }
        } else if !pending.isEmpty, Self.isNotesRunning {
            // Only into an open 메모 app: one closed after a failure is opened by the next save.
            Task { await send() }
        }
    }

    /// Opens the 메모 app if needed, asks for permission (a prompt the first time), then sends.
    private func askAndSend(all: Bool) async {
        guard let book else { return }
        if all {
            pending.formUnion(book.allNoteIDs().map(\.uuidString))
            // Copies of memos emptied while the mirror was off.
            pending.formUnion(ids.keys)
            sent = [:]
        }
        status = .sending
        guard await launchNotes() else {
            status = .failed
            return
        }
        switch await script.permission(ask: true) {
        case noErr:
            status = .idle
            await send()
        case OSStatus(errAEEventNotPermitted):
            status = .denied
        default:
            status = .failed
        }
    }

    /// Sends what is waiting, one copy at a time, opening the 메모 app first if it is closed. A
    /// key leaves the waiting list only once its copy is in, so quitting midway loses nothing.
    private func send() async {
        guard isOn, !isSending, let book, !pending.isEmpty else { return }
        isSending = true
        guard await launchNotes() else {
            isSending = false
            status = .failed
            return
        }
        savedWhileSending = []
        // Failed this round: tried again on the next save or retry, not straight away.
        var failed: Set<String> = []
        var stopped = false
        let calendar = Calendar.simplify
        while isOn, let key = pending.sorted().first(where: { !failed.contains($0) && !savedWhileSending.contains($0) }) {
            let name: String, body: String?
            if let id = UUID(uuidString: key) {
                switch book.stored(note: id, calendar: calendar) {
                case .memo(let period, let text, let memo):
                    name = NotesHTML.noteName(for: period, memo: memo)
                    body = NotesHTML.body(name: name, text: text)
                case .gone:
                    // Deleted: its note goes, found by id or by the name it went under.
                    guard ids[key] != nil || names[key] != nil else {
                        pending.remove(key)
                        continue
                    }
                    name = names[key] ?? ""
                    body = nil
                case .unreadable:
                    // A memo that cannot be read now leaves its copy alone and waits.
                    failed.insert(key)
                    continue
                }
            } else {
                // A period key from before: the period's note, whose memo is gone.
                guard let period = PeriodScope.allCases.lazy.compactMap({ Period(key: key, scope: $0, calendar: calendar) }).first else {
                    pending.remove(key)
                    continue
                }
                name = NotesHTML.noteName(for: period)
                body = nil
            }
            guard sent[key] != (body ?? "") else {
                pending.remove(key)
                continue
            }
            status = .sending
            do {
                if let body {
                    ids[key] = try await script.write(id: ids[key] ?? "", name: name, body: body)
                    names[key] = name
                } else {
                    try await script.delete(id: ids[key] ?? "", name: name)
                    ids[key] = nil
                    names[key] = nil
                }
                sent[key] = body ?? ""
                if !savedWhileSending.contains(key) { pending.remove(key) }
                status = .idle
            } catch {
                guard isOn else { break }
                failed.insert(key)
                status = error == .denied ? .denied : .failed
                // Nothing else can go either; `retry` takes it up again.
                if error == .denied || error == .notesClosed {
                    stopped = true
                    break
                }
            }
        }
        isSending = false
        if isOn, !stopped, !savedWhileSending.isEmpty { scheduleSend() }
    }

    private static var isNotesRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: notesBundleID).isEmpty
    }

    /// Opens the 메모 app behind Simplify, without bringing it to the front, and waits until it
    /// takes Apple events, which it does a moment after it opens.
    private func launchNotes() async -> Bool {
        if Self.isNotesRunning { return true }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.notesBundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        guard (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil else { return false }
        for _ in 0..<20 {
            if await script.permission(ask: false) != OSStatus(procNotFound) { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }
}

enum NotesScriptError: Error, Equatable {
    case denied, notesClosed, failed(Int)
}

/// The 메모 app's side: AppleScript handlers, run off the main thread on one thread of their own
/// (NSAppleScript is not documented as safe across threads). Memo text reaches the handlers as
/// parameters of an Apple event, never as script source, so nothing written in a memo can become
/// part of the script.
private final class NotesScript: @unchecked Sendable {
    private let thread = ScriptThread()
    /// Compiled on first use, only ever touched on `thread`.
    private var compiled: NSAppleScript?

    init() {
        thread.start()
    }

    /// A note is found by the id this Mac saved, then by name in the folder, else made anew. A
    /// note found by id but sitting elsewhere (최근 삭제된 항목) counts as gone.
    private static let source = """
    on simplifyFolder()
    	tell application id "com.apple.Notes"
    		tell default account
    			if not (exists folder "Simplify") then make new folder with properties {name:"Simplify"}
    			return folder "Simplify"
    		end tell
    	end tell
    end simplifyFolder

    on findNote(theFolder, noteID, noteName)
    	tell application id "com.apple.Notes"
    		if noteID is not "" then
    			try
    				set found to note id noteID
    				if (id of container of found) is (id of theFolder) then return found
    			end try
    		end if
    		set matches to (notes of theFolder whose name is noteName)
    		if (count of matches) > 0 then return item 1 of matches
    		return missing value
    	end tell
    end findNote

    on writeNote(noteID, noteName, noteBody)
    	set theFolder to simplifyFolder()
    	set found to findNote(theFolder, noteID, noteName)
    	tell application id "com.apple.Notes"
    		if found is missing value then
    			set found to make new note at theFolder with properties {body:noteBody}
    		else
    			set body of found to noteBody
    		end if
    		return id of found
    	end tell
    end writeNote

    on deleteNote(noteID, noteName)
    	tell application id "com.apple.Notes"
    		if not (exists folder "Simplify" of default account) then return ""
    	end tell
    	set theFolder to simplifyFolder()
    	set found to findNote(theFolder, noteID, noteName)
    	tell application id "com.apple.Notes"
    		if found is not missing value then delete found
    	end tell
    	return ""
    end deleteNote
    """

    /// Writes the note and returns its id.
    func write(id: String, name: String, body: String) async throws(NotesScriptError) -> String {
        try await call("writenote", [id, name, body])
    }

    func delete(id: String, name: String) async throws(NotesScriptError) {
        _ = try await call("deletenote", [id, name])
    }

    /// Whether Simplify may send the 메모 app Apple events; `ask` shows the system prompt when
    /// nobody has answered yet. The 메모 app has to be open.
    func permission(ask: Bool) async -> OSStatus {
        await withCheckedContinuation { continuation in
            thread.run {
                let target = NSAppleEventDescriptor(bundleIdentifier: NotesMirror.notesBundleID)
                continuation.resume(returning: AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask))
            }
        }
    }

    private func call(_ handler: String, _ arguments: [String]) async throws(NotesScriptError) -> String {
        let result: Result<String, NotesScriptError> = await withCheckedContinuation { continuation in
            thread.run { continuation.resume(returning: self.run(handler, arguments)) }
        }
        return try result.get()
    }

    /// Calls a handler of the compiled script with string arguments (an `ascr/psbr` event).
    private func run(_ handler: String, _ arguments: [String]) -> Result<String, NotesScriptError> {
        if compiled == nil {
            let script = NSAppleScript(source: Self.source)
            var error: NSDictionary?
            guard script?.compileAndReturnError(&error) == true else { return .failure(.failed(Self.number(error))) }
            compiled = script
        }
        let parameters = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() {
            parameters.insert(NSAppleEventDescriptor(string: argument), at: index + 1)
        }
        // Carbon's kASAppleScriptSuite, kASSubroutineEvent and keyASSubroutineName.
        let event = NSAppleEventDescriptor(eventClass: 0x6173_6372, eventID: 0x7073_6272,
                                           targetDescriptor: .currentProcess(), returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: handler), forKeyword: 0x736E_616D)
        event.setParam(parameters, forKeyword: keyDirectObject)
        var error: NSDictionary?
        guard let reply = compiled?.executeAppleEvent(event, error: &error) else {
            switch Self.number(error) {
            case Int(errAEEventNotPermitted): return .failure(.denied)
            // Not running, or quit midway.
            case Int(procNotFound), Int(connectionInvalid): return .failure(.notesClosed)
            case let number: return .failure(.failed(number))
            }
        }
        return .success(reply.stringValue ?? "")
    }

    private static func number(_ error: NSDictionary?) -> Int {
        error?[NSAppleScript.errorNumber] as? Int ?? 0
    }
}

/// One thread that runs jobs in order, so the compiled script always stays on the same thread.
private final class ScriptThread: Thread, @unchecked Sendable {
    private let lock = NSLock()
    private let waiting = DispatchSemaphore(value: 0)
    private var jobs: [@Sendable () -> Void] = []

    func run(_ job: @escaping @Sendable () -> Void) {
        lock.withLock { jobs.append(job) }
        waiting.signal()
    }

    override func main() {
        while true {
            waiting.wait()
            let job = lock.withLock { jobs.removeFirst() }
            job()
        }
    }
}
