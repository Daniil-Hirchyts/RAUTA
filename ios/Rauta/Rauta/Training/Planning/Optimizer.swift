import Foundation

private nonisolated let UPPER: [MuscleId] = [
    .chest, .upperBack, .deltoids, .biceps, .triceps, .trapezius, .forearm, .serratus,
]
private nonisolated let PUSH: [MuscleId] = [.chest, .deltoids, .triceps, .serratus]
private nonisolated let PULL: [MuscleId] = [.upperBack, .biceps, .trapezius, .forearm]

/// The muscle groups the split candidates are cut along, so a caller can name a
/// session from its own focus without restating the split.
nonisolated enum SplitMuscleGroups {
    static let upper = UPPER
    static let push = PUSH
    static let pull = PULL
}

nonisolated struct SplitCandidate {
    var name: String
    var sessions: [PlannedSession]
}

nonisolated enum Optimizer {
    static func generateSplitCandidates(_ input: OptimizationInput) -> [SplitCandidate] {
        let all = input.targets.filter { $0.preferred > 0 }.map(\.muscleId)
        let lower = all.filter { !UPPER.contains($0) }
        let upper = all.filter { UPPER.contains($0) }
        let days = (input.request.schedule.sessionDays ?? input.request.schedule.days).sorted()

        var structures: [(name: String, groups: [[MuscleId]])] = [("full_body", [all])]
        if days.count >= 2 { structures.append(("upper_lower", [upper, lower])) }
        if days.count >= 3 {
            structures.append((
                "push_pull_legs",
                [all.filter { PUSH.contains($0) }, all.filter { PULL.contains($0) }, lower]
            ))
        }

        let hasSlots = input.request.schedule.sessionDays != nil
        return structures.map { structure in
            SplitCandidate(
                name: structure.name,
                sessions: days.enumerated().map { index, day in
                    PlannedSession(
                        id: "week-0/day-\(day)" + (hasSlots ? "/slot-\(index)" : ""),
                        scheduledAt: ISOTime.addDays(input.request.schedule.weekStart, Double(day)),
                        focus: structure.groups[index % structure.groups.count],
                        exercises: [],
                        duration: SessionTiming.estimateSession([], input.index, input.policy)
                    )
                }
            )
        }
    }

    private static func weekKey(_ week: TrainingWeek) -> String {
        week.sessions
            .map { session in
                session.exercises
                    .map { "\($0.exerciseId):\($0.workingSets.count)" }
                    .joined(separator: ",")
            }
            .joined(separator: "|")
    }

    static func hardConstructionChecks(
        _ week: TrainingWeek,
        _ input: OptimizationInput,
        requireNonempty: Bool = false
    ) -> Bool {
        if requireNonempty && week.sessions.contains(where: { $0.exercises.isEmpty }) { return false }

        let maxSessionSeconds = input.request.preferences.maxSessionDurationMinutes * 60
        for session in week.sessions {
            let seconds = SessionTiming.estimateSession(session.exercises, input.index, input.policy).totalSeconds
            if seconds > maxSessionSeconds { return false }
        }

        let sets = week.sessions.reduce(0) { total, session in
            total + session.exercises.reduce(0) { $0 + $1.workingSets.count }
        }
        let maximumWorkingSets = input.adaptation?.remainingWorkingSetBudget
            ?? input.request.preferences.maxWeeklyWorkingSets
        if let maximumWorkingSets, Double(sets) > maximumWorkingSets { return false }

        let volume = Scoring.weekVolume(week, input)
        let bounds = input.adaptation?.remainingMuscleVolumeBounds
            ?? input.request.preferences.muscleVolumeBounds
            ?? []
        for bound in bounds {
            let value = volume[bound.muscleId] ?? 0
            if let maximum = bound.maximum, value > maximum + 1e-6 { return false }
            if requireNonempty, let minimum = bound.minimum, value < minimum - 1e-6 { return false }
        }
        return true
    }

    private static func poolForSession(
        _ session: PlannedSession,
        _ input: OptimizationInput,
        _ valid: Set<String>
    ) -> [IndexedExercise] {
        var map: [String: IndexedExercise] = [:]
        for muscle in session.focus {
            for exercise in input.index.byMuscle[muscle] ?? [] where valid.contains(exercise.exercise.id) {
                map[exercise.exercise.id] = exercise
            }
        }
        return map.values.sorted { compareIds($0.exercise.id, $1.exercise.id) < 0 }
    }

    /// Coordinate descent: reduce unnecessary sets or swap one exercise,
    /// retaining feasibility.
    private static func improveWeek(
        _ initial: TrainingWeek,
        _ input: OptimizationInput,
        _ pools: [[IndexedExercise]]
    ) -> (week: TrainingWeek, iterations: Int) {
        var best = initial
        var score = Scoring.scoreWeek(best, input).total
        var iterations = 0

        for _ in 0..<input.policy.localIterations {
            var improved = false
            var sessionIndex = 0
            while sessionIndex < best.sessions.count && !improved {
                var exerciseIndex = 0
                while exerciseIndex < best.sessions[sessionIndex].exercises.count && !improved {
                    let original = best.sessions[sessionIndex].exercises[exerciseIndex]
                    let scorer = Scoring.createExerciseScorer(best.sessions[sessionIndex], best, input)
                    let existingIds = Set(best.sessions[sessionIndex].exercises.map(\.exerciseId))
                    let swaps = pools[sessionIndex]
                        .filter { !existingIds.contains($0.exercise.id) }
                        .map { (exercise: $0, score: scorer($0)) }
                        .sorted { left, right in
                            if left.score.total != right.score.total { return left.score.total > right.score.total }
                            return compareIds(left.exercise.exercise.id, right.exercise.exercise.id) < 0
                        }
                        .prefix(2)

                    var mutations: [PlannedExercise] = []
                    if original.workingSets.count > 1, let item = input.index.byId[original.exerciseId] {
                        mutations.append(Prescribe.exercise(
                            item,
                            count: original.workingSets.count - 1,
                            sessionId: best.sessions[sessionIndex].id,
                            rationale: original.rationale,
                            input: input
                        ))
                    }
                    for swap in swaps {
                        mutations.append(Prescribe.exercise(
                            swap.exercise,
                            count: original.workingSets.count,
                            sessionId: best.sessions[sessionIndex].id,
                            rationale: swap.score,
                            input: input
                        ))
                    }

                    for replacement in mutations {
                        iterations += 1
                        var candidate = best
                        candidate.sessions[sessionIndex].exercises[exerciseIndex] = replacement
                        guard hardConstructionChecks(candidate, input, requireNonempty: true) else { continue }
                        let next = Scoring.scoreWeek(candidate, input).total
                        if next > score + 1e-8 {
                            best = candidate
                            score = next
                            improved = true
                            break
                        }
                    }
                    exerciseIndex += 1
                }
                sessionIndex += 1
            }
            if !improved { break }
        }
        return (best, iterations)
    }

    static func optimize(_ input: OptimizationInput) -> OptimizationResult {
        let valid = Set(
            input.index.byId.values
                .filter {
                    ExerciseData.exclusionReasons(
                        $0, input.request.preferences, input.policy,
                        experience: input.request.profile.trainingExperience
                    ).isEmpty
                }
                .map(\.exercise.id)
        )
        let candidates = generateSplitCandidates(input)

        struct SplitResult {
            var name: String
            var week: TrainingWeek
            var score: Double
            var valid: Bool
        }
        var results: [SplitResult] = []
        var iterations = 0

        for split in candidates {
            let pools = split.sessions.map { poolForSession($0, input, valid) }
            var beam: [TrainingWeek] = [
                TrainingWeek(
                    id: "week-0",
                    start: input.request.schedule.weekStart,
                    phase: .base,
                    sessions: split.sessions,
                    targets: input.targets
                )
            ]

            let depthLimit = input.policy.maxExercisesPerSession * split.sessions.count
            for depth in 0..<Swift.max(0, depthLimit) {
                let sessionIndex = depth % split.sessions.count
                var expansions: [TrainingWeek] = []

                for week in beam {
                    let session = week.sessions[sessionIndex]
                    if !session.exercises.isEmpty { expansions.append(week) }
                    let scorer = Scoring.createExerciseScorer(session, week, input)
                    let existingIds = Set(session.exercises.map(\.exerciseId))
                    let ranked = pools[sessionIndex]
                        .filter { !existingIds.contains($0.exercise.id) }
                        .map { (exercise: $0, score: scorer($0)) }
                        .sorted { left, right in
                            if left.score.total != right.score.total { return left.score.total > right.score.total }
                            return compareIds(left.exercise.exercise.id, right.exercise.exercise.id) < 0
                        }
                        .prefix(input.policy.candidateLimit)

                    for candidate in ranked {
                        for count in 1...Swift.max(1, input.policy.maxSetsPerExercise) {
                            iterations += 1
                            var prescribed = Prescribe.exercise(
                                candidate.exercise,
                                count: count,
                                sessionId: session.id,
                                rationale: candidate.score,
                                input: input
                            )
                            prescribed.order = session.exercises.count
                            var next = week
                            next.sessions[sessionIndex].exercises.append(prescribed)
                            if hardConstructionChecks(next, input) { expansions.append(next) }
                        }
                    }
                }

                if expansions.isEmpty { break }

                var seen = Set<String>()
                beam = expansions
                    .map { (week: $0, score: Scoring.scoreWeek($0, input).total, key: weekKey($0)) }
                    .sorted { left, right in
                        if left.score != right.score { return left.score > right.score }
                        return compareIds(left.key, right.key) < 0
                    }
                    .filter { seen.insert($0.key).inserted }
                    .prefix(input.policy.beamWidth)
                    .map(\.week)
            }

            let eligible = beam.filter { hardConstructionChecks($0, input, requireNonempty: true) }
            guard let selected = eligible.first ?? beam.first else { continue }
            let improved = hardConstructionChecks(selected, input, requireNonempty: true)
                ? improveWeek(selected, input, pools)
                : (week: selected, iterations: 0)
            iterations += improved.iterations

            var week = improved.week
            week.sessions = week.sessions.map { session in
                var ordered = session
                ordered.exercises = Scoring.orderExercises(session.exercises, input)
                ordered.duration = SessionTiming.estimateSession(ordered.exercises, input.index, input.policy)
                return ordered
            }

            results.append(SplitResult(
                name: split.name,
                week: week,
                score: Scoring.scoreWeek(week, input).total,
                valid: hardConstructionChecks(week, input, requireNonempty: true)
            ))
        }

        let best = results
            .filter(\.valid)
            .sorted { left, right in
                if left.score != right.score { return left.score > right.score }
                return compareIds(left.name, right.name) < 0
            }
            .first

        return OptimizationResult(
            week: best?.week,
            split: best?.name ?? "none",
            candidates: valid.count,
            iterations: iterations,
            splits: results.map { SplitDiagnostic(name: $0.name, score: $0.score, valid: $0.valid) }
        )
    }
}
