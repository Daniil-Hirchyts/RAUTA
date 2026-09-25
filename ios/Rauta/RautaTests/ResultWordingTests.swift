import Foundation
import SwiftUI
import Testing
@testable import Rauta

/// What the app claims about work it has done.
///
/// These are not copy tests. Each one pins a claim that would be false if the
/// wording were derived from an intention rather than from the result.
@Suite("Result wording")
struct ResultWordingTests {
    // MARK: Receipts

    private func receipt(
        sets: Int,
        exercises: Int,
        planned: Int,
        complete: Bool,
        sessionId: String? = "session-1"
    ) -> WorkoutReceipt {
        WorkoutReceipt(
            sessionId: sessionId,
            workoutId: "w1",
            workoutName: "Full body",
            completedAt: "2026-09-21T18:00:00.000Z",
            durationMs: 42 * 60_000,
            exercisesRecorded: exercises,
            exercisesPlanned: planned,
            setsRecorded: sets,
            isComplete: complete,
            healthSyncPending: false
        )
    }

    @Test func aPartialSessionIsSavedWithoutClaimingCompletion() {
        let partial = receipt(sets: 5, exercises: 2, planned: 4, complete: false)
        #expect(partial.title == "Session saved")
        #expect(partial.summaryLine.contains("not performed"))
        #expect(partial.facts.contains { $0.value == "2/4" })
    }

    @Test func aCompleteSessionSaysSo() {
        let full = receipt(sets: 12, exercises: 4, planned: 4, complete: true)
        #expect(full.title == "Workout saved")
        #expect(full.summaryLine == "Every prescribed set is recorded.")
    }

    /// Nothing logged is a real outcome. It is recorded as a session and not
    /// dressed up as work that did not happen.
    @Test func aSessionWithNoSetsSaysThatPlainly() {
        let empty = receipt(sets: 0, exercises: 0, planned: 3, complete: false, sessionId: nil)
        #expect(empty.summaryLine.contains("No sets were logged"))
        #expect(!empty.facts.contains { $0.label.contains("Set") })
        // Without a structured session the receipt still has a durable identity.
        #expect(empty.id == "w1")
    }

    // MARK: Refusals

    /// The refusal shake interpolates. Storing its phase as an integer rounded
    /// every intermediate value to zero, so the effect drew nothing at all.
    @Test func theRefusalShakeActuallyMoves() {
        // `m31` is the horizontal translation the effect applies.
        let offset = ShakeEffect(phase: 1.25)
            .effectValue(size: CGSize(width: 100, height: 44)).m31
        #expect(abs(offset) > 0.5)
        // It settles at whole phases, which is where it comes to rest.
        #expect(abs(ShakeEffect(phase: 2).effectValue(size: .zero).m31) < 0.001)
    }
}
