import Foundation

/// The seam between the workout a person is running and the structured record
/// of what they actually did.
///
/// The app has two halves of a session: the shell — the clock, the current
/// exercise, the check marks — and the training records, which hold real
/// observations the deterministic engine can read. This file keeps exactly one
/// draft alive alongside exactly one running session, so a manually built
/// workout produces the same structured history a generated one will.
///
/// Nothing here invents performance. Starting a workout creates an empty draft:
/// the exercises are listed, and not one set exists until a set is logged.
@MainActor
enum TrainingSessionBridge {
    /// The performed exercise inside the live draft, or nil when the session has
    /// no structured draft.
    static func draftExercise(
        _ draft: PersistedActiveWorkoutDraft?,
        _ exerciseId: String
    ) -> PersistedActiveExerciseDraft? {
        draft?.exercises.first { $0.exerciseId == exerciseId }
    }

    /// Exercises of the live draft that carry at least one performed set. A
    /// logged set is the stronger statement: an exercise nobody remembered to
    /// check off is still an exercise that was done.
    static func performedExerciseIds() -> Set<String> {
        let draft = TrainingRecordsStore.shared.data.activeWorkout
        return Set(
            (draft?.exercises ?? [])
                .filter { exercise in exercise.sets.contains { $0.observation?.completed == true } }
                .map(\.exerciseId)
        )
    }

    private static func draftHasObservations(_ draft: PersistedActiveWorkoutDraft?) -> Bool {
        draft?.exercises.contains { exercise in
            exercise.sets.contains { $0.observation?.completed == true }
        } ?? false
    }

    /// Opens the structured draft for a session that is starting.
    ///
    /// A draft left behind by an earlier session is closed first rather than
    /// discarded: whatever sets it holds were genuinely performed, and they
    /// belong in history under their own session, not in this one.
    ///
    /// A planned workout must keep its lineage: when its planned draft cannot be
    /// opened this returns false and no free draft is substituted for it.
    static func beginTrainingDraft(
        exerciseIds: [String],
        startedAt: String,
        sourceWorkoutId: String,
        planned: PlannedWorkoutReference?
    ) -> Bool {
        let store = TrainingRecordsStore.shared
        if let stale = store.data.activeWorkout {
            _ = try? store.abortWorkout(completedAt: draftClosingTime(stale, now: startedAt))
        }
        if let planned {
            do {
                try store.startPlannedWorkout(
                    programId: planned.programId,
                    plannedSessionId: planned.sessionId,
                    startedAt: startedAt,
                    sourceWorkoutId: sourceWorkoutId
                )
                return true
            } catch {
                return false
            }
        }
        do {
            try store.startFreeWorkout(
                exerciseIds: exerciseIds,
                startedAt: startedAt,
                sourceWorkoutId: sourceWorkoutId
            )
            return true
        } catch {
            return false
        }
    }

    /// When a stale draft is treated as having ended: now, or the moment of its
    /// own last recorded set if the device clock has since moved backwards. A
    /// session cannot have finished before the work it contains.
    static func draftClosingTime(
        _ draft: PersistedActiveWorkoutDraft,
        now: String = ISOTime.now()
    ) -> String {
        var instants: [Double] = [
            ISOTime.parse(now) ?? 0,
            ISOTime.parse(draft.startedAt) ?? 0,
        ]
        for exercise in draft.exercises {
            for set in exercise.sets {
                if let timestamp = set.observation?.timestamp,
                   let parsed = ISOTime.parse(timestamp) {
                    instants.append(parsed)
                }
            }
        }
        return ISOTime.string(fromMillis: instants.max() ?? 0)
    }

    /// Follows the workout being edited while it runs.
    ///
    /// Only additions are mirrored. An exercise dropped from the workout keeps
    /// its draft entry, because removing it from the plan says nothing about
    /// whether it was performed.
    static func syncTrainingDraftExercises(_ exerciseIds: [String]) {
        let store = TrainingRecordsStore.shared
        guard let draft = store.data.activeWorkout else { return }

        for exerciseId in exerciseIds {
            guard !draft.exercises.contains(where: { $0.exerciseId == exerciseId }) else { continue }
            guard let program = try? EngineWorkout.buildProgram(EngineWorkout.Input(
                date: CalendarDate.today,
                exerciseIds: [exerciseId]
            )),
                  let prescribed = program.weeks.first?.sessions.first?.exercises.first
            else { continue }
            try? store.addExercise(
                exerciseId,
                targets: prescribed.workingSets.map { set in
                    PersistedSetTarget(
                        reps: set.targetReps,
                        rir: set.targetRir,
                        resistance: set.resistance
                    )
                }
            )
        }

        guard let current = store.data.activeWorkout else { return }
        let requested = exerciseIds.compactMap { exerciseId in
            current.exercises.first { $0.exerciseId == exerciseId }?.id
        }
        let retainedHistory = current.exercises
            .filter { !exerciseIds.contains($0.exerciseId) }
            .map(\.id)
        try? store.reorderExercises(requested + retainedHistory)
    }

    /// The planned session a draft is performing, read back out of the immutable
    /// snapshot it was opened from.
    private static func plannedSession(
        _ data: PersistedTrainingState,
        _ draft: PersistedActiveWorkoutDraft
    ) -> PlannedSession? {
        guard let record = data.programs.first(where: { $0.id == draft.plannedProgramId })
        else { return nil }
        return ProgramRecords.toEngineProgram(record.snapshot)
            .weeks
            .flatMap(\.sessions)
            .first { $0.id == draft.plannedSessionId }
    }

    /// How much of the running session's prescription has been performed, or nil
    /// when there is nothing prescribed.
    static func activePlannedCoverage(
        _ data: PersistedTrainingState? = nil
    ) -> WorkoutDrafts.PlannedWorkCoverage? {
        let data = data ?? TrainingRecordsStore.shared.data
        guard let draft = data.activeWorkout else { return nil }
        return WorkoutDrafts.plannedWorkCoverage(draft, plannedSession(data, draft))
    }

    /// Closes the draft the way the session ended.
    ///
    /// Only sets with a real observation are written. The status is what the
    /// evidence supports rather than which button was pressed: a session walked
    /// away from is partial, and a finished one is completed only when every
    /// prescribed working set was actually performed.
    @discardableResult
    static func endTrainingDraft(
        outcome: ActiveWorkoutOutcome,
        completedAt: String = ISOTime.now()
    ) -> String? {
        let store = TrainingRecordsStore.shared
        guard let draft = store.data.activeWorkout else { return nil }
        if !draftHasObservations(draft) {
            try? store.cancelWorkout()
            return nil
        }
        let covered = activePlannedCoverage(store.data)?.complete ?? true
        return try? store.completeWorkout(
            status: outcome == .finished && covered ? .completed : .partial,
            completedAt: completedAt
        )
    }
}
