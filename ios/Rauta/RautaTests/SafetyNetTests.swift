import Foundation
import Testing
@testable import Rauta

/// The guards that keep stored data, dates and a running workout safe from
/// what arrives from outside: imported files, another device, another time
/// zone.
@Suite("Safety net")
struct SafetyNetTests {
    // MARK: Numbers from files

    /// `Int(_:)` on a Double out of range traps; a number read from a file
    /// anyone could have written must fail softly instead.
    @Test func wholeNumbersOutOfRangeReadAsNothing() {
        #expect(JSONValue.number(1e20).intValue == nil)
        #expect(JSONValue.number(2.5).intValue == nil)
        #expect(JSONValue.number(.nan).intValue == nil)
        #expect(JSONValue.number(4).intValue == 4)
        #expect(JSONValue.string("4").intValue == nil)
        #expect(Storage.version(.number(1e20)) == -1)
        #expect(Storage.version(nil) == -1)
        #expect(Storage.version(.number(1)) == 1)
    }

    // MARK: Local days

    private let newYork = TimeZone(identifier: "America/New_York")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    /// 23:00 on Monday 5 October in New York is already Tuesday in UTC. The
    /// person's today is still Monday.
    @Test func anEveningWestOfGreenwichIsStillToday() {
        let lateMonday = "2026-10-06T03:00:00.000Z"
        #expect(ISOTime.localDay(lateMonday, in: newYork) == "2026-10-05")
        #expect(ISOTime.localDay(lateMonday, in: tokyo) == "2026-10-06")
        #expect(ISOTime.localDay(lateMonday, in: TimeZone(secondsFromGMT: 0)!) == "2026-10-06")
    }

    /// A plan made on Sunday evening in New York starts tomorrow, the next
    /// Monday — not the Monday after, though UTC has already reached Monday.
    @Test func aSundayEveningPlanStartsTomorrow() {
        let sundayEvening = "2026-10-05T01:30:00.000Z" // Sun 4 Oct, 21:30 in New York
        #expect(TrainingWorkflow.nextMonday(after: sundayEvening, in: newYork) == "2026-10-05T00:00:00.000Z")
        // On Monday itself the plan starts the Monday after.
        let mondayMorning = "2026-10-05T13:00:00.000Z" // Mon 5 Oct, 09:00 in New York
        #expect(TrainingWorkflow.nextMonday(after: mondayMorning, in: newYork) == "2026-10-12T00:00:00.000Z")
    }

    /// The dates workouts are filed under are Gregorian, whatever calendar the
    /// phone shows, so they read back as the same day.
    @Test func calendarDatesRoundTripAcrossMonthsAndYears() throws {
        for day in ["2026-10-05", "2024-02-29", "2026-12-31", "2027-01-01"] {
            let date = try #require(CalendarDate.parse(day))
            #expect(CalendarDate.toISO(date) == day)
        }
        #expect(CalendarDate.shift("2026-12-31", by: 1) == "2027-01-01")
        #expect(CalendarDate.shift("2024-03-01", by: -1) == "2024-02-29")
    }
}
