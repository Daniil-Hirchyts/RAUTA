import Foundation
import Observation
import Combine

/// Why the last session stopped. Read by the Live Activity sync to decide
/// between a lingering "workout complete" card and an immediate dismissal.
enum ActiveWorkoutOutcome: String, Sendable {
    case finished, cancelled
}

/// Whether a workout could be started, and if not, why not in plain words.
enum WorkoutStartOutcome: Equatable {
    case started
    case refused(String)

    var isStarted: Bool { self == .started }

    var refusal: String? {
        if case .refused(let reason) = self { return reason }
        return nil
    }
}

@MainActor
@Observable
final class ActiveWorkoutStore {
    static let shared = ActiveWorkoutStore()

    static let storageKey = "gym-lib-active-workout"
    static let version = 1

    private(set) var session: ActiveWorkoutSession?
    private(set) var lastOutcome: ActiveWorkoutOutcome?
    let changed = PassthroughSubject<Void, Never>()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        load()
    }

    // MARK: Hydration

    static func sanitizeSession(_ value: JSONValue?) -> ActiveWorkoutSession? {
        guard let object = value?.objectValue,
              let workoutId = object["workoutId"]?.stringValue, !workoutId.isEmpty
        else { return nil }

        let exerciseIds = Sanitize.uniqueStrings(object["exerciseIds"]) { ExerciseCatalogue.has($0) }
        guard !exerciseIds.isEmpty else { return nil }

        let completedIds = Sanitize.uniqueStrings(object["completedIds"]) { exerciseIds.contains($0) }
        let currentExerciseId = object["currentExerciseId"]?.stringValue ?? ""
        let name = (object["workoutName"]?.stringValue ?? "Workout")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let now = ActiveWorkout.nowMillis()
        let startedAt = validTimestamp(object["startedAt"]) ?? now
        return ActiveWorkoutSession(
            workoutId: workoutId,
            workoutName: name.isEmpty ? "Workout" : name,
            workoutDate: object["workoutDate"]?.stringValue ?? "",
            exerciseIds: exerciseIds,
            completedIds: completedIds,
            currentExerciseId: exerciseIds.contains(currentExerciseId) ? currentExerciseId : nil,
            runningSince: validTimestamp(object["runningSince"]),
            accumulatedMs: Swift.max(0, object["accumulatedMs"]?.numberValue ?? 0),
            startedAt: startedAt,
            setPhaseStartedAt: validTimestamp(object["setPhaseStartedAt"]) ?? now,
            restUntil: validTimestamp(object["restUntil"]),
            // A warm-up still running when the app closed is picked back up;
            // one that ran out meanwhile is over.
            warmupUntil: validTimestamp(object["warmupUntil"]).flatMap { $0 > now ? $0 : nil }
        )
    }

    private static func validTimestamp(_ value: JSONValue?) -> Double? {
        guard let number = value?.numberValue, number.isFinite, number > 0 else { return nil }
        return number
    }

    private func load() {
        guard let envelope = Storage.readEnvelope(Self.storageKey) else { return }
        let stored = envelope.state["session"]
        session = Self.sanitizeSession(stored)
        if session != nil,
           Self.validTimestamp(stored?.objectValue?["setPhaseStartedAt"]) == nil {
            persist()
        }
    }

    func persist() {
        Storage.writeEnvelope(
            Self.storageKey,
            state: .object(["session": session?.jsonTree ?? .null]),
            version: Self.version
        )
    }

    private func mutate(_ body: () -> Void) {
        body()
        persist()
        changed.send()
    }

    func setSession(_ next: ActiveWorkoutSession?, outcome: ActiveWorkoutOutcome?) {
        mutate {
            session = next
            lastOutcome = outcome
        }
    }

    // MARK: Lifecycle

    /// Whether `workout` came from a plan that has since been replaced. No plan
    /// can take its session any more, but it is still a workout.
    static func planWasReplaced(_ workout: Workout) -> Bool {
        guard let planned = workout.planned else { return false }
        return !ProgramRecords.isStartablePlannedSession(
            TrainingRecordsStore.shared.data, planned.programId, planned.sessionId
        )
    }

    /// Starts a workout from a replaced plan as a workout of its own. The link
    /// to the old plan is let go — because the person asked to train it, never
    /// as a silent fallback inside ``start(_:)`` — and is put back if the start
    /// is refused.
    @discardableResult
    func startAsOwnWorkout(_ workout: Workout) -> WorkoutStartOutcome {
        guard let planned = workout.planned, Self.planWasReplaced(workout) else { return start(workout) }
        let workouts = WorkoutsStore.shared
        workouts.updateWorkout(workout.id, .init(clearsPlanned: true))
        guard let own = workouts.workout(workout.id) else {
            return .refused("This workout is no longer here.")
        }
        let outcome = start(own, carrying: planned)
        if !outcome.isStarted { workouts.updateWorkout(workout.id, .init(planned: planned)) }
        return outcome
    }

    /// Opens a session for `workout`, or says why it will not.
    ///
    /// A refusal used to be a bare `false`, which left every caller to invent
    /// its own guess at the reason. The reason is always known here, so it is
    /// returned.
    @discardableResult
    func start(_ workout: Workout) -> WorkoutStartOutcome {
        start(workout, carrying: nil)
    }

    private func start(_ workout: Workout, carrying prescription: PlannedWorkoutReference?) -> WorkoutStartOutcome {
        if workout.completion != nil {
            return .refused("This workout is already finished. Reuse it to train it again.")
        }
        if session?.workoutId == workout.id { return .started }
        if session != nil {
            return .refused("Another workout is running. Finish it before starting this one.")
        }
        let exerciseIds = workout.exerciseIds.filter { ExerciseCatalogue.has($0) }
        if exerciseIds.isEmpty {
            return .refused("This workout has no exercises yet. Add some first.")
        }

        let now = ActiveWorkout.nowMillis()
        let date = CalendarDate.toISO(Date(timeIntervalSince1970: now / 1000))
        // Every workout opens with the warm-up chosen in Settings, whichever
        // way it was started.
        let warmup = SettingsStore.shared.warmupLength.seconds
        let warmupUntil: Double? = warmup > 0 ? now + warmup * 1_000 : nil
        // Write down the start before any of it happens, so a relaunch between
        // the draft landing and the shell appearing can put back the session the
        // person was already looking at rather than losing it.
        var shellWorkout = workout
        shellWorkout.date = date
        shellWorkout.exerciseIds = exerciseIds
        do {
            try WorkoutTransition.recordStartIntent(shellWorkout, startedAtMs: now)
        } catch {
            return .refused(Self.message(error))
        }

        // Open the structured record before exposing a running session. A
        // planned workout whose program cannot be resolved must not silently
        // become a free workout or leave a shell session behind.
        do {
            try TrainingSessionBridge.beginTrainingDraft(
                exerciseIds: exerciseIds,
                startedAt: ISOTime.string(fromMillis: now),
                sourceWorkoutId: workout.id,
                planned: workout.planned,
                carrying: prescription
            )
        } catch {
            WorkoutTransition.settleWorkoutTransition()
            return .refused(Self.message(error))
        }

        setSession(
            ActiveWorkoutSession(
                workoutId: workout.id,
                workoutName: workout.name,
                workoutDate: date,
                exerciseIds: exerciseIds,
                completedIds: [],
                currentExerciseId: exerciseIds.first,
                runningSince: now,
                accumulatedMs: 0,
                startedAt: now,
                setPhaseStartedAt: warmupUntil ?? now,
                restUntil: nil,
                warmupUntil: warmupUntil
            ),
            outcome: nil
        )
        if let warmupUntil {
            RestAlerts.shared.schedule(
                deadline: Date(timeIntervalSince1970: warmupUntil / 1_000),
                exerciseName: exerciseIds.first.flatMap(ExerciseCatalogue.name),
                kind: .warmup
            )
        }
        if WorkoutsStore.shared.workout(workout.id) != nil {
            WorkoutsStore.shared.updateWorkout(workout.id, WorkoutsStore.WorkoutPatch(date: date))
        }
        WorkoutTransition.settleWorkoutTransition()
        return .started
    }

    /// Finishes the running session and says, from the records themselves,
    /// whether it is saved.
    ///
    /// Nothing about this call is optimistic. The finish intent is written
    /// first; if that write is refused, the session is left exactly as it was
    /// and the refusal is returned. After the transition runs, the durable
    /// records are read back: only once the draft is closed, the workout is
    /// marked complete, and any logged sets are in history does this hand back
    /// a receipt and clear the session. A failure keeps the draft, the shell and
    /// the last set, so finishing can simply be tried again — the journal makes
    /// the retry land on the same session rather than a second one.
    @discardableResult
    func finish() -> WorkoutFinishOutcome {
        guard let session else {
            return .failed("There is no workout to finish.")
        }
        let durationMs = ActiveWorkout.elapsedMs(session)
        let records = TrainingRecordsStore.shared
        let draft = records.data.activeWorkout
        let draftStartedAt = draft?.startedAt
        let loggedSets = draft?.exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter { $0.observation?.completed == true }.count
        } ?? 0

        // Everything the finish will use is decided once and written down, so an
        // interruption resumes to exactly this result.
        let intent: PersistedTransitionIntent
        do {
            intent = try WorkoutTransition.recordFinishIntent(session, durationMs: durationMs)
        } catch {
            return .failed(Self.message(error))
        }

        // Both records close together: the legacy workout keeps duration,
        // calories and which exercises were checked off, while the structured
        // session keeps the sets that were really performed.
        var draftFailure: String?
        WorkoutTransition.recoverWorkoutTransition(draftFailure: &draftFailure)

        // A refused write used to be swallowed here, so a finish could report
        // success that history never received. It is the whole answer now.
        if let draftFailure {
            return .failed("\(draftFailure) Nothing you logged is lost — try finishing again.")
        }

        if let reason = WorkoutTransition.unfinishedFinishReason(
            workoutId: session.workoutId,
            expectedStructuredSession: loggedSets > 0,
            sessionId: intent.sessionId,
            draftStartedAt: draftStartedAt
        ) {
            return .failed("\(reason) Nothing you logged is lost — try finishing again.")
        }

        let recorded = WorkoutTransition.recordedSession(
            sessionId: intent.sessionId,
            workoutId: session.workoutId,
            startedAt: draftStartedAt
        )
        let completion = WorkoutsStore.shared.workout(session.workoutId)?.completion
        let receipt = WorkoutReceipt(
            sessionId: recorded?.id,
            workoutId: session.workoutId,
            workoutName: session.workoutName,
            completedAt: intent.completedAt ?? intent.recordedAt,
            durationMs: intent.legacy?.durationMs ?? durationMs,
            exercisesRecorded: Self.recordedExerciseCount(recorded, session: session),
            exercisesPlanned: session.exerciseIds.count,
            setsRecorded: recorded?.exercises.reduce(0) { total, exercise in
                total + exercise.sets.filter(\.completed).count
            } ?? 0,
            isComplete: (recorded?.status ?? intent.status) == .completed,
            healthSyncPending: completion?.healthSyncStatus == .pending
        )

        setSession(nil, outcome: .finished)
        RestAlerts.shared.cancel()
        WorkoutTransition.settleWorkoutTransition()
        return .saved(receipt)
    }

    /// Exercises the session can honestly claim: those holding a recorded set,
    /// plus any checked off by hand that hold none.
    private static func recordedExerciseCount(
        _ recorded: PersistedCompletedSession?,
        session: ActiveWorkoutSession
    ) -> Int {
        var ids = Set(
            (recorded?.exercises ?? [])
                .filter { $0.sets.contains(where: \.completed) }
                .map(\.exerciseId)
        )
        ids.formUnion(session.completedIds)
        return ids.intersection(session.exerciseIds).count
    }

    private static func message(_ error: Error) -> String {
        (error as? TrainingPersistenceError)?.message ?? error.localizedDescription
    }

    func cancel() {
        // A discarded session is still evidence of the sets it did produce, so
        // they are kept as a partial session rather than thrown away.
        if let session {
            _ = try? WorkoutTransition.recordCancelIntent(session)
            WorkoutTransition.recoverWorkoutTransition()
        }
        setSession(nil, outcome: .cancelled)
        RestAlerts.shared.cancel()
        WorkoutTransition.settleWorkoutTransition()
    }

    func pause() {
        guard var current = session, current.runningSince != nil else { return }
        current.accumulatedMs = ActiveWorkout.elapsedMs(current)
        current.runningSince = nil
        mutate { session = current }
    }

    func resume() {
        guard var current = session, current.runningSince == nil else { return }
        current.runningSince = ActiveWorkout.nowMillis()
        mutate { session = current }
    }

    /// Starts a rest phase from the authoritative session clock. The same
    /// deadline drives both the UI and the local notification, so reopening a
    /// tab or sheet cannot restart the countdown.
    /// `announce` sounds the rest's start: from the Watch, RAUTA or Siri. A set
    /// logged in the app has already sounded.
    func startRest(seconds: TimeInterval, exerciseName: String?, announce: Bool = true) {
        guard var current = session else { return }
        let durationMs = Swift.max(1, seconds.rounded()) * 1_000
        let deadlineMs = ActiveWorkout.nowMillis() + durationMs
        current.restUntil = deadlineMs
        current.setPhaseStartedAt = deadlineMs
        // A logged set means the warm-up is done, however much of it ran.
        current.warmupUntil = nil
        mutate { session = current }
        if announce { WorkoutAudio.play(.restStart) }
        RestAlerts.shared.schedule(
            deadline: Date(timeIntervalSince1970: deadlineMs / 1_000),
            exerciseName: exerciseName
        )
    }

    // MARK: Warm-up

    /// A minute more (or `seconds`) of warm-up, from where it stands.
    func extendWarmup(by seconds: TimeInterval) {
        guard var current = session, let warmupUntil = current.warmupUntil else { return }
        let deadlineMs = Swift.max(warmupUntil, ActiveWorkout.nowMillis()) + Swift.max(1, seconds.rounded()) * 1_000
        current.warmupUntil = deadlineMs
        current.setPhaseStartedAt = deadlineMs
        mutate { session = current }
        RestAlerts.shared.schedule(
            deadline: Date(timeIntervalSince1970: deadlineMs / 1_000),
            exerciseName: current.currentExerciseId.flatMap(ExerciseCatalogue.name),
            kind: .warmup
        )
    }

    /// Ends the warm-up now, early or on time: the first set's clock starts.
    func endWarmup() {
        guard var current = session, current.warmupUntil != nil else { return }
        current.warmupUntil = nil
        current.setPhaseStartedAt = ActiveWorkout.nowMillis()
        mutate { session = current }
        if RestAlerts.shared.kind == .warmup { RestAlerts.shared.cancel() }
    }

    /// Pushes the shared rest deadline out by `seconds`.
    ///
    /// The deadline is the one the local alert, the Live Activity, the Watch
    /// and every on-screen timer read, so moving it here moves all of them.
    func extendRest(by seconds: TimeInterval, exerciseName: String?) {
        guard var current = session, let restUntil = current.restUntil else { return }
        let now = ActiveWorkout.nowMillis()
        // Extending an already-expired rest starts the extra time from now
        // rather than from a deadline in the past.
        let deadlineMs = Swift.max(restUntil, now) + Swift.max(1, seconds.rounded()) * 1_000
        current.restUntil = deadlineMs
        current.setPhaseStartedAt = deadlineMs
        mutate { session = current }
        RestAlerts.shared.schedule(
            deadline: Date(timeIntervalSince1970: deadlineMs / 1_000),
            exerciseName: exerciseName
        )
    }

    /// Ends rest now. It records nothing: a set is logged by logging it.
    func endRest() {
        guard var current = session, current.restUntil != nil else { return }
        current.restUntil = nil
        current.setPhaseStartedAt = ActiveWorkout.nowMillis()
        mutate { session = current }
        RestAlerts.shared.cancel()
    }

    func setCurrentExercise(_ exerciseId: String) {
        guard var current = session, current.exerciseIds.contains(exerciseId) else { return }
        // Re-selecting a finished exercise means it is being done again, so it
        // goes back to being the one in progress.
        current.completedIds.removeAll { $0 == exerciseId }
        current.currentExerciseId = exerciseId
        mutate { session = current }
    }

    func toggleComplete(_ exerciseId: String) {
        guard var current = session, current.exerciseIds.contains(exerciseId) else { return }
        if current.completedIds.contains(exerciseId) {
            current.completedIds.removeAll { $0 == exerciseId }
            current.currentExerciseId = current.currentExerciseId ?? exerciseId
        } else {
            let wasCurrent = exerciseId == current.currentExerciseId
            current.completedIds.append(exerciseId)
            if wasCurrent {
                current.currentExerciseId = ActiveWorkout.nextPendingExerciseId(
                    current, from: exerciseId
                )
            }
        }
        mutate { session = current }
    }

    func completeCurrent() {
        guard var current = session,
              let exerciseId = current.currentExerciseId,
              !current.completedIds.contains(exerciseId)
        else { return }
        current.completedIds.append(exerciseId)
        current.currentExerciseId = ActiveWorkout.nextPendingExerciseId(current, from: exerciseId)
        mutate { session = current }
    }

    /// Keeps a running session aligned with edits made to the saved workout.
    func syncExercises(_ exerciseIds: [String], movedExerciseId: String? = nil) {
        let wasRunning = session != nil
        if var current = session {
            let next = exerciseIds.filter { ExerciseCatalogue.has($0) }
            // Emptying the workout leaves nothing to perform, so the session ends
            // rather than lingering with no current exercise.
            if next.isEmpty {
                setSession(nil, outcome: .cancelled)
            } else {
                let completedIds = current.completedIds.filter { next.contains($0) }
                var currentExerciseId: String? = {
                    if let id = current.currentExerciseId, next.contains(id) { return id }
                    return next.first { !completedIds.contains($0) }
                }()

                // The active marker represents the current position in the
                // workout. If that row itself is moved, keep the position active
                // and advance to the first unfinished exercise now occupying or
                // following that slot.
                if let moved = movedExerciseId,
                   let previousCurrent = current.currentExerciseId,
                   moved == previousCurrent {
                    let previousIndex = current.exerciseIds.firstIndex(of: previousCurrent) ?? 0
                    let startIndex = Swift.min(Swift.max(previousIndex, 0), next.count - 1)
                    let fromCurrentSlot = Array(next[startIndex...]) + Array(next[..<startIndex])
                    currentExerciseId = fromCurrentSlot.first { !completedIds.contains($0) }
                }

                current.exerciseIds = next
                current.completedIds = completedIds
                current.currentExerciseId = currentExerciseId
                mutate { session = current }
            }
        }

        guard wasRunning else { return }
        if let running = session {
            TrainingSessionBridge.syncTrainingDraftExercises(running.exerciseIds)
        } else {
            TrainingSessionBridge.endTrainingDraft(outcome: .cancelled)
        }
    }

    /// The same, for every part of the workout the session mirrors.
    func syncWorkout(_ workout: Workout) {
        guard let current = session, current.workoutId == workout.id else { return }

        // The date is on the Lock Screen card, so moving a workout has to reach
        // the session too.
        if current.workoutDate != workout.date || current.workoutName != workout.name {
            var next = current
            next.workoutDate = workout.date
            next.workoutName = workout.name
            mutate { session = next }
        }

        // Compared after the same filtering `syncExercises` applies, so an id the
        // library does not know cannot make the two look forever out of step.
        let exerciseIds = workout.exerciseIds.filter { ExerciseCatalogue.has($0) }
        if session?.exerciseIds != exerciseIds { syncExercises(exerciseIds) }
    }

    // MARK: Restore

    /// One workout, put back together before anything can read it.
    @discardableResult
    func reconcileRestored() -> SessionReconciliation {
        // The journal goes first: where an interrupted transition said what it
        // meant to do, finishing it is better than making its wreckage safe.
        let shell = session
        let resumed = WorkoutTransition.recoverWorkoutTransition(
            shellWorkoutId: shell?.workoutId,
            shellStartedAtMs: shell?.startedAt
        )

        if resumed.shell == .restore, let restore = resumed.restore {
            setSession(
                ActiveWorkoutSession(
                    workoutId: restore.workoutId,
                    workoutName: restore.workoutName,
                    workoutDate: restore.workoutDate,
                    exerciseIds: restore.exerciseIds,
                    completedIds: [],
                    currentExerciseId: restore.exerciseIds.first,
                    runningSince: restore.startedAtMs,
                    accumulatedMs: 0,
                    startedAt: restore.startedAtMs,
                    setPhaseStartedAt: restore.startedAtMs,
                    restUntil: nil
                ),
                outcome: nil
            )
        } else if resumed.shell == .clear {
            setSession(nil, outcome: nil)
        }

        if resumed.clearIntent { WorkoutTransition.settleWorkoutTransition() }

        let outcome = SessionReconciler.reconcileRestoredSession(session)
        // `lastOutcome` stays nil: nothing just happened in front of the person,
        // so a repair at launch must not read as a workout that ended a moment
        // ago.
        if outcome.session == .clear { setSession(nil, outcome: nil) }
        return outcome
    }

    /// A session follows the workout it is performing, wherever that workout is
    /// edited from. One missed path leaves a Live Activity counting for a workout
    /// that no longer exists, so the invariant lives here rather than at every
    /// call site.
    func observeWorkouts() {
        WorkoutsStore.shared.changed
            .sink { [weak self] in
                guard let self, let current = self.session else { return }
                guard let workout = WorkoutsStore.shared.workout(current.workoutId) else {
                    self.setSession(nil, outcome: .cancelled)
                    return
                }
                if workout.completion != nil {
                    self.setSession(nil, outcome: .finished)
                    return
                }
                self.syncWorkout(workout)
            }
            .store(in: &cancellables)
    }
}
