import Foundation

/// Reviewed corrections to what an exercise needs and who it suits, layered over
/// the generated catalogue and its curated metadata.
///
/// `exercises.generated.json` and `exercise-metadata.curated.complete.json` are
/// produced by the catalogue tooling in the separate `gym-lib-react` project and
/// are never edited by hand here. A decision below records what a review of the
/// exercise's own instructions found that the curated record gets wrong — a band
/// or bar the instructions require, a variation too advanced to prescribe to a
/// beginner, a movement with no load to progress. Each decision names the source
/// fingerprint it was reviewed against, exactly as the curated reviews do: if the
/// exercise's name or instructions change upstream, the decision no longer
/// applies and the exercise drops out of automatic planning until it is reviewed
/// again. When the catalogue is next regenerated upstream, fold these decisions
/// into `training-catalogue-reviewed-decisions.ts` and delete them here.
///
/// The resistance an exercise is logged in (`ExerciseSummary.equipment`) stays as
/// the catalogue has it; only what must be present to perform it changes.
nonisolated struct ExerciseRequirementDecision: Sendable {
    let exerciseId: String
    /// `CuratedExercises.sourceExerciseFingerprint` of the exercise as reviewed.
    let source: String
    var adds: [String] = []
    var removes: [String] = []
    var skill: Skill?
    /// The least training experience the exercise may be prescribed to
    /// automatically. Nil keeps it open to everyone the skill rule allows.
    var minimumExperience: Experience?
    var automaticProgramming: AutomaticProgramming?
    var movementPatterns: [MovementPattern]?
    var mechanics: Mechanics?
    var setRoles: [(MuscleId, EffectiveSetRole.Role)]?
    var familyId: String?
    let reason: String
}

