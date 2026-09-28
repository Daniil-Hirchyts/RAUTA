import Foundation

enum TrainingAdaptationMode: String {
    case remainingWeek = "remaining_week"
    case nextWeek = "next_week"
}

/// Mon–Sun as offsets from the week the engine is asked to plan. The only
/// genuinely week-specific answer the profile cannot already give.
let DEFAULT_TRAINING_DAYS: [Int] = [0, 2, 4]

@MainActor
enum TrainingWorkflow {
    private static var cachedIndex: ExerciseIndex?

    /// The catalogue index, built once. Every planning call shares it.
    static func trainingIndex() -> ExerciseIndex {
        if let cachedIndex { return cachedIndex }
        let index = ExerciseData.createIndex(ExerciseCatalogue.all)
        cachedIndex = index
        return index
    }

    struct RemainingSlots {
        var week: TrainingWeek?
        var sessions: [PlannedSession]
    }

    /// The source week's own untouched future slots, shared by eligibility and
    /// the engine request. Even a set-less application completion reserves its
    /// slot.
    static func remainingTrainingSlots(
        _ source: PersistedProgramRecord,
        _ now: String,
        data: PersistedTrainingState? = nil,
        workouts: [Workout]? = nil
    ) -> RemainingSlots {
        let data = data ?? TrainingRecordsStore.shared.data
        let workouts = workouts ?? WorkoutsStore.shared.workouts
        let nowMillis = ISOTime.parse(now) ?? 0

        func remaining(_ week: TrainingWeek) -> [PlannedSession] {
            week.sessions.filter { session in
                guard (ISOTime.parse(session.scheduledAt) ?? 0) > nowMillis else { return false }
                if ProgramRecords.isSupersededPlannedSession(data, source.id, session.id) {
                    return false
                }
                if data.sessions.contains(where: { $0.plannedSessionId == session.id }) {
                    return false
                }
                return !workouts.contains { workout in
                    workout.completion != nil
                        && workout.planned?.programId == source.id
                        && workout.planned?.sessionId == session.id
                }
            }
        }

        let engineProgram = ProgramRecords.toEngineProgram(source.snapshot)
        let week = engineProgram.weeks.first { !remaining($0).isEmpty }
        return RemainingSlots(week: week, sessions: week.map(remaining) ?? [])
    }

    /// Where every kilogram the engine may prescribe would be measured.
    ///
    /// The same resolution the set editor uses, asked of the whole catalogue.
    /// Without this the engine has no grid to round to and prescribes
    /// "calibrate" forever, however much real history exists. It states no load:
    /// it only says what a load would mean.
    static func engineLoadPreferences(
        settings: PersistedTrainingSettings? = nil,
        increments: [String: Double]? = nil
    ) -> TrainingEngineAdapter.LoadPreferences {
        let settings = settings ?? TrainingRecordsStore.shared.data.settings
        let increments = increments ?? FiltersStore.shared.equipmentLoadIncrements
        var loadContexts: [String: LoadContext] = [:]
        var loadGrids: [String: LoadGrid] = [:]
        let index = trainingIndex()

        for mode in [TrackingMode.externalLoad, .assistance] {
            for indexed in index.byTracking[mode] ?? [] {
                let exercise = indexed.exercise
                let resistanceMode: ResistanceMode = mode == .externalLoad ? .externalLoad : .assistance
                let context = Resistance.resolveLoadContext(
                    for: exercise,
                    mode: resistanceMode,
                    settings: settings,
                    equipmentIncrementKg: increments[exercise.equipment]
                )
                loadContexts[exercise.id] = LoadContext(
                    stationId: context.stationId, basis: context.basis
                )
                loadGrids[exercise.id] = context.grid
            }
        }
        return TrainingEngineAdapter.LoadPreferences(
            loadContexts: loadContexts, loadGrids: loadGrids
        )
    }

