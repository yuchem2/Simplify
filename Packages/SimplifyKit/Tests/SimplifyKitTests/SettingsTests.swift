import Foundation
import SwiftData
import Testing
@testable import SimplifyKit

/// Stage 8: colours picked on this Mac, patterns, the week's first day, the new event's calendar.
@MainActor
struct SettingsTests {
    // MARK: Picked colours and shapes

    @Test func pickedStyleOverridesTheProviderColour() {
        #expect(CalendarStyle().look(auto: .blue) == CalendarLook(.blue))
        #expect(CalendarStyle(palette: .green).look(auto: .blue) == CalendarLook(.green))
        // A shape left on 자동 follows the colour; a picked one stays whatever the colour.
        #expect(CalendarStyle(shape: .x).look(auto: .blue) == CalendarLook(color: .palette(.blue), shape: .x))
        #expect(CalendarStyle(palette: .pink, shape: .diamond).look(auto: .blue).shape == .diamond)
        // A colour from the wheel wins over a palette colour, and takes the nearest colour's shape.
        let custom = CalendarStyle(palette: .pink, hex: "#2fa84f").look(auto: .blue)
        #expect(custom.color == .custom(hex: "#2fa84f"))
        #expect(custom.shape == Palette.green.markShape)
        #expect(custom.name == "직접 고른 색")
        // Holidays keep their provider's colour and shape.
        #expect(CalendarStyle(palette: .blue, shape: .x).look(auto: .red, isHoliday: true) == CalendarLook(.red))
        // A hex that is not #RRGGBB counts as none.
        for bad in ["#12345", "#1234567", "+12345", "#gg0000"] {
            #expect(CalendarStyle(palette: .teal, hex: bad).look(auto: .blue) == CalendarLook(.teal), "\(bad)")
        }
    }

    @Test func stylesLiveInTheSharedDefaultsUntilTheAccountGoes() throws {
        let defaults = WidgetStoreTests().defaults()
        CalendarStyles.set(CalendarStyle(hex: "#123456", shape: .cross), for: "google:1|work", in: defaults)
        CalendarStyles.set(CalendarStyle(palette: .teal), for: "icloud:1|home", in: defaults)
        #expect(CalendarStyles.all(in: defaults)["google:1|work"] == CalendarStyle(hex: "#123456", shape: .cross))
        // Back to 자동 for both: nothing kept.
        CalendarStyles.set(CalendarStyle(), for: "icloud:1|home", in: defaults)
        #expect(CalendarStyles.all(in: defaults).keys.sorted() == ["google:1|work"])
        CalendarStyles.set(CalendarStyle(palette: .teal), for: "icloud:1|home", in: defaults)
        CalendarStyles.remove(account: "google:1", in: defaults)
        #expect(CalendarStyles.all(in: defaults).keys.sorted() == ["icloud:1|home"])
    }