nonisolated enum ReviewedRequirements {
    /// Bumped whenever a decision is added or changed; carried in every
    /// reviewed record's rule version so a plan says which review it used.
    static let version = "2026-10-10"

    /// Tag on every record a decision changed.
    static let reviewedTag = "requirement_review"
    /// Tag on a record whose decision went stale: the source changed since.
    static let staleTag = "stale_requirement_review"

    static let decisions: [String: ExerciseRequirementDecision] = {
        var table: [String: ExerciseRequirementDecision] = [:]
        for decision in all { table[decision.exerciseId] = decision }
        return table
    }()

    static func decision(_ exerciseId: String) -> ExerciseRequirementDecision? {
        decisions[exerciseId]
    }

    // MARK: Fixtures the instructions require

    private static let fixtures: [ExerciseRequirementDecision] = [
        .init(
            exerciseId: "0628", source: "6a16bd51",
            adds: ["resistance band"],
            movementPatterns: [.hipAbduction], mechanics: .isolation,
            setRoles: [(.gluteal, .direct), (.quadriceps, .incidental)],
            familyId: "hip_abduction",
            reason: "Monster walk: the instructions loop a resistance band around the ankles; "
                + "it is a banded hip-abduction walk, not body-weight locomotion."
        ),
        .init(
            exerciseId: "0466", source: "6681a261",
            adds: ["pull-up bar"], skill: .complex, minimumExperience: .intermediate,
            movementPatterns: [.verticalPull], mechanics: .compound,
            setRoles: [(.upperBack, .direct), (.biceps, .indirect), (.deltoids, .indirect)],
            familyId: "pull_up",
            reason: "Gironda sternum chin: hangs from a high bar and pulls the sternum to it with "
                + "a lean-back — an advanced chin-up, not a beginner movement."
        ),
        .init(
            exerciseId: "0139", source: "5770f92e",
            adds: ["pull-up bar"], minimumExperience: .intermediate,
            reason: "Hangs from a pull-up bar; a full body-weight pull-up is beyond most beginners."
        ),
        .init(
            exerciseId: "0253", source: "03329f40",
            adds: ["pull-up bar"], minimumExperience: .intermediate,
            reason: "Hangs from a pull-up bar; a full body-weight chin-up is beyond most beginners."
        ),
        .init(
            exerciseId: "0467", source: "2df89a52",
            adds: ["pull-up bar"], skill: .complex, minimumExperience: .intermediate,
            reason: "Gorilla chin: a chin-up with a knee raise from a pull-up bar."
        ),
        .init(
            exerciseId: "0720", source: "8dbe7bdd",
            adds: ["pull-up bar"], skill: .complex, minimumExperience: .intermediate,
            movementPatterns: [.verticalPull], mechanics: .compound, familyId: "pull_up",
            reason: "Side-to-side chin: an uneven chin-up variation from a pull-up bar."
        ),
        .init(
            exerciseId: "0807", source: "4dbeabd0",
            adds: ["pull-up bar"], minimumExperience: .intermediate,
            reason: "Hangs from a pull-up bar; hanging core work needs grip and shoulder strength first."
        ),
        .init(
            exerciseId: "0805", source: "bc3c7929", adds: ["suspension trainer"],
            reason: "Uses a suspension trainer anchored overhead."
        ),
        .init(
            exerciseId: "0806", source: "238f90cf", adds: ["suspension trainer"],
            reason: "Uses a suspension trainer anchored overhead."
        ),
        .init(
            exerciseId: "0808", source: "528c0f4c", adds: ["suspension trainer"],
            reason: "Uses a suspension trainer anchored overhead."
        ),
        .init(
            exerciseId: "0809", source: "a24f33c2", adds: ["suspension trainer"],
            reason: "The rear foot rests in a suspension trainer's foot cradle."
        ),
        .init(
            exerciseId: "3289", source: "b2fd922a",
            adds: ["dip station"], skill: .complex, minimumExperience: .advanced,
            reason: "Impossible dips: performed between parallel bars; an advanced dip variation."
        ),
        .init(
            exerciseId: "2963", source: "bc0abece",
            adds: ["dip station"], removes: ["chair"],
            reason: "A captain's chair is a knee-raise station with arm pads, not a household chair."
        ),
        .init(
            exerciseId: "3193", source: "26f6c16e",
            adds: ["glute-ham bench"], minimumExperience: .intermediate,
            reason: "Needs a glute-ham raise machine, and the raise is demanding on the hamstrings."
        ),
        .init(
            exerciseId: "0730", source: "4434beb0", adds: ["slide board"],
            reason: "Needs a slide board or platform the foot can glide on."
        ),
        .init(
            exerciseId: "0020", source: "80e4e6a6",
            adds: ["balance board"], automaticProgramming: .manualOnly,
            reason: "A balance hold on a balance board: no load or repetitions to progress."
        ),
    ]

    // MARK: Nothing to progress

    /// Movements whose instructions describe no load path, a hold, or a drill:
    /// they stay in the library, but a plan cannot prescribe sets of them.
    private static let unloaded: [ExerciseRequirementDecision] = [
        .init(exerciseId: "1773", source: "98a19a05", automaticProgramming: .manualOnly,
              reason: "Pulling a hanging towel with no anchor gives no resistance to progress."),
        .init(exerciseId: "1355", source: "94111537", automaticProgramming: .manualOnly,
              reason: "A static press against a wall: a hold, not repetitions with a load."),
        .init(exerciseId: "3669", source: "b36a8655", automaticProgramming: .manualOnly,
              reason: "An unloaded rotation drill."),
        .init(exerciseId: "0816", source: "d91a32f6", automaticProgramming: .manualOnly,
              reason: "The standing instructions describe no load on the triceps."),
        .init(exerciseId: "3012", source: "0ac82cca", automaticProgramming: .manualOnly,
              reason: "The instructions describe a standing drill, not a loaded dip."),
        .init(exerciseId: "1769", source: "3c7dc548", automaticProgramming: .manualOnly,
              reason: "An unloaded curl: the forearm's own weight is no resistance."),
        .init(exerciseId: "0858", source: "3131388c", automaticProgramming: .manualOnly,
              reason: "Sprinting is conditioning, not sets of a resistance exercise."),
        .init(exerciseId: "1418", source: "50c0228b", automaticProgramming: .manualOnly,
              reason: "A mobility hold rather than a resistance exercise."),
    ]

    // MARK: Too advanced to prescribe automatically

    private static func pullUp(_ id: String, _ source: String) -> ExerciseRequirementDecision {
        .init(exerciseId: id, source: source, minimumExperience: .intermediate,
              reason: "A full body-weight pull-up or chin-up is beyond most beginners; "
                + "rows and assisted variations come first.")
    }

    private static func hanging(_ id: String, _ source: String) -> ExerciseRequirementDecision {
        .init(exerciseId: id, source: source, minimumExperience: .intermediate,
              reason: "Hanging leg raises need grip and shoulder strength before they train the abs.")
    }

    private static let advanced: [ExerciseRequirementDecision] = [
        pullUp("0140", "b59e2111"), pullUp("1326", "1cd17dff"), pullUp("1327", "710b4808"),
        pullUp("0627", "aa811abe"), pullUp("0651", "4273c5d4"), pullUp("0652", "7f089561"),
        pullUp("0670", "bd907707"), pullUp("0674", "f8c2d049"), pullUp("0678", "e491761c"),
        pullUp("1763", "dd4a5deb"), pullUp("1429", "9ee1e756"), pullUp("1367", "f286b331"),
        .init(exerciseId: "3293", source: "179ce056", skill: .complex, minimumExperience: .advanced,
              reason: "Archer pull-up: most of the body weight on one arm."),
        .init(exerciseId: "3418", source: "61c1f517", skill: .complex, minimumExperience: .advanced,
              reason: "L-sit pull-up: a pull-up holding the legs at hip height."),
        .init(exerciseId: "0638", source: "8a8f0115", skill: .complex, minimumExperience: .advanced,
              reason: "One-arm chin-up: an elite strength skill."),
        .init(exerciseId: "0251", source: "8f0ff8cf", minimumExperience: .intermediate,
              reason: "Full body-weight dips load the shoulders heavily; build pressing strength first."),
        .init(exerciseId: "1430", source: "cd9d818a", minimumExperience: .intermediate,
              reason: "Full body-weight dips load the shoulders heavily; build pressing strength first."),
        .init(exerciseId: "2363", source: "df7b5f46", minimumExperience: .intermediate,
              reason: "Full body-weight dips load the shoulders heavily; build pressing strength first."),
        .init(exerciseId: "2462", source: "5a057fc7", skill: .complex, minimumExperience: .intermediate,
              reason: "Dips on a single straight bar need balance as well as pressing strength."),
        .init(exerciseId: "3288", source: "20ce2a8d", skill: .complex, minimumExperience: .advanced,
              reason: "Korean dips: a behind-the-body dip that stresses the shoulders."),
        .init(exerciseId: "0639", source: "09d9e9fb", skill: .complex, minimumExperience: .advanced,
              reason: "One-arm dip: an advanced unilateral press."),
        hanging("0472", "428835cb"), hanging("0475", "18cf22b0"), hanging("0474", "4c5266dd"),
        hanging("0473", "0af7d813"), hanging("1764", "3a8e84d3"), hanging("1761", "b8d5cdf5"),
        hanging("0476", "a16455b2"),
        .init(exerciseId: "1273", source: "abc37ba3", skill: .complex, minimumExperience: .intermediate,
              reason: "Clap push-up: plyometric; land-and-catch needs solid push-ups first."),
        .init(exerciseId: "0725", source: "5f35068f", skill: .complex, minimumExperience: .advanced,
              reason: "Single-arm push-up: most of the body weight on one arm."),
        .init(exerciseId: "3294", source: "7f012201", minimumExperience: .intermediate,
              reason: "Archer push-up: shifts most of the body weight onto one arm."),
        .init(exerciseId: "0666", source: "850d515a", minimumExperience: .intermediate,
              reason: "A push-up with one arm extended: most of the load on the other arm."),
        .init(exerciseId: "0803", source: "5a8d3fad", minimumExperience: .intermediate,
              reason: "A push-up while lifting an arm and the opposite leg."),
        .init(exerciseId: "1476", source: "aa93fa97", skill: .complex, minimumExperience: .advanced,
              reason: "One-leg squat: a pistol-style squat on a single leg."),
        .init(exerciseId: "1489", source: "3bdb0c5a", minimumExperience: .intermediate,
              reason: "Sissy squats load the knees at long lengths; build squat strength first."),
        .init(exerciseId: "0851", source: "6c3875a5", minimumExperience: .intermediate,
              reason: "Sissy squats load the knees at long lengths; build squat strength first."),
        .init(exerciseId: "0841", source: "76012c79", minimumExperience: .intermediate,
              reason: "A weighted pull-up assumes body-weight pull-ups are already easy."),
        .init(exerciseId: "2987", source: "a92fea32", minimumExperience: .intermediate,
              reason: "A weighted chin-up assumes body-weight chin-ups are already easy."),
        .init(exerciseId: "3313", source: "ebbcf307", minimumExperience: .intermediate,
              reason: "A weighted dip assumes body-weight dips are already easy."),
        .init(exerciseId: "1767", source: "9b2f4c98", minimumExperience: .intermediate,
              reason: "A weighted dip assumes body-weight dips are already easy."),
        .init(exerciseId: "0866", source: "b66b4311", minimumExperience: .intermediate,
              reason: "A weighted hanging raise assumes the unweighted one is already easy."),
    ]

    static let all: [ExerciseRequirementDecision] = fixtures + unloaded + advanced

    // MARK: Applying

    /// Applies the exercise's decision, if it has one, to the merged metadata
    /// object `CuratedExercises.resolveMetadata` is about to decode.
    static func apply(_ exercise: ExerciseSummary, to merged: inout [String: JSONValue]) {
        guard let decision = decision(exercise.id) else { return }
        var tags = Set((merged["tags"]?.arrayValue ?? []).compactMap(\.stringValue))

        guard decision.source == CuratedExercises.sourceExerciseFingerprint(exercise) else {
            // Reviewed against different text: what was found may no longer be
            // true, and what it fixed may be wrong again. Out of automatic
            // planning until someone looks.
            tags.insert(staleTag)
            merged["tags"] = .array(tags.sorted().map(JSONValue.string))
            merged["automaticProgramming"] = .string(AutomaticProgramming.manualOnly.rawValue)
            return
        }

        var equipment = (merged["requiredEquipment"]?.arrayValue ?? []).compactMap(\.stringValue)
        equipment.removeAll { decision.removes.contains($0) }
        for item in decision.adds where !equipment.contains(item) { equipment.append(item) }
        merged["requiredEquipment"] = .array(equipment.sorted().map(JSONValue.string))

        if let skill = decision.skill { merged["skill"] = .string(skill.rawValue) }
        if let minimum = decision.minimumExperience {
            merged["minimumExperience"] = .string(minimum.rawValue)
        }
        if let programming = decision.automaticProgramming {
            merged["automaticProgramming"] = .string(programming.rawValue)
        }
        if let patterns = decision.movementPatterns {
            merged["movementPatterns"] = .array(patterns.map { .string($0.rawValue) })
        }
        if let mechanics = decision.mechanics { merged["mechanics"] = .string(mechanics.rawValue) }
        if let roles = decision.setRoles {
            merged["setRoles"] = .array(roles.map { muscle, role in
                .object([
                    "muscleId": .string(muscle.rawValue),
                    "role": .string(role.rawValue),
                    "provenance": .string(EffectiveSetRole.Provenance.curated.rawValue),
                ])
            })
        }
        if let familyId = decision.familyId { merged["familyId"] = .string(familyId) }

        tags.insert(reviewedTag)
        merged["tags"] = .array(tags.sorted().map(JSONValue.string))
    }
}

nonisolated extension Experience {
    var rank: Int {
        switch self {
        case .beginner: return 0
        case .intermediate: return 1
        case .advanced: return 2
        }
    }
}
