import Foundation
import Combine

/// Why the last session stopped. Read by the Live Activity sync to decide
/// between a lingering "workout complete" card and an immediate dismissal.
enum ActiveWorkoutOutcome: String, Sendable {
    case finished, cancelled
}

@MainActor
final class ActiveWorkoutStore: ObservableObject {
    static let shared = ActiveWorkoutStore()

    static let storageKey = "gym-lib-active-workout"
    static let version = 1

    @Published private(set) var session: ActiveWorkoutSession?
    @Published private(set) var lastOutcome: ActiveWorkoutOutcome?
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

        return ActiveWorkoutSession(
            workoutId: workoutId,
            workoutName: name.isEmpty ? "Workout" : name,
            workoutDate: object["workoutDate"]?.stringValue ?? "",
            exerciseIds: exerciseIds,
            completedIds: completedIds,
            currentExerciseId: exerciseIds.contains(currentExerciseId) ? currentExerciseId : nil,
            runningSince: validTimestamp(object["runningSince"]),
            accumulatedMs: Swift.max(0, object["accumulatedMs"]?.numberValue ?? 0),
            startedAt: validTimestamp(object["startedAt"]) ?? ActiveWorkout.nowMillis()
        )
    }

    private static func validTimestamp(_ value: JSONValue?) -> Double? {
        guard let number = value?.numberValue, number.isFinite, number > 0 else { return nil }
        return number
    }

    private func load() {
        guard let envelope = Storage.readEnvelope(Self.storageKey) else { return }
        session = Self.sanitizeSession(envelope.state["session"])
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

    /// Opens a session for `workout`, or refuses when there is nothing to
    /// perform or the structured draft could not be opened.
    @discardableResult
    func start(_ workout: Workout) -> Bool {
        if workout.completion != nil { return false }
        if session?.workoutId == workout.id { return true }
        let exerciseIds = workout.exerciseIds.filter { ExerciseCatalogue.has($0) }
        if exerciseIds.isEmpty { return false }

        let now = ActiveWorkout.nowMillis()
        let date = CalendarDate.toISO(Date(timeIntervalSince1970: now / 1000))
        // Write down the start before any of it happens, so a relaunch between
        // the draft landing and the shell appearing can put back the session the
        // person was already looking at rather than losing it.
        var shellWorkout = workout
        shellWorkout.date = date
        shellWorkout.exerciseIds = exerciseIds
        do {
            try WorkoutTransition.recordStartIntent(shellWorkout, startedAtMs: now)
        } catch {
            return false
        }

        // Open the structured record before exposing a running session. A
        // planned workout whose program cannot be resolved must not silently
        // become a free workout or leave a shell session behind.
        let draftStarted = TrainingSessionBridge.beginTrainingDraft(
            exerciseIds: exerciseIds,
            startedAt: ISOTime.string(fromMillis: now),
            sourceWorkoutId: workout.id,
            planned: workout.planned
        )
        guard draftStarted else {
            WorkoutTransition.settleWorkoutTransition()
            return false
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
                startedAt: now
            ),
            outcome: nil
        )
        if WorkoutsStore.shared.workout(workout.id) != nil {
            WorkoutsStore.shared.updateWorkout(workout.id, WorkoutsStore.WorkoutPatch(date: date))
        }
        WorkoutTransition.settleWorkoutTransition()
        return true
    }

    func finish() {
        guard let session else { return }
        // Everything the finish will use is decided once and written down, so an
        // interruption resumes to exactly this result.
        _ = try? WorkoutTransition.recordFinishIntent(
            session, durationMs: ActiveWorkout.elapsedMs(session)
        )
        // Both records close together: the legacy workout keeps duration,
        // calories and which exercises were checked off, while the structured
        // session keeps the sets that were really performed.
        WorkoutTransition.recoverWorkoutTransition()
        setSession(nil, outcome: .finished)
        WorkoutTransition.settleWorkoutTransition()
    }

    func cancel() {
        // A discarded session is still evidence of the sets it did produce, so
        // they are kept as a partial session rather than thrown away.
        if let session {
            _ = try? WorkoutTransition.recordCancelIntent(session)
            WorkoutTransition.recoverWorkoutTransition()
        }
        setSession(nil, outcome: .cancelled)
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
                    startedAt: restore.startedAtMs
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
