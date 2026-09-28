import Foundation

@MainActor
enum TrainingEdits {
    /// A calendar edit or substitution creates a revision. Completed
    /// prescriptions stay in their original snapshot; every unfinished workout
    /// keeps its UI id.
    private static func editPlannedWorkout(
        _ workoutId: String,
        _ edit: (inout PlannedSession, TrainingProgram) throws -> Bool
    ) throws {
        let records = TrainingRecordsStore.shared
        let previous = WorkoutsStore.shared.workouts
        guard let workout = previous.first(where: { $0.id == workoutId }),
              let plannedReference = workout.planned,
              workout.completion == nil
        else { throw TrainingPersistenceError("This workout cannot be edited.") }

        if records.data.activeWorkout != nil || ActiveWorkoutStore.shared.session != nil {
            throw TrainingPersistenceError(
                "Finish or end your current workout before editing the plan."
            )
        }

        let programId = plannedReference.programId
        let sessionId = plannedReference.sessionId
        guard ProgramRecords.isStartablePlannedSession(records.data, programId, sessionId) else {
            throw TrainingPersistenceError("This planned session is no longer available.")
        }
        guard let source = records.data.programs.first(where: { $0.id == programId }) else {
            throw TrainingPersistenceError("This planned session is no longer available.")
        }

        var program = ProgramRecords.toEngineProgram(source.snapshot)
        var pending = program.weeks
            .flatMap(\.sessions)
            .filter { session in
                !ProgramRecords.isSupersededPlannedSession(records.data, source.id, session.id)
                    && !records.data.sessions.contains { $0.plannedSessionId == session.id }
                    && !previous.contains {
                        $0.planned?.sessionId == session.id && $0.completion != nil
                    }
                    // A past day with no workout on screen was deleted or
                    // skipped: it is not carried into the next revision.
                    && (previous.contains { $0.planned?.sessionId == session.id }
                        || String(session.scheduledAt.prefix(10)) >= CalendarDate.today)
            }
        guard let targetIndex = pending.firstIndex(where: { $0.id == sessionId }) else {
            throw TrainingPersistenceError("This session has already been recorded.")
        }

        var target = pending[targetIndex]
        let keepTarget = try edit(&target, program)
        pending[targetIndex] = target

        let replacedSessionIds = pending.map(\.id)
        let newProgramId = "program-\(UUID().uuidString.lowercased())"
        let generatedAt = ISOTime.now()

        var newSessionIds: [String: String] = [:]
        var weekOrder: [String] = []
        var weeks: [String: TrainingWeek] = [:]
        let template = program.weeks.first

        let carried = pending
            .enumerated()
            .filter { keepTarget || $0.offset != targetIndex }
            .map(\.element)
            .sorted { $0.scheduledAt.compare($1.scheduledAt) == .orderedAscending }

        for var session in carried {
            let start = EngineWorkout.mondayFor(String(session.scheduledAt.prefix(10)))
            if weeks[start] == nil {
                var week = template ?? TrainingWeek(
                    id: "", start: start, phase: .base, sessions: [], targets: []
                )
                week.id = "\(newProgramId)/week-\(weeks.count)"
                week.start = start
                week.sessions = []
                weeks[start] = week
                weekOrder.append(start)
            }
            guard var week = weeks[start] else { continue }
            let newId = "\(week.id)/session-\(week.sessions.count)"
            newSessionIds[session.id] = newId
            session.id = newId
            for exerciseIndex in session.exercises.indices {
                let exerciseId = session.exercises[exerciseIndex].exerciseId
                for setIndex in session.exercises[exerciseIndex].workingSets.indices {
                    session.exercises[exerciseIndex].workingSets[setIndex].id =
                        "\(newId)/\(exerciseId)/work/\(setIndex)"
                }
                for setIndex in session.exercises[exerciseIndex].warmupSets.indices {
                    session.exercises[exerciseIndex].warmupSets[setIndex].id =
                        "\(newId)/\(exerciseId)/warm/\(setIndex)"
                }
            }
            week.sessions.append(session)
            weeks[start] = week
        }

        if weeks.isEmpty, var start = template {
            start.id = "\(newProgramId)/week-0"
            start.sessions = []
            weeks[start.start] = start
            weekOrder.append(start.start)
        }

        program.id = newProgramId
        program.generatedAt = generatedAt
        program.adaptation = nil
        program.weeks = weekOrder.compactMap { weeks[$0] }
        program.durationWeeks = program.weeks.count

        let views = TrainingPlan.sessionViews(program)
        var byId: [String: PlannedSessionView] = [:]
        for view in views { byId[view.sessionId] = view }
        let pendingIds = Set(replacedSessionIds)

        var projected: [Workout] = []
        for item in previous {
            let wasPending = item.planned?.programId == programId
                && pendingIds.contains(item.planned?.sessionId ?? "")
            let newId = item.planned?.programId == programId
                ? newSessionIds[item.planned?.sessionId ?? ""]
                : nil
            if let newId, let view = byId[newId] {
                var updated = item
                updated.date = view.date
                updated.exerciseIds = view.exerciseIds
                updated.updatedAt = generatedAt
                updated.planned = PlannedWorkoutReference(
                    programId: program.id, sessionId: view.sessionId
                )
                projected.append(updated)
            } else if !wasPending {
                projected.append(item)
            }
        }
        for view in views where !projected.contains(where: {
            $0.planned?.sessionId == view.sessionId
        }) {
            projected.append(Workout(
                id: "planned-\(view.sessionId)",
                name: view.title,
                date: view.date,
                exerciseIds: view.exerciseIds,
                completion: nil,
                createdAt: generatedAt,
                updatedAt: generatedAt,
                planned: PlannedWorkoutReference(
                    programId: program.id, sessionId: view.sessionId
                )
            ))
        }

        WorkoutsStore.shared.replaceAll(projected)
        do {
            try records.saveProgram(
                program,
                activate: source.effectiveKind != .workout,
                kind: source.kind,
                manualSourceProgramId: programId,
                replacedSessionIds: replacedSessionIds
            )
        } catch {
            WorkoutsStore.shared.replaceAll(previous)
            throw error
        }
    }

