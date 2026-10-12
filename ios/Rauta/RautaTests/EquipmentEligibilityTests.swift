import Foundation
import Testing
@testable import Rauta

/// What a plan may prescribe, for the kits and people RAUTA is for. Every plan
/// here goes through the same adapter the app uses, so what the profile says
/// someone has is what the engine is told.
@Suite("Equipment and experience eligibility")
@MainActor
struct EquipmentEligibilityTests {
    static let now = "2026-10-06T09:00:00.000Z"
    static let weekStart = "2026-10-12T00:00:00.000Z"

    static let homeKit = ["band", "resistance band", "dumbbell", "kettlebell"]
    static var fullGym: [String] { ExerciseCatalogue.equipmentOptions }

    static func profile(
        _ experience: Experience,
        goal: TrainingGoal = .generalFitness,
        minutes: Double = 60
    ) -> TrainingProfile {
        var profile = TrainingProfile.createDefault()
        profile.trainingExperience = experience
        profile.goal = goal
        profile.preferredSessionDurationMinutes = minutes
        return profile
    }

    static func request(
        _ profile: TrainingProfile,
        equipment: [String],
        fixtures: [String],
        days: [Int] = [0, 2, 4]
    ) -> ProgramGenerationRequest {
        ProgramGenerationRequest(
            profile: TrainingEngineAdapter.buildEngineProfile(profile),
            preferences: TrainingEngineAdapter.buildPlanningPreferences(
                profile, equipment: equipment, fixtures: fixtures
            ),
            schedule: TrainingSchedule(weekStart: weekStart, days: days, sessionDays: nil, durationWeeks: 1),
            history: .empty,
            exercises: ExerciseCatalogue.all,
            now: now,
            readiness: nil,
            metadata: nil,
            policy: nil
        )
    }

    static func plannedIds(_ program: TrainingProgram) -> [String] {
        program.weeks.flatMap(\.sessions).flatMap { $0.exercises.map(\.exerciseId) }
    }

