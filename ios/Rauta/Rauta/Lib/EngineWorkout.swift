import Foundation

/// One prescribed session, built with the same ranking, progression and duration
/// rules the weekly planner uses.
@MainActor
enum EngineWorkout {
    struct Input: Sendable {
        var date: String
        var exerciseIds: [String]?
        var focusMuscles: [MuscleId]?
        var avoidExerciseIds: [String]?
        var availableEquipment: [String]?
        var now: String?
        /// How the person says they are today; sore muscles rank lower.
        var readiness: Readiness?

        init(
            date: String,
            exerciseIds: [String]? = nil,
            focusMuscles: [MuscleId]? = nil,
            avoidExerciseIds: [String]? = nil,
            availableEquipment: [String]? = nil,
            now: String? = nil,
            readiness: Readiness? = nil
        ) {
            self.date = date
            self.exerciseIds = exerciseIds
            self.focusMuscles = focusMuscles
            self.avoidExerciseIds = avoidExerciseIds
            self.availableEquipment = availableEquipment
            self.now = now
            self.readiness = readiness
        }
    }

    nonisolated static func mondayFor(_ date: String) -> String {
        guard let millis = ISOTime.parse("\(date)T00:00:00.000Z") else { return date }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(epochMillis: millis)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: start) ?? start
        return ISOTime.string(from: monday)
    }

    nonisolated private static func focusFor(
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

    /// What composing a session needs from the stores, read on the main actor.
    struct Prepared: Sendable {
        var request: ProgramGenerationRequest
        var index: ExerciseIndex
        var now: String
    }

    static func prepare(_ input: Input) -> Prepared {
        let now = input.now ?? ISOTime.now()
        var overrides = TrainingEngineAdapter.PreferenceOverrides()
        if let availableEquipment = input.availableEquipment {
            overrides.availableEquipment = availableEquipment
        }
        var request = TrainingWorkflow.buildTrainingRequest(
            TrainingEngineAdapter.buildEngineInputs(overrides: overrides),
            now: now,
            readiness: input.readiness
        )
        request.schedule = TrainingSchedule(
            weekStart: mondayFor(input.date),
            days: [0],
            sessionDays: nil,
            durationWeeks: 1
        )
        return Prepared(request: request, index: TrainingWorkflow.trainingIndex(), now: now)
    }

    /// Builds the session where it is asked for — for the prescription of a
    /// single exercise added mid-workout, which is small.
    static func buildProgram(_ input: Input) throws -> TrainingProgram {
        try compose(input, prepare(input))
    }

    /// Builds the session away from the main actor: ranking the catalogue is
    /// the expensive part of proposing a workout.
    @concurrent
    static func buildProgramInBackground(_ input: Input, _ prepared: Prepared) async throws -> TrainingProgram {
        try Task.checkCancellation()
        return try compose(input, prepared)
    }

    nonisolated private static func compose(_ input: Input, _ prepared: Prepared) throws -> TrainingProgram {
        let now = prepared.now
        let request = prepared.request
        let optimization = Generate.preparation(
            request, previousProgram: nil, index: prepared.index
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
        availableEquipment: [String]? = nil,
        readiness: Readiness? = nil
    ) async throws -> [String] {
        let input = Input(
            date: date,
            focusMuscles: focusMuscles,
            avoidExerciseIds: previousExerciseIds,
            availableEquipment: availableEquipment,
            readiness: readiness
        )
        let program = try await buildProgramInBackground(input, prepare(input))
        return program.weeks.first?.sessions.first?.exercises.map(\.exerciseId) ?? []
    }

    /// Builds the workout's session off the main actor, then records it.
    ///
    /// A workout RAUTA picked the exercises for — `focusMuscles` and no
    /// `exerciseIds`, or `rautaBuilt` for a proposal RAUTA picked earlier —
    /// remembers those muscles, so it can be built again.
    @discardableResult
    static func createWorkout(
        date: String,
        name: String? = nil,
        exerciseIds: [String]? = nil,
        focusMuscles: [MuscleId]? = nil,
        rautaBuilt: Bool? = nil,
        availableEquipment: [String]? = nil,
        workoutId: String? = nil,
        now: String? = nil,
        expectedBasis: PlanBasis? = nil
    ) async throws -> String {
        let input = Input(
            date: date,
            exerciseIds: exerciseIds,
            focusMuscles: focusMuscles,
            availableEquipment: availableEquipment,
            now: now
        )
        let program = try await buildProgramInBackground(input, prepare(input))
        if let expectedBasis, PlanBasis.current() != expectedBasis {
            throw TrainingPersistenceError("Training changed while the workout was being built. Ask for a fresh preview.")
        }
        let rautaFocus = (rautaBuilt ?? (exerciseIds?.isEmpty ?? true)) ? focusMuscles : nil
        return try record(program, date: date, name: name, workoutId: workoutId, rautaFocus: rautaFocus)
    }

    /// Builds a RAUTA-built workout again around the same muscles, with other
    /// exercises where there are other good ones, in place: same day, same
    /// name, same workout. Only for a workout nobody has started.
    static func regenerate(_ workoutId: String) async throws {
        guard let workout = WorkoutsStore.shared.workout(workoutId),
              let focus = workout.rautaFocus, !focus.isEmpty,
              canRegenerate(workout)
        else { throw TrainingPersistenceError("This workout can't be rebuilt any more.") }
        let basis = PlanBasis.current()
        let input = Input(date: workout.date, focusMuscles: focus, avoidExerciseIds: workout.exerciseIds)
        let program = try await buildProgramInBackground(input, prepare(input))
        guard let current = WorkoutsStore.shared.workout(workoutId), canRegenerate(current),
              PlanBasis.current() == basis
        else { throw TrainingPersistenceError("Training changed while the workout was being rebuilt.") }
        _ = try record(program, date: current.date, name: current.name, workoutId: workoutId, rautaFocus: focus)
    }

    /// RAUTA built it and it has not been trained: nothing started, nothing
    /// logged, nothing finished.
    static func canRegenerate(_ workout: Workout) -> Bool {
        guard workout.rautaFocus?.isEmpty == false, workout.completion == nil else { return false }
        let records = TrainingRecordsStore.shared.data
        if ActiveWorkoutStore.shared.session?.workoutId == workout.id { return false }
        if records.activeWorkout?.sourceWorkoutId == workout.id { return false }
        return !records.sessions.contains { $0.sourceWorkoutId == workout.id }
    }

    /// The same, in place — for migrating one legacy workout as it is opened.
    private static func createWorkoutNow(
        date: String,
        name: String?,
        exerciseIds: [String],
        workoutId: String
    ) throws -> String {
        let program = try buildProgram(Input(date: date, exerciseIds: exerciseIds))
        return try record(program, date: date, name: name, workoutId: workoutId)
    }

    private static func record(
        _ program: TrainingProgram,
        date: String,
        name: String?,
        workoutId: String?,
        rautaFocus: [MuscleId]? = nil
    ) throws -> String {
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
            planned: PlannedWorkoutReference(programId: program.id, sessionId: view.sessionId),
            rautaFocus: rautaFocus
        )
    }

    /// A new workout made from an existing one: the same name and exercises on
    /// another day, prescribed afresh from where training is now.
    static func reuse(_ workoutId: String, date: String) async throws -> String {
        guard let source = WorkoutsStore.shared.workout(workoutId) else {
            throw TrainingPersistenceError("Workout not found.")
        }
        guard date >= CalendarDate.today else {
            throw TrainingPersistenceError("Choose today or a future date.")
        }
        let exerciseIds = source.exerciseIds.filter(ExerciseCatalogue.has)
        guard !exerciseIds.isEmpty else {
            throw TrainingPersistenceError("This workout has no exercises to reuse.")
        }
        return try await createWorkout(date: date, name: source.name, exerciseIds: exerciseIds)
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

        return (try? createWorkoutNow(
            date: workout.date,
            name: workout.name,
            exerciseIds: workout.exerciseIds,
            workoutId: workoutId
        )) ?? workoutId
    }
}
