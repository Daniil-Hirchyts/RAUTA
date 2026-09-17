import Foundation

nonisolated enum TrainingStateAnalysis {
    static func analyze(
        _ request: ProgramGenerationRequest,
        index: ExerciseIndex? = nil,
        targets: [MuscleTarget] = [],
        policy: TrainingPolicy? = nil,
        previousProgram: TrainingProgram? = nil
    ) -> DerivedTrainingState {
        let index = index ?? ExerciseData.createIndex(request.exercises, overrides: request.metadata ?? [])
        let policy = policy ?? request.policy ?? DEFAULT_POLICY
        let now = ISOTime.parse(request.now) ?? 0
        let start = ISOTime.parse(request.schedule.weekStart) ?? 0

        let windows = [7.0, 14.0, 28.0].map { days in
            Volume.historyVolume(
                request.history, index, policy,
                from: now - days * DAY_MS, to: now
            )
        }
        let week = Volume.historyVolume(
            request.history, index, policy,
            from: start,
            to: Swift.min(start + 7 * DAY_MS - 1, now),
            inclusiveStart: true
        )

        let knownHistory: Bool = {
            guard request.history.coverage == .complete,
                  let coverageStart = request.history.coverageStart,
                  let parsed = ISOTime.parse(coverageStart)
            else { return false }
            return parsed <= now - 28 * DAY_MS
        }()

        var muscles: [MuscleId: MuscleTrainingState] = [:]
        for muscleId in MuscleId.allCases {
            let target = targets.first { $0.muscleId == muscleId }
            var decayedWorkload = 0.0
            var lastMeaningfulTrainingAt: String?
            var recentSessionCount = 0.0

            for session in request.history.sessions {
                var exposure = 0.0
                for performed in session.exercises {
                    guard let exercise = index.byId[performed.exerciseId] else { continue }
                    let credit = Volume.effectiveSetCredit(exercise, muscleId, policy).effective
                    for set in performed.sets {
                        let at = set.timestamp ?? session.completedAt
                        guard let time = ISOTime.parse(at) else { continue }
                        let hours = (now - time) / 3_600_000
                        if !Volume.isWorkingSet(set) || hours < 0 { continue }
                        let value = credit * (set.side == .both ? 1 : 0.5)
                        decayedWorkload += value * exp((-M_LN2 * hours) / policy.workloadHalfLifeHours)
                        if hours < 28 * 24 { exposure += value }
                        if value > 0 {
                            let previous = lastMeaningfulTrainingAt.flatMap(ISOTime.parse)
                            if previous == nil || time > previous! { lastMeaningfulTrainingAt = at }
                        }
                    }
                }
                if exposure >= policy.meaningfulExposureSets { recentSessionCount += 1 }
            }

            let preferred = target?.preferred ?? 0
            let effective = week[muscleId]?.effective ?? 0
            let earlier = (windows[2][muscleId]?.effective ?? 0) - (windows[1][muscleId]?.effective ?? 0)

            let status: MuscleTrainingState.Status = {
                guard let target, knownHistory || recentSessionCount > 0 else { return .unknown }
                if effective < target.minimum { return .underTarget }
                if effective > target.upperGuideline { return .overTarget }
                return .onTarget
            }()

            let confidence: Confidence = {
                if knownHistory {
                    return recentSessionCount >= Double(policy.historyMinSessions) ? .medium : .low
                }
                return recentSessionCount > 0 ? .low : .none
            }()

            muscles[muscleId] = MuscleTrainingState(
                muscleId: muscleId,
                targetWeeklyEffectiveSets: preferred,
                effectiveSetsCurrentWeek: effective,
                directSetsCurrentWeek: week[muscleId]?.direct ?? 0,
                indirectSetsCurrentWeek: week[muscleId]?.indirect ?? 0,
                rolling7DaySets: windows[0][muscleId]?.effective ?? 0,
                rolling14DaySets: windows[1][muscleId]?.effective ?? 0,
                rolling28DaySets: windows[2][muscleId]?.effective ?? 0,
                recentSessionCount: recentSessionCount,
                lastMeaningfulTrainingAt: lastMeaningfulTrainingAt,
                decayedWorkload: decayedWorkload,
                volumeTargetDeficit: Swift.max(0, preferred - effective),
                workloadTrend: knownHistory && earlier > 0
                    ? ((windows[1][muscleId]?.effective ?? 0) - earlier) / earlier
                    : nil,
                priorityScore: (target?.importance ?? 1)
                    * (preferred > 0 ? Num.clamp((preferred - effective) / preferred) : 0),
                status: status,
                confidence: confidence
            )
        }

        var seen = Set<String>()
        var ids: [String] = []
        for session in request.history.sessions {
            for performed in session.exercises where !seen.contains(performed.exerciseId) {
                seen.insert(performed.exerciseId)
                ids.append(performed.exerciseId)
            }
        }
        ids = ids.filter { index.byId[$0] != nil }

        var exercises: [String: ExercisePerformanceState] = [:]
        for id in ids {
            exercises[id] = Strength.analyzePerformance(
                request.history, id, request.now, policy,
                allowStrengthEstimates: index.byId[id]?.metadata.tracking == .externalLoad
            )
        }

        var adherence = AdherenceState()
        if let previousProgram,
           request.history.coverage == .complete,
           let coverageStart = request.history.coverageStart,
           let coverageStartMillis = ISOTime.parse(coverageStart) {
            let planned = previousProgram.weeks
                .flatMap(\.sessions)
                .filter { session in
                    guard let at = ISOTime.parse(session.scheduledAt) else { return false }
                    return at < now && at >= coverageStartMillis
                }

            if !planned.isEmpty {
                let matched = planned.map { session in
                    (
                        planned: session,
                        actual: request.history.sessions.first { $0.plannedSessionId == session.id }
                    )
                }

                adherence.sessionCompletion = Double(
                    matched.filter { $0.actual?.status == .completed }.count
                ) / Double(planned.count)

                let plannedSetIds = planned
                    .flatMap { $0.exercises.flatMap(\.workingSets) }
                    .map(\.id)
                var completedUnits: [String: Double] = [:]
                for entry in matched {
                    for performed in entry.actual?.exercises ?? [] {
                        for set in performed.sets {
                            guard let plannedSetId = set.plannedSetId else { continue }
                            let matchesPlan = entry.planned.exercises.contains { plannedExercise in
                                plannedExercise.exerciseId == performed.exerciseId
                                    && plannedExercise.workingSets.contains { $0.id == plannedSetId }
                            }
                            guard matchesPlan else { continue }
                            completedUnits[plannedSetId] = Swift.min(
                                1,
                                (completedUnits[plannedSetId] ?? 0) + Volume.completedWorkingSetUnits(set)
                            )
                        }
                    }
                }
                if !plannedSetIds.isEmpty {
                    adherence.setCompletion = plannedSetIds.reduce(0.0) {
                        $0 + (completedUnits[$1] ?? 0)
                    } / Double(plannedSetIds.count)
                }

                let plannedExercises = matched.flatMap { entry in
                    entry.planned.exercises.map { (id: $0.exerciseId, actual: entry.actual) }
                }
                if !plannedExercises.isEmpty {
                    let performedCount = plannedExercises.filter { entry in
                        entry.actual?.exercises.contains {
                            $0.exerciseId == entry.id && $0.sets.contains(where: Volume.isWorkingSet)
                        } ?? false
                    }.count
                    adherence.exerciseCompletion = Double(performedCount) / Double(plannedExercises.count)
                }

                let ratios = matched.compactMap { entry -> Double? in
                    guard let duration = entry.actual?.durationSeconds,
                          entry.planned.duration.totalSeconds > 0
                    else { return nil }
                    return duration / entry.planned.duration.totalSeconds
                }
                if !ratios.isEmpty { adherence.durationRatio = Num.mean(ratios) }
            }
        }

        return DerivedTrainingState(
            muscles: muscles,
            exercises: exercises,
            adherence: adherence,
            confidence: knownHistory ? .medium : (ids.isEmpty ? .none : .low),
            issues: request.history.coverage == .unknown ? [PlanningIssue(.incompleteHistory)] : []
        )
    }
}
