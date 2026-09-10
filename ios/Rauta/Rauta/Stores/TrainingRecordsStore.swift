import Foundation
import Combine

let TRAINING_STORAGE_KEY = "gym-lib-training"

@MainActor
final class TrainingRecordsStore: ObservableObject {
    static let shared = TrainingRecordsStore()

    @Published private(set) var data: PersistedTrainingState = .empty()
    @Published private(set) var persistenceIssues: [TrainingPersistenceIssue] = []
    let changed = PassthroughSubject<Void, Never>()

    private init() { load() }

    // MARK: Hydration

    private func load() {
        guard let envelope = Storage.readEnvelope(TRAINING_STORAGE_KEY) else { return }
        // Zustand wrapped the payload in `{ data: … }`; unwrap either shape.
        let payload = envelope.state["data"] ?? envelope.state
        let recovered = PersistenceValidation.recover(payload)
        data = recovered.state
        persistenceIssues = recovered.issues
    }

    func persist() {
        Storage.writeEnvelope(
            TRAINING_STORAGE_KEY,
            state: .object(["data": data.jsonTree]),
            version: TRAINING_PERSISTENCE_SCHEMA_VERSION
        )
    }

    /// Every write goes through the validator first: memory is only replaced by
    /// a state the schema accepts, and a failed write leaves the draft alone.
    private func commit(_ next: PersistedTrainingState) throws {
        let normalized = PersistenceValidation.normalize(next)
        let issues = PersistenceValidation.validate(normalized)
        if !issues.isEmpty { throw TrainingPersistenceValidationError(issues: issues) }
        data = normalized
        persist()
        changed.send()
    }

    func replaceAll(_ next: PersistedTrainingState) {
        data = next
        persistenceIssues = []
        persist()
        changed.send()
    }