    @Test func syncMovesOnlyTheProviderColour() async throws {
        let google = FakeGoogle(calendars: SyncTests.twoCalendars)
        google.events["me@example.com"] = ["": (200, #"{"items":[],"nextSyncToken":"s1"}"#), "s1": (200, #"{"items":[],"nextSyncToken":"s1"}"#)]
        google.events["ko.south_korea#holiday@group.v.calendar.google.com"] = ["": (200, #"{"items":[],"nextSyncToken":"h1"}"#),
                                                                             "h1": (200, #"{"items":[],"nextSyncToken":"h1"}"#)]
        let tests = SyncTests()
        let (container, engine, api) = try tests.setup(google)
        try await engine.upsertAccount(id: tests.account, provider: .google, email: "me@example.com")
        try await engine.sync(tests.account, provider: api, calendar: tests.cal)
        let work = tests.account + "|me@example.com"
        func auto() throws -> Palette {
            try #require(try ModelContext(container).fetch(FetchDescriptor<CalendarSource>(predicate: #Predicate { $0.id == work })).first).palette
        }
        let picked = CalendarStyle(palette: .green, shape: .triangle)
        #expect(try picked.look(auto: auto()) == CalendarLook(color: .palette(.green), shape: .triangle))

        // Google changes the calendar's colour: the automatic look follows, the picked one stays.
        google.calendars = SyncTests.twoCalendars.replacingOccurrences(of: "#4986e7", with: "#fad165")
        try await engine.sync(tests.account, provider: api, calendar: tests.cal)
        #expect(try auto() == .yellow)
        #expect(try CalendarStyle().look(auto: auto()) == CalendarLook(.yellow))
        #expect(try picked.look(auto: auto()) == CalendarLook(color: .palette(.green), shape: .triangle))
    }

    @Test func widgetsDrawThePickedStyle() throws {
        let store = WidgetStoreTests()
        let defaults = store.defaults()
        try store.fillCache()
        CalendarStyles.set(CalendarStyle(hex: "#2fa84f", shape: .x), for: "google:1|work", in: defaults)
        let data = WidgetStore.load(now: store.now, calendar: store.cal, cache: store.cache, diary: store.diary, pending: [], defaults: defaults)
        #expect(data.events.first { $0.title == "회의" }?.look == CalendarLook(color: .custom(hex: "#2fa84f"), shape: .x))
    }

    // MARK: Monday weeks

    static func monday() -> Calendar {
        var calendar = Calendar.simplify(firstWeekday: 2)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    let sunday = PeriodTests.calendar()
    let monday = SettingsTests.monday()

    @Test func mondayWeeksRunMondayToSunday() {
        let week = Period(containing: PeriodTests.date(2026, 11, 8, in: monday), scope: .week, calendar: monday)
        #expect(week.start == PeriodTests.date(2026, 11, 2, 0, in: monday))
        #expect(week.days.count == 7)
        #expect(week.rangeText == "11.2 – 11.8")
        #expect(week.title == "11월 1주차")
        // Named after the month of its first day: 10.26 – 11.1 is still October's.
        #expect(week.advanced(by: -1).title == "10월 4주차")
        #expect(monday.weekdaysInOrder == [2, 3, 4, 5, 6, 7, 1])
        #expect(sunday.weekdaysInOrder == [1, 2, 3, 4, 5, 6, 7])

        let grid = MonthGrid(month: PeriodTests.date(2026, 11, 3, in: monday), calendar: monday)
        #expect(grid.weeks.first?.first == PeriodTests.date(2026, 10, 26, 0, in: monday))
        #expect(grid.weeks.last?.last == PeriodTests.date(2026, 12, 6, 0, in: monday))
        #expect(grid.weeks.count == 6)
    }

    @Test func mondayWeekKeepsTheKeyOfTheSundayWeekItStartsIn() {
        // 11.2 – 11.8 shares six days with the Sunday week 11.1 – 11.7, and its memo.
        let mondayWeek = Period(containing: PeriodTests.date(2026, 11, 4, in: monday), scope: .week, calendar: monday)
        let sundayWeek = Period(containing: PeriodTests.date(2026, 11, 4, in: sunday), scope: .week, calendar: sunday)
        #expect(mondayWeek.key == sundayWeek.key)
        #expect(mondayWeek.key == "2026-W45")
        // A year starting on a Sunday, where plain Monday week numbers would run one ahead.
        #expect(Period(containing: PeriodTests.date(2023, 1, 2, in: monday), scope: .week, calendar: monday).key == "2023-W01")
        #expect(Period(containing: PeriodTests.date(2023, 1, 1, in: monday), scope: .week, calendar: monday).key == "2022-W53")
        #expect(Period(key: "2023-W01", scope: .week, calendar: monday)?.start == PeriodTests.date(2023, 1, 2, 0, in: monday))
    }

    @Test func weekKeysHoldAcrossYearEnds() {
        // Every week of 2015 – 2035 in both calendars: one key each, read back to the same week,
        // and a Monday week keyed like the Sunday week that starts the day before it.
        for calendar in [sunday, monday] {
            var week = Period(containing: PeriodTests.date(2015, 1, 1, in: calendar), scope: .week, calendar: calendar)
            var seen: Set<String> = []
            while calendar.component(.year, from: week.start) < 2036 {
                #expect(seen.insert(week.key).inserted, "\(week.key) twice")
                #expect(Period(key: week.key, scope: .week, calendar: calendar) == week, "\(week.key)")
                if calendar.firstWeekday == 2 {
                    let before = sunday.date(byAdding: .day, value: -1, to: week.start)!
                    #expect(Period(containing: before, scope: .week, calendar: sunday).key == week.key, "\(week.key)")
                }
                week = week.advanced(by: 1)
            }
        }
    }

    @Test func firstWeekdaySettingReadsSundayUnlessMonday() {
        let defaults = WidgetStoreTests().defaults()
        #expect(SharedSettings.firstWeekday(in: defaults) == 1)
        defaults.set(2, forKey: SharedSettings.firstWeekday)
        #expect(SharedSettings.firstWeekday(in: defaults) == 2)
        defaults.set(5, forKey: SharedSettings.firstWeekday)
        #expect(SharedSettings.firstWeekday(in: defaults) == 1)
    }

    // MARK: Patterns

    @Test func patternsAreOffUntilTurnedOnAndReachTheWidgets() throws {
        let store = WidgetStoreTests()
        let defaults = store.defaults()
        #expect(!SharedSettings.showsPatterns(in: defaults))
        try store.fillCache()
        #expect(!WidgetStore.load(now: store.now, calendar: store.cal, cache: store.cache, diary: store.diary, pending: [], defaults: defaults).showsPatterns)
        defaults.set(true, forKey: SharedSettings.showsPatterns)
        #expect(SharedSettings.showsPatterns(in: defaults))
        #expect(WidgetStore.load(now: store.now, calendar: store.cal, cache: store.cache, diary: store.diary, pending: [], defaults: defaults).showsPatterns)
        #expect(WidgetStore.load(now: store.now, calendar: store.cal, cache: nil, diary: nil, pending: [], defaults: defaults).showsPatterns)
    }

    @Test func everyColourHasItsOwnShapeUnlessPicked() {
        #expect(Set(Palette.allCases.map(\.markShape)).count == Palette.allCases.count)
        #expect(Palette.red.markShape == .square)
    }

    // MARK: New event calendar

    @Test func newEventCalendarFallsBackToTheLastUsed() {
        let writable = ["a", "b", "c"]
        #expect(NewEventCalendar.pick(preferred: nil, last: "b", writable: writable) == "b")
        #expect(NewEventCalendar.pick(preferred: "c", last: "b", writable: writable) == "c")
        // Turned read-only or gone: the last one used, then the first one there is.
        #expect(NewEventCalendar.pick(preferred: "gone", last: "b", writable: writable) == "b")
        #expect(NewEventCalendar.pick(preferred: "gone", last: "gone too", writable: writable) == "a")
        #expect(NewEventCalendar.pick(preferred: "c", last: nil, writable: []) == nil)
    }
}