    /// Deletes any workout: one still to come, one from a replaced plan, or one
    /// already trained. A trained workout takes its logged sessions with it, so
    /// history, streak and records stop counting it.
    static func deleteWorkout(_ workoutId: String) throws {
        let records = TrainingRecordsStore.shared
        guard let workout = WorkoutsStore.shared.workout(workoutId) else {
            throw TrainingPersistenceError("This workout cannot be deleted.")
        }
        if ActiveWorkoutStore.shared.session?.workoutId == workoutId
            || records.data.activeWorkout?.sourceWorkoutId == workoutId
            || records.data.transition?.sourceWorkoutId == workoutId {
            throw TrainingPersistenceError("Finish or end this workout before deleting it.")
        }
        guard isHistory(workout) else {
            try deleteScheduledWorkout(workoutId)
            return
        }
        // The sessions go first: if the app stopped in between, what is left
        // is a workout that can still be seen and deleted, never sessions that
        // count in the stats with nothing on screen to delete.
        try records.deleteCompletedSessions(sourceWorkoutId: workoutId, planned: workout.planned)
        WorkoutsStore.shared.deleteWorkout(workoutId)
    }

    /// Trained already, finished or not: completed, or with a session on record.
    static func isHistory(_ workout: Workout) -> Bool {
        if workout.completion != nil { return true }
        let sessions = TrainingRecordsStore.shared.data.sessions
        if sessions.contains(where: { $0.sourceWorkoutId == workout.id }) { return true }
        guard let planned = workout.planned else { return false }
        return sessions.contains { $0.plannedSessionId == planned.sessionId }
    }

    static func deleteScheduledWorkout(_ workoutId: String) throws {
        guard let workout = WorkoutsStore.shared.workout(workoutId), workout.completion == nil
        else { throw TrainingPersistenceError("This workout cannot be deleted.") }

        guard let planned = workout.planned else {
            WorkoutsStore.shared.deleteWorkout(workoutId)
            return
        }
        let source = TrainingRecordsStore.shared.data.programs.first {
            $0.id == planned.programId
        }
        // A session whose plan has been replaced belongs to no plan any more:
        // it goes like a workout of its own, and the old plan stays as it was.
        if source?.effectiveKind == .workout || ActiveWorkoutStore.planWasReplaced(workout) {
            WorkoutsStore.shared.deleteWorkout(workoutId)
            return
        }
        try editPlannedWorkout(workoutId) { _, _ in false }
    }

