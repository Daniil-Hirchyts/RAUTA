import Foundation
import Testing
@testable import Rauta

/// Cancellation of the expensive work screens start, and the measurements the
/// choice to move it off the main actor rests on.
@Suite("Background work", .serialized)
struct WorkCostTests {
    private var style: ExerciseMediaStyle { ExerciseMediaStyle(tone: .dark, hueShift: 0) }

    @Test func cancelledAnimationDecodeDoesNothing() async throws {
        let id = try #require(ExerciseCatalogue.all.first?.id)
        let task = Task { await ExerciseMedia.loadAnimation(for: id, style: style) }
        task.cancel()
        #expect(await task.value == nil)
    }

    @Test func cancelledPosterDecodeDoesNothing() async throws {
        let id = try #require(ExerciseCatalogue.all.last?.id)
        let task = Task { await ExerciseMedia.loadPoster(for: id, style: style) }
        task.cancel()
        #expect(await task.value == nil)
    }

    @Test func cancelledPlanGenerationProducesNoPlan() async {
        let requests = [PlanGeneration.request(weekStart: nil, offsets: [0, 2, 4], now: ISOTime.now())]
        let task = Task { await PlanGeneration.generate(requests) }
        task.cancel()
        #expect(await task.value == nil)
    }

    @Test func planGenerationRunsOffTheMainThread() async {
        let requests = [PlanGeneration.request(weekStart: nil, offsets: [0, 2, 4], now: ISOTime.now())]
        let clock = ContinuousClock()
        var elapsed = Duration.zero
        let results = await clock.measure { elapsed = $0 } during: { await PlanGeneration.generate(requests) }
        #expect(results?.count == 1)
        print("MEASURE plan generation, one week: \(elapsed)")
    }

    @Test func singleWorkoutProposalCost() async throws {
        let clock = ContinuousClock()
        var elapsed = Duration.zero
        let ids = try await clock.measureThrowing({ elapsed = $0 }) {
            try await EngineWorkout.propose(date: CalendarDate.today, focusMuscles: [.chest])
        }
        #expect(!ids.isEmpty)
        print("MEASURE single-workout proposal: \(elapsed)")
    }

    @Test func planAdjustmentCost() async throws {
        guard let source = TrainingPlan.activeProgramRecord() else { return }
        let clock = ContinuousClock()
        var elapsed = Duration.zero
        _ = try? await clock.measureThrowing({ elapsed = $0 }) {
            try await TrainingWorkflow.planTrainingWeek(source: source)
        }
        print("MEASURE plan adjustment (read only): \(elapsed)")
    }

    @Test func summaryDerivationCost() {
        let clock = ContinuousClock()
        let store = TrainingRecordsStore.shared
        var history = store.trainingHistory()
        // Handing it the workouts skips the kept answer: this is the build itself.
        let derive = clock.measure { history = store.trainingHistory(legacyWorkouts: []) }
        let kept = clock.measure { history = store.trainingHistory() }
        let workouts = WorkoutsStore.shared.workouts
        let snapshot = clock.measure { _ = MonthlySummarySnapshot(workouts: workouts, history: history) }
        print("MEASURE training history derivation: \(derive), kept: \(kept), month snapshot: \(snapshot), sessions \(history.sessions.count)")
    }

    @Test func setLogRecommendationCost() {
        guard let exercise = TrainingRecordsStore.shared.data.activeWorkout?.exercises.first else { return }
        let clock = ContinuousClock()
        _ = TrainingWorkflow.nextPerformance(exercise)
        let elapsed = clock.measure { _ = TrainingWorkflow.nextPerformance(exercise) }
        print("MEASURE set log recommendation: \(elapsed)")
    }

    @Test func historyWriteCost() {
        let state = TrainingRecordsStore.shared.data.jsonTree
        let clock = ContinuousClock()
        var text = ""
        let encode = clock.measure { text = JSONValue.object(["data": state]).canonical }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "rauta-cost-\(UUID().uuidString)", directoryHint: .isDirectory)
        Storage.directoryOverride = directory
        defer {
            Storage.directoryOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let file = clock.measure {
            try? Storage.writeEnvelopeFile("cost", state: .object(["data": state]), version: 1)
        }
        print("MEASURE history: \(text.utf8.count) bytes, encode \(encode), encode+file write \(file)")
    }
}

private extension ContinuousClock {
    func measure<T>(_ report: (Duration) -> Void, during work: () async -> T) async -> T {
        let start = now
        let value = await work()
        report(now - start)
        return value
    }

    func measureThrowing<T>(_ report: (Duration) -> Void, during work: () async throws -> T) async throws -> T {
        let start = now
        defer { report(now - start) }
        return try await work()
    }
}
