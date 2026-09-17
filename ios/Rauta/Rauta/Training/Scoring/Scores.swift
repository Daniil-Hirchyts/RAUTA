import Foundation

/// Everything the optimizer scores a candidate week against.
nonisolated struct OptimizationInput: Sendable {
    struct Adaptation: Sendable {
        var baselineCompletedWorkingSets: Double
        var baselineMuscleVolume: [MuscleId: Double]
        var remainingWorkingSetBudget: Double?
        var remainingMuscleVolumeBounds: [MuscleVolumeBound]?
    }

    var request: ProgramGenerationRequest
    var index: ExerciseIndex
    var state: DerivedTrainingState
    var targets: [MuscleTarget]
    var policy: TrainingPolicy
    var continuityIds: [String]?
    var baselineVolume: [MuscleId: Double]?
    var adaptation: Adaptation?
}

nonisolated struct OptimizationResult: Sendable {
    var week: TrainingWeek?
    var split: String
    var candidates: Int
    var iterations: Int
    var splits: [SplitDiagnostic]
}

nonisolated enum Scoring {
    static func skillSuitability(
        _ experience: Experience,
        _ skill: Skill,
        explicitlyPreferred: Bool = false,
        strengthSpecific: Bool = false
    ) -> Double {
        if strengthSpecific { return 1 }
        if explicitlyPreferred { return 0.95 }
        if experience == .advanced { return skill == .unknown ? 0.85 : 1 }
        if experience == .intermediate {
            if skill == .complex { return 0.9 }
            return skill == .unknown ? 0.75 : 1
        }
        if skill == .complex { return 0.25 }
        return skill == .unknown ? 0.6 : 1
    }

    /// Weighted mean over `|weight|`, matching the engine's normalisation so a
    /// negative weight still counts against the denominator.
    static func weightedScore(_ values: [(String, Double)], _ weights: [String: Double]) -> Score {
        let contributions = values.map { factor, value -> ScoreContribution in
            let rawValue = Num.clamp(value)
            let weight = weights[factor] ?? 0
            return ScoreContribution(
                factor: factor,
                rawValue: rawValue,
                weight: weight,
                contribution: rawValue * weight
            )
        }
        let denominator = weights.values.reduce(0.0) { $0 + abs($1) }
        let total = denominator > 0
            ? contributions.reduce(0.0) { $0 + $1.contribution } / denominator
            : 0
        return Score(total: total, contributions: contributions)
    }

    private static func jaccard<T: Hashable>(_ a: [T], _ b: [T]) -> Double {
        let union = Set(a).union(b)
        guard !union.isEmpty else { return 0 }
        let bSet = Set(b)
        let shared = a.filter(bSet.contains).count
        return Double(shared) / Double(union.count)
    }

    static func exerciseSimilarity(
        _ a: IndexedExercise,
        _ b: IndexedExercise,
        _ weights: SimilarityWeights = DEFAULT_POLICY.similarityWeights
    ) -> Double {
        if a.exercise.id == b.exercise.id { return 1 }
        let sameFamily = a.metadata.familyId != nil && a.metadata.familyId == b.metadata.familyId
        let directA = a.metadata.setRoles.filter { $0.role == .direct }.map(\.muscleId)
        let directB = b.metadata.setRoles.filter { $0.role == .direct }.map(\.muscleId)

        var total = weights.family * (sameFamily ? 1 : 0)
        total += weights.patterns * jaccard(a.metadata.movementPatterns, b.metadata.movementPatterns)
        total += weights.directMuscles * jaccard(directA, directB)
        total += weights.mechanics * (a.metadata.mechanics == b.metadata.mechanics ? 1 : 0)
        total += weights.tracking * (a.metadata.tracking == b.metadata.tracking ? 1 : 0)
        total += weights.laterality * (a.metadata.laterality == b.metadata.laterality ? 1 : 0)
        total += weights.equipment * (a.exercise.equipment == b.exercise.equipment ? 1 : 0)
        return total
    }

    static func volumeUtility(_ volume: Double, _ preferred: Double, _ upper: Double) -> Double {
        guard preferred > 0 else { return volume <= upper ? 1 : 0 }
        if volume <= preferred { return Num.clamp(volume / preferred) }
        return Num.clamp(1 - (volume - preferred) / Swift.max(1, upper - preferred))
    }

    // MARK: Exercise scoring

    static func createExerciseScorer(
        _ session: PlannedSession,
        _ week: TrainingWeek,
        _ input: OptimizationInput
    ) -> (IndexedExercise) -> Score {
        let index = input.index
        let policy = input.policy
        let targets = input.targets
        let request = input.request
        let state = input.state

        let sessionVolume = Volume.sessionVolume(session.exercises, index, policy)
        var allocated = Volume.empty()
        for weekSession in week.sessions {
            let volume = Volume.sessionVolume(weekSession.exercises, index, policy)
            for target in targets {
                var entry = allocated[target.muscleId] ?? MuscleVolume(direct: 0, indirect: 0, effective: 0)
                entry.effective += volume[target.muscleId]?.effective ?? 0
                allocated[target.muscleId] = entry
            }
        }

        let relevant = targets.filter { session.focus.contains($0.muscleId) && $0.preferred > 0 }
        let existing = session.exercises.compactMap { index.byId[$0.exerciseId] }
        let usedPatterns = existing.flatMap(\.metadata.movementPatterns)
        let goal = policy.goal(request.preferences.goal.policyKey)

        var exposureSlots: [MuscleId: Double] = [:]
        for target in relevant {
            exposureSlots[target.muscleId] = Double(
                week.sessions.filter { $0.focus.contains(target.muscleId) }.count
            )
        }
        let importanceDenominator = Swift.max(
            1,
            relevant.reduce(0.0) { $0 + $1.importance } / 3
        )

        let weights: [String: Double] = {
            var weights = policy.exerciseWeights
            weights["specificity"] = goal.specificityWeight
            let continuityBoost: Double = (input.continuityIds?.isEmpty == false) ? 2 : 1
            weights["continuity"] = (policy.exerciseWeights["continuity"] ?? 0) * continuityBoost
            return weights
        }()

        return { candidate in
            var coverageSum = 0.0
            for target in relevant {
                let weekly = (allocated[target.muscleId]?.effective ?? 0)
                    + (input.baselineVolume?[target.muscleId] ?? 0)
                let slots = Swift.max(1, exposureSlots[target.muscleId] ?? 0)
                let quota = target.preferred / slots
                let credit = Volume.effectiveSetCredit(candidate, target.muscleId, policy).effective
                let remainingWeek = Num.clamp((target.preferred - weekly) / Swift.max(1, target.preferred))
                let sessionSoFar = sessionVolume[target.muscleId]?.effective ?? 0
                let remainingSession = Num.clamp((quota - sessionSoFar) / Swift.max(1, quota))
                coverageSum += credit * target.importance * Swift.min(remainingWeek, remainingSession)
            }
            let coverage = coverageSum / importanceDenominator

            let isStrengthSpecific = request.preferences.strengthExerciseIds?
                .contains(candidate.exercise.id) == true
            let specificity: Double = {
                if isStrengthSpecific { return 1 }
                let heavyCompound = candidate.metadata.tracking == .externalLoad
                    && candidate.metadata.mechanics == .compound
                return heavyCompound ? 0.5 : 0
            }()

            let hasHistory = (state.exercises[candidate.exercise.id]?.exposureCount ?? 0) > 0
            let continuity: Double = (input.continuityIds?.contains(candidate.exercise.id) == true || hasHistory)
                ? 1 : 0

            let isPreferred = request.preferences.preferredExerciseIds?
                .contains(candidate.exercise.id) == true
            let isDisliked = request.preferences.dislikedExerciseIds?
                .contains(candidate.exercise.id) == true
            let preference: Double = isDisliked ? 0 : (isPreferred ? 1 : 0.5)

            let skillFit = skillSuitability(
                request.profile.trainingExperience,
                candidate.metadata.skill,
                explicitlyPreferred: isPreferred,
                strengthSpecific: isStrengthSpecific
            )

            let directMuscles = candidate.metadata.setRoles
                .filter { $0.role == .direct }
                .map(\.muscleId)
            let workload = Num.mean(directMuscles.map { muscleId -> Double in
                let decayed = state.muscles[muscleId]?.decayedWorkload ?? 0
                let base = Num.clamp(decayed / policy.sessionMuscleGuideline)
                let sore = request.readiness?.soreness?.contains {
                    $0.muscleId == muscleId && $0.level == .high
                } ?? false
                return base + (sore ? 1 : 0)
            })

            let patternNeed: Double = candidate.metadata.movementPatterns
                .contains { !usedPatterns.contains($0) } ? 1 : 0
            let redundancy: Double = existing.isEmpty
                ? 0
                : (existing.map { exerciseSimilarity(candidate, $0, policy.similarityWeights) }.max() ?? 0)
            let maxSessionSeconds = request.preferences.maxSessionDurationMinutes * 60
            let duration = maxSessionSeconds > 0 ? candidate.metadata.setupSeconds / maxSessionSeconds : 0

            return weightedScore(
                [
                    ("coverage", coverage),
                    ("specificity", specificity),
                    ("continuity", continuity),
                    ("preference", preference),
                    ("skillSuitability", skillFit),
                    ("patternNeed", patternNeed),
                    ("quality", candidate.metadata.classificationConfidence),
                    ("redundancy", redundancy),
                    ("workload", workload),
                    ("duration", duration),
                ],
                weights
            )
        }
    }

    static func scoreExercise(
        _ exercise: IndexedExercise,
        _ session: PlannedSession,
        _ week: TrainingWeek,
        _ input: OptimizationInput
    ) -> Score {
        createExerciseScorer(session, week, input)(exercise)
    }

    static func orderExercises(
        _ exercises: [PlannedExercise],
        _ input: OptimizationInput
    ) -> [PlannedExercise] {
        func importance(_ planned: PlannedExercise) -> Double {
            guard let exercise = input.index.byId[planned.exerciseId] else { return 0 }
            let explicit: Double = input.request.preferences.strengthExerciseIds?
                .contains(planned.exerciseId) == true
                ? input.policy.orderingWeights.specific
                : 0
            let directImportances = exercise.metadata.setRoles
                .filter { $0.role == .direct }
                .map { role in
                    input.targets.first { $0.muscleId == role.muscleId }?.importance ?? 1
                }
            let priority = Swift.max(directImportances.max() ?? 0, 0)
            let compound: Double = exercise.metadata.mechanics == .compound ? 1 : 0
            return explicit
                + priority * input.policy.orderingWeights.priority
                + compound * input.policy.orderingWeights.compound
        }

        return exercises
            .sorted { left, right in
                let a = importance(left)
                let b = importance(right)
                if a != b { return a > b }
                return left.order < right.order
            }
            .enumerated()
            .map { order, exercise in
                var updated = exercise
                updated.order = order
                return updated
            }
    }

    // MARK: Session & week scoring

    static func scoreSession(_ session: PlannedSession, _ input: OptimizationInput) -> Score {
        let volume = Volume.sessionVolume(session.exercises, input.index, input.policy)
        let list = session.exercises.compactMap { input.index.byId[$0.exerciseId] }

        var pairs: [Double] = []
        for (i, exercise) in list.enumerated() {
            for other in list.dropFirst(i + 1) {
                pairs.append(exerciseSimilarity(exercise, other, input.policy.similarityWeights))
            }
        }

        let duration = SessionTiming.estimateSession(session.exercises, input.index, input.policy).totalSeconds
        let idealMinutes = input.request.preferences.preferredSessionDurationMinutes
            ?? input.request.preferences.maxSessionDurationMinutes
        let ideal = idealMinutes * 60

        let covered = session.focus.filter { (volume[$0]?.effective ?? 0) > 0 }.count
        let coverage = Double(covered) / Swift.max(1, Double(session.focus.count))

        let concentration = Num.mean(
            input.targets
                .filter { $0.preferred > 0 }
                .map { target in
                    let effective = volume[target.muscleId]?.effective ?? 0
                    let guideline = input.policy.sessionMuscleGuideline
                    return Num.clamp((effective - guideline) / guideline)
                }
        )

        return weightedScore(
            [
                ("coverage", coverage),
                ("duration", duration <= ideal ? 1 : Num.clamp(ideal / duration)),
                ("quality", Num.mean(list.map(\.metadata.classificationConfidence))),
                ("redundancy", Num.mean(pairs)),
                ("concentration", concentration),
                ("nonempty", list.isEmpty ? 0 : 1),
            ],
            input.policy.sessionWeights
        )
    }

    private static let patternFamilies: [[MovementPattern]] = [
        [.horizontalPush, .verticalPush],
        [.horizontalPull, .verticalPull],
        [.squat, .lunge],
        [.hinge, .kneeFlexion, .hipExtension],
        [.trunkFlexion, .trunkRotation],
    ]

    static func scoreWeek(_ week: TrainingWeek, _ input: OptimizationInput) -> Score {
        let index = input.index
        let policy = input.policy
        let targets = input.targets
        let request = input.request

        let volumes = week.sessions.map { Volume.sessionVolume($0.exercises, index, policy) }
        let targeted = targets.filter { $0.preferred > 0 }
        let denominator = Swift.max(1, targeted.reduce(0.0) { $0 + $1.importance })

        var volumeScore = 0.0
        for target in targeted {
            let total = volumes.reduce(input.baselineVolume?[target.muscleId] ?? 0) {
                $0 + ($1[target.muscleId]?.effective ?? 0)
            }
            volumeScore += target.importance * volumeUtility(total, target.preferred, target.upperGuideline)
        }
        let volume = volumeScore / denominator

        let frequency = Num.mean(targeted.map { target -> Double in
            let exposures = volumes.filter {
                ($0[target.muscleId]?.effective ?? 0) >= policy.meaningfulExposureSets
            }.count
            return Num.clamp(Double(exposures) / Swift.max(1, target.preferredExposures))
        })

        let selected = week.sessions
            .flatMap(\.exercises)
            .compactMap { index.byId[$0.exerciseId] }
        let patterns = Set(selected.flatMap(\.metadata.movementPatterns))
        let balance = Double(patternFamilies.filter { family in
            family.contains { patterns.contains($0) }
        }.count) / Double(patternFamilies.count)

        let redundancies = week.sessions.map { session -> Double in
            let list = session.exercises.compactMap { index.byId[$0.exerciseId] }
            var pairs: [Double] = []
            for (i, exercise) in list.enumerated() {
                for other in list.dropFirst(i + 1) {
                    pairs.append(exerciseSimilarity(exercise, other, policy.similarityWeights))
                }
            }
            return Num.mean(pairs)
        }

        let preferredMinutes = request.preferences.preferredSessionDurationMinutes
            ?? request.preferences.maxSessionDurationMinutes
        let duration = Num.mean(week.sessions.map { session -> Double in
            let seconds = SessionTiming.estimateSession(session.exercises, index, policy).totalSeconds
            let target = preferredMinutes * 60
            return seconds <= target ? 1 : Num.clamp(target / seconds)
        })

        var recoveryConflicts: [Double] = []
        if !week.sessions.isEmpty {
            for i in week.sessions.indices {
                let next = (i + 1) % week.sessions.count
                let a = ISOTime.parse(week.sessions[i].scheduledAt) ?? 0
                let b = ISOTime.parse(week.sessions[next].scheduledAt) ?? 0
                var gap = ((b - a) / 3_600_000 + 168).truncatingRemainder(dividingBy: 168)
                if gap == 0 { gap = 168 }
                if gap < policy.workloadHalfLifeHours {
                    let overlap = Num.mean(targeted.map { target -> Double in
                        let first = volumes[i][target.muscleId]?.effective ?? 0
                        let second = volumes[next][target.muscleId]?.effective ?? 0
                        return Swift.min(first, second) / policy.sessionMuscleGuideline
                    })
                    recoveryConflicts.append(overlap * (1 - gap / policy.workloadHalfLifeHours))
                }
            }
        }

        let specificIds = request.preferences.strengthExerciseIds ?? []
        let goal = policy.goal(request.preferences.goal.policyKey)

        let specificity: Double = specificIds.isEmpty
            ? Num.mean(selected.map {
                ($0.metadata.tracking == .externalLoad && $0.metadata.mechanics == .compound) ? 1 : 0
            })
            : Num.mean(specificIds.map { id -> Double in
                guard let exercise = index.byId[id] else { return 0 }
                let exposureTargets = exercise.metadata.setRoles
                    .filter { $0.role == .direct }
                    .map { role in
                        targets.first { $0.muscleId == role.muscleId }?.preferredExposures ?? 0
                    }
                let desired = Swift.max(1, exposureTargets.max() ?? 0)
                let actual = week.sessions.filter { session in
                    session.exercises.contains { $0.exerciseId == id }
                }.count
                return Num.clamp(Double(actual) / desired)
            })

        let continuity = Num.mean(selected.map { exercise -> Double in
            let hasHistory = (input.state.exercises[exercise.exercise.id]?.exposureCount ?? 0) > 0
            let carried = input.continuityIds?.contains(exercise.exercise.id) == true
            return (hasHistory || carried) ? 1 : 0
        })

        let preference = Num.mean(selected.map { exercise -> Double in
            if request.preferences.dislikedExerciseIds?.contains(exercise.exercise.id) == true { return 0 }
            if request.preferences.preferredExerciseIds?.contains(exercise.exercise.id) == true { return 1 }
            return 0.5
        })

        var weights = policy.programWeights
        weights["specificity"] = (policy.programWeights["specificity"] ?? 0) * goal.specificityWeight

        return weightedScore(
            [
                ("volume", volume),
                ("specificity", specificity),
                ("frequency", frequency),
                ("balance", balance),
                ("quality", Num.mean(selected.map(\.metadata.classificationConfidence))),
                ("continuity", continuity),
                ("duration", duration),
                ("preference", preference),
                ("redundancy", Num.mean(redundancies)),
                ("recovery", Num.mean(recoveryConflicts)),
                ("session", Num.mean(week.sessions.map { Swift.max(0, scoreSession($0, input).total) })),
            ],
            weights
        )
    }

    static func weekVolume(_ week: TrainingWeek, _ input: OptimizationInput) -> [MuscleId: Double] {
        var totals = Volume.empty()
        for session in week.sessions {
            let current = Volume.sessionVolume(session.exercises, input.index, input.policy)
            for target in input.targets {
                var entry = totals[target.muscleId] ?? MuscleVolume(direct: 0, indirect: 0, effective: 0)
                entry.effective += current[target.muscleId]?.effective ?? 0
                totals[target.muscleId] = entry
            }
        }
        var result: [MuscleId: Double] = [:]
        for target in input.targets {
            result[target.muscleId] = (totals[target.muscleId]?.effective ?? 0)
                + (input.baselineVolume?[target.muscleId] ?? 0)
        }
        return result
    }
}
