import Foundation
import HealthKit
import Observation

/// The watch's HealthKit workout, following the workout running on the phone.
///
/// The lifecycle lives here rather than in a view, so a workout starts and ends
/// with the phone's even while the watch app is in the background — which an
/// active workout session, with the workout-processing background mode, keeps
/// it running in. HealthKit drives the ending: ``end(_:)`` asks the session to
/// end, and only once the session reports `.ended` is collection closed and the
/// workout saved — or, for a workout the phone discarded, dropped.
///
/// The phone can open this app into a workout (`startWatchApp`); the session
/// then starts at once, before the phone has said which workout it is, and
/// takes the workout's identity from the first envelope.
///
/// This watch saves what it records; see ``RautaHealthWorkout`` for how the
/// phone stays out of the way.
@MainActor
@Observable
final class WatchWorkoutManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = WatchWorkoutManager()

    private(set) var heartRate: Double?
    private(set) var activeKilocalories: Double = 0
    private(set) var isTracking = false
    private(set) var issue: String?

    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private var workoutSession: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    /// The phone workout the session records; nil for a session opened by the
    /// phone that has not been told which one yet. Kept on disk, so a session
    /// recovered after a relaunch still knows which workout it is.
    @ObservationIgnored private var workoutId: String? {
        didSet { UserDefaults.standard.set(workoutId, forKey: Self.workoutIdKey) }
    }
    /// The workout the phone is running now, which the session catches up with.
    @ObservationIgnored private var wantedWorkoutId: String?
    /// How the phone's last workout ended.
    @ObservationIgnored private var lastEnded: RautaWatchEndedWorkout?
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var isFinishing = false
    @ObservationIgnored private var unboundTimeout: Task<Void, Never>?

    private static let workoutIdKey = "rauta-watch-recording-workout"
    /// How long a session opened by the phone waits to be told its workout.
    private static let unboundGrace: Duration = .seconds(90)

    private override init() {
        super.init()
        workoutId = UserDefaults.standard.string(forKey: Self.workoutIdKey)
    }

    /// A workout on the phone is a workout recorded here.
    func follow(_ link: WatchSessionModel) {
        link.onWorkoutChange = { [weak self] workoutId in self?.follow(workoutId: workoutId) }
        link.onEnded = { [weak self] ended in self?.lastEnded = ended }
        link.onPausedChange = { [weak self] paused in self?.followPause(paused) }
    }

    private func follow(workoutId wanted: String?) {
        wantedWorkoutId = wanted
        reconcile()
    }

    /// Moves the session one step towards the wanted workout. Called again
    /// whenever a step finishes, so a change that arrives mid-step is not lost.
    private func reconcile() {
        guard !isStarting, !isFinishing else { return }
        if let session = workoutSession {
            guard let workoutId else {
                // Opened by the phone: the first workout it names is this one.
                if let wanted = wantedWorkoutId { bind(wanted) }
                return
            }
            if workoutId != wantedWorkoutId { end(session) }
            return
        }
        if let wanted = wantedWorkoutId { begin(wanted) }
    }

    /// The phone opened the app into a workout: WatchKit expects the session
    /// to start now, so it does, and learns which workout from the next
    /// envelope.
    func startForPhone() {
        guard workoutSession == nil, !isStarting else { return }
        begin(wantedWorkoutId)
    }

    /// Picks up a session the system kept running through a relaunch.
    func recoverActiveWorkout() {
        guard workoutSession == nil, !isStarting else { return }
        isStarting = true
        Task {
            defer {
                isStarting = false
                reconcile()
            }
            guard let session = try? await healthStore.recoverActiveWorkoutSession() else { return }
            adopt(session)
            isTracking = session.state == .running || session.state == .paused
            if let workoutId { WatchSessionModel.shared.claimHealthWorkout(workoutId) }
        }
    }

    private func begin(_ id: String?) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        isStarting = true
        Task {
            defer {
                isStarting = false
                reconcile()
            }
            let readTypes: Set<HKObjectType> = [
                HKQuantityType(.heartRate),
                HKQuantityType(.activeEnergyBurned),
            ]
            let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
            do {
                try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
                try await start(id)
            } catch {
                issue = "Health access unavailable"
                // A session that opened but could not collect is closed again;
                // its `.ended` report clears it.
                workoutSession?.end()
            }
        }
    }

    private func start(_ id: String?) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        workoutId = id
        issue = nil
        adopt(session)

        let start = Date()
        session.startActivity(with: start)
        try await builder?.beginCollection(at: start)
        isTracking = true
        if let id {
            try await stamp(id)
        } else {
            waitToBeBound()
        }
    }

    /// The session takes the phone's workout as its own.
    private func bind(_ id: String) {
        unboundTimeout?.cancel()
        unboundTimeout = nil
        workoutId = id
        Task {
            do { try await stamp(id) } catch { issue = "Workout could not be linked" }
        }
    }

    /// Stamped on the workout, so it is recognisable in Health however the
    /// session ends, and claimed, so the phone leaves the saving to the watch.
    private func stamp(_ id: String) async throws {
        try await builder?.addMetadata([
            HKMetadataKeyExternalUUID: RautaHealthWorkout.externalID(forWorkout: id),
        ])
        WatchSessionModel.shared.claimHealthWorkout(id)
    }

    /// A session opened by the phone that is never told its workout — the
    /// phone's start was refused, say — does not run on unseen.
    private func waitToBeBound() {
        unboundTimeout?.cancel()
        unboundTimeout = Task { [weak self] in
            try? await Task.sleep(for: Self.unboundGrace)
            guard !Task.isCancelled, let self, self.workoutId == nil, let session = self.workoutSession else { return }
            self.end(session)
        }
    }

    private func adopt(_ session: HKWorkoutSession) {
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: session.workoutConfiguration
        )
        session.delegate = self
        builder.delegate = self
        workoutSession = session
        self.builder = builder
    }

    /// The watch's recording pauses and resumes with the phone's workout, so
    /// Health's duration and energy match the time actually trained.
    private func followPause(_ paused: Bool) {
        guard let session = workoutSession else { return }
        switch (paused, session.state) {
        case (true, .running): session.pause()
        case (false, .paused): session.resume()
        default: break
        }
    }

    /// Asks the session to end; ``finish(_:at:)`` completes it when HealthKit
    /// reports the session has ended.
    private func end(_ session: HKWorkoutSession) {
        switch session.state {
        case .ended:
            finish(ObjectIdentifier(session), at: session.endDate ?? Date())
        case .stopped, .running, .paused, .prepared, .notStarted:
            session.end()
        @unknown default:
            session.end()
        }
    }

    private func finish(_ sessionID: ObjectIdentifier, at endDate: Date) {
        guard let session = workoutSession, ObjectIdentifier(session) == sessionID,
              let builder, !isFinishing
        else { return }
        isFinishing = true
        let id = workoutId
        // A workout the phone discarded is not kept; one it finished, or one
        // it said nothing about, is.
        let discarded = id != nil && lastEnded?.workoutId == id && lastEnded?.outcome == .cancelled
        Task {
            defer {
                reset()
                isFinishing = false
                reconcile()
            }
            do {
                try await builder.endCollection(at: endDate)
                guard let id, !discarded else {
                    builder.discardWorkout()
                    return
                }
                let alreadySaved = await hasSavedWorkout(workoutId: id)
                if RautaHealthWorkout.watchShouldSave(alreadyInHealth: alreadySaved) {
                    _ = try await builder.finishWorkout()
                } else {
                    builder.discardWorkout()
                }
            } catch {
                issue = "Workout could not be saved"
            }
        }
    }

    private func reset() {
        unboundTimeout?.cancel()
        unboundTimeout = nil
        workoutSession = nil
        builder = nil
        workoutId = nil
        isTracking = false
        heartRate = nil
        activeKilocalories = 0
    }

    private func hasSavedWorkout(workoutId: String) async -> Bool {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [RautaHealthWorkout.externalID(forWorkout: workoutId)]
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [],
            limit: 1
        )
        let results = (try? await descriptor.result(for: healthStore)) ?? []
        return !results.isEmpty
    }

    private func refreshStatistics(for types: Set<HKSampleType>) {
        guard let builder else { return }

        let heartType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)

        if types.contains(heartType),
           let value = builder.statistics(for: heartType)?.mostRecentQuantity() {
            heartRate = value.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        if types.contains(energyType),
           let value = builder.statistics(for: energyType)?.sumQuantity() {
            activeKilocalories = value.doubleValue(for: .kilocalorie())
        }
    }

    // MARK: Delegates

    // HealthKit calls these on a queue of its own; each hops to the main actor
    // with values only.

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor [weak self] in self?.refreshStatistics(for: collectedTypes) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let sessionID = ObjectIdentifier(workoutSession)
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch toState {
            case .running, .paused:
                self.isTracking = true
            case .ended:
                // Ended by the phone's workout, by the person from the system
                // UI, or by the system: collection closes and the save follows
                // in every case.
                self.finish(sessionID, at: date)
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.issue = "Workout tracking stopped"
            self?.isTracking = false
        }
    }
}
