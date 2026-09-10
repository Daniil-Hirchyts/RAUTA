import Combine
import Foundation
import HealthKit
import UIKit

enum AppleHealthConnectionResult {
    case connected(bodyWeightKg: Double?)
    case unavailable
}

/// Apple Health, as much of it as RAUTA uses: it writes finished workouts and
/// their active energy, and reads body weight so calorie estimates and the
/// engine's load reasoning have a real number to work from.
@MainActor
final class HealthService {
    static let shared = HealthService()

    private let store = HKHealthStore()
    private var cancellable: AnyCancellable?
    private var previousSession: ActiveWorkoutSession?

    private init() {}

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        return types
    }

    private var readTypes: Set<HKObjectType> {
        guard let weight = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        return [weight]
    }

    func requestAccess() async -> AppleHealthConnectionResult {
        guard isAvailable else { return .unavailable }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        } catch {
            return .unavailable
        }
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            return .unavailable
        }
        // A denied or empty read does not prevent workout writes. HealthKit does
        // not distinguish those two cases, so calories use the safe fallback.
        return .connected(bodyWeightKg: await readBodyWeightKg())
    }

    func readBodyWeightKg() async -> Double? {
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .bodyMass)
        else { return nil }

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let kilograms = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                guard kilograms >= 30, kilograms <= 300 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (kilograms * 10).rounded() / 10)
            }
            store.execute(query)
        }
    }

    struct WorkoutExport {
        var startDate: Date
        var endDate: Date
        var activeCalories: Double?
        var workoutId: String
        var workoutName: String
    }

    @discardableResult
    func saveCompletedWorkout(_ input: WorkoutExport) async -> Bool {
        guard isAvailable else { return false }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining

        do {
            let builder = HKWorkoutBuilder(
                healthStore: store, configuration: configuration, device: .local()
            )
            try await builder.beginCollection(at: input.startDate)

            if let calories = input.activeCalories, calories > 0,
               let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                let sample = HKQuantitySample(
                    type: energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                    start: input.startDate,
                    end: input.endDate
                )
                try await builder.addSamples([sample])
            }

            try await builder.addMetadata([
                "gymLibWorkoutId": input.workoutId,
                "workoutName": input.workoutName,
            ])
            try await builder.endCollection(at: input.endDate)
            _ = try await builder.finishWorkout()
            return true
        } catch {
            return false
        }
    }

    /// Opens the Health app on this app's data sources.
    func openAppleHealthSettings() {
        guard let url = URL(string: "x-apple-health://") else { return }
        Task { @MainActor in
            await UIApplication.shared.open(url)
        }
    }

    /// Syncs only intentional finishes; discarded sessions are never exported.
    func startAutoSync() {
        let store = ActiveWorkoutStore.shared
        previousSession = store.session
        cancellable = store.changed
            .sink { [weak self] in
                guard let self else { return }
                let current = store.session
                let previous = previousSession
                previousSession = current
                guard previous != nil, current == nil, store.lastOutcome == .finished,
                      let finished = previous
                else { return }
                Task { await self.sync(finished) }
            }
    }

    private func sync(_ session: ActiveWorkoutSession) async {
        let settings = SettingsStore.shared
        guard settings.appleHealthEnabled, settings.autoSyncWorkouts else { return }

        let durationMs = ActiveWorkout.elapsedMs(session)
        let workout = WorkoutsStore.shared.workout(session.workoutId)
        let activeCalories = workout?.completion?.activeCalories
            ?? WorkoutStats.estimateStrengthCalories(
                durationMs, bodyWeightKg: settings.healthBodyWeightKg
            )

        let success = await saveCompletedWorkout(WorkoutExport(
            startDate: Date(timeIntervalSince1970: session.startedAt / 1000),
            endDate: Date(timeIntervalSince1970: (session.startedAt + durationMs) / 1000),
            activeCalories: settings.syncActiveCalories ? activeCalories : nil,
            workoutId: session.workoutId,
            workoutName: session.workoutName
        ))
        WorkoutsStore.shared.setHealthSyncStatus(session.workoutId, success ? .synced : .failed)
    }
}