    static func makeId(_ prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.lowercased())"
    }

    private func exerciseName(_ exerciseId: String) -> String? {
        ExerciseCatalogue.name(exerciseId)
    }

    // MARK: Programs

    func saveProgram(
        _ program: TrainingProgram,
        activate: Bool = true,
        kind: PersistedProgramRecord.Kind? = nil,
        manualSourceProgramId: String? = nil,
        manualRevisionAt: String? = nil,
        incorporatedSessionIds: [String]? = nil,
        replacedSessionIds: [String]? = nil
    ) throws {
        let record = ProgramRecords.createRecord(program, options: ProgramRecords.RecordOptions(
            kind: kind,
            lifecycle: activate ? .active : .archived,
            manualSourceProgramId: manualSourceProgramId,
            manualRevisionAt: manualRevisionAt,
            incorporatedSessionIds: incorporatedSessionIds,
            replacedSessionIds: replacedSessionIds
        ))

        if let existing = data.programs.first(where: { $0.id == record.id }) {
            if existing.snapshot != record.snapshot {
                throw TrainingPersistenceError(
                    "Program ID already exists with a different immutable snapshot"
                )
            }
            return
        }
        if let revision = record.revision,
           !data.programs.contains(where: { $0.id == revision.sourceProgramId }) {
            throw TrainingPersistenceError("Program revision source must be persisted first")
        }

        var next = data
        next.programs = next.programs.map { item in
            guard activate, item.lifecycle == .active else { return item }
            var updated = item
            updated.lifecycle = .archived
            return updated
        }
        next.programs.append(record)
        if activate { next.activeProgramId = record.id }
        try commit(next)
    }

    func activateProgram(_ programId: String) throws {
        guard data.programs.contains(where: { $0.id == programId }) else {
            throw TrainingPersistenceError("Program not found")
        }
        var next = data
        next.activeProgramId = programId
        next.programs = next.programs.map { program in
            var updated = program
            if program.id == programId { updated.lifecycle = .active }
            else if program.lifecycle == .active { updated.lifecycle = .archived }
            return updated
        }
        try commit(next)
    }

    func archiveProgram(_ programId: String) throws {
        guard data.programs.contains(where: { $0.id == programId }) else {
            throw TrainingPersistenceError("Program not found")
        }
        var next = data
        if next.activeProgramId == programId { next.activeProgramId = nil }
        next.programs = next.programs.map { program in
            guard program.id == programId else { return program }
            var updated = program
            updated.lifecycle = .archived
            return updated
        }
        try commit(next)
    }

    // MARK: Starting a workout

    @discardableResult
    func startPlannedWorkout(
        programId: String,
        plannedSessionId: String,
        startedAt: String = ISOTime.now(),
        sourceWorkoutId: String? = nil
    ) throws -> String {
        if data.activeWorkout != nil { throw TrainingPersistenceError("A workout is already active") }
        if data.sessions.contains(where: { $0.plannedSessionId == plannedSessionId }) {
            throw TrainingPersistenceError("This planned session has already been recorded")
        }
        guard let record = data.programs.first(where: { $0.id == programId }) else {
            throw TrainingPersistenceError("Program not found")
        }
        if ProgramRecords.isSupersededPlannedSession(data, programId, plannedSessionId) {
            throw TrainingPersistenceError("This planned session has been replaced")
        }
        if !ProgramRecords.isStartablePlannedSession(data, programId, plannedSessionId) {
            throw TrainingPersistenceError("This planned session is no longer active")
        }

        let program = ProgramRecords.toEngineProgram(record.snapshot)
        guard let session = program.weeks.flatMap(\.sessions).first(where: {
            $0.id == plannedSessionId
        }) else {
            throw TrainingPersistenceError("Planned session not found")
        }

        let draftId = Self.makeId("workout-draft")
        let draft = try WorkoutDrafts.createFromPlannedSession(WorkoutDrafts.PlannedDraftInput(
            draftId: draftId,
            programId: programId,
            session: session,
            startedAt: startedAt,
            makeId: { Self.makeId("draft-\($0.rawValue)") },
            exerciseNameSnapshot: { [weak self] in self?.exerciseName($0) },
            sourceWorkoutId: sourceWorkoutId
        ))

        var next = data
        next.activeWorkout = draft
        try commit(next)
        return draftId
    }

    @discardableResult
    func startFreeWorkout(
        exerciseIds: [String],
        startedAt: String = ISOTime.now(),
        sourceWorkoutId: String? = nil
    ) throws -> String {
        if data.activeWorkout != nil { throw TrainingPersistenceError("A workout is already active") }
        let draftId = Self.makeId("workout-draft")
        let draft = try WorkoutDrafts.createFreeDraft(WorkoutDrafts.FreeDraftInput(
            draftId: draftId,
            startedAt: startedAt,
            exerciseIds: exerciseIds,
            makeId: { Self.makeId("draft-\($0.rawValue)") },
            exerciseNameSnapshot: { [weak self] in self?.exerciseName($0) },
            sourceWorkoutId: sourceWorkoutId
        ))

        var next = data
        next.activeWorkout = draft
        try commit(next)
        return draftId
    }

    // MARK: Live draft edits

    private func withActiveDraft(
        _ body: (inout PersistedActiveWorkoutDraft) throws -> Void
    ) throws {
        guard var draft = data.activeWorkout else {
            throw TrainingPersistenceError("No active workout")
        }
        try body(&draft)
        var next = data
        next.activeWorkout = draft
        try commit(next)
    }

    func recordSet(
        exerciseEntryId: String,
        setDraftId: String,
        observation: PersistedSetObservation
    ) throws {
        try withActiveDraft { draft in
            draft = try WorkoutDrafts.recordSetObservation(
                draft,
                exerciseEntryId: exerciseEntryId,
                setDraftId: setDraftId,
                observation: observation
            )
        }
    }

    @discardableResult
    func addUnplannedSet(
        exerciseEntryId: String,
        setType: SetType,
        side: SetSide,
        observation: PersistedSetObservation? = nil
    ) throws -> String {
        let setDraftId = Self.makeId("draft-set")
        try withActiveDraft { draft in
            draft = try WorkoutDrafts.addUnplannedSet(
                draft,
                exerciseEntryId: exerciseEntryId,
                setDraftId: setDraftId,
                setType: setType,
                side: side,
                observation: observation
            )
        }
        return setDraftId
    }

    func substituteExercise(
        exerciseEntryId: String,
        exerciseId: String,
        targets: [PersistedSetTarget?]? = nil
    ) throws {
        try withActiveDraft { [weak self] draft in
            draft = try WorkoutDrafts.substituteExercise(
                draft,
                exerciseEntryId: exerciseEntryId,
                exerciseId: exerciseId,
                exerciseNameSnapshot: self?.exerciseName(exerciseId)
            )
            guard let targets else { return }
            guard let index = draft.exercises.firstIndex(where: { $0.id == exerciseEntryId })
            else { return }
            guard targets.count == draft.exercises[index].sets.count else {
                throw TrainingPersistenceError("Replacement targets do not match the planned sets")
            }
            for (setIndex, target) in targets.enumerated() {
                draft.exercises[index].sets[setIndex].target = target
            }
        }
    }

    func addExercise(_ exerciseId: String, targets: [PersistedSetTarget?] = []) throws {
        guard ExerciseCatalogue.has(exerciseId) else {
            throw TrainingPersistenceError("Exercise not found")
        }
        try withActiveDraft { [weak self] draft in
            draft.exercises.append(PersistedActiveExerciseDraft(
                id: Self.makeId("draft-exercise"),
                exerciseId: exerciseId,
                plannedExerciseId: nil,
                exerciseNameSnapshot: self?.exerciseName(exerciseId),
                sets: targets.map { target in
                    PersistedActiveSetDraft(
                        id: Self.makeId("draft-set"),
                        plannedSetId: nil,
                        setType: .working,
                        side: .both,
                        target: target,
                        observation: nil
                    )
                }
            ))
        }
    }

    func moveExercise(_ exerciseEntryId: String, direction: Int) throws {
        try withActiveDraft { draft in
            guard let index = draft.exercises.firstIndex(where: { $0.id == exerciseEntryId })
            else { return }
            let next = index + direction
            guard next >= 0, next < draft.exercises.count else { return }
            draft.exercises.swapAt(index, next)
        }
    }

    func reorderExercises(_ exerciseEntryIds: [String]) throws {
        guard let draft = data.activeWorkout,
              exerciseEntryIds.count == draft.exercises.count,
              Set(exerciseEntryIds).count == exerciseEntryIds.count,
              exerciseEntryIds.allSatisfy({ id in draft.exercises.contains { $0.id == id } })
        else { throw TrainingPersistenceError("Invalid exercise order") }

        try withActiveDraft { draft in
            draft.exercises = exerciseEntryIds.compactMap { id in
                draft.exercises.first { $0.id == id }
            }
        }
    }

    func updateSetDetails(
        exerciseEntryId: String,
        setDraftId: String,
        setType: SetType,
        side: SetSide
    ) throws {
        try withActiveDraft { draft in
            guard let exerciseIndex = draft.exercises.firstIndex(where: { $0.id == exerciseEntryId }),
                  let setIndex = draft.exercises[exerciseIndex].sets.firstIndex(where: {
                      $0.id == setDraftId
                  })
            else { throw TrainingPersistenceError("Set not found") }
            draft.exercises[exerciseIndex].sets[setIndex].setType = setType
            draft.exercises[exerciseIndex].sets[setIndex].side = side
        }
    }

    func removeUnplannedSet(exerciseEntryId: String, setDraftId: String) throws {
        try withActiveDraft { draft in
            guard let exerciseIndex = draft.exercises.firstIndex(where: { $0.id == exerciseEntryId }),
                  let set = draft.exercises[exerciseIndex].sets.first(where: { $0.id == setDraftId }),
                  set.plannedSetId == nil,
                  set.observation?.completed != true
            else { throw TrainingPersistenceError("Only unfinished additional sets can be removed") }
            draft.exercises[exerciseIndex].sets.removeAll { $0.id == setDraftId }
        }
    }

    /// A live draft is not history: only completion writes evidence, so a set
    /// logged by mistake can still be taken back until then. A planned set is the
    /// prescription rather than a record and stays.
    func discardLoggedSet(exerciseEntryId: String, setDraftId: String) throws {
        try withActiveDraft { draft in
            guard let exerciseIndex = draft.exercises.firstIndex(where: { $0.id == exerciseEntryId }),
                  let set = draft.exercises[exerciseIndex].sets.first(where: { $0.id == setDraftId }),
                  set.plannedSetId == nil
            else { throw TrainingPersistenceError("Prescribed sets stay in the workout") }
            draft.exercises[exerciseIndex].sets.removeAll { $0.id == setDraftId }
        }
    }

    // MARK: Completion

    @discardableResult
    func completeWorkout(
        status: CompletedSession.Status = .completed,
        completedAt: String = ISOTime.now(),
        sessionId fixedSessionId: String? = nil
    ) throws -> String? {
        guard let draft = data.activeWorkout else { return nil }
        let sessionId = fixedSessionId ?? Self.makeId("training-session")
        // A fixed identity is a promise that this session is written once.
        if let fixedSessionId, data.sessions.contains(where: { $0.id == fixedSessionId }) {
            return fixedSessionId
        }

        var childId = 0
        let session = try WorkoutDrafts.complete(
            draft,
            sessionId: sessionId,
            completedAt: completedAt,
            status: status,
            makeId: { kind in
                if let fixedSessionId {
                    defer { childId += 1 }
                    return "\(fixedSessionId)-\(kind.rawValue)-\(childId)"
                }
                return Self.makeId("completed-\(kind.rawValue)")
            }
        )

        var next = data
        next.sessions.append(session)
        next.activeWorkout = nil
        try commit(next)
        return sessionId
    }

    @discardableResult
    func abortWorkout(completedAt: String = ISOTime.now()) throws -> String? {
        guard let draft = data.activeWorkout else { return nil }
        let hasCompletedWork = draft.exercises.contains { exercise in
            exercise.sets.contains { $0.observation?.completed == true }
        }
        if hasCompletedWork {
            return try completeWorkout(status: .partial, completedAt: completedAt)
        }
        var next = data
        next.activeWorkout = nil
        try commit(next)
        return nil
    }

    func cancelWorkout() throws {
        var next = data
        next.activeWorkout = nil
        try commit(next)
    }

    // MARK: Transition journal

    /// Writes one transition at a time. A pending intent must be settled first.
    func beginTransition(_ intent: PersistedTransitionIntent) throws {
        if let existing = data.transition, existing.id != intent.id {
            throw TrainingPersistenceError("A workout transition is already pending")
        }
        var next = data
        next.transition = intent
        try commit(next)
    }

    /// Drops the journal entry once its transition is fully applied.
    func clearTransition() throws {
        guard data.transition != nil else { return }
        var next = data
        next.transition = nil
        try commit(next)
    }

    // MARK: Coverage and stations

    func setHistoryCoverageUnknown() throws {
        var next = data
        next.settings.historyCoverage = .unknown
        try commit(next)
    }

    func setHistoryCoverageCompleteFrom(_ coverageStart: String) throws {
        var next = data
        next.settings.historyCoverage = PersistedHistoryCoverage(
            status: .complete, coverageStart: coverageStart
        )
        try commit(next)
    }

    @discardableResult
    func saveLoadConfiguration(
        id: String? = nil,
        exerciseId: String,
        stationId: String,
        mode: PersistedLoadConfiguration.Mode = .externalLoad,
        basis: LoadBasis,
        grid: LoadGrid
    ) throws -> String {
        // One station of one exercise in one measurement is one record.
        // Describing it again — a second turn of the dial — corrects the record
        // that is already there rather than making a rival one.
        let existing = data.settings.loadConfigurations.first {
            $0.exerciseId == exerciseId
                && $0.stationId == stationId
                && $0.basis == basis
                && $0.effectiveMode == mode
        }
        let configurationId = id ?? existing?.id ?? Self.makeId("load-context")
        let configuration = PersistedLoadConfiguration(
            id: configurationId,
            exerciseId: exerciseId,
            stationId: stationId,
            mode: mode == .externalLoad ? nil : mode,
            basis: basis,
            grid: grid
        )

        var next = data
        next.settings.loadConfigurations = next.settings.loadConfigurations
            .filter { $0.id != configurationId } + [configuration]
        try commit(next)
        return configurationId
    }

    func removeLoadConfiguration(_ id: String) throws {
        var next = data
        next.settings.loadConfigurations.removeAll { $0.id == id }
        // A station that no longer exists cannot stay selected: the exercise
        // returns to its equipment default rather than to a grid nothing
        // describes.
        if var active = next.settings.activeLoadConfigurations {
            active = active.filter { $0.value != id }
            next.settings.activeLoadConfigurations = active
        }
        try commit(next)
    }

    /// Pins which saved station an exercise is being trained at; nil returns it
    /// to the equipment default.
    func selectLoadConfiguration(_ exerciseId: String, _ configurationId: String?) throws {
        if let configurationId,
           !data.settings.loadConfigurations.contains(where: {
               $0.id == configurationId && $0.exerciseId == exerciseId
           }) {
            throw TrainingPersistenceError("Load configuration not found for this exercise")
        }
        var next = data
        var active = next.settings.activeLoadConfigurations ?? [:]
        if let configurationId { active[exerciseId] = configurationId }
        else { active.removeValue(forKey: exerciseId) }
        next.settings.activeLoadConfigurations = active
        try commit(next)
    }

    // MARK: History

    func trainingHistory(
        legacyWorkouts: [LegacyWorkoutObservation]? = nil
    ) -> TrainingHistory {
        let legacy = legacyWorkouts ?? WorkoutsStore.shared.workouts.map { workout in
            LegacyWorkoutObservation(
                id: workout.id,
                completion: workout.completion.map { completion in
                    LegacyWorkouts.LegacyCompletion(
                        startedAt: completion.startedAt,
                        completedAt: completion.completedAt,
                        durationMs: completion.durationMs,
                        completedExerciseIds: completion.completedExerciseIds
                    )
                }
            )
        }
        return PersistedHistory.toTrainingHistory(data, legacyWorkouts: legacy)
    }
}