    static func updateScheduledWorkoutExercises(
        _ workoutId: String,
        _ exerciseIds: [String],
        rePrescribe: Bool = false
    ) throws {
        guard let workout = WorkoutsStore.shared.workout(workoutId), workout.completion == nil
        else { throw TrainingPersistenceError("This workout cannot be edited.") }

        var seen = Set<String>()
        let unique = exerciseIds.filter { seen.insert($0).inserted }

        guard workout.planned != nil else {
            WorkoutsStore.shared.updateWorkout(
                workoutId, WorkoutsStore.WorkoutPatch(exerciseIds: unique)
            )
            return
        }

        try editPlannedWorkout(workoutId) { session, program in
            var request = TrainingWorkflow.buildTrainingRequest(
                TrainingEngineAdapter.buildEngineInputs(), now: ISOTime.now()
            )
            request.policy = program.policy
            let input = Generate.preparation(
                request, previousProgram: program, index: TrainingWorkflow.trainingIndex()
            )
            var existing: [String: PlannedExercise] = [:]
            for exercise in session.exercises { existing[exercise.exerciseId] = exercise }

            let exercises = unique.compactMap { exerciseId -> PlannedExercise? in
                guard let indexed = input.index.byId[exerciseId] else { return nil }
                let previous = existing[exerciseId]
                if let previous, !rePrescribe { return previous }
                return Prescribe.exercise(
                    indexed,
                    count: previous?.workingSets.count ?? 3,
                    sessionId: session.id,
                    rationale: .zero,
                    input: input
                )
            }
            session.exercises = exercises.enumerated().map { order, exercise in
                var updated = exercise
                updated.order = order
                return updated
            }
            var seenMuscles = Set<MuscleId>()
            session.focus = session.exercises
                .flatMap(\.targetMuscles)
                .filter { seenMuscles.insert($0).inserted }
            session.duration = SessionTiming.estimateSession(
                session.exercises, input.index, input.policy
            )
            return true
        }
    }

    static func rescheduleWorkout(_ workoutId: String, date: String) throws {
        guard let workout = WorkoutsStore.shared.workout(workoutId), workout.completion == nil
        else { throw TrainingPersistenceError("This workout cannot be rescheduled.") }

        guard date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              CalendarDate.parse(date) != nil
        else { throw TrainingPersistenceError("Choose a valid workout date.") }
        guard date >= CalendarDate.today else {
            throw TrainingPersistenceError("Choose today or a future date.")
        }
        if ActiveWorkoutStore.shared.session?.workoutId == workoutId {
            throw TrainingPersistenceError("A running workout stays on the day it started.")
        }
        if workout.date == date { return }

        guard workout.planned != nil else {
            WorkoutsStore.shared.updateWorkout(workoutId, WorkoutsStore.WorkoutPatch(date: date))
            return
        }
        try editPlannedWorkout(workoutId) { session, _ in
            session.scheduledAt = "\(date)T00:00:00.000Z"
            return true
        }
    }

    static func substituteScheduledPlannedExercise(
        _ workoutId: String,
        _ exerciseId: String,
        _ replacementId: String
    ) throws {
        guard TrainingWorkflow.replacementIds(exerciseId, workoutId: workoutId)
            .contains(replacementId)
        else {
            throw TrainingPersistenceError(
                "That alternative no longer fits this workout and your equipment."
            )
        }

        try editPlannedWorkout(workoutId) { session, program in
            guard let position = session.exercises.firstIndex(where: {
                $0.exerciseId == exerciseId
            }), !session.exercises.contains(where: { $0.exerciseId == replacementId })
            else {
                throw TrainingPersistenceError(
                    "Choose an exercise that is not already in this session."
                )
            }
            var request = TrainingWorkflow.buildTrainingRequest(
                TrainingEngineAdapter.buildEngineInputs(), now: ISOTime.now()
            )
            request.policy = program.policy
            let input = Generate.preparation(
                request, previousProgram: program, index: TrainingWorkflow.trainingIndex()
            )
            guard let indexed = input.index.byId[replacementId] else {
                throw TrainingPersistenceError("That exercise is not in the catalogue.")
            }
            let original = session.exercises[position]
            var replacement = Prescribe.exercise(
                indexed,
                count: original.workingSets.count,
                sessionId: session.id,
                rationale: original.rationale,
                input: input
            )
            replacement.order = original.order
            session.exercises[position] = replacement
            session.duration = SessionTiming.estimateSession(
                session.exercises, input.index, input.policy
            )
            return true
        }
    }
}

