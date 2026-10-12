import Foundation

/// A muscle the week was meant to train that the plan could not reach.
nonisolated struct CoverageGap: Hashable, Sendable {
    var muscleId: MuscleId
    /// Effective sets the plan gives the muscle this week.
    var plannedSets: Double
    /// The engine's own minimum for the muscle this week.
    var minimumSets: Double
    /// Whether anything the person can do trains it directly. False is the
    /// honest "nothing you have reaches this muscle", rather than a plan that
    /// simply ran out of time.
    var hasEligibleExercise: Bool
    /// Equipment or fixtures that would open up direct work for the muscle,
    /// most useful first: each is the single missing requirement of exercises
    /// that otherwise fit the person.
    var unlockedBy: [String]
}

/// Which target muscles a generated week leaves short, and what would fix it.
///
/// Deterministic and read-only: it asks the same eligibility check the planner
/// used, so its answer cannot disagree with why the plan looks the way it does.
nonisolated enum Coverage {
    /// `candidates` are things the person could add, most practical first,
    /// each with everything it brings with it (a band brings its anchor).
    /// Without them, only exercises missing exactly one thing are counted.
    static func gaps(
        week: TrainingWeek,
        request: ProgramGenerationRequest,
        index: ExerciseIndex,
        policy: TrainingPolicy,
        candidates: [(name: String, provides: Set<String>)] = []
    ) -> [CoverageGap] {
        var planned = Volume.empty()
        for session in week.sessions {
            for exercise in session.exercises {
                guard let item = index.byId[exercise.exerciseId] else { continue }
                Volume.addExerciseVolume(&planned, item, Double(exercise.workingSets.count), policy)
            }
        }

        let experience = request.profile.trainingExperience
        var gaps: [CoverageGap] = []
        for target in week.targets where target.minimum > 0 {
            let sets = planned[target.muscleId]?.effective ?? 0
            guard sets + 1e-6 < target.minimum else { continue }

            let direct = (index.byDirectMuscle[target.muscleId] ?? [])
            let eligible = direct.contains { item in
                ExerciseData.exclusionReasons(
                    item, request.preferences, policy, experience: experience
                ).isEmpty
            }

            // Exercises held back by equipment alone: what is missing for
            // each, so the additions that would make them plannable can be
            // named.
            var missingSets: [Set<String>] = []
            for item in direct {
                let issues = ExerciseData.exclusionReasons(
                    item, request.preferences, policy, experience: experience
                )
                guard issues.count == 1, issues[0].code == .unavailableEquipment,
                      case .strings(let missing)? = issues[0].context?["missing"]
                else { continue }
                missingSets.append(Set(missing))
            }
            let unlockedBy: [String]
            if candidates.isEmpty {
                var counts: [String: Int] = [:]
                for missing in missingSets where missing.count == 1 {
                    counts[missing.first!, default: 0] += 1
                }
                unlockedBy = counts
                    .sorted { left, right in
                        left.value != right.value ? left.value > right.value : left.key < right.key
                    }
                    .prefix(3)
                    .map(\.key)
            } else {
                unlockedBy = candidates
                    .filter { candidate in missingSets.contains { $0.isSubset(of: candidate.provides) } }
                    .prefix(3)
                    .map(\.name)
            }

            gaps.append(CoverageGap(
                muscleId: target.muscleId,
                plannedSets: sets,
                minimumSets: target.minimum,
                hasEligibleExercise: eligible,
                unlockedBy: unlockedBy
            ))
        }
        return gaps.sorted { left, right in
            let a = MAJOR_MUSCLES.firstIndex(of: left.muscleId) ?? Int.max
            let b = MAJOR_MUSCLES.firstIndex(of: right.muscleId) ?? Int.max
            return a != b ? a < b : left.muscleId.rawValue < right.muscleId.rawValue
        }
    }
}
