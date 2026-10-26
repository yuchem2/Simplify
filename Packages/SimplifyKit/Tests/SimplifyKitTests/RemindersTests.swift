import Foundation
import Testing
@testable import SimplifyKit

struct RemindersTests {
    let cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    @Test func dueDayIsAnAllDayEntry() throws {
        let item = ReminderItem(id: "r1", title: " 우유 사기 ", due: DateComponents(year: 2026, month: 10, day: 27), isCompleted: false)
        let event = try #require(item.snapshot(sourceID: "reminders:local|L", calendar: cal))
        #expect(event.isAllDay)
        #expect(event.startDay == "2026-10-27")
        #expect(event.title == "우유 사기")
        #expect(!event.isCompleted)
        let october = DateInterval(start: cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!,
                                   end: cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!)
        let occurrence = try #require(OccurrenceBuilder.occurrences(from: [event], in: october, calendar: cal).first)
        #expect(occurrence.start == cal.date(from: DateComponents(year: 2026, month: 10, day: 27)))
        #expect(occurrence.isBand)
    }

    @Test func dueTimeIsAMoment() throws {
        var due = DateComponents(year: 2026, month: 10, day: 27, hour: 18, minute: 30)
        due.timeZone = TimeZone(identifier: "Asia/Seoul")
        let item = ReminderItem(id: "r2", title: "약 먹기", due: due, isCompleted: true)
        let event = try #require(item.snapshot(sourceID: "s", calendar: cal))
        #expect(!event.isAllDay)
        #expect(event.start == cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 18, minute: 30)))
        #expect(event.end == event.start)
        #expect(event.isCompleted)
        let day = DateInterval(start: cal.date(from: DateComponents(year: 2026, month: 10, day: 27))!, duration: 86_400)
        let occurrence = try #require(OccurrenceBuilder.occurrences(from: [event], in: day, calendar: cal).first)
        #expect(!occurrence.isBand)
        #expect(occurrence.isCompleted)
    }

    @Test func undatedRemindersStayOff() {
        #expect(ReminderItem(id: "r3", title: "언젠가", due: nil, isCompleted: false).snapshot(sourceID: "s", calendar: cal) == nil)
        #expect(ReminderItem(id: "r4", title: "연도만", due: DateComponents(year: 2026), isCompleted: false).snapshot(sourceID: "s", calendar: cal) == nil)
    }

    @Test func unchangedListsWriteNothing() {
        let events = [ReminderItem(id: "a", title: "A", due: DateComponents(year: 2026, month: 10, day: 1), isCompleted: false),
                      ReminderItem(id: "b", title: "B", due: DateComponents(year: 2026, month: 10, day: 2), isCompleted: false)]
            .compactMap { $0.snapshot(sourceID: "s", calendar: cal) }
        let first = RemindersProvider.changes(for: events, syncToken: nil)
        #expect(first.isFullFetch && first.changes.count == 2)
        // Same reminders in another order: nothing to write.
        let again = RemindersProvider.changes(for: events.reversed(), syncToken: first.nextSyncToken)
        #expect(!again.isFullFetch && again.changes.isEmpty && again.nextSyncToken == first.nextSyncToken)
        var changed = events
        changed[0].isCompleted = true
        #expect(RemindersProvider.changes(for: changed, syncToken: first.nextSyncToken).isFullFetch)
    }
}
