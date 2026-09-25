import Testing
@testable import Rauta

/// What RAUTA opens with. Every offer it makes has to be one its menu leads
/// with, and a quiet day has to be called a quiet day.
@Suite("Rauta greeting")
struct RautaGreetingTests {
    // Friday.
    private let today = "2026-09-25"

    private func input(
        active: String? = nil,
        upcoming: [RautaGreeting.Day] = [],
        trainedToday: Bool = false,
        hasPlan: Bool = true
    ) -> RautaGreeting.Input {
        RautaGreeting.Input(
            activeWorkout: active,
            today: today,
            upcoming: upcoming,
            trainedToday: trainedToday,
            hasPlan: hasPlan
        )
    }

    @Test func aRunningWorkoutComesFirst() {
        let line = RautaGreeting.line(input(
            active: "Push",
            upcoming: [.init(name: "Legs", date: today)]
        ))
        #expect(line == "Push is still going. Tap me to jump back in.")
    }

    @Test func todaysWorkoutIsOffered() {
        let line = RautaGreeting.line(input(upcoming: [
            .init(name: "Legs", date: "2026-09-27"),
            .init(name: "Full body", date: today),
        ]))
        #expect(line == "Full body is on for today. Tap me and we'll start.")
    }

    @Test func aRestDayIsCalledOneAndNamesWhatIsNext() {
        let tomorrow = RautaGreeting.line(input(upcoming: [.init(name: "Legs", date: "2026-09-26")]))
        #expect(tomorrow == "Rest day. Next up: Legs tomorrow.")

        let later = RautaGreeting.line(input(upcoming: [.init(name: "Legs", date: "2026-09-28")]))
        #expect(later.hasPrefix("Rest day. Next up: Legs on "))
    }

    /// A planned day that went by untrained is not what is next.
    @Test func daysAlreadyGoneAreNotOffered() {
        let line = RautaGreeting.line(input(upcoming: [.init(name: "Legs", date: "2026-09-23")]))
        #expect(line == "That plan is done. Tap me and I'll build the next one.")
    }

    @Test func trainingTodayIsAcknowledged() {
        #expect(RautaGreeting.line(input(trainedToday: true)) == "Done for today. Nice work.")
    }

    @Test func withoutAPlanRautaOffersToBuildOne() {
        #expect(RautaGreeting.line(input(hasPlan: false)) == "No plan yet. Tap me and I'll build your week.")
    }
}
