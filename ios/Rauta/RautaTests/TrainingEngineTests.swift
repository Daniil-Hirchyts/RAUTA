import Foundation
import Testing
@testable import Rauta

/// Pins what the planning engine produces today for fixed inputs, so moving
/// or deduplicating code around it cannot change a plan unnoticed. The
/// expected values were recorded from the engine as it stood; when a change
/// to the engine is intended, re-record them deliberately.
@Suite("Training engine")
struct TrainingEngineTests {
    // MARK: Fixtures

    static let now = "2026-09-23T09:00:00.000Z"
    static let weekStart = "2026-09-28T00:00:00.000Z"

    static let profile = UserTrainingProfile(
        age: 30,
        bodyWeightKg: 80,
        heightCm: 180,
        trainingAgeMonths: 12,
        trainingExperience: .intermediate,
        health: .healthy
    )

    static var allEquipment: [String] {
        Array(Set(ExerciseCatalogue.all.map(\.equipment))).sorted()
    }

    static func request(
        goal: TrainingGoal = .hypertrophy,
        equipment: [String]? = nil,
        days: [Int] = [0, 2, 4],
        minutes: Double = 60,
        history: TrainingHistory = .empty
    ) -> ProgramGenerationRequest {
        ProgramGenerationRequest(
            profile: profile,
            preferences: PlanningPreferences(
                goal: goal,
                availableEquipment: equipment ?? allEquipment,
                maxSessionDurationMinutes: minutes
            ),
            schedule: TrainingSchedule(weekStart: weekStart, days: days, sessionDays: nil, durationWeeks: 1),
            history: history,
            exercises: ExerciseCatalogue.all,
            now: now,
            readiness: nil,
            metadata: nil,
            policy: nil
        )
    }

    /// One line per session: its day offset, then its exercises with set
    /// counts and rep ranges, e.g. `0: a×3(8-12) b×2(10-15)`.
    static func fingerprint(_ program: TrainingProgram) -> [String] {
        let start = ISOTime.parse(weekStart) ?? 0
        return program.weeks.flatMap(\.sessions).map { session in
            let day = Int((((ISOTime.parse(session.scheduledAt) ?? 0) - start) / DAY_MS).rounded(.down))
            let exercises = session.exercises.map { planned in
                let reps = planned.workingSets.first.map { "\(Int($0.targetReps.min))-\(Int($0.targetReps.max))" } ?? "-"
                return "\(planned.exerciseId)×\(planned.workingSets.count)(\(reps))"
            }
            return "\(day): " + exercises.joined(separator: " ")
        }
    }

    // MARK: Generation

    static let hypertrophyWeek = [
        "0: 1651×3(6-12) 0660×1(6-12) 0244×4(6-12) 1000×4(10-20) 0586×3(10-20)",
        "2: 0536×4(6-12) 0300×1(6-12) 0663×4(6-12) 0071×4(6-12) 0232×2(6-12) 1397×2(10-20)",
        "4: 0244×4(6-12) 1749×1(6-12) 1000×4(10-20) 0157×2(6-12) 0071×2(6-12)",
    ]

    @Test func generatesAValidDeterministicWeek() throws {
        let request = Self.request()
        let first = Generate.generateTrainingProgram(request)
        let second = Generate.generateTrainingProgram(request)
        // Partial, not success: with no history the engine flags that loads
        // still need calibrating.
        #expect(first.statusName == "partial")
        let program = try #require(first.program)
        let again = try #require(second.program)
        #expect(Self.fingerprint(program) == Self.fingerprint(again))
        #expect(Self.fingerprint(program) == Self.hypertrophyWeek)
        #expect(program.diagnostics.selectedSplit == "full_body")

        let validation = ProgramValidation.validate(program, request)
        #expect(validation.valid, "\(validation.issues)")
    }

    @Test func refusesAnEmptySchedule() {
        let result = Generate.generateTrainingProgram(Self.request(days: []))
        #expect(result.program == nil)
        #expect(result.statusName == "invalid")
        #expect(result.issues.map(\.code) == [.invalidInput])
    }

