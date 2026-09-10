import Foundation

/// One prescribed session, built with the same ranking, progression and duration
/// rules the weekly planner uses.
@MainActor
enum EngineWorkout {
    struct Input {
        var date: String
        var exerciseIds: [String]?
        var focusMuscles: [MuscleId]?
        var avoidExerciseIds: [String]?
        var availableEquipment: [String]?
        var now: String?

        init(
            date: String,
            exerciseIds: [String]? = nil,
            focusMuscles: [MuscleId]? = nil,
            avoidExerciseIds: [String]? = nil,
            availableEquipment: [String]? = nil,
            now: String? = nil
        ) {
            self.date = date
            self.exerciseIds = exerciseIds
            self.focusMuscles = focusMuscles
            self.avoidExerciseIds = avoidExerciseIds
            self.availableEquipment = availableEquipment
            self.now = now
        }
    }

    static func mondayFor(_ date: String) -> String {
        guard let millis = ISOTime.parse("\(date)T00:00:00.000Z") else { return date }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: millis / 1000)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: start) ?? start
        return ISOTime.string(from: monday)
    }

    private static func focusFor(
        _ exerciseIds: [String],
        _ requested: [MuscleId]?
    ) -> [MuscleId] {
        var seen = Set<MuscleId>()
        if let requested, !requested.isEmpty {
            return requested.filter { seen.insert($0).inserted }
        }
        var result: [MuscleId] = []
        for id in exerciseIds {
            for muscle in ExerciseCatalogue.byId[id]?.muscles ?? []
            where seen.insert(muscle).inserted {
                result.append(muscle)
            }
        }
        return result
    }

    static func buildProgram(_ input: Input) throws -> TrainingProgram {
        let now = input.now ?? ISOTime.now()
        var overrides = TrainingEngineAdapter.PreferenceOverrides()
        if let availableEquipment = input.availableEquipment {
            overrides.availableEquipment = availableEquipment
        }
        var request = TrainingWorkflow.buildTrainingRequest(
            TrainingEngineAdapter.buildEngineInputs(overrides: overrides),
            now: now
        )
        request.schedule = TrainingSchedule(
            weekStart: mondayFor(input.date),
            days: [0],
            sessionDays: nil,
            durationWeeks: 1
        )

        let optimization = Generate.preparation(
            request, previousProgram: nil, index: TrainingWorkflow.trainingIndex()
        )
        let focus = focusFor(input.exerciseIds ?? [], input.focusMuscles)
        let ranked = Ranking.rankExerciseCandidates(request, focus: focus)
        var ranking: [String: Score] = [:]
        for candidate in ranked { ranking[candidate.exerciseId] = candidate.score }

        var seen = Set<String>()
        var exerciseIds = (input.exerciseIds ?? [])
            .filter { seen.insert($0).inserted && optimization.index.byId[$0] != nil }

        if exerciseIds.isEmpty {
            let requested = Set(focus)
            let avoided = Set(input.avoidExerciseIds ?? [])
            let eligible = ranked.filter { candidate in
                optimization.index.byId[candidate.exerciseId]?.metadata.setRoles.contains {
                    $0.role == .direct && requested.contains($0.muscleId)
                } ?? false
            }

            var picked: [String] = []
            for muscleId in focus {
                let choices = eligible.filter { candidate in
                    !picked.contains(candidate.exerciseId)
                        && (optimization.index.byId[candidate.exerciseId]?.metadata.setRoles.contains {
                            $0.role == .direct && $0.muscleId == muscleId
                        } ?? false)
                }
                let fresh = choices.filter { !avoided.contains($0.exerciseId) }
                let pool = Array((fresh.isEmpty ? choices : fresh).prefix(4))
                if let chosen = pool.randomElement() { picked.append(chosen.exerciseId) }
            }

            let remaining = eligible
                .filter { !picked.contains($0.exerciseId) }
                .sorted { left, right in
                    let leftAvoided = avoided.contains(left.exerciseId) ? 1 : 0
                    let rightAvoided = avoided.contains(right.exerciseId) ? 1 : 0
                    if leftAvoided != rightAvoided { return leftAvoided < rightAvoided }
                    return Bool.random()
                }
                .map(\.exerciseId)

            exerciseIds = Array(
                (picked + remaining).prefix(optimization.policy.maxExercisesPerSession)
            )
        }

        guard !exerciseIds.isEmpty else {
            throw TrainingPersistenceError(
                "No exercise matches those muscles and your saved equipment."
            )
        }

        let programId = "program-workout-\(UUID().uuidString.lowercased())"
        let weekId = "\(programId)/week-0"
        let sessionId = "\(weekId)/session-0"

        let exercises = exerciseIds.compactMap { exerciseId -> PlannedExercise? in
            guard let indexed = optimization.index.byId[exerciseId] else { return nil }
            return Prescribe.exercise(
                indexed,
                count: 3,
                sessionId: sessionId,
                rationale: ranking[exerciseId] ?? .zero,
                input: optimization
            )
        }
        let ordered = Scoring.orderExercises(exercises, optimization)

        let session = PlannedSession(
            id: sessionId,
            scheduledAt: "\(input.date)T00:00:00.000Z",
            focus: focus,
            exercises: ordered,
            duration: SessionTiming.estimateSession(
                ordered, optimization.index, optimization.policy
            )
        )
        let week = TrainingWeek(
            id: weekId,
            start: mondayFor(input.date),
            phase: .base,
            sessions: [session],
            targets: optimization.targets
        )
        let score = Scoring.scoreWeek(week, optimization)

        return TrainingProgram(
            id: programId,
            engineVersion: ENGINE_VERSION,
            policyVersion: optimization.policy.version,
            policy: optimization.policy,
            datasetFingerprint: optimization.index.fingerprint,
            generatedAt: now,
            goal: request.preferences.goal,
            durationWeeks: 1,
            weeks: [week],
            diagnostics: ProgramDiagnostics(
                splits: [SplitDiagnostic(name: "single_session", score: score.total, valid: true)],
                candidateCount: ranked.count,
                optimizerIterations: 0,
                selectedSplit: "single_session",
                score: score,
                warnings: []
            ),
            adaptation: nil
        )
    }

    static func propose(
        date: String,
        focusMuscles: [MuscleId],
        previousExerciseIds: [String]? = nil,
        availableEquipment: [String]? = nil
    ) throws -> [String] {
        let program = try buildProgram(Input(
            date: date,
            focusMuscles: focusMuscles,
            avoidExerciseIds: previousExerciseIds,
            availableEquipment: availableEquipment
        ))
        return program.weeks.first?.sessions.first?.exercises.map(\.exerciseId) ?? []
    }

    @discardableResult
    static func createWorkout(
        date: String,
        name: String? = nil,
        exerciseIds: [String]? = nil,
        focusMuscles: [MuscleId]? = nil,
        workoutId: String? = nil,
        now: String? = nil
    ) throws -> String {
        let program = try buildProgram(Input(
            date: date,
            exerciseIds: exerciseIds,
            focusMuscles: focusMuscles,
            now: now
        ))
        try TrainingRecordsStore.shared.saveProgram(program, activate: false, kind: .workout)
        guard let view = TrainingPlan.sessionViews(program).first else {
            throw TrainingPersistenceError("The generated workout had no session.")
        }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (trimmedName?.isEmpty == false) ? trimmedName! : view.title

        if let workoutId {
            WorkoutsStore.shared.updateWorkout(workoutId, WorkoutsStore.WorkoutPatch(
                name: title,
                date: date,
                exerciseIds: view.exerciseIds,
                planned: PlannedWorkoutReference(
                    programId: program.id, sessionId: view.sessionId
                )
            ))
            return workoutId
        }
        return WorkoutsStore.shared.createWorkout(
            name: title,
            date: date,
            exerciseIds: view.exerciseIds,
            planned: PlannedWorkoutReference(programId: program.id, sessionId: view.sessionId)
        )
    }

    static func duplicateWithEngine(_ workoutId: String, date: String) throws -> String {
        guard let source = WorkoutsStore.shared.workout(workoutId) else {
            throw TrainingPersistenceError("Workout not found.")
        }
        return try createWorkout(
            date: date,
            name: "\(source.name) copy",
            exerciseIds: source.exerciseIds
        )
    }

    /// Migrates a legacy unfinished workout when it next becomes relevant.
    @discardableResult
    static func ensureEngineWorkout(_ workoutId: String) -> String {
        guard let workout = WorkoutsStore.shared.workout(workoutId),
              workout.planned == nil,
              workout.completion == nil,
              !workout.exerciseIds.isEmpty,
              TrainingRecordsStore.shared.data.activeWorkout?.sourceWorkoutId != workoutId
        else { return workoutId }

        return (try? createWorkout(
            date: workout.date,
            name: workout.name,
            exerciseIds: workout.exerciseIds,
            workoutId: workoutId
        )) ?? workoutId
    }
}
