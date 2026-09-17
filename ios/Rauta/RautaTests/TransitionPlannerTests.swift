import Testing
@testable import Rauta

/// Recovery of an interrupted start, finish or cancel: the planner must carry
/// the transition to the same end however often it is replayed.
@Suite("Workout transition reconciliation")
struct TransitionPlannerTests {
    private let startedAtMs = 1_780_000_000_000.0

    private func draft(id: String = "draft-1", workout: String = "w1") -> PersistedActiveWorkoutDraft {
        PersistedActiveWorkoutDraft(
            id: id,
            sourceWorkoutId: workout,
            plannedProgramId: nil,
            plannedSessionId: nil,
            startedAt: ISOTime.string(fromMillis: startedAtMs),
            exercises: []
        )
    }

    private func intent(_ kind: PersistedTransitionIntent.Kind, draftId: String? = "draft-1") -> PersistedTransitionIntent {
        PersistedTransitionIntent(
            id: "intent-1",
            kind: kind,
            recordedAt: ISOTime.string(fromMillis: startedAtMs),
            sourceWorkoutId: "w1",
            draftId: draftId,
            planned: nil,
            shell: PersistedTransitionShell(
                workoutName: "Full body",
                workoutDate: "2026-09-17",
                exerciseIds: ["a", "b"],
                startedAtMs: startedAtMs
            ),
            completedAt: kind == .finish ? ISOTime.string(fromMillis: startedAtMs + 60_000) : nil,
            sessionId: kind == .start ? nil : "session-1",
            status: kind == .finish ? .completed : nil,
            legacy: nil
        )
    }

    private func input(
        _ intent: PersistedTransitionIntent?,
        draft: PersistedActiveWorkoutDraft?,
        shellWorkoutId: String? = nil,
        shellStartedAtMs: Double? = nil
    ) -> TransitionPlanner.Input {
        TransitionPlanner.Input(
            intent: intent,
            draft: draft,
            sessions: [],
            workoutCompleted: false,
            workoutExists: true,
            shellWorkoutId: shellWorkoutId,
            shellStartedAtMs: shellStartedAtMs
        )
    }

    @Test func nothingInFlightChangesNothing() {
        let plan = TransitionPlanner.plan(input(nil, draft: draft()))
        #expect(plan.reason == .none)
        #expect(plan.clearIntent == false)
        #expect(plan.shell == .keep)
    }

    @Test func startWhoseShellNeverAppearedIsRestored() throws {
        let plan = TransitionPlanner.plan(input(intent(.start), draft: draft()))
        #expect(plan.reason == .startResumed)
        #expect(plan.shell == .restore)
        let restore = try #require(plan.restore)
        #expect(restore.workoutId == "w1")
        #expect(restore.exerciseIds == ["a", "b"])
        #expect(restore.startedAtMs == startedAtMs)
    }

    @Test func startAlreadyCompleteOnlySpendsTheIntent() {
        let plan = TransitionPlanner.plan(
            input(intent(.start), draft: draft(), shellWorkoutId: "w1", shellStartedAtMs: startedAtMs)
        )
        #expect(plan.reason == .startSettled)
        #expect(plan.shell == .keep)
        #expect(plan.clearIntent)
    }

    @Test func startWhoseDraftNeverLandedIsAbandoned() {
        let plan = TransitionPlanner.plan(input(intent(.start), draft: nil, shellWorkoutId: "w1"))
        #expect(plan.reason == .startAbandoned)
        #expect(plan.shell == .clear)
    }

    @Test func staleIntentNeverClosesAnUnrelatedDraft() {
        let plan = TransitionPlanner.plan(input(intent(.finish), draft: draft(id: "other-draft")))
        #expect(plan.reason == .intentStale)
        #expect(plan.draft == .keep)
        #expect(plan.close == nil)
    }

    @Test func finishClosesTheDraftAtTheRecordedInstant() throws {
        let finish = intent(.finish)
        let plan = TransitionPlanner.plan(input(finish, draft: draft(), shellWorkoutId: "w1"))
        #expect(plan.reason == .finishResumed)
        #expect(plan.draft == .close)
        #expect(plan.shell == .clear)
        let close = try #require(plan.close)
        #expect(close.sessionId == "session-1")
        #expect(close.completedAt == finish.completedAt)
        #expect(close.status == .completed)
    }

    @Test func cancelIsAlwaysPartial() throws {
        let plan = TransitionPlanner.plan(input(intent(.cancel), draft: draft()))
        #expect(plan.reason == .cancelResumed)
        #expect(try #require(plan.close).status == .partial)
    }

    @Test func replayingAPlanIsDeterministic() {
        let value = input(intent(.finish), draft: draft(), shellWorkoutId: "w1")
        let first = TransitionPlanner.plan(value)
        let second = TransitionPlanner.plan(value)
        #expect(first.reason == second.reason)
        #expect(first.draft == second.draft)
        #expect(first.close?.sessionId == second.close?.sessionId)
    }
}