    @Test func withoutEquipmentPlansWhatItCanAndSaysSo() {
        let result = Generate.generateTrainingProgram(Self.request(equipment: []))
        #expect(result.statusName == "partial")
        #expect(result.issues.map(\.code.rawValue) == [
            "INCOMPLETE_HISTORY", "VOLUME_BELOW_TARGET", "VOLUME_BELOW_TARGET",
            "VOLUME_BELOW_TARGET", "VOLUME_BELOW_TARGET", "INSUFFICIENT_HISTORY_FOR_LOAD",
        ])
    }

    @Test func goalsShapeTheWeek() throws {
        let expected: [TrainingGoal: [String]] = [
            .strength: [
                "0: 0663×2(3-6) 1655×2(3-6) 0536×1(3-6) 0244×3(3-6) 1000×4(8-12)",
                "3: 0663×3(3-6) 1732×1(3-6) 0244×3(3-6) 0071×3(3-6) 0752×3(3-6) 2133×1(3-6)",
            ],
            .generalFitness: [
                "0: 0536×4(8-12) 0300×2(8-12) 0244×2(8-12) 0071×3(8-12) 1000×2(10-15) 0446×3(10-15)",
                "3: 0244×4(8-12) 1000×4(10-15) 0660×2(8-12) 0157×2(8-12) 0586×2(10-15)",
            ],
        ]
        for (goal, week) in expected {
            let result = Generate.generateTrainingProgram(Self.request(goal: goal, days: [0, 3]))
            let program = try #require(result.program)
            #expect(Self.fingerprint(program) == week, "\(goal)")
        }
    }

    // MARK: Adaptation

    @Test func adaptsTheNextWeekFromTheFirst() throws {
        let request = Self.request()
        let program = try #require(Generate.generateTrainingProgram(request).program)
        var next = request
        next.schedule.weekStart = ISOTime.addDays(Self.weekStart, 7)
        next.now = ISOTime.addDays(Self.now, 7)
        let result = Adapt.adaptTrainingProgram(
            AdaptationRequest(previousProgram: program, request: next, mode: .nextWeek)
        )
        #expect(result.statusName == "partial")
        let adapted = try #require(result.program)
        // Nothing was logged, so the next week repeats the first a week later.
        #expect(Self.fingerprint(adapted) == Self.hypertrophyWeek.map { line in
            let day = Int(line.prefix { $0 != ":" })! + 7
            return "\(day)" + line.drop { $0 != ":" }
        })
    }

    // MARK: Substitutions

    @Test func substitutionsForAPlannedExercise() throws {
        let request = Self.request()
        let program = try #require(Generate.generateTrainingProgram(request).program)
        let first = try #require(program.weeks.first?.sessions.first?.exercises.first)
        let candidates = Substitutions.findExerciseSubstitutions(first.exerciseId, request, limit: 5)
        #expect(!candidates.contains { $0.exerciseId == first.exerciseId })
        #expect(first.exerciseId == "1651")
        #expect(candidates.map(\.exerciseId) == ["1658", "1655", "0336", "0298", "0312"])
    }

    // MARK: Progression

    static let index = ExerciseData.createIndex(ExerciseCatalogue.all, overrides: [])

    /// The first loadable, bilateral exercise the engine may program on its own.
    static var loadedExercise: IndexedExercise {
        index.byId.values
            .filter {
                $0.metadata.tracking == .externalLoad
                    && $0.metadata.automaticProgramming == .allowed
                    && $0.metadata.laterality == .bilateral
            }
            .min { $0.id < $1.id }!
    }

    static func loggedSession(_ id: String, day: Int, exerciseId: String, reps: Double, kg: Double, rir: Double) -> CompletedSession {
        let at = ISOTime.addDays(now, Double(day))
        return CompletedSession(
            id: id,
            plannedSessionId: nil,
            startedAt: at,
            completedAt: at,
            durationSeconds: 3_600,
            status: .completed,
            exercises: [CompletedExercise(exerciseId: exerciseId, sets: (1...3).map { number in
                CompletedSet(
                    id: "\(id)-\(number)",
                    plannedSetId: nil,
                    reps: reps,
                    resistance: .load(kg, basis: .total, stationId: "rack"),
                    rir: rir,
                    rpe: nil,
                    completed: true,
                    setType: .working,
                    side: .both,
                    timestamp: at
                )
            })]
        )
    }

    static func progression(history: TrainingHistory) -> ProgressionRecommendation {
        Progression.recommend(ProgressionInput(
            exercise: loadedExercise,
            history: history,
            now: now,
            reps: RepRange(min: 8, max: 12),
            rir: 2,
            requiredSets: 3,
            loadGrid: LoadGrid(incrementKg: 2.5),
            loadContext: LoadContext(stationId: "rack", basis: .total),
            policy: DEFAULT_POLICY
        ))
    }

    static func describe(_ recommendation: ProgressionRecommendation) -> String {
        let kg = recommendation.resistance.kg.map { "\($0)" } ?? "-"
        return "\(recommendation.action.rawValue) \(kg)kg "
            + "\(Int(recommendation.targetReps.min))-\(Int(recommendation.targetReps.max)) "
            + recommendation.reasons.map(\.rawValue).joined(separator: ",")
    }

    @Test func progressionWithoutHistoryCalibrates() {
        let recommendation = Self.progression(history: .empty)
        #expect(Self.describe(recommendation) == "calibrate -kg 8-12 no_history")
    }

    @Test func progressionAtTheTopOfTheRangeAddsLoad() {
        let id = Self.loadedExercise.id
        let history = TrainingHistory(
            sessions: [
                Self.loggedSession("a", day: -5, exerciseId: id, reps: 12, kg: 60, rir: 2),
                Self.loggedSession("b", day: -2, exerciseId: id, reps: 12, kg: 60, rir: 2),
            ],
            coverage: .complete,
            coverageStart: ISOTime.addDays(Self.now, -30)
        )
        #expect(Self.describe(Self.progression(history: history)) == "increase_load 62.5kg 8-12 top_of_range")
    }

    @Test func progressionWithinTheRangeHolds() {
        let id = Self.loadedExercise.id
        let history = TrainingHistory(
            sessions: [Self.loggedSession("a", day: -2, exerciseId: id, reps: 9, kg: 60, rir: 2)],
            coverage: .complete,
            coverageStart: ISOTime.addDays(Self.now, -30)
        )
        #expect(Self.describe(Self.progression(history: history)) == "hold 60.0kg 8-12 within_range")
    }

    @Test func loadsRoundToTheGrid() {
        let grid = LoadGrid(incrementKg: 2.5)
        #expect(Progression.roundLoad(61.3, grid) == 62.5)
        #expect(Progression.roundLoad(61.3, grid, .down) == 60)
        #expect(Progression.roundLoad(60.1, grid, .up) == 62.5)
        #expect(Progression.roundLoad(-1, grid) == nil)
        let discrete = LoadGrid(availableLoadsKg: [8, 12, 16, 20])
        #expect(Progression.roundLoad(13, discrete) == 12)
        #expect(Progression.roundLoad(13, discrete, .up) == 16)
    }

    // MARK: Strength and volume

    static func set(reps: Double, kg: Double, rir: Double?, side: SetSide = .both) -> CompletedSet {
        CompletedSet(
            id: "s", plannedSetId: nil, reps: reps,
            resistance: .load(kg, basis: .total, stationId: "rack"),
            rir: rir, rpe: nil, completed: true, setType: .working, side: side, timestamp: nil
        )
    }

    @Test func oneRepMaxEstimates() throws {
        let epley = try #require(Strength.estimate(Self.set(reps: 5, kg: 100, rir: 1), using: .epley))
        #expect(abs(epley.estimated1RMKg - 100 * (1 + 5.0 / 30)) < 1e-9)
        let brzycki = try #require(Strength.estimate(Self.set(reps: 5, kg: 100, rir: 1), using: .brzycki))
        #expect(abs(brzycki.estimated1RMKg - 100 * 36 / 32) < 1e-9)
        let single = try #require(Strength.estimate(Self.set(reps: 1, kg: 140, rir: 0), using: .epley))
        #expect(single.estimated1RMKg == 140)
        #expect(single.confidence == .high)
        // Outside what the estimate trusts: too many reps, too far from failure, one side.
        #expect(Strength.estimate(Self.set(reps: 11, kg: 60, rir: 1), using: .epley) == nil)
        #expect(Strength.estimate(Self.set(reps: 5, kg: 60, rir: 3), using: .epley) == nil)
        #expect(Strength.estimate(Self.set(reps: 5, kg: 60, rir: 1, side: .left), using: .epley) == nil)
    }

    @Test func historyVolumeCreditsWorkingSets() {
        let id = Self.loadedExercise.id
        let history = TrainingHistory(
            sessions: [Self.loggedSession("a", day: -2, exerciseId: id, reps: 10, kg: 60, rir: 2)],
            coverage: .complete,
            coverageStart: nil
        )
        let to = ISOTime.parse(Self.now) ?? 0
        let volume = Volume.historyVolume(history, Self.index, DEFAULT_POLICY, from: to - 7 * DAY_MS, to: to)
        let credited = volume
            .filter { $0.value.effective > 0 }
            .map { "\($0.key.rawValue)=\(($0.value.effective * 100).rounded() / 100)" }
            .sorted()
        #expect(id == "0022")
        #expect(credited == ["upper-back=3.0"])
    }
}