    /// The Monday a new plan starts on: the next one, including today when the
    /// plan is generated before its slots.
    private static func nextMonday(after now: String) -> String {
        guard let nowMillis = ISOTime.parse(now) else { return now }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: nowMillis / 1000)
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        // `weekday` is 1 = Sunday. Days until the next Monday, wrapping to 7.
        let daysAhead = (9 - weekday) % 7
        var monday = calendar.date(byAdding: .day, value: daysAhead, to: startOfDay) ?? startOfDay
        if monday.timeIntervalSince1970 * 1000 <= nowMillis {
            monday = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        }
        return ISOTime.string(from: monday)
    }

    static func buildTrainingRequest(
        _ setup: TrainingEngineAdapter.PlanSetup,
        now: String,
        source: PersistedProgramRecord? = nil,
        availableDays: [Int] = DEFAULT_TRAINING_DAYS,
        adaptationMode: TrainingAdaptationMode = .remainingWeek,
        readiness: Readiness? = nil
    ) -> ProgramGenerationRequest {
        let store = TrainingRecordsStore.shared
        let remaining: RemainingSlots? = (source != nil && adaptationMode == .remainingWeek)
            ? remainingTrainingSlots(source!, now)
            : nil
        let sourceWeek = remaining?.week

        var preferences = setup.preferences
        let loads = engineLoadPreferences(settings: store.data.settings)
        preferences.loadContexts = loads.loadContexts
        preferences.loadGrids = loads.loadGrids

        let weekStart = sourceWeek?.start ?? nextMonday(after: now)
        let weekStartMillis = ISOTime.parse(weekStart) ?? 0

        func offset(_ session: PlannedSession) -> Int {
            let at = ISOTime.parse(session.scheduledAt) ?? 0
            return Int(((at - weekStartMillis) / DAY_MS).rounded(.down))
        }

        let days: [Int]
        if source != nil, adaptationMode == .remainingWeek {
            var seen = Set<Int>()
            days = (remaining?.sessions ?? [])
                .map(offset)
                .filter { seen.insert($0).inserted }
                .sorted()
        } else {
            var seen = Set<Int>()
            days = availableDays.filter { seen.insert($0).inserted }.sorted()
        }

        var sessionDays: [Int]?
        if let sessions = remaining?.sessions, !sessions.isEmpty,
           Set(sessions.map(\.scheduledAt)).count != sessions.count {
            sessionDays = sessions.map(offset).sorted()
        }

        var policy: TrainingPolicy?
        if let source { policy = ProgramRecords.toEngineProgram(source.snapshot).policy }

        return ProgramGenerationRequest(
            profile: setup.profile,
            preferences: preferences,
            schedule: TrainingSchedule(
                weekStart: weekStart,
                days: days,
                sessionDays: sessionDays,
                durationWeeks: 1
            ),
            history: store.trainingHistory(),
            exercises: ExerciseCatalogue.all,
            now: now,
            readiness: readiness,
            metadata: nil,
            policy: policy
        )
    }

    struct PlanAttempt {
        var request: ProgramGenerationRequest
        var result: ProgramGenerationResult
    }

    /// Asks the engine for a week and hands back exactly what it said, refusals
    /// included. Nothing is persisted here. The request is read from the stores
    /// here; the engine's search runs off the main actor.
    static func planTrainingWeek(
        setup: TrainingEngineAdapter.PlanSetup? = nil,
        now: String = ISOTime.now(),
        source: PersistedProgramRecord? = nil,
        availableDays: [Int] = DEFAULT_TRAINING_DAYS,
        adaptationMode: TrainingAdaptationMode = .remainingWeek,
        readiness: Readiness? = nil
    ) async throws -> PlanAttempt {
        let setup = setup ?? TrainingEngineAdapter.buildEngineInputs()
        let request = buildTrainingRequest(
            setup,
            now: now,
            source: source,
            availableDays: availableDays,
            adaptationMode: adaptationMode,
            readiness: readiness
        )
        guard !request.schedule.days.isEmpty else {
            throw TrainingPersistenceError(
                "There are no future sessions left in this period. "
                    + "Create a new training plan instead."
            )
        }

        let adaptation = source.map { source in
            AdaptationRequest(
                previousProgram: ProgramRecords.toEngineProgram(source.snapshot),
                request: request,
                mode: adaptationMode == .remainingWeek ? .remainingWeek : .nextWeek
            )
        }
        let result = try await search(request, adaptation: adaptation)
        return PlanAttempt(request: request, result: result)
    }

    @concurrent
    private static func search(
        _ request: ProgramGenerationRequest,
        adaptation: AdaptationRequest?
    ) async throws -> ProgramGenerationResult {
        try Task.checkCancellation()
        if let adaptation { return Adapt.adaptTrainingProgram(adaptation) }
        return Generate.generateTrainingProgram(request)
    }

    /// The rest of a plan's week, reshaped around what has happened since, and
    /// held back for somebody to keep. Throws the engine's refusal as a reason.
    static func previewAdjustedWeek(
        source: PersistedProgramRecord,
        now: String = ISOTime.now(),
        readiness: Readiness? = nil
    ) async throws -> PlanPreview {
        let basis = PlanBasis.current(now: now, readiness: readiness)
        let attempt = try await planTrainingWeek(now: now, source: source, readiness: readiness)
        guard let program = attempt.result.program else {
            throw TrainingPersistenceError(
                "No plan could be created (\(attempt.result.statusName)). "
                    + "Check available equipment and future training days."
            )
        }
        return PlanPreview(
            kind: .adjustWeek,
            program: program,
            sessions: TrainingPlan.sessionViews(program),
            issues: attempt.result.issues,
            sourceProgramId: source.id,
            basis: basis
        )
    }

    /// The alternatives that still fit this exercise's place in the workout.
    static func replacementIds(_ exerciseId: String, workoutId: String? = nil) -> [String] {
        let records = TrainingRecordsStore.shared
        let workouts = WorkoutsStore.shared.workouts
        let workout = workouts.first { item in
            if let workoutId { return item.id == workoutId }
            return item.id == records.data.activeWorkout?.sourceWorkoutId
        }
        let activeExercise = records.data.activeWorkout?.exercises.first {
            $0.exerciseId == exerciseId
        }
        let sourceExerciseId = activeExercise?.plannedExerciseId ?? exerciseId
        let sourceProgram = workout?.planned.flatMap { planned in
            records.data.programs.first { $0.id == planned.programId }
        }

        let overrides = TrainingEngineAdapter.PreferenceOverrides(
            goal: sourceProgram?.snapshot.goal
        )
        let request = buildTrainingRequest(
            TrainingEngineAdapter.buildEngineInputs(overrides: overrides),
            now: ISOTime.now()
        )

        let substitutions = Substitutions.findExerciseSubstitutions(
            sourceExerciseId,
            request,
            limit: 100,
            index: trainingIndex(),
            selectedExerciseIds: workout?.exerciseIds
        ).map(\.exerciseId)

        return (sourceExerciseId != exerciseId ? [sourceExerciseId] : []) + substitutions
    }

    /// What the engine would prescribe next for a live draft exercise.
    static func nextPerformance(
        _ exercise: PersistedActiveExerciseDraft,
        now: String = ISOTime.now(),
        data: PersistedTrainingState? = nil,
        increments: [String: Double]? = nil,
        loggedMode: ResistanceMode? = nil,
        loggedContext: StationContext? = nil
    ) -> ProgressionRecommendation? {
        let data = data ?? TrainingRecordsStore.shared.data
        let increments = increments ?? FiltersStore.shared.equipmentLoadIncrements
        guard let indexed = trainingIndex().byId[exercise.exerciseId],
              let catalogueExercise = ExerciseCatalogue.byId[exercise.exerciseId]
        else { return nil }

        let target = exercise.sets.first { $0.setType == .working }?.target
        let mode = loggedMode
            ?? target?.resistance.type
            ?? Resistance.modes(for: catalogueExercise).first
            ?? .unknown

        // Legacy workouts are read live: they carry no sets, so they can move a
        // recommendation's staleness but never its load.
        let legacy = WorkoutsStore.shared.workouts.map { workout in
            LegacyWorkoutObservation(
                id: workout.id,
                completion: workout.completion.map {
                    LegacyWorkouts.LegacyCompletion(
                        startedAt: $0.startedAt,
                        completedAt: $0.completedAt,
                        durationMs: $0.durationMs,
                        completedExerciseIds: $0.completedExerciseIds
                    )
                }
            )
        }
        let history = PersistedHistory.toTrainingHistory(data, legacyWorkouts: legacy)

        let measured = mode == .externalLoad || mode == .assistance
        // The station this exercise is being trained at now, not the one the
        // last set happened to be logged at.
        let context: StationContext? = measured
            ? (loggedContext ?? Resistance.loadContext(
                for: catalogueExercise,
                mode: mode,
                configuration: Resistance.activeConfiguration(
                    exercise.exerciseId, mode, data.settings
                ),
                equipmentIncrementKg: increments[catalogueExercise.equipment]
            ))
            : nil

        return Progression.recommend(ProgressionInput(
            exercise: indexed,
            history: history,
            now: now,
            reps: target?.reps ?? RepRange(min: 8, max: 12),
            rir: target?.rir ?? 2,
            requiredSets: Swift.max(1, exercise.sets.filter { $0.setType == .working }.count),
            loadGrid: context?.grid,
            loadContext: context.map { LoadContext(stationId: $0.stationId, basis: $0.basis) },
            policy: DEFAULT_POLICY
        ))
    }
}
