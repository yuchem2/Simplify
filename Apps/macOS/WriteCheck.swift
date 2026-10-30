#if DEBUG
import AppKit
import SimplifyKit

/// Debug-only: makes, changes and deletes events in calendars whose name contains "테스트" or
/// "test", through the same controller calls the editor uses, then quits. Run with
/// `open --env SIMPLIFY_WRITE_CHECK=1 Simplify.app`; the result lands in
/// `~/Library/Containers/dev.yoom.simplify/Data/tmp/write-check.txt`. Other calendars are never touched.
@MainActor
enum WriteCheck {
    private static var lines: [String] = []

    static func runIfRequested(model: AppModel, calendars: CalendarController) {
        guard ProcessInfo.processInfo.environment["SIMPLIFY_WRITE_CHECK"] != nil else { return }
        Task {
            await run(model: model, calendars: calendars)
            let file = FileManager.default.temporaryDirectory.appending(path: "write-check.txt")
            try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    private static func log(_ line: String) { lines.append(line) }

    private static func check(_ ok: Bool, _ what: String) {
        log((ok ? "PASS  " : "FAIL  ") + what)
    }

    private static func run(model: AppModel, calendars: CalendarController) async {
        // Sync every account once so newly made calendars are known.
        for account in calendars.accounts where account.provider != .reminders {
            if let any = calendars.sources.values.first(where: { $0.accountID == account.id }) {
                await calendars.resync(sourceID: any.id)
            }
        }
        // Next month, where a weekly event shows four or five times.
        model.select(model.calendar.date(byAdding: .month, value: 1, to: model.calendar.startOfDay(for: .now))!)
        calendars.show(days: model.grid.weeks.flatMap { $0 }, calendar: model.calendar)
        let tests = calendars.writableSources.flatMap(\.1).filter {
            $0.name.contains("테스트") || $0.name.lowercased().contains("test")
        }
        guard !tests.isEmpty else {
            log("FAIL  이름에 '테스트'나 'test'가 들어간 쓸 수 있는 캘린더가 없어요")
            return
        }
        for source in tests {
            let provider = calendars.accounts.first { $0.id == source.accountID }?.provider.label ?? "?"
            log("== \(provider) · \(source.name)")
            await scenario(source: source, model: model, calendars: calendars)
        }
    }

    private static func scenario(source: CalendarController.Source, model: AppModel, calendars: CalendarController) async {
        let cal = model.calendar
        let stamp = String(Int(Date.now.timeIntervalSince1970) % 100_000)
        // The second week's Monday of the shown month, 10:00.
        let monday = model.grid.weeks[1][1]
        func occurrences(_ prefix: String) -> [EventOccurrence] {
            calendars.slots.values.joined().map(\.occurrence)
                .filter { $0.sourceID == source.id && $0.title.hasPrefix(prefix) }
                .reduce(into: [EventOccurrence]()) { list, o in if !list.contains(where: { $0.id == o.id }) { list.append(o) } }
                .sorted { $0.start < $1.start }
        }
        func save(_ editor: EventEditorModel, _ scope: CalendarController.WriteScope, _ what: String) async -> Bool {
            do {
                let outcome = try await calendars.save(editor, scope: scope)
                await calendars.resync(sourceID: source.id)
                log("      \(what): \(outcome)")
                return true
            } catch {
                log("FAIL  \(what): \(error.eventWriteMessage)")
                return false
            }
        }
        func delete(_ occurrence: EventOccurrence, _ scope: CalendarController.WriteScope, _ what: String) async {
            do {
                let outcome = try await calendars.delete(occurrence, scope: scope)
                await calendars.resync(sourceID: source.id)
                log("      \(what): \(outcome)")
            } catch {
                log("FAIL  \(what): \(error.eventWriteMessage)")
            }
        }
        func editor(_ occurrence: EventOccurrence) -> EventEditorModel? {
            guard let event = calendars.event(id: occurrence.eventID) else { return nil }
            return EventEditorModel(editing: occurrence, event: event, calendar: cal)
        }

        // 1. A single event: make, change, delete.
        let single = "S4B 단일 \(stamp)"
        let new = EventEditorModel(newOn: monday, sourceID: source.id, calendar: cal)
        new.fields.title = single
        new.setStart(cal.date(bySettingHour: 10, minute: 0, second: 0, of: monday)!)
        new.fields.location = "테스트 장소"
        new.fields.notes = "Simplify 4-B 확인"
        guard await save(new, .allOccurrences, "새 일정") else { return }
        guard let made = occurrences(single).first else { check(false, "새 일정이 달력에 보여요"); return }
        check(EventText.time(made.start, calendar: cal) == "오전 10:00" && made.location == "테스트 장소", "새 일정이 그 시간·장소로 보여요")
        check(calendars.event(id: made.eventID)?.notes == "Simplify 4-B 확인", "메모가 저장돼요")
        if let edit = editor(made) {
            edit.fields.title = single + " 고침"
            edit.setStart(made.start.addingTimeInterval(3600))
            _ = await save(edit, .allOccurrences, "고치기")
            let changed = occurrences(single).first
            check(changed?.title == single + " 고침" && changed.map { EventText.time($0.start, calendar: cal) } == "오전 11:00", "고친 제목·시간이 보여요")
            if let changed { await delete(changed, .allOccurrences, "지우기") }
            check(occurrences(single).isEmpty, "지운 일정이 사라져요")
        }

        // 2. A weekly series: this only, this and following, delete one, delete all.
        let weekly = "S4B 반복 \(stamp)"
        let series = EventEditorModel(newOn: monday, sourceID: source.id, calendar: cal)
        series.fields.title = weekly
        series.setStart(cal.date(bySettingHour: 9, minute: 0, second: 0, of: monday)!)
        series.fields.repeatChoice = .weekly
        guard await save(series, .allOccurrences, "매주 반복 새 일정") else { return }
        var all = occurrences(weekly)
        check(all.count >= 3, "반복이 여러 주에 보여요 (\(all.count)개)")
        guard all.count >= 3 else { return }

        if let edit = editor(all[1]) {
            edit.fields.title = weekly + " 이번만"
            _ = await save(edit, .thisOccurrence, "이 일정만 고치기")
        }
        all = occurrences(weekly)
        check(all.count >= 3 && all[1].title == weekly + " 이번만" && all[0].title == weekly && all[2].title == weekly,
              "이 일정만: 그 주만 바뀌어요")

        if all.count >= 3, let edit = editor(all[2]) {
            edit.fields.title = weekly + " 이후"
            _ = await save(edit, .thisAndFollowing, "이후 모든 일정 고치기")
        }
        all = occurrences(weekly)
        check(all.count >= 3 && all[0].title == weekly && all[2...].allSatisfy { $0.title == weekly + " 이후" },
              "이후 모든 일정: 셋째 주부터 바뀌고 첫 주는 그대로예요")

        if let first = all.first {
            await delete(first, .thisOccurrence, "이 일정만 지우기")
            let after = occurrences(weekly)
            check(!after.contains { $0.start == first.start } && after.count == all.count - 1, "이 일정만 지우기: 그 주만 사라져요")
        }

        // Clean up: delete each remaining series whole.
        var guardRounds = 0
        while let left = occurrences(weekly).first, guardRounds < 5 {
            guardRounds += 1
            await delete(left, .allOccurrences, "모든 일정 지우기")
        }
        check(occurrences(weekly).isEmpty, "모든 일정 지우기: 반복이 모두 사라져요")
        check(calendars.unsentWrites.isEmpty, "보내기 대기가 남지 않아요")
    }
}
#endif
