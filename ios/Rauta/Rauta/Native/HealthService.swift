import Combine
import Foundation
import HealthKit
import UIKit

enum AppleHealthConnectionResult {
    case connected(bodyWeightKg: Double?)
    /// The person said no to saving workouts, or has not said yes yet.
    case denied
    /// No Health on this device, or the request itself failed.
    case unavailable
}

/// Apple Health, as much of it as RAUTA uses: it writes finished workouts and
/// their active energy, and reads body weight so calorie estimates and the
/// engine's load reasoning have a real number to work from.
///
/// A workout the watch recorded is the watch's to save — see
/// ``RautaHealthWorkout`` for the rule both devices follow.
@MainActor
final class HealthService {
    static let shared = HealthService()

    private let store = HKHealthStore()
    private var cancellable: AnyCancellable?
    private var previousSession: ActiveWorkoutSession?

    private let watchClaimsKey = "rauta-health-watch-claims"
    /// Workouts the watch said it is recording, newest last.
    private(set) var watchClaims: [String]

    private init() {
        watchClaims = Storage.defaults.stringArray(forKey: watchClaimsKey) ?? []
    }

    /// The watch is recording `workoutId` and will save it.
    func recordWatchClaim(workoutId: String) {
        watchClaims = RecentIDs.recording(workoutId, in: watchClaims, limit: 32)
        Storage.defaults.set(watchClaims, forKey: watchClaimsKey)
    }

    /// Clearing all data forgets which workouts the watch said it would save.
    func forgetWatchClaims() {
        watchClaims = []
        Storage.defaults.removeObject(forKey: watchClaimsKey)
    }

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

    private static let readinessAccessKey = "rauta-health-readiness-requested"

    var readinessAccessRequested: Bool {
        Storage.defaults.bool(forKey: Self.readinessAccessKey)
    }

    private var readinessReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!]
        for identifier: HKQuantityTypeIdentifier in [
            .restingHeartRate, .heartRateVariabilitySDNN,
            .appleExerciseTime, .activeEnergyBurned,
        ] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) { types.insert(type) }
        }
        return types
    }

    func requestReadinessAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readinessReadTypes)
            Storage.defaults.set(true, forKey: Self.readinessAccessKey)
            return true
        } catch { return false }
    }

    private struct ReadinessMeasurement: Sendable {
        var value: Double
        var at: Date
    }

    private struct SleepInterval: Sendable {
        var start: Date
        var end: Date
    }

    private func quantityMeasurements(
        _ identifier: HKQuantityTypeIdentifier, unit: HKUnit, since: Date
    ) async -> [ReadinessMeasurement] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: [])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 500,
                                      sortDescriptors: nil) { _, samples, _ in
                let values = (samples ?? []).compactMap { sample -> ReadinessMeasurement? in
                    guard let sample = sample as? HKQuantitySample else { return nil }
                    let value = sample.quantity.doubleValue(for: unit)
                    return value.isFinite && value >= 0
                        ? ReadinessMeasurement(value: value, at: sample.endDate) : nil
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    private func sleepIntervals(since: Date) async -> [SleepInterval] {
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: [])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 500,
                                      sortDescriptors: nil) { _, samples, _ in
                let sleeping = (samples ?? []).compactMap { sample -> SleepInterval? in
                    guard let sample = sample as? HKCategorySample else { return nil }
                    let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    guard value == .asleepUnspecified || value == .asleepCore
                            || value == .asleepDeep || value == .asleepREM else { return nil }
                    return SleepInterval(start: sample.startDate, end: sample.endDate)
                }
                continuation.resume(returning: sleeping)
            }
            store.execute(query)
        }
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func mergedHours(_ intervals: [SleepInterval], since: Date) -> Double? {
        let ranges = intervals.map { (max($0.start, since), $0.end) }
            .filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        guard var first = ranges.first else { return nil }
        var seconds = 0.0
        for range in ranges.dropFirst() {
            if range.0 <= first.1 { first.1 = max(first.1, range.1) }
            else { seconds += first.1.timeIntervalSince(first.0); first = range }
        }
        seconds += first.1.timeIntervalSince(first.0)
        return min(12, seconds / 3600)
    }

    func readinessSnapshot() async -> HealthReadinessSnapshot? {
        guard isAvailable, readinessAccessRequested else { return nil }
        let now = Date()
        let lastDay = now.addingTimeInterval(-24 * 3600)
        let previousDay = now.addingTimeInterval(-48 * 3600)
        let week = now.addingTimeInterval(-8 * 24 * 3600)
        async let sleep = sleepIntervals(since: lastDay)
        async let hrv = quantityMeasurements(.heartRateVariabilitySDNN,
                                              unit: .secondUnit(with: .milli), since: week)
        async let resting = quantityMeasurements(.restingHeartRate,
                                                  unit: .count().unitDivided(by: .minute()), since: week)
        async let exercise = quantityMeasurements(.appleExerciseTime, unit: .minute(), since: previousDay)
        async let energy = quantityMeasurements(.activeEnergyBurned, unit: .kilocalorie(), since: previousDay)
        let hrvValues = await hrv
        let restingValues = await resting
        let exerciseValues = await exercise
        let energyValues = await energy
        return HealthReadinessSnapshot(
            sleepHours: Self.mergedHours(await sleep, since: lastDay),
            hrvTodayMs: Self.mean(hrvValues.filter { $0.at >= lastDay }.map(\.value)),
            hrvBaselineMs: Self.mean(hrvValues.filter { $0.at < lastDay }.map(\.value)),
            restingHeartRateToday: Self.mean(restingValues.filter { $0.at >= lastDay }.map(\.value)),
            restingHeartRateBaseline: Self.mean(restingValues.filter { $0.at < lastDay }.map(\.value)),
            exerciseMinutesYesterday: Self.mean(exerciseValues.filter { $0.at >= previousDay && $0.at < lastDay }.map(\.value)),
            activeEnergyYesterday: Self.mean(energyValues.filter { $0.at >= previousDay && $0.at < lastDay }.map(\.value))
        )
    }

    func requestAccess() async -> AppleHealthConnectionResult {
        guard isAvailable else { return .unavailable }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        } catch {
            return .unavailable
        }
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            return .denied
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

    /// Whether Health already holds the workout saved for `workoutId`, by
    /// either device.
    func hasSavedWorkout(workoutId: String) async -> Bool {
        guard isAvailable else { return false }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [RautaHealthWorkout.externalID(forWorkout: workoutId)]
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [],
            limit: 1
        )
        let results = (try? await descriptor.result(for: store)) ?? []
        return !results.isEmpty
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
                HKMetadataKeyExternalUUID: RautaHealthWorkout.externalID(forWorkout: input.workoutId),
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

        let decision = RautaHealthWorkout.phoneDecision(
            workoutId: session.workoutId,
            watchClaims: Set(watchClaims),
            alreadyInHealth: await hasSavedWorkout(workoutId: session.workoutId)
        )
        guard decision == .save else {
            // The watch saves what it recorded; a workout already in Health
            // needs nothing more. Either way it is in Health, not pending.
            WorkoutsStore.shared.setHealthSyncStatus(session.workoutId, .synced)
            return
        }

        let success = await saveCompletedWorkout(WorkoutExport(
            startDate: Date(epochMillis: session.startedAt),
            endDate: Date(epochMillis: session.startedAt + durationMs),
            activeCalories: settings.syncActiveCalories ? activeCalories : nil,
            workoutId: session.workoutId,
            workoutName: session.workoutName
        ))
        WorkoutsStore.shared.setHealthSyncStatus(session.workoutId, success ? .synced : .failed)
    }
}
