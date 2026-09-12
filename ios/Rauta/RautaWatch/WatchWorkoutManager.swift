import Combine
import Foundation
import HealthKit

final class WatchWorkoutManager: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, @unchecked Sendable {
    @Published private(set) var heartRate: Double?
    @Published private(set) var activeKilocalories: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var isTracking = false
    @Published private(set) var issue: String?

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var isStarting = false

    func beginIfNeeded() {
        guard !isTracking, !isStarting, HKHealthStore.isHealthDataAvailable() else { return }
        isStarting = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isStarting = false }

            let heartRateType = HKQuantityType(.heartRate)
            let energyType = HKQuantityType(.activeEnergyBurned)
            let distanceType = HKQuantityType(.distanceWalkingRunning)
            let readTypes: Set<HKObjectType> = [heartRateType, energyType, distanceType]
            let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]

            do {
                try await self.healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
                try self.startWorkout()
            } catch {
                self.issue = "Health access unavailable"
            }
        }
    }

    func endIfNeeded() {
        guard let workoutSession, let builder else { return }
        let end = Date()
        workoutSession.end()
        builder.endCollection(withEnd: end) { [weak self] _, _ in
            builder.finishWorkout { _, _ in
                DispatchQueue.main.async {
                    self?.workoutSession = nil
                    self?.builder = nil
                    self?.isTracking = false
                    self?.heartRate = nil
                    self?.activeKilocalories = 0
                    self?.distanceMeters = 0
                }
            }
        }
    }

    @MainActor
    private func startWorkout() throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let workoutSession = try HKWorkoutSession(
            healthStore: healthStore,
            configuration: configuration
        )
        let builder = workoutSession.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )
        workoutSession.delegate = self
        builder.delegate = self

        self.workoutSession = workoutSession
        self.builder = builder
        issue = nil

        let start = Date()
        workoutSession.startActivity(with: start)
        builder.beginCollection(withStart: start) { [weak self] success, _ in
            DispatchQueue.main.async { self?.isTracking = success }
        }
    }

    private func refreshStatistics(for types: Set<HKSampleType>) {
        guard let builder else { return }

        let heartType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        let distanceType = HKQuantityType(.distanceWalkingRunning)

        if types.contains(heartType),
           let value = builder.statistics(for: heartType)?.mostRecentQuantity() {
            heartRate = value.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        if types.contains(energyType),
           let value = builder.statistics(for: energyType)?.sumQuantity() {
            activeKilocalories = value.doubleValue(for: .kilocalorie())
        }
        if types.contains(distanceType),
           let value = builder.statistics(for: distanceType)?.sumQuantity() {
            distanceMeters = value.doubleValue(for: .meter())
        }
    }

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        DispatchQueue.main.async { [weak self] in self?.refreshStatistics(for: collectedTypes) }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        if toState == .running {
            DispatchQueue.main.async { [weak self] in self?.isTracking = true }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.issue = "Workout tracking stopped"
            self?.isTracking = false
        }
    }
}