@MainActor
enum PlannedSubstitution {
    /// Replaces one exercise while a planned workout is actually being performed.
    ///
    /// The program snapshot remains immutable. The structured draft changes
    /// first, preserving its planned lineage, then the workout shell is updated
    /// so the timer and checklist follow the performed exercise.
    static func substituteRunningPlannedExercise(
        _ workoutId: String,
        _ exerciseId: String,
        _ replacementId: String
    ) throws {
        let workoutsStore = WorkoutsStore.shared
        let records = TrainingRecordsStore.shared
        let running = ActiveWorkoutStore.shared.session
        let draft = records.data.activeWorkout

        guard let workout = workoutsStore.workout(workoutId),
              let planned = workout.planned,
              running?.workoutId == workoutId
        else {
            throw TrainingPersistenceError(
                "Start this planned workout before changing an exercise."
            )
        }
        guard let draft,
              draft.sourceWorkoutId == workoutId,
              draft.plannedProgramId == planned.programId,
              draft.plannedSessionId == planned.sessionId
        else {
            throw TrainingPersistenceError(
                "The active training record no longer matches this workout."
            )
        }
        if workout.exerciseIds.contains(replacementId) {
            throw TrainingPersistenceError("That exercise is already in this workout.")
        }
        guard TrainingWorkflow.replacementIds(exerciseId, workoutId: workoutId)
            .contains(replacementId)
        else {
            throw TrainingPersistenceError(
                "That alternative no longer fits this training session."
            )
        }
        guard let entry = draft.exercises.first(where: {
            $0.exerciseId == exerciseId && $0.plannedExerciseId != nil
        }) else {
            throw TrainingPersistenceError("Planned exercise not found in the active workout.")
        }

        let sourceProgram = records.data.programs.first { $0.id == planned.programId }
        let input = Generate.preparation(
            TrainingWorkflow.buildTrainingRequest(
                TrainingEngineAdapter.buildEngineInputs(
                    overrides: TrainingEngineAdapter.PreferenceOverrides(
                        goal: sourceProgram?.snapshot.goal
                    )
                ),
                now: ISOTime.now()
            ),
            previousProgram: nil,
            index: TrainingWorkflow.trainingIndex()
        )
        guard let indexed = input.index.byId[replacementId] else {
            throw TrainingPersistenceError("That exercise is not in the catalogue.")
        }
        let workingSetCount = Swift.max(1, entry.sets.filter { $0.setType == .working }.count)
        let prescribed = Prescribe.exercise(
            indexed,
            count: workingSetCount,
            sessionId: planned.sessionId,
            rationale: .zero,
            input: input
        )

        // A different station or movement must never inherit the old exercise's
        // kilograms.
        let targets: [PersistedSetTarget?] = entry.sets.map { set in
            let source = set.setType == .warmup
                ? prescribed.warmupSets.first
                : prescribed.workingSets.first
            if let source {
                return PersistedSetTarget(
                    reps: source.targetReps,
                    rir: source.targetRir,
                    resistance: source.resistance
                )
            }
            guard var existing = set.target else { return nil }
            existing.resistance = .unknown
            return existing
        }

        let previousWorkouts = workoutsStore.workouts
        do {
            try records.substituteExercise(
                exerciseEntryId: entry.id,
                exerciseId: replacementId,
                targets: targets
            )
            workoutsStore.updateWorkout(workoutId, WorkoutsStore.WorkoutPatch(
                exerciseIds: workout.exerciseIds.map {
                    $0 == exerciseId ? replacementId : $0
                }
            ))
        } catch {
            workoutsStore.replaceAll(previousWorkouts)
            throw error
        }
    }
}
