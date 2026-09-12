import Combine
import Foundation
import WatchConnectivity

final class WatchConnectivityService: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityService()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var processedActionIDs = Set<String>()
    private let processedActionIDsKey = "rauta-watch-processed-actions"

    private override init() {
        super.init()
        processedActionIDs = Set(UserDefaults.standard.stringArray(forKey: processedActionIDsKey) ?? [])
    }

    @MainActor
    func start() {
        guard !started, WCSession.isSupported() else { return }
        started = true

        let session = WCSession.default
        session.delegate = self
        session.activate()

        ActiveWorkoutStore.shared.changed
            .sink { [weak self] in self?.sendLatestSnapshot() }
            .store(in: &cancellables)
        TrainingRecordsStore.shared.changed
            .sink { [weak self] in self?.sendLatestSnapshot() }
            .store(in: &cancellables)

        sendLatestSnapshot()
    }

    @MainActor
    private func sendLatestSnapshot() {
        guard started, WCSession.default.activationState == .activated else { return }
        do {
            let data = try encoder.encode(RautaWatchSnapshotEnvelope(snapshot: makeSnapshot()))
            try WCSession.default.updateApplicationContext([RautaWatchMessageKey.snapshot: data])
        } catch {
            // Watch sync is best-effort. The next store mutation or snapshot
            // request retries with the newest authoritative phone state.
        }
    }

    @MainActor
    private func makeSnapshot() -> RautaWatchWorkoutSnapshot? {
        guard let session = ActiveWorkoutStore.shared.session else { return nil }

        let draft = TrainingRecordsStore.shared.data.activeWorkout
        let currentExerciseId = session.currentExerciseId
        let exerciseEntry = currentExerciseId.flatMap { id in
            draft?.exercises.first(where: { $0.exerciseId == id })
        }

        let nextSetIndex = exerciseEntry?.sets.firstIndex(where: {
            $0.observation?.completed != true
        })
        let nextSet = nextSetIndex.flatMap { index in exerciseEntry?.sets[index] }
        let previousObservation = exerciseEntry.flatMap { entry -> PersistedSetObservation? in
            let upperBound = nextSetIndex ?? entry.sets.count
            guard upperBound > 0 else { return nil }
            return entry.sets[..<upperBound]
                .reversed()
                .compactMap(\.observation)
                .first(where: { $0.completed })
        }

        let load = nextSet?.observation?.resistance?.kg
            ?? nextSet?.target?.resistance.kg
            ?? previousObservation?.resistance?.kg
            ?? 0
        let repsValue = nextSet?.observation?.reps
            ?? nextSet?.target?.reps.max
            ?? previousObservation?.reps
            ?? 10

        let exerciseName: String = {
            guard let currentExerciseId else { return "Workout complete" }
            return exerciseEntry?.exerciseNameSnapshot
                ?? ExerciseCatalogue.name(currentExerciseId)
                ?? "Exercise"
        }()
        let restSeconds: Double = {
            guard let currentExerciseId,
                  let workout = WorkoutsStore.shared.workout(session.workoutId),
                  let reference = workout.planned,
                  let plan = TrainingPlan.plannedSessionView(reference.programId, reference.sessionId)
            else { return 90 }
            return plan.prescription.first(where: { $0.exerciseId == currentExerciseId })?.restSeconds ?? 90
        }()

        return RautaWatchWorkoutSnapshot(
            workoutId: session.workoutId,
            workoutName: session.workoutName,
            exerciseId: currentExerciseId,
            exerciseEntryId: exerciseEntry?.id,
            exerciseName: exerciseName,
            setDraftId: nextSet?.id,
            setIndex: (nextSetIndex ?? exerciseEntry?.sets.count ?? 0) + 1,
            setCount: exerciseEntry?.sets.count ?? 0,
            loadKg: load,
            reps: Swift.max(1, Int(repsValue.rounded())),
            restSeconds: restSeconds,
            accumulatedSeconds: session.accumulatedMs / 1000,
            runningSinceMilliseconds: session.runningSince,
            isPaused: session.runningSince == nil
        )
    }

    @MainActor
    private func apply(_ action: RautaWatchSetAction) -> Bool {
        if processedActionIDs.contains(action.id) { return true }
        guard let active = ActiveWorkoutStore.shared.session,
              active.workoutId == action.workoutId,
              let activeDraft = TrainingRecordsStore.shared.data.activeWorkout,
              let exercise = activeDraft.exercises.first(where: { $0.id == action.exerciseEntryId }),
              let catalogueExercise = ExerciseCatalogue.byId[exercise.exerciseId]
        else { return false }

        let targetSet = action.setDraftId.flatMap { id in
            exercise.sets.first(where: { $0.id == id })
        }
        let observation = PersistedSetObservation(
            reps: Double(Swift.max(1, action.reps)),
            resistance: resistanceValue(
                for: catalogueExercise,
                set: targetSet,
                loadKg: Swift.max(0, action.loadKg)
            ),
            rir: targetSet?.target?.rir,
            completed: true,
            timestamp: ISOTime.now()
        )

        do {
            if let targetSet {
                try TrainingRecordsStore.shared.recordSet(
                    exerciseEntryId: exercise.id,
                    setDraftId: targetSet.id,
                    observation: observation
                )

                if let refreshed = TrainingRecordsStore.shared.data.activeWorkout?.exercises
                    .first(where: { $0.id == exercise.id }),
                   !refreshed.sets.isEmpty,
                   refreshed.sets.allSatisfy({ $0.observation?.completed == true }),
                   ActiveWorkoutStore.shared.session?.currentExerciseId == exercise.exerciseId {
                    ActiveWorkoutStore.shared.completeCurrent()
                }
            } else {
                _ = try TrainingRecordsStore.shared.addUnplannedSet(
                    exerciseEntryId: exercise.id,
                    setType: .working,
                    side: .both,
                    observation: observation
                )
            }
            processedActionIDs.insert(action.id)
            UserDefaults.standard.set(Array(processedActionIDs.suffix(64)), forKey: processedActionIDsKey)
            let completedAt = action.completedAtMilliseconds.map { $0 / 1000 }
                ?? Date().timeIntervalSince1970
            let elapsed = Date().timeIntervalSince1970 - completedAt
            ActiveWorkoutStore.shared.startRest(
                seconds: Swift.max(1, action.restSeconds - elapsed),
                exerciseName: catalogueExercise.name
            )
            return true
        } catch {
            return false
        }
    }

    private func resistanceValue(
        for exercise: ExerciseSummary,
        set: PersistedActiveSetDraft?,
        loadKg: Double
    ) -> ResistanceValue? {
        let existing = set?.observation?.resistance ?? set?.target?.resistance
        if let existing {
            if Resistance.isMeasuredInKg(existing.type) {
                return ResistanceValue(
                    type: existing.type,
                    kg: loadKg,
                    basis: existing.basis,
                    stationId: existing.stationId
                )
            }
            if loadKg <= 0 { return existing }
        }

        let modes = Resistance.modes(for: exercise)
        let mode = loadKg > 0
            ? modes.first(where: { Resistance.isMeasuredInKg($0) }) ?? modes.first
            : existing?.type ?? modes.first
        guard let mode else { return nil }

        if Resistance.isMeasuredInKg(mode) {
            let context = Resistance.loadContext(for: exercise, mode: mode)
            return Resistance.makeResistance(mode, loadKg, context)
        }
        return ResistanceValue(type: mode)
    }

    @MainActor
    private func reply(ok: Bool) -> [String: Any] {
        var reply: [String: Any] = [RautaWatchMessageKey.ok: ok]
        if let data = try? encoder.encode(RautaWatchSnapshotEnvelope(snapshot: makeSnapshot())) {
            reply[RautaWatchMessageKey.snapshot] = data
        }
        return reply
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor [weak self] in
            self?.applyIncoming(session.receivedApplicationContext)
            self?.sendLatestSnapshot()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if message[RautaWatchMessageKey.requestSnapshot] as? Bool == true {
            Task { @MainActor [weak self] in
                guard let self else { return }
                replyHandler(self.reply(ok: true))
            }
            return
        }

        guard let data = message[RautaWatchMessageKey.action] as? Data,
              let action = try? decoder.decode(RautaWatchSetAction.self, from: data)
        else {
            replyHandler([RautaWatchMessageKey.ok: false])
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = self.apply(action)
            self.sendLatestSnapshot()
            replyHandler(self.reply(ok: ok))
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor [weak self] in self?.applyIncoming(userInfo) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor [weak self] in self?.applyIncoming(applicationContext) }
    }

    @MainActor
    private func applyIncoming(_ message: [String: Any]) {
        guard let data = message[RautaWatchMessageKey.action] as? Data,
              let action = try? decoder.decode(RautaWatchSetAction.self, from: data)
        else { return }
        _ = apply(action)
        sendLatestSnapshot()
    }
}
