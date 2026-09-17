import Combine
import Foundation
import HealthKit

/// The watch's HealthKit workout, following the workout running on the phone.
///
/// The lifecycle lives here rather than in a view, so a workout starts and ends
/// with the phone's even while the watch app is in the background — which an
/// active workout session keeps it running in. HealthKit drives the ending:
/// ``end(_:)`` asks the session to end, and only once the session reports
/// `.ended` is collection closed and the workout saved, in that order.
///
/// This watch saves what it records; see ``RautaHealthWorkout`` for how the
/// phone stays out of the way.
@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = WatchWorkoutManager()

    @Published private(set) var heartRate: Double?
    @Published private(set) var activeKilocalories: Double = 0
    @Published private(set) var isTracking = false
    @Published private(set) var issue: String?

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// The phone workout the session records. Kept on disk, so a session
    /// recovered after a relaunch still knows which workout it is.
    private var workoutId: String? {
        didSet { UserDefaults.standard.set(workoutId, forKey: Self.workoutIdKey) }
    }
    /// The workout the phone is running now, which the session catches up with.
    private var wantedWorkoutId: String?
    private var isStarting = false
    private var isFinishing = false
    private var cancellables = Set<AnyCancellable>()

    private static let workoutIdKey = "rauta-watch-recording-workout"

    private override init() {
        super.init()
        workoutId = UserDefaults.standard.string(forKey: Self.workoutIdKey)
    }

    /// A workout on the phone is a workout recorded here.
    func follow(_ link: WatchSessionModel) {
        cancellables.removeAll()
        link.$snapshot
            .map { $0?.workoutId }
            .removeDuplicates()
            .sink { [weak self] workoutId in self?.follow(workoutId: workoutId) }
            .store(in: &cancellables)
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
            if workoutId != wantedWorkoutId { end(session) }
            return
        }
        if let wanted = wantedWorkoutId { begin(wanted) }
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
            isTracking = session.state == .running
            if let workoutId { WatchSessionModel.shared.claimHealthWorkout(workoutId) }
        }
    }

    private func begin(_ id: String) {
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

    private func start(_ id: String) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        workoutId = id
        issue = nil
        adopt(session)

        let start = Date()
        session.startActivity(with: start)
        let builder = session.associatedWorkoutBuilder()
        try await builder.beginCollection(at: start)
        // Stamped from the start, so this workout is recognisable in Health
        // however the session ends.
        try await builder.addMetadata([
            HKMetadataKeyExternalUUID: RautaHealthWorkout.externalID(forWorkout: id),
        ])
        isTracking = true
        WatchSessionModel.shared.claimHealthWorkout(id)
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
        Task {
            defer {
                reset()
                isFinishing = false
                reconcile()
            }
            do {
                try await builder.endCollection(at: endDate)
                var alreadySaved = false
                if let id { alreadySaved = await hasSavedWorkout(workoutId: id) }
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
            case .running:
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
