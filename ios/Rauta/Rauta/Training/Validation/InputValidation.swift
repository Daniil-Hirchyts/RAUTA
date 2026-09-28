import Foundation

/// The engine's request guard. Swift's types already carry the shape checks the
/// TypeScript validator had to make by hand, so what remains here is the
/// semantic half: ranges, uniqueness, ordering and cross-field agreement.
nonisolated enum InputValidation {
    private static func issue(_ path: String) -> PlanningIssue {
        PlanningIssue(.invalidInput, path: path)
    }

    private static func isInteger(_ value: Double, _ min: Double, _ max: Double) -> Bool {
        Num.isFinite(value, min: min, max: max) && value == value.rounded()
    }

    static func validResistance(_ resistance: ResistanceValue) -> Bool {
        switch resistance.type {
        case .unknown, .bodyweight, .bandResistance:
            return true
        case .externalLoad, .assistance:
            guard let kg = resistance.kg, Num.isFinite(kg, min: 0, max: 2000),
                  resistance.basis != nil,
                  let stationId = resistance.stationId, !stationId.isEmpty
            else { return false }
            return true
        }
    }

    static func validatePolicy(_ policy: TrainingPolicy) -> [PlanningIssue] {
        var issues: [PlanningIssue] = []

        if policy.version.isEmpty { issues.append(issue("policy.version")) }

        let integerFields: [(String, Int, Double)] = [
            ("beamWidth", policy.beamWidth, 30),
            ("candidateLimit", policy.candidateLimit, 30),
            ("maxExercisesPerSession", policy.maxExercisesPerSession, 30),
            ("maxSetsPerExercise", policy.maxSetsPerExercise, 30),
            ("localIterations", policy.localIterations, 100),
        ]
        for (name, value, upper) in integerFields where !isInteger(Double(value), 1, upper) {
            issues.append(issue("policy.\(name)"))
        }

        for goal in policy.goals.values {
            let repsValid = [goal.compoundReps, goal.isolationReps].allSatisfy { range in
                isInteger(range.min, 1, 50) && isInteger(range.max, range.min, 50)
            }
            let valid = goal.volume.minimum >= 0
                && goal.volume.minimum <= goal.volume.preferred
                && goal.volume.preferred <= goal.volume.upperGuideline
                && goal.volume.upperGuideline <= 40
                && goal.compoundRest >= 30
                && goal.isolationRest >= 30
                && goal.rir >= 0 && goal.rir <= 5
                && goal.specificityWeight >= 0
                && repsValid
            if !valid { issues.append(issue("policy.goals")) }
        }

        let invalidCore = policy.workloadHalfLifeHours <= 0
            || policy.staleAfterDays <= 0
            || policy.secondsPerRep <= 0
            || policy.sessionMuscleGuideline <= 0
            || policy.meaningfulExposureSets <= 0
            || policy.indirectCredit < 0 || policy.indirectCredit > 1
            || policy.minimumAutomaticClassificationConfidence < 0
            || policy.minimumAutomaticClassificationConfidence > 1
            || policy.minimumSpecializedClassificationConfidence < 0
            || policy.minimumSpecializedClassificationConfidence > 1
            || policy.reductionFraction < 0 || policy.reductionFraction > 0.5
            || policy.maxLoadIncreaseFraction <= 0 || policy.maxLoadIncreaseFraction > 0.2
            || policy.coarseGridMaxLoadIncreaseFraction <= policy.maxLoadIncreaseFraction
            || policy.coarseGridMaxLoadIncreaseFraction > 1
            || !isInteger(policy.coarseGridMaxExtraReps, 0, 20)
            || !isInteger(Double(policy.coarseGridRequiredTopExposures), 1, 10)
            || !isInteger(Double(policy.progressionEvidenceSets), 1, 10)
            || policy.maxWeeklyVolumeIncrease < 0 || policy.maxWeeklyVolumeIncrease > 4
            || policy.warmupFractions.count != policy.warmupReps.count
            || policy.warmupFractions.contains { $0 <= 0 || $0 >= 1 }
            || policy.warmupReps.contains { !isInteger($0, 1, 10) }
            || policy.generalWarmupSeconds < 0
            || policy.transitionSeconds < 0
            || policy.warmupRestSeconds < 0
            || policy.rirTolerance < 0 || policy.rirTolerance > 2
            || policy.trendThreshold < 0
            || !isInteger(policy.maxBodyweightReps, 1, 50)
            || policy.historyMinSessions < 1
            || !policy.priorityMultipliers.values.allSatisfy { $0 > 0 && $0 <= 2 }
        if invalidCore { issues.append(issue("policy")) }

        let similarityTotal = [
            policy.similarityWeights.family,
            policy.similarityWeights.patterns,
            policy.similarityWeights.directMuscles,
            policy.similarityWeights.mechanics,
            policy.similarityWeights.tracking,
            policy.similarityWeights.laterality,
            policy.similarityWeights.equipment,
        ]
        let orderingValues = [
            policy.orderingWeights.specific,
            policy.orderingWeights.priority,
            policy.orderingWeights.compound,
        ]
        let invalidScoring = !Num.isFinite(policy.adherenceReductionThreshold, min: 0, max: 1)
            || !Num.isFinite(policy.beginnerRir, min: 0, max: 5)
            || !isInteger(policy.heavyWarmupMaxReps, 1, 20)
            || orderingValues.contains { $0 < 0 }
            || similarityTotal.contains { $0 < 0 }
            || abs(similarityTotal.reduce(0, +) - 1) > 1e-6
        if invalidScoring { issues.append(issue("policy.scoring")) }

        return issues
    }

    static func validateGenerationRequest(_ request: ProgramGenerationRequest) -> [PlanningIssue] {
        var issues: [PlanningIssue] = []
        func check(_ valid: Bool, _ path: String) {
            if !valid { issues.append(issue(path)) }
        }

        let profile = request.profile
        let preferences = request.preferences
        let schedule = request.schedule
        let history = request.history

        check(Num.isFinite(profile.age, min: 0, max: 120), "profile.age")
        let demographicsValid = (profile.bodyWeightKg.map { Num.isFinite($0, min: 20, max: 500) } ?? true)
            && (profile.heightCm.map { Num.isFinite($0, min: 50, max: 260) } ?? true)
            && (profile.trainingAgeMonths.map { Num.isFinite($0, min: 0, max: 1200) } ?? true)
        check(demographicsValid, "profile.demographics")
        check(
            profile.health.status == .healthy || !(profile.health.reasons ?? []).isEmpty,
            "profile.health"
        )

        check(
            !preferences.availableEquipment.isEmpty || preferences.availableEquipment.isEmpty,
            "preferences.availableEquipment"
        )
        let uniqueEquipment = Set(preferences.availableEquipment).count == preferences.availableEquipment.count
            && preferences.availableEquipment.allSatisfy { !$0.isEmpty }
        check(uniqueEquipment, "preferences.availableEquipment")

        let idLists: [(String, [String]?)] = [
            ("preferredExerciseIds", preferences.preferredExerciseIds),
            ("dislikedExerciseIds", preferences.dislikedExerciseIds),
            ("excludedExerciseIds", preferences.excludedExerciseIds),
            ("strengthExerciseIds", preferences.strengthExerciseIds),
        ]
        for (name, values) in idLists {
            guard let values else { continue }
            check(
                Set(values).count == values.count && values.allSatisfy { !$0.isEmpty },
                "preferences.\(name)"
            )
        }
        if let patterns = preferences.excludedPatterns {
            check(Set(patterns).count == patterns.count, "preferences.excludedPatterns")
        }

        check(
            Num.isFinite(preferences.maxSessionDurationMinutes, min: 1, max: 300),
            "preferences.maxSessionDurationMinutes"
        )
        if let preferred = preferences.preferredSessionDurationMinutes {
            check(
                Num.isFinite(preferred, min: 1, max: preferences.maxSessionDurationMinutes),
                "preferences.preferredSessionDurationMinutes"
            )
        }
        if let maxSets = preferences.maxWeeklyWorkingSets {
            check(isInteger(maxSets, 1, 500), "preferences.maxWeeklyWorkingSets")
        }

        if let priorities = preferences.priorityMuscles {
            check(
                Set(priorities.map(\.muscleId)).count == priorities.count,
                "preferences.priorityMuscles"
            )
        }
        if let bounds = preferences.muscleVolumeBounds {
            let valid = bounds.allSatisfy { bound in
                (bound.minimum.map { Num.isFinite($0, min: 0, max: 40) } ?? true)
                    && (bound.maximum.map { Num.isFinite($0, min: 0, max: 40) } ?? true)
                    && (bound.minimum ?? 0) <= (bound.maximum ?? 40)
            }
            check(valid && Set(bounds.map(\.muscleId)).count == bounds.count, "preferences.muscleVolumeBounds")
        }

        if let contexts = preferences.loadContexts {
            check(contexts.values.allSatisfy { !$0.stationId.isEmpty }, "preferences.loadContexts")
        }
        if let grids = preferences.loadGrids {
            let valid = grids.values.allSatisfy { grid in
                if let loads = grid.availableLoadsKg {
                    return !loads.isEmpty && loads.count <= 1000
                        && loads.allSatisfy { Num.isFinite($0, min: 0, max: 2000) }
                }
                guard let increment = grid.incrementKg,
                      Num.isFinite(increment, min: 0.001, max: 100)
                else { return false }
                if let minimum = grid.minimumKg, !Num.isFinite(minimum, min: 0, max: 2000) { return false }
                if let maximum = grid.maximumKg,
                   !Num.isFinite(maximum, min: grid.minimumKg ?? 0, max: 2000) { return false }
                return true
            }
            check(valid, "preferences.loadGrids")
        }

        check(ISOTime.valid(request.now), "now")
        check(
            ISOTime.valid(schedule.weekStart) && schedule.weekStart.contains("T00:00:00"),
            "schedule.weekStart"
        )
        check(
            schedule.days.count >= 1 && schedule.days.count <= 7
                && schedule.days.allSatisfy { $0 >= 0 && $0 <= 6 }
                && Set(schedule.days).count == schedule.days.count,
            "schedule.days"
        )
        if let slots = schedule.sessionDays {
            let valid = slots.count >= 1 && slots.count <= 7
                && slots.allSatisfy { $0 >= 0 && $0 <= 6 && schedule.days.contains($0) }
                && schedule.days.allSatisfy { slots.contains($0) }
            check(valid, "schedule.sessionDays")
        }
        check(schedule.durationWeeks >= 1 && schedule.durationWeeks <= 12, "schedule.durationWeeks")

        let nowMillis = ISOTime.parse(request.now) ?? 0
        let coverageValid: Bool = {
            if history.coverage == .complete {
                guard let start = history.coverageStart, ISOTime.valid(start) else { return false }
            }
            if let start = history.coverageStart {
                guard ISOTime.valid(start), (ISOTime.parse(start) ?? .infinity) <= nowMillis else { return false }
            }
            return true
        }()
        check(coverageValid, "history.coverage")

        if let policy = request.policy { issues += validatePolicy(policy) }
        issues += ExerciseData.validateExerciseData(request.exercises)
        check(request.exercises.count <= 10000, "exercises")
        check(history.sessions.count <= 10000, "history.sessions")
        if history.sessions.count > 10000 { return issues }

        var sessionIds = Set<String>()
        var setIds = Set<String>()
        var plannedSessions = Set<String>()
        struct PlannedSetUse { var sides: [SetSide]; var exerciseId: String; var sessionId: String }
        var plannedSets: [String: PlannedSetUse] = [:]
        let exerciseIds = Set(request.exercises.map(\.id))

        for (index, session) in history.sessions.enumerated() {
            let path = "history.sessions.\(index)"
            guard !session.id.isEmpty,
                  ISOTime.valid(session.startedAt),
                  ISOTime.valid(session.completedAt)
            else {
                check(false, path)
                continue
            }
            check(!sessionIds.contains(session.id), path + ".id")
            sessionIds.insert(session.id)

            let startedAt = ISOTime.parse(session.startedAt) ?? 0
            let completedAt = ISOTime.parse(session.completedAt) ?? 0
            check(startedAt <= completedAt && completedAt <= nowMillis, path + ".time")
            if let duration = session.durationSeconds {
                check(Num.isFinite(duration, min: 0, max: 86400), path)
            }

            if let plannedSessionId = session.plannedSessionId {
                check(!plannedSessions.contains(plannedSessionId), path + ".plannedSessionId")
                plannedSessions.insert(plannedSessionId)
            }

            var perSessionIds = Set<String>()
            for performed in session.exercises {
                guard performed.sets.count <= 100 else {
                    check(false, path + ".exercises")
                    continue
                }
                check(!perSessionIds.contains(performed.exerciseId), path + ".exerciseId")
                perSessionIds.insert(performed.exerciseId)
                if !exerciseIds.contains(performed.exerciseId) {
                    issues.append(PlanningIssue(
                        .unknownExercise,
                        path: path,
                        context: ["exerciseId": .string(performed.exerciseId)]
                    ))
                }

                for set in performed.sets {
                    check(!set.id.isEmpty && !setIds.contains(set.id), path + ".set.id")
                    setIds.insert(set.id)
                    check(
                        isInteger(set.reps, set.completed ? 1 : 0, 1000) && validResistance(set.resistance),
                        path + ".set"
                    )
                    let effortValid: Bool = {
                        if let rir = set.rir, !Num.isFinite(rir, min: 0, max: 10) { return false }
                        if let rpe = set.rpe, !Num.isFinite(rpe, min: 0, max: 10) { return false }
                        if let rir = set.rir, let rpe = set.rpe, abs(rir + rpe - 10) > 1 { return false }
                        return true
                    }()
                    check(effortValid, path + ".set.effort")
                    if let timestamp = set.timestamp {
                        let at = ISOTime.parse(timestamp)
                        check(
                            ISOTime.valid(timestamp) && at.map { $0 >= startedAt && $0 <= completedAt } == true,
                            path + ".set.timestamp"
                        )
                    }
                    if let plannedSetId = set.plannedSetId {
                        let prior = plannedSets[plannedSetId]
                        let valid = prior.map { prior in
                            prior.exerciseId == performed.exerciseId
                                && prior.sessionId == session.id
                                && !prior.sides.contains(set.side)
                                && !prior.sides.contains(.both)
                                && set.side != .both
                        } ?? true
                        check(valid, path + ".plannedSetId")
                        plannedSets[plannedSetId] = PlannedSetUse(
                            sides: (prior?.sides ?? []) + [set.side],
                            exerciseId: performed.exerciseId,
                            sessionId: session.id
                        )
                    }
                }
            }
        }

        return issues
    }

    static func planningEligibility(_ request: ProgramGenerationRequest) -> [PlanningIssue] {
        if request.profile.age < 18
            || request.profile.health.status != .healthy
            || request.readiness?.pain == true {
            return [PlanningIssue(.unsupportedPopulation)]
        }
        if request.preferences.goal == .power {
            return [PlanningIssue(.unsupportedGoal, context: ["goal": .string("power")])]
        }
        return []
    }
}
