import Combine
import Foundation
import WatchConnectivity

/// The phone's side of the workout link. Its state belongs to the stores, so it
/// lives on the main actor; WatchConnectivity calls the delegate on a queue of
/// its own, and each callback copies out the `Data` it carries before hopping.
@MainActor
final class WatchConnectivityService: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityService()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    /// Oldest first, so the persisted window keeps the most recent actions. A
    /// watch set arrives up to three times (message, application context, user
    /// info) and the context is replayed on every activation.
    private var processedActionIDs: [String] = []
    private let processedActionIDsKey = "rauta-watch-processed-actions"
    private static let processedActionWindow = 64

    private override init() {
        super.init()
        processedActionIDs = UserDefaults.standard.stringArray(forKey: processedActionIDsKey) ?? []
    }

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
        // A new accent reaches the watch at once, workout or not.
        SettingsStore.shared.changed
            .map { SettingsStore.shared.accent }
            // Seeded with the accent in use, so only a real change gets through
            // — including the very first one.
            .prepend(SettingsStore.shared.accent)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.sendLatestSnapshot() }
            .store(in: &cancellables)

        sendLatestSnapshot()
    }

    private func sendLatestSnapshot() {
        guard started, WCSession.default.activationState == .activated else { return }
        do {
            let data = try encoder.encode(makeEnvelope())
            try WCSession.default.updateApplicationContext([RautaWatchMessageKey.snapshot: data])
        } catch {
            // Watch sync is best-effort. The next store mutation or snapshot
            // request retries with the newest authoritative phone state.
        }
    }

    private func makeEnvelope() -> RautaWatchSnapshotEnvelope {
        let signature = SettingsStore.shared.accent.signature
        return RautaWatchSnapshotEnvelope(
            snapshot: makeSnapshot(),
            accent: RautaWatchAccent(
                primary: signature.primary,
                gradientStart: signature.gradientStart,
                gradientEnd: signature.gradientEnd,
                whiteLabel: signature.whiteLabel
            )
        )
    }

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
            else { return PlannedExercisePrescription.fallbackRestSeconds }
            return plan.prescription.first(where: { $0.exerciseId == currentExerciseId })?.restSeconds
                ?? PlannedExercisePrescription.fallbackRestSeconds
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
            processedActionIDs = RecentIDs.recording(
                action.id, in: processedActionIDs, limit: Self.processedActionWindow
            )
            UserDefaults.standard.set(processedActionIDs, forKey: processedActionIDsKey)
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

    /// Tells the watch what became of a set it sent, with the state that
    /// resulted. Best effort: the application context carries the same state.
    private func sendResult(of action: RautaWatchSetAction, ok: Bool) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable,
              let result = try? encoder.encode(RautaWatchActionResult(actionId: action.id, ok: ok))
        else { return }
        var message: [String: Any] = [RautaWatchMessageKey.actionResult: result]
        if let snapshot = try? encoder.encode(makeEnvelope()) {
            message[RautaWatchMessageKey.snapshot] = snapshot
        }
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    /// Hands the watch the current state directly, for a watch that asked.
    private func sendSnapshotMessage() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable,
              let snapshot = try? encoder.encode(makeEnvelope())
        else { return }
        session.sendMessage([RautaWatchMessageKey.snapshot: snapshot], replyHandler: nil, errorHandler: nil)
    }

    // MARK: WCSessionDelegate

    // WatchConnectivity calls these on a queue of its own. Each one copies the
    // `Data` it needs out of the dictionary and hands only that to the main
    // actor; a reply handler is answered where it arrived and never leaves.

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        let incoming = Incoming(session.receivedApplicationContext)
        Task { @MainActor [weak self] in
            self?.handle(incoming)
            self?.sendLatestSnapshot()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        // Only receipt is acknowledged here. What became of the message is
        // sent back once the stores have applied it.
        replyHandler([RautaWatchMessageKey.received: true])
        receive(Incoming(message), reportingResult: true)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(Incoming(message), reportingResult: true)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(Incoming(userInfo), reportingResult: false)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(Incoming(applicationContext), reportingResult: false)
    }

    /// The parts of a WatchConnectivity dictionary this service reads, as
    /// values that can cross to the main actor.
    private struct Incoming: Sendable {
        var action: Data?
        var healthClaim: Data?
        var wantsSnapshot: Bool

        nonisolated init(_ dictionary: [String: Any]) {
            action = dictionary[RautaWatchMessageKey.action] as? Data
            healthClaim = dictionary[RautaWatchMessageKey.healthClaim] as? Data
            wantsSnapshot = dictionary[RautaWatchMessageKey.requestSnapshot] as? Bool == true
        }
    }

    nonisolated private func receive(_ incoming: Incoming, reportingResult: Bool) {
        Task { @MainActor [weak self] in
            self?.handle(incoming, reportingResult: reportingResult)
        }
    }

    private func handle(_ incoming: Incoming, reportingResult: Bool = false) {
        if let data = incoming.healthClaim,
           let claim = try? decoder.decode(RautaWatchHealthClaim.self, from: data) {
            HealthService.shared.recordWatchClaim(workoutId: claim.workoutId)
        }
        if let data = incoming.action,
           let action = try? decoder.decode(RautaWatchSetAction.self, from: data) {
            let ok = apply(action)
            sendLatestSnapshot()
            if reportingResult { sendResult(of: action, ok: ok) }
        } else if incoming.wantsSnapshot {
            sendLatestSnapshot()
            sendSnapshotMessage()
        }
    }
}
