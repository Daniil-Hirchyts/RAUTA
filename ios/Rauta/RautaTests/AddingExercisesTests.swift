import Foundation
import Testing
@testable import Rauta

/// Exercises picked from inside a workout go into that workout, not through a
/// page asking where.
@Suite("Adding exercises to a workout")
@MainActor
struct AddingExercisesTests {
    @Test func aComingWorkoutTakesExercisesAfterItsOwnWithoutDuplicates() async throws {
        try await IsolatedStores.run {
            let id = WorkoutsStore.shared.createWorkout(
                name: "Mine", date: CalendarDate.shift(CalendarDate.today, by: 1), exerciseIds: ["0662"]
            )
            #expect(TrainingEdits.takesExercises(id))
            try TrainingEdits.addExercises(["1760", "0662", "0276"], to: id)
            #expect(WorkoutsStore.shared.workout(id)?.exerciseIds == ["0662", "1760", "0276"])
        }
    }

    @Test func aFinishedWorkoutTakesNoMore() async throws {
        try await IsolatedStores.run {
            try await IsolatedStores.finishWorkout()
            let finished = try #require(WorkoutsStore.shared.workouts.first { $0.completion != nil })
            #expect(!TrainingEdits.takesExercises(finished.id))
            #expect(throws: TrainingPersistenceError.self) {
                try TrainingEdits.addExercises(["1760"], to: finished.id)
            }
        }
    }

    @Test func aPlannedWorkoutTakesThemIntoItsPlan() async throws {
        try await IsolatedStores.run {
            let dates = PlanStart.nextWeek.dates(trainingDays: [1, 3, 5], firstWeekday: 2)
            guard case .created? = await TrainingPlan.createTrainingPlanForDates(dates: dates) else {
                Issue.record("No plan"); return
            }
            let workout = try #require(WorkoutsStore.shared.workouts.first { $0.planned != nil })
            let extra = try #require(["0276", "0705", "3013"].first { !workout.exerciseIds.contains($0) })
            #expect(TrainingEdits.takesExercises(workout.id))
            try TrainingEdits.addExercises([extra], to: workout.id)
            let after = try #require(WorkoutsStore.shared.workout(workout.id))
            #expect(after.exerciseIds.last == extra)
            let planned = try #require(after.planned)
            let view = try #require(TrainingPlan.plannedSessionView(planned.programId, planned.sessionId))
            #expect(view.exerciseIds.contains(extra))
        }
    }
}
