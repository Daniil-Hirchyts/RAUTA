import Combine
import Foundation
import HealthKit
import WatchConnectivity

/// The phone's side of the workout link. Its state belongs to the stores, so it
/// lives on the main actor; WatchConnectivity calls the delegate on a queue of
/// its own, and each callback copies out the `Data` it carries before hopping.
///
/// The phone owns the workout and tells the watch about it in envelopes that
/// carry a revision, so one arriving late can never undo a newer one. Each
/// goes as the application context — the latest state, delivered whenever the
/// watch next runs — and, while the watch is listening, as a message too, so
/// it shows on the wrist at once rather than whenever the system gets round
/// to it.
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
    /// When the newest watch set that started a rest was done, in seconds.
    private var latestRestStart: TimeInterval = 0
    /// The workout that ended last, carried in every envelope until the next
    /// one starts.
    private var ended: RautaWatchEndedWorkout?
    private var lastRevision: Int64 = 0
    private var previousWorkoutId: String?
    /// Store changes come in bursts — a set logged changes the records and the
    /// session together. One envelope goes per burst.
    private var sendScheduled = false

    private let processedActionIDsKey = "rauta-watch-processed-actions"
    private let revisionKey = "rauta-watch-revision"
    private let endedKey = "rauta-watch-ended"
    private static let processedActionWindow = 64
    /// How many applied actions each envelope names.
    private static let appliedWindow = 16

    private override init() {
        super.init()
        processedActionIDs = Storage.defaults.stringArray(forKey: processedActionIDsKey) ?? []
        lastRevision = Int64(Storage.defaults.integer(forKey: revisionKey))
        ended = Storage.defaults.data(forKey: endedKey)
            .flatMap { try? decoder.decode(RautaWatchEndedWorkout.self, from: $0) }
    }

    /// Clearing all data forgets which watch sets were already applied.
    func forgetProcessedActions() {
        processedActionIDs = []
        Storage.defaults.removeObject(forKey: processedActionIDsKey)
    }

    func start() {
        guard !started, WCSession.isSupported() else { return }
        started = true

        let session = WCSession.default
        session.delegate = self
        session.activate()

        previousWorkoutId = ActiveWorkoutStore.shared.session?.workoutId
        ActiveWorkoutStore.shared.changed
            .sink { [weak self] in
                self?.followSession()
                self?.scheduleSend()
            }
            .store(in: &cancellables)
        TrainingRecordsStore.shared.changed
            .sink { [weak self] in self?.scheduleSend() }
            .store(in: &cancellables)
        // A new accent reaches the watch at once, workout or not.
        SettingsStore.shared.accentChanges
            .sink { [weak self] _ in self?.scheduleSend() }
            .store(in: &cancellables)

        sendLatest()
    }

    /// Whether there is a watch to tell anything to.
    private var watchIsThere: Bool {
        let session = WCSession.default
        return started && session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    // MARK: Start and end

    /// A workout starting opens the watch app with it; one ending is
    /// remembered with how it ended, so the watch keeps or drops what it
    /// recorded.
    private func followSession() {
        let store = ActiveWorkoutStore.shared
        let current = store.session?.workoutId
        defer { previousWorkoutId = current }
        guard current != previousWorkoutId else { return }

        if let previousWorkoutId, current == nil {
            switch store.lastOutcome {
            case .finished: remember(RautaWatchEndedWorkout(workoutId: previousWorkoutId, outcome: .finished))
            case .cancelled: remember(RautaWatchEndedWorkout(workoutId: previousWorkoutId, outcome: .cancelled))
            case nil: remember(nil)
            }
            if let ended, watchIsThere, let data = try? encoder.encode(RautaWatchSnapshotEnvelope(snapshot: nil, ended: ended)) {
                // Queued, so it reaches a watch that is out of reach right now.
                WCSession.default.transferUserInfo([RautaWatchMessageKey.snapshot: data])
            }
        }
        if current != nil {
            remember(nil)
            openWatchApp()
        }
    }

    private func remember(_ next: RautaWatchEndedWorkout?) {
        ended = next
        if let next, let data = try? encoder.encode(next) {
            Storage.defaults.set(data, forKey: endedKey)
        } else {
            Storage.defaults.removeObject(forKey: endedKey)
        }
    }

    /// Opens the watch app into the workout, the way Fitness does. The watch
    /// starts its HealthKit session as it opens and picks up which workout it
    /// is from the next envelope.
    private func openWatchApp() {
        guard watchIsThere, HKHealthStore.isHealthDataAvailable() else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        Self.startWatchApp(configuration)
    }

    /// `nonisolated`: HealthKit answers on a queue of its own.
    private nonisolated static func startWatchApp(_ configuration: HKWorkoutConfiguration) {
        HKHealthStore().startWatchApp(with: configuration) { _, _ in }
    }

    // MARK: Sending

    private func scheduleSend() {
        guard !sendScheduled else { return }
        sendScheduled = true
        Task { @MainActor [weak self] in
            self?.sendScheduled = false
            self?.sendLatest()
        }
    }

    /// The latest state, as the context and — when the watch is listening — as
    /// a message.
    private func sendLatest() {
        guard watchIsThere, let data = try? encoder.encode(makeEnvelope()) else { return }
        do {
            try WCSession.default.updateApplicationContext([RautaWatchMessageKey.snapshot: data])
        } catch {
            // The context is best-effort; the message below and the next change
            // carry the same state.
        }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage([RautaWatchMessageKey.snapshot: data], replyHandler: nil, errorHandler: nil)
        }
    }

    private func makeEnvelope() -> RautaWatchSnapshotEnvelope {
        let signature = SettingsStore.shared.accent.signature
        lastRevision = RautaWatchSync.nextRevision(after: lastRevision, nowMilliseconds: ActiveWorkout.nowMillis())
        Storage.defaults.set(Int(lastRevision), forKey: revisionKey)
        return RautaWatchSnapshotEnvelope(
            snapshot: makeSnapshot(),
            accent: RautaWatchAccent(
                primary: signature.primary,
                gradientStart: signature.gradientStart,
                gradientEnd: signature.gradientEnd,
                whiteLabel: signature.whiteLabel
            ),
            revision: lastRevision,
            ended: ended,
            appliedActionIds: Array(processedActionIDs.suffix(Self.appliedWindow))
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
        let now = ActiveWorkout.nowMillis()
        let nextExerciseName = ActiveWorkout.nextPendingExerciseId(session)
            .flatMap { ExerciseCatalogue.name($0) }

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
            restSeconds: restSeconds(session),
            accumulatedSeconds: session.accumulatedMs / 1000,
            runningSinceMilliseconds: session.runningSince,
            isPaused: session.runningSince == nil,
            phase: RautaWatchSync.phase(
                warmupUntil: session.warmupUntil,
                restUntil: session.restUntil,
                hasCurrentExercise: currentExerciseId != nil,
                nowMilliseconds: now
            ),
            warmupUntilMilliseconds: session.warmupUntil.flatMap { $0 > now ? $0 : nil },
            restUntilMilliseconds: session.restUntil.flatMap { $0 > now ? $0 : nil },
            exerciseNumber: currentExerciseId.flatMap { id in session.exerciseIds.firstIndex(of: id) }.map { $0 + 1 },
            exerciseCount: session.exerciseIds.count,
            nextExerciseName: nextExerciseName,
            sets: exerciseEntry?.sets.map(Self.slot)
        )
    }

    private static func slot(_ set: PersistedActiveSetDraft) -> RautaWatchSetSlot {
        let observation = set.observation?.completed == true ? set.observation : nil
        return RautaWatchSetSlot(
            id: set.id,
            targetLoadKg: set.target?.resistance.kg,
            targetReps: set.target.map { Swift.max(1, Int($0.reps.max.rounded())) },
            done: observation != nil,
            loggedLoadKg: observation?.resistance?.kg,
            loggedReps: observation?.reps.map { Int($0.rounded()) }
        )
    }

    private func restSeconds(_ session: ActiveWorkoutSession) -> Double {
        guard let currentExerciseId = session.currentExerciseId,
              let workout = WorkoutsStore.shared.workout(session.workoutId),
              let reference = workout.planned,
              let plan = TrainingPlan.plannedSessionView(reference.programId, reference.sessionId)
        else { return PlannedExercisePrescription.fallbackRestSeconds }
        return plan.prescription.first(where: { $0.exerciseId == currentExerciseId })?.restSeconds
            ?? PlannedExercisePrescription.fallbackRestSeconds
    }

    // MARK: Applying the watch's sets

    private func apply(_ action: RautaWatchSetAction) -> Bool {
        if processedActionIDs.contains(action.id) { return true }
        guard let active = ActiveWorkoutStore.shared.session,
              active.workoutId == action.workoutId,
              let activeDraft = TrainingRecordsStore.shared.data.activeWorkout,
              let exercise = activeDraft.exercises.first(where: { $0.id == action.exerciseEntryId }),
              let catalogueExercise = ExerciseCatalogue.byId[exercise.exerciseId]
        else { return false }

        var targetSet = action.setDraftId.flatMap { id in
            exercise.sets.first(where: { $0.id == id })
        }
        if let logged = targetSet, logged.observation?.completed == true {
            let loggedAt = logged.observation?.timestamp.flatMap(ISOTime.parse)
            // Logged on both devices: it is one set, already here.
            if action.version != nil, RautaWatchSync.isSameSet(
                phoneLoggedAtMilliseconds: loggedAt,
                watchCompletedAtMilliseconds: action.completedAtMilliseconds,
                restSeconds: action.restSeconds
            ) {
                markProcessed(action.id)
                return true
            }
            // Otherwise the watch was a set behind: this one is the next.
            targetSet = exercise.sets.first { $0.observation?.completed != true }
        }
        let completedAt = action.completedAtMilliseconds ?? ActiveWorkout.nowMillis()
        let observation = PersistedSetObservation(
            reps: Double(Swift.max(1, action.reps)),
            resistance: resistanceValue(
                for: catalogueExercise,
                set: targetSet,
                loadKg: Swift.max(0, action.loadKg)
            ),
            // Neither the watch nor the phone asks how many reps were left:
            // the set is logged at the plan's target.
            rir: targetSet?.target?.rir,
            completed: true,
            timestamp: ISOTime.string(fromMillis: completedAt)
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
            markProcessed(action.id)
            let remaining = action.restSeconds - (ActiveWorkout.nowMillis() - completedAt) / 1000
            // A set that reached the phone late — queued while it was out of
            // reach — has had its rest already. Only the newest set, still
            // resting, starts the clock and sounds; a batch arriving at once
            // no longer fires a string of one-second rests.
            if remaining >= 1, completedAt >= latestRestStart {
                latestRestStart = completedAt
                ActiveWorkoutStore.shared.startRest(seconds: remaining, exerciseName: catalogueExercise.name)
            }
            return true
        } catch {
            Storage.report("Applying a set from the watch", error)
            return false
        }
    }

    private func markProcessed(_ id: String) {
        processedActionIDs = RecentIDs.recording(id, in: processedActionIDs, limit: Self.processedActionWindow)
        Storage.defaults.set(processedActionIDs, forKey: processedActionIDsKey)
    }

    private func apply(_ control: RautaWatchControlAction) -> Bool {
        if processedActionIDs.contains(control.id) { return true }
        let store = ActiveWorkoutStore.shared
        guard let session = store.session, session.workoutId == control.workoutId else { return false }
        switch control.kind {
        case .pause: store.pause()
        case .resume: store.resume()
        case .endRest: store.endRest()
        case .extendRest:
            store.extendRest(
                by: control.seconds ?? 30,
                exerciseName: session.currentExerciseId.flatMap(ExerciseCatalogue.name)
            )
        case .endWarmup: store.endWarmup()
        }
        markProcessed(control.id)
        return true
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

    /// Tells the watch what became of something it sent, with the state that
    /// resulted. Best effort: the application context carries the same state.
    private func sendResult(of actionId: String, ok: Bool) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable,
              let result = try? encoder.encode(RautaWatchActionResult(actionId: actionId, ok: ok))
        else { return }
        var message: [String: Any] = [RautaWatchMessageKey.actionResult: result]
        if let snapshot = try? encoder.encode(makeEnvelope()) {
            message[RautaWatchMessageKey.snapshot] = snapshot
        }
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
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
            self?.sendLatest()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        // A watch paired or the app installed: it gets the state straight away.
        Task { @MainActor [weak self] in self?.sendLatest() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor [weak self] in self?.sendLatest() }
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
        var control: Data?
        var healthClaim: Data?
        var wantsSnapshot: Bool

        nonisolated init(_ dictionary: [String: Any]) {
            action = dictionary[RautaWatchMessageKey.action] as? Data
            control = dictionary[RautaWatchMessageKey.control] as? Data
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
        var handled: (id: String, ok: Bool)?
        if let data = incoming.action,
           let action = try? decoder.decode(RautaWatchSetAction.self, from: data) {
            handled = (action.id, apply(action))
        }
        if let data = incoming.control,
           let control = try? decoder.decode(RautaWatchControlAction.self, from: data) {
            handled = (control.id, apply(control))
        }
        if let handled {
            sendLatest()
            if reportingResult { sendResult(of: handled.id, ok: handled.ok) }
        } else if incoming.wantsSnapshot {
            sendLatest()
        }
    }
}
