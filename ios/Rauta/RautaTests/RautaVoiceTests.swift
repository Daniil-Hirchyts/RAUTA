import Testing
@testable import Rauta

/// What RAUTA says while it plans and celebrates.
///
/// Each line is pinned where a looser one would say something untrue: a plan
/// with sessions it does not have, a partial session called complete.
@Suite("Rauta voice")
struct RautaVoiceTests {
    // MARK: Planning

    @Test func daysAreReadAsWords() {
        // Mon 28, Wed 30 Sep, Fri 2 Oct 2026.
        #expect(PlanTalk.days(["2026-09-30", "2026-09-28", "2026-10-02"]) == "Mon, Wed and Fri")
        #expect(PlanTalk.days(["2026-09-28"]) == "Mon")
        #expect(PlanTalk.days(["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02"]) == "5 days")
    }

    @Test func aBuiltPlanNamesOnlyTheSessionsItHas() {
        let line = PlanTalk.built(dates: ["2026-10-02", "2026-09-28"])
        #expect(line.hasPrefix("Done! 2 sessions"))
        #expect(PlanTalk.built(dates: []).contains("nothing to schedule"))
    }

    @Test func askingChangesWithWhatIsPicked() {
        #expect(PlanTalk.asking(selected: [], minutes: 45, continuing: false).hasPrefix("Pick the days"))
        #expect(PlanTalk.asking(selected: ["2026-09-28"], minutes: 45, continuing: false)
            == "Mon. I'll fit about 45 min into each.")
    }

    // MARK: Celebrating

    private func receipt(sets: Int, complete: Bool) -> WorkoutReceipt {
        WorkoutReceipt(
            sessionId: "s", workoutId: "w", workoutName: "Upper",
            completedAt: "2026-09-25T18:00:00.000Z", durationMs: 40 * 60_000,
            exercisesRecorded: 2, exercisesPlanned: 3, setsRecorded: sets,
            isComplete: complete, healthSyncPending: false
        )
    }

    @Test func celebrationNeverOverstatesTheWork() {
        #expect(receipt(sets: 12, complete: true).rautaLine.contains("Every set on the plan"))
        #expect(!receipt(sets: 5, complete: false).rautaLine.contains("Every set"))
        #expect(receipt(sets: 0, complete: false).rautaLine.hasPrefix("No sets logged"))
    }
}