    /// Every exercise in the plan can be performed with what was offered and
    /// suits the person's experience.
    static func expectEligible(
        _ program: TrainingProgram,
        _ request: ProgramGenerationRequest,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let index = TrainingWorkflow.trainingIndex()
        let available = Set(request.preferences.availableEquipment)
        for id in plannedIds(program) {
            guard let item = index.byId[id] else {
                Issue.record("Unknown exercise \(id)", sourceLocation: sourceLocation); continue
            }
            let missing = item.metadata.requiredEquipment.filter { $0 != "body weight" && !available.contains($0) }
            #expect(missing.isEmpty, "\(id) \(item.exercise.name) needs \(missing)", sourceLocation: sourceLocation)
            #expect(
                ExerciseData.suits(item.metadata, request.profile.trainingExperience),
                "\(id) \(item.exercise.name) does not suit a \(request.profile.trainingExperience)",
                sourceLocation: sourceLocation
            )
            #expect(item.metadata.automaticProgramming == .allowed, "\(id)", sourceLocation: sourceLocation)
        }
    }

    // MARK: The reviewed catalogue

    @Test func everyReviewedDecisionMatchesTheExerciseItWasReviewedAgainst() throws {
        for decision in ReviewedRequirements.all {
            let exercise = try #require(ExerciseCatalogue.byId[decision.exerciseId], "\(decision.exerciseId)")
            #expect(
                decision.source == CuratedExercises.sourceExerciseFingerprint(exercise),
                "\(decision.exerciseId) \(exercise.name) changed since it was reviewed"
            )
            let metadata = try #require(TrainingWorkflow.trainingIndex().byId[decision.exerciseId]?.metadata)
            #expect(metadata.tags.contains(ReviewedRequirements.reviewedTag), "\(decision.exerciseId)")
            for item in decision.adds {
                #expect(metadata.requiredEquipment.contains(item), "\(decision.exerciseId) should need \(item)")
            }
        }
        #expect(Set(ReviewedRequirements.all.map(\.exerciseId)).count == ReviewedRequirements.all.count)
    }

    @Test func monsterWalkNeedsTheBandItsInstructionsLoopAroundTheAnkles() throws {
        let walk = try #require(TrainingWorkflow.trainingIndex().byId["0628"])
        #expect(walk.exercise.instructions.first?.localizedCaseInsensitiveContains("resistance band") == true)
        #expect(walk.metadata.requiredEquipment.contains("resistance band"))
        #expect(walk.metadata.movementPatterns == [.hipAbduction])
        #expect(walk.exercise.equipment == "body weight", "The resistance it is logged in is unchanged")

        let missing = TrainingEngineAdapter.missingRequirements("0628", equipment: [], fixtures: [])
        #expect(missing == ["resistance band"])
        #expect(TrainingEngineAdapter.missingRequirements("0628", equipment: ["resistance band"], fixtures: []).isEmpty)
    }

    @Test func girondaSternumChinNeedsAHighBarAndIsNotForBeginners() throws {
        let chin = try #require(TrainingWorkflow.trainingIndex().byId["0466"])
        #expect(chin.exercise.instructions.joined().localizedCaseInsensitiveContains("high bar"))
        #expect(chin.metadata.requiredEquipment.contains("pull-up bar"))
        #expect(chin.metadata.skill == .complex)
        #expect(!ExerciseData.suits(chin.metadata, .beginner))
        #expect(ExerciseData.suits(chin.metadata, .intermediate))
    }

    @Test func aDecisionReviewedAgainstOtherTextTakesTheExerciseOutOfAutomaticPlans() throws {
        var exercise = try #require(ExerciseCatalogue.byId["0628"])
        exercise.instructions = ["Walk sideways."]
        var merged = try #require(TrainingWorkflow.trainingIndex().byId["0628"]?.metadata.jsonTree.objectValue)
        merged["automaticProgramming"] = .string("allowed")
        ReviewedRequirements.apply(exercise, to: &merged)
        #expect(merged["automaticProgramming"]?.stringValue == "manual_only")
        #expect(merged["tags"]?.arrayValue?.contains(.string(ReviewedRequirements.staleTag)) == true)
    }

    // MARK: Fixtures

    @Test func homeEquipmentNoLongerImpliesABench() {
        let available = TrainingEngineAdapter.toEngineEquipment(Self.homeKit)
        #expect(!available.contains("bench"))
        #expect(!available.contains("pull-up bar"))
        #expect(available.contains("chair"), "Household fixtures come with body weight")
        let withBench = TrainingEngineAdapter.toEngineEquipment(Self.homeKit, fixtures: ["bench", "dip station"])
        #expect(withBench.contains("bench"))
        #expect(withBench.contains("dip bars"), "A fixture brings its other catalogue names")
    }

    @Test func aProfileSavedBeforeFixturesKeepsPlanningAsItDid() {
        #expect(TrainingEngineAdapter.legacyFixtures(for: ["dumbbell"]) == ["bench"])
        #expect(TrainingEngineAdapter.legacyFixtures(for: ["stability ball"]) == ["dip station", "bench"])
        #expect(TrainingEngineAdapter.legacyFixtures(for: ["body weight"]).isEmpty)

        let legacy = FiltersStore.sanitize(.object(["gymEquipment": .array([.string("dumbbell")])]))
        #expect(legacy.gymFixtures == nil, "Never chosen is not the same as none")
        let chosen = FiltersStore.sanitize(.object([
            "gymEquipment": .array([.string("dumbbell")]),
            "gymFixtures": .array([.string("pull-up bar"), .string("not a fixture")]),
        ]))
        #expect(chosen.gymFixtures == ["pull-up bar"])
    }

    // MARK: Representative plans

    @Test func aBeginnerWithNoEquipmentGetsOnlyWhatTheyCanDo() throws {
        let profile = Self.profile(.beginner)
        let request = Self.request(profile, equipment: [], fixtures: [])
        let result = Generate.generateTrainingProgram(request)
        let program = try #require(result.program, "\(result.statusName) \(result.issues)")
        Self.expectEligible(program, request)
        let ids = Set(Self.plannedIds(program))
        #expect(!ids.contains("0628"), "Monster walk needs a band")
        #expect(!ids.contains("0466"), "Gironda sternum chin needs a bar and experience")

        // Nothing without equipment trains the upper back directly: the plan
        // says so and names what would change that.
        let gaps = Coverage.gaps(
            week: try #require(program.weeks.first),
            request: request,
            index: TrainingWorkflow.trainingIndex(),
            policy: program.policy
        )
        let back = try #require(gaps.first { $0.muscleId == .upperBack })
        #expect(!back.hasEligibleExercise)
        #expect(!back.unlockedBy.isEmpty)
    }

    @Test func aHomeKitPlanNeverAssumesABenchOrBar() throws {
        let request = Self.request(Self.profile(.beginner), equipment: Self.homeKit, fixtures: [])
        let program = try #require(Generate.generateTrainingProgram(request).program)
        Self.expectEligible(program, request)
        let index = TrainingWorkflow.trainingIndex()
        for id in Self.plannedIds(program) {
            let needs = index.byId[id]?.metadata.requiredEquipment ?? []
            #expect(!needs.contains("bench") && !needs.contains("pull-up bar"), "\(id) needs \(needs)")
        }
    }

    @Test func aFullGymPlanForAnIntermediateIsValidAndEligible() throws {
        let request = Self.request(
            Self.profile(.intermediate, goal: .hypertrophy),
            equipment: Self.fullGym,
            fixtures: TrainingEngineAdapter.selectableFixtures
        )
        let result = Generate.generateTrainingProgram(request)
        let program = try #require(result.program, "\(result.issues)")
        Self.expectEligible(program, request)
        #expect(ProgramValidation.validate(program, request).valid)
    }

    @Test(arguments: [20.0, 30.0, 45.0])
    func shortSessionsStayInsideTheirLimit(_ minutes: Double) throws {
        let profile = Self.profile(.beginner, minutes: minutes)
        let request = Self.request(profile, equipment: Self.homeKit, fixtures: ["bench"])
        let program = try #require(Generate.generateTrainingProgram(request).program, "\(minutes) min")
        Self.expectEligible(program, request)
        let ceiling = (minutes + TrainingEngineAdapter.sessionDurationHeadroomMinutes) * 60
        for session in program.weeks.flatMap(\.sessions) {
            #expect(session.duration.totalSeconds <= ceiling, "\(session.duration.totalSeconds)s > \(ceiling)s")
            #expect(!session.exercises.isEmpty)
        }
    }

    @Test func aBandAndAPullUpBarAreEnoughForABeginnersBackWithoutFullPullUps() throws {
        let request = Self.request(Self.profile(.beginner), equipment: ["band"], fixtures: ["pull-up bar"])
        let program = try #require(Generate.generateTrainingProgram(request).program)
        Self.expectEligible(program, request)
        let index = TrainingWorkflow.trainingIndex()
        let pullUps = Self.plannedIds(program).filter {
            index.byId[$0]?.metadata.minimumExperience == .intermediate
        }
        #expect(pullUps.isEmpty)
    }

    @Test func substitutionsRespectEquipmentAndExperience() throws {
        let request = Self.request(Self.profile(.beginner), equipment: [], fixtures: [])
        let index = TrainingWorkflow.trainingIndex()
        let candidates = Substitutions.findExerciseSubstitutions("0662", request, limit: 40, index: index)
        #expect(!candidates.isEmpty, "Push-ups have body-weight alternatives")
        let available = Set(request.preferences.availableEquipment)
        for candidate in candidates {
            let item = try #require(index.byId[candidate.exerciseId])
            #expect(item.metadata.requiredEquipment.allSatisfy { $0 == "body weight" || available.contains($0) },
                    "\(candidate.exerciseId) \(item.exercise.name)")
            #expect(ExerciseData.suits(item.metadata, .beginner), "\(candidate.exerciseId) \(item.exercise.name)")
        }
    }

    @Test func askingForAnExerciseByNameIsTheirChoice() throws {
        var request = Self.request(Self.profile(.beginner), equipment: [], fixtures: ["pull-up bar"])
        let item = try #require(TrainingWorkflow.trainingIndex().byId["0652"])
        #expect(!ExerciseData.exclusionReasons(item, request.preferences, DEFAULT_POLICY, experience: .beginner).isEmpty)
        request.preferences.preferredExerciseIds = ["0652"]
        #expect(ExerciseData.exclusionReasons(item, request.preferences, DEFAULT_POLICY, experience: .beginner).isEmpty)
    }
}
