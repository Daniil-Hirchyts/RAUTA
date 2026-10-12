import Foundation

nonisolated struct AdaptationRequest {
    var previousProgram: TrainingProgram
    var request: ProgramGenerationRequest
    var mode: ProgramAdaptation.Mode
}

nonisolated enum Adapt {
    /// The structural guard the TypeScript `validSource` applied to an untyped
    /// program; what survives in Swift is the semantic half.
    private static func validSource(_ program: TrainingProgram) -> Bool {
        guard !program.id.isEmpty,
              InputValidation.validatePolicy(program.policy).isEmpty,
              !program.weeks.isEmpty, program.weeks.count <= 12
        else { return false }

        return program.weeks.allSatisfy { week in
            ISOTime.valid(week.start)
                && !week.sessions.isEmpty && week.sessions.count <= 7
                && week.sessions.allSatisfy { session in
                    !session.id.isEmpty
                        && ISOTime.valid(session.scheduledAt)
                        && !session.exercises.isEmpty
                        && session.exercises.allSatisfy { exercise in
                            !exercise.exerciseId.isEmpty
                                && !exercise.workingSets.isEmpty
                                && exercise.workingSets.count <= 30
                                && (exercise.workingSets + exercise.warmupSets).allSatisfy { set in
                                    !set.id.isEmpty
                                        && Num.isFinite(set.targetReps.min, min: 1, max: 50)
                                        && Num.isFinite(set.targetReps.max, min: set.targetReps.min, max: 50)
                                        && InputValidation.validResistance(set.resistance)
                                }
                        }
                }
        }
    }

    /// Returns a revision for requested FUTURE slots. Completed and past
    /// sessions remain in the source program.
    static func adaptTrainingProgram(_ adaptationRequest: AdaptationRequest) -> ProgramGenerationResult {
        let previousProgram = adaptationRequest.previousProgram
        let request = adaptationRequest.request
        let mode = adaptationRequest.mode

        let invalid = InputValidation.validateGenerationRequest(request)
        if !invalid.isEmpty { return .invalid(issues: invalid, suggestions: [.reviewInput]) }
        let eligibility = InputValidation.planningEligibility(request)
        if !eligibility.isEmpty { return .unsupported(issues: eligibility, suggestions: [.reviewInput]) }

        let policyMatches = fingerprint(previousProgram.policy.jsonTree)
            == fingerprint((request.policy ?? previousProgram.policy).jsonTree)
        guard validSource(previousProgram), policyMatches else {
            return .invalid(
                issues: [PlanningIssue(
                    .invalidProgram,
                    context: ["reason": .string("incompatible_source")]
                )],
                suggestions: [.reviewInput]
            )
        }

        let source = mode == .remainingWeek
            ? previousProgram.weeks.first { $0.start == request.schedule.weekStart }
            : previousProgram.weeks.last
        guard let source, request.schedule.durationWeeks == 1 else {
            return .invalid(
                issues: [PlanningIssue(.invalidInput, path: "adaptation.schedule")],
                suggestions: [.reviewInput]
            )
        }

        let scheduledDays = request.schedule.sessionDays ?? request.schedule.days
        let nowMillis = ISOTime.parse(request.now) ?? 0
        let futureDays = scheduledDays.filter { day in
            (ISOTime.parse(ISOTime.addDays(request.schedule.weekStart, Double(day))) ?? 0) > nowMillis
        }
        guard futureDays.count == scheduledDays.count, !futureDays.isEmpty else {
            return .invalid(
                issues: [PlanningIssue(.invalidInput, path: "adaptation.futureDays")],
                suggestions: [.reviewInput]
            )
        }

        var authoritativeRequest = request
        authoritativeRequest.policy = request.policy ?? previousProgram.policy

        let base = Generate.preparation(authoritativeRequest, previousProgram: previousProgram)
        let weekStartMillis = ISOTime.parse(request.schedule.weekStart) ?? 0

        let actual = Volume.historyVolume(
            request.history, base.index, base.policy,
            from: weekStartMillis, to: nowMillis, inclusiveStart: true
        )
        let actualFrequency: [MuscleId: Double]? = mode == .remainingWeek
            ? Volume.historyFrequency(
                request.history, base.index, base.policy,
                from: weekStartMillis, to: nowMillis, inclusiveStart: true
            )
            : nil
        let actualSpecificFrequency: [String: Double] = mode == .remainingWeek
            ? Volume.historyExerciseFrequency(
                request.history, base.policy,
                from: weekStartMillis, to: nowMillis, inclusiveStart: true
            )
            : [:]

        let completedSets: Double = mode == .remainingWeek
            ? request.history.sessions
                .filter { session in
                    let at = ISOTime.parse(session.completedAt) ?? .nan
                    return at >= weekStartMillis && at <= nowMillis
                }
                .reduce(0.0) { total, session in
                    total + session.exercises.reduce(0.0) { exerciseTotal, exercise in
                        exerciseTotal + exercise.sets.reduce(0.0) {
                            $0 + Volume.completedWorkingSetUnits($1)
                        }
                    }
                }
            : 0

        if mode == .remainingWeek,
           request.preferences.muscleVolumeBounds?.contains(where: { bound in
               guard let maximum = bound.maximum else { return false }
               return (actual[bound.muscleId]?.effective ?? 0) > maximum
           }) == true {
            return .infeasible(
                issues: [PlanningIssue(
                    .volumeLimit,
                    context: ["reason": .string("completed_work_already_exceeds_bound")]
                )],
                suggestions: [.relaxVolumeBounds]
            )
        }

        let remainingBudget: Double? = request.preferences.maxWeeklyWorkingSets
            .map { ($0 - completedSets).rounded(.down) }
        if let remainingBudget, remainingBudget < Double(futureDays.count) {
            return .infeasible(issues: [PlanningIssue(.volumeLimit)], suggestions: [.relaxVolumeBounds])
        }

        let remainingMuscleVolumeBounds: [MuscleVolumeBound]? = mode == .remainingWeek
            ? request.preferences.muscleVolumeBounds?.map { bound in
                let done = actual[bound.muscleId]?.effective ?? 0
                return MuscleVolumeBound(
                    muscleId: bound.muscleId,
                    minimum: Swift.max(0, (bound.minimum ?? 0) - done),
                    maximum: bound.maximum.map { Swift.max(0, $0 - done) }
                )
            }
            : nil

        let targets: [MuscleTarget] = base.targets.map { target in
            let done = mode == .remainingWeek ? (actual[target.muscleId]?.effective ?? 0) : 0
            let doneExposures = mode == .remainingWeek ? (actualFrequency?[target.muscleId] ?? 0) : 0
            var updated = target
            updated.minimum = Swift.max(0, target.minimum - done)
            updated.preferred = Swift.max(0, target.preferred - done)
            updated.preferredExposures = Swift.max(0, target.preferredExposures - doneExposures)
            return updated
        }

        var remainingSpecificTargets: [(exerciseId: String, desired: Double)] = []
        for exerciseId in request.preferences.strengthExerciseIds ?? [] {
            let planned = Double(source.sessions.filter { session in
                session.exercises.contains { $0.exerciseId == exerciseId }
            }.count)
            let done = mode == .remainingWeek ? (actualSpecificFrequency[exerciseId] ?? 0) : 0
            remainingSpecificTargets.append((exerciseId, Swift.max(0, planned - done)))
        }
        let remainingSpecificLookup = Dictionary(
            remainingSpecificTargets.map { ($0.exerciseId, $0.desired) },
            uniquingKeysWith: { _, last in last }
        )

        var input = base
        input.request = authoritativeRequest
        input.targets = targets
        input.continuityIds = source.sessions.flatMap { $0.exercises.map(\.exerciseId) }
        if mode == .remainingWeek {
            var baselineMuscleVolume: [MuscleId: Double] = [:]
            for (muscleId, volume) in actual { baselineMuscleVolume[muscleId] = volume.effective }
            input.adaptation = OptimizationInput.Adaptation(
                baselineCompletedWorkingSets: completedSets,
                baselineMuscleVolume: baselineMuscleVolume,
                remainingWorkingSetBudget: remainingBudget,
                remainingMuscleVolumeBounds: remainingMuscleVolumeBounds
            )
        }

        let decliningCount = base.state.exercises.values.filter { $0.trend == .declining }.count
        let phase: TrainingWeek.Phase = (request.readiness?.perceivedReadiness == .low && decliningCount >= 2)
            ? .reducedVolume
            : .base

        guard let firstSplit = Optimizer.generateSplitCandidates(input).first else {
            return .infeasible(
                issues: [PlanningIssue(.noValidExercises)],
                suggestions: [.addEquipment, .reviewInput]
            )
        }

        var week = TrainingWeek(
            id: "week-0",
            start: request.schedule.weekStart,
            phase: phase,
            sessions: firstSplit.sessions,
            targets: targets
        )

        func plannedMuscleExposures(_ candidate: TrainingWeek, _ muscleId: MuscleId) -> Double {
            Double(candidate.sessions.filter { session in
                let volume = Volume.sessionVolume(session.exercises, input.index, input.policy)
                return (volume[muscleId]?.effective ?? 0) >= input.policy.meaningfulExposureSets
            }.count)
        }

        func plannedSpecificExposures(_ candidate: TrainingWeek, _ exerciseId: String) -> Double {
            Double(candidate.sessions.filter { session in
                session.exercises.contains { $0.exerciseId == exerciseId }
            }.count)
        }

        let sortedFutureDays = futureDays.sorted()
        let sourceStart = ISOTime.parse(source.start) ?? 0

        for si in week.sessions.indices {
            let day = sortedFutureDays[si]
            let sameDaySessions = source.sessions.filter { session in
                let offset = ((ISOTime.parse(session.scheduledAt) ?? 0) - sourceStart) / DAY_MS
                return offset == Double(day)
            }
            let repeatIndex = sortedFutureDays.prefix(si).filter { $0 == day }.count
            let prior = repeatIndex < sameDaySessions.count
                ? sameDaySessions[repeatIndex]
                : source.sessions[si % source.sessions.count]

            week.sessions[si].focus = prior.focus
            week.sessions[si].exercises = []

            for old in prior.exercises {
                var replacement = input.index.byId[old.exerciseId]
                let blocked = replacement.map {
                    !ExerciseData.exclusionReasons(
                        $0, authoritativeRequest.preferences, input.policy,
                        experience: authoritativeRequest.profile.trainingExperience
                    ).isEmpty
                } ?? true

                if blocked {
                    let preferred = input.index.byId[old.exerciseId]
                    let chosenIds = Set(week.sessions[si].exercises.map(\.exerciseId))
                    replacement = input.index.byId.values
                        .filter { candidate in
                            !chosenIds.contains(candidate.exercise.id)
                                && ExerciseData.exclusionReasons(
                                    candidate, authoritativeRequest.preferences, input.policy,
                                    experience: authoritativeRequest.profile.trainingExperience
                                ).isEmpty
                                && candidate.metadata.setRoles.contains {
                                    $0.role == .direct && old.targetMuscles.contains($0.muscleId)
                                }
                        }
                        .sorted { left, right in
                            func sharesPattern(_ item: IndexedExercise) -> Bool {
                                item.metadata.movementPatterns.contains {
                                    preferred?.metadata.movementPatterns.contains($0) == true
                                }
                            }
                            let a = sharesPattern(left) ? 1 : 0
                            let b = sharesPattern(right) ? 1 : 0
                            if a != b { return a > b }
                            return compareIds(left.exercise.id, right.exercise.id) < 0
                        }
                        .first
                }

                guard let chosen = replacement,
                      !week.sessions[si].exercises.contains(where: { $0.exerciseId == chosen.exercise.id })
                else { continue }

                let current = Scoring.weekVolume(week, input)
                let needsWork = chosen.metadata.setRoles.contains { role in
                    guard role.role == .direct else { return false }
                    let preferred = targets.first { $0.muscleId == role.muscleId }?.preferred ?? 0
                    return (current[role.muscleId] ?? 0) < preferred
                }
                let needsFrequency = chosen.metadata.setRoles.contains { role in
                    guard role.role == .direct else { return false }
                    let preferredExposures = targets.first { $0.muscleId == role.muscleId }?
                        .preferredExposures ?? 0
                    return plannedMuscleExposures(week, role.muscleId) < preferredExposures
                }
                let needsSpecificity = plannedSpecificExposures(week, chosen.exercise.id)
                    < (remainingSpecificLookup[chosen.exercise.id] ?? 0)

                if !needsWork && !needsFrequency && !needsSpecificity && mode == .remainingWeek { continue }

                let count = week.phase == .reducedVolume
                    ? Swift.max(1, old.workingSets.count - 1)
                    : old.workingSets.count
                var prescription = Prescribe.exercise(
                    chosen,
                    count: count,
                    sessionId: week.sessions[si].id,
                    rationale: Scoring.scoreExercise(chosen, week.sessions[si], week, input),
                    input: input
                )
                prescription.order = week.sessions[si].exercises.count
                week.sessions[si].exercises.append(prescription)
            }
        }

        // Work from sessions of this week that have passed without being
        // trained moves into what is left of the week — only where a muscle
        // is still short of its weekly target, only exercises the person can
        // perform, and only while every session stays inside its time limit
        // and exercise count. What does not fit is reported as dropped below.
        if mode == .remainingWeek {
            let performed = Set(request.history.sessions.compactMap(\.plannedSessionId))
            let missedSessions = source.sessions.filter { session in
                (ISOTime.parse(session.scheduledAt) ?? .infinity) < nowMillis
                    && !performed.contains(session.id)
            }
            for missed in missedSessions {
                for old in missed.exercises {
                    guard let item = input.index.byId[old.exerciseId],
                          ExerciseData.exclusionReasons(
                              item, authoritativeRequest.preferences, input.policy,
                              experience: authoritativeRequest.profile.trainingExperience
                          ).isEmpty
                    else { continue }
                    let current = Scoring.weekVolume(week, input)
                    let short = item.metadata.setRoles.contains { role in
                        guard role.role == .direct else { return false }
                        let preferred = targets.first { $0.muscleId == role.muscleId }?.preferred ?? 0
                        return (current[role.muscleId] ?? 0) < preferred
                    }
                    guard short else { continue }

                    // The session with the most room that trains these
                    // muscles and does not already hold the exercise.
                    let candidates = week.sessions.indices
                        .filter { index in
                            !week.sessions[index].exercises.contains { $0.exerciseId == item.exercise.id }
                                && week.sessions[index].exercises.count < input.policy.maxExercisesPerSession
                                && item.metadata.setRoles.contains { role in
                                    role.role == .direct && week.sessions[index].focus.contains(role.muscleId)
                                }
                        }
                        .sorted { left, right in
                            let a = SessionTiming.estimateSession(week.sessions[left].exercises, input.index, input.policy).totalSeconds
                            let b = SessionTiming.estimateSession(week.sessions[right].exercises, input.index, input.policy).totalSeconds
                            return a != b ? a < b : left < right
                        }
                    for index in candidates {
                        var trial = week
                        var placed = false
                        for count in stride(from: Swift.min(old.workingSets.count, 2), through: 1, by: -1) {
                            var prescription = Prescribe.exercise(
                                item,
                                count: count,
                                sessionId: trial.sessions[index].id,
                                rationale: Scoring.scoreExercise(item, trial.sessions[index], trial, input),
                                input: input
                            )
                            prescription.order = trial.sessions[index].exercises.count
                            var attempt = week
                            attempt.sessions[index].exercises.append(prescription)
                            if Optimizer.hardConstructionChecks(attempt, input) {
                                trial = attempt
                                placed = true
                                break
                            }
                        }
                        if placed {
                            week = trial
                            break
                        }
                    }
                }
            }
        }

        // Reschedule explicit strength-lift occurrences that were missed earlier
        // in the week when a future slot remains. One lift occurrence is never
        // stacked twice into the same session.
        for (exerciseId, desired) in remainingSpecificTargets {
            guard let item = input.index.byId[exerciseId],
                  ExerciseData.exclusionReasons(
                      item, authoritativeRequest.preferences, input.policy,
                      experience: authoritativeRequest.profile.trainingExperience
                  ).isEmpty
            else { continue }

            let template = source.sessions
                .flatMap(\.exercises)
                .first { $0.exerciseId == exerciseId }

            while plannedSpecificExposures(week, exerciseId) < desired,
                  plannedSpecificExposures(week, exerciseId) < Double(week.sessions.count) {
                let existingTimes = week.sessions
                    .filter { $0.exercises.contains { $0.exerciseId == exerciseId } }
                    .compactMap { ISOTime.parse($0.scheduledAt) }

                func spacing(_ session: PlannedSession) -> Double {
                    guard !existingTimes.isEmpty else { return .infinity }
                    let at = ISOTime.parse(session.scheduledAt) ?? 0
                    return existingTimes.map { abs(at - $0) }.min() ?? .infinity
                }

                let candidates = week.sessions
                    .filter { !$0.exercises.contains { $0.exerciseId == exerciseId } }
                    .sorted { left, right in
                        let a = spacing(left)
                        let b = spacing(right)
                        if a != b { return a > b }
                        return compareIds(left.id, right.id) < 0
                    }
                guard let session = candidates.first,
                      let index = week.sessions.firstIndex(where: { $0.id == session.id })
                else { break }

                let templateSets = template?.workingSets.count ?? 1
                let count = Swift.min(
                    input.policy.maxSetsPerExercise,
                    Swift.max(1, week.phase == .reducedVolume ? templateSets - 1 : templateSets)
                )
                var prescription = Prescribe.exercise(
                    item,
                    count: count,
                    sessionId: session.id,
                    rationale: Scoring.scoreExercise(item, session, week, input),
                    input: input
                )
                prescription.order = week.sessions[index].exercises.count
                week.sessions[index].exercises.append(prescription)
            }
        }

        // Trim lowest-cost work until new time and volume constraints fit,
        // without reducing rest.
        let maximumTrims = week.sessions.reduce(0) { total, session in
            total + session.exercises.reduce(0) { $0 + $1.workingSets.count }
        }
        var step = 0
        while step < maximumTrims && !Optimizer.hardConstructionChecks(week, input) {
            step += 1
            var removals: [(candidate: TrainingWeek, score: Double)] = []
            for si in week.sessions.indices {
                for ei in week.sessions[si].exercises.indices {
                    let exercise = week.sessions[si].exercises[ei]
                    if week.sessions[si].exercises.count == 1 && exercise.workingSets.count == 1 { continue }
                    var candidate = week
                    if exercise.workingSets.count > 1, let item = input.index.byId[exercise.exerciseId] {
                        var reduced = Prescribe.exercise(
                            item,
                            count: exercise.workingSets.count - 1,
                            sessionId: week.sessions[si].id,
                            rationale: exercise.rationale,
                            input: input
                        )
                        reduced.order = exercise.order
                        candidate.sessions[si].exercises[ei] = reduced
                    } else {
                        candidate.sessions[si].exercises.remove(at: ei)
                    }
                    let keepsSpecificity = remainingSpecificTargets.allSatisfy { entry in
                        plannedSpecificExposures(candidate, entry.exerciseId)
                            >= Swift.min(entry.desired, Double(candidate.sessions.count))
                    }
                    guard keepsSpecificity else { continue }
                    removals.append((candidate, Scoring.scoreWeek(candidate, input).total))
                }
            }
            guard let best = removals.max(by: { $0.score < $1.score }) else { break }
            week = best.candidate
        }

        week.sessions = week.sessions.map { session in
            var ordered = session
            ordered.exercises = Scoring.orderExercises(session.exercises, input)
            ordered.duration = SessionTiming.estimateSession(ordered.exercises, input.index, input.policy)
            return ordered
        }

        guard Optimizer.hardConstructionChecks(week, input, requireNonempty: true) else {
            return .infeasible(
                issues: [PlanningIssue(.sessionDurationInfeasible)],
                suggestions: [.increaseDuration, .relaxVolumeBounds]
            )
        }

        let adaptationRecord = ProgramAdaptation(
            sourceProgramId: previousProgram.id,
            asOf: request.now,
            mode: mode
        )
        let preservedWeek = week
        let preservedScore = Scoring.scoreWeek(week, input).total
        let candidateCount = input.index.byId.count

        let result = Generate.generateTrainingProgram(
            authoritativeRequest,
            optimize: { _ in
                OptimizationResult(
                    week: preservedWeek,
                    split: "preserved_structure",
                    candidates: candidateCount,
                    iterations: maximumTrims,
                    splits: [SplitDiagnostic(name: "preserved_structure", score: preservedScore, valid: true)]
                )
            },
            adaptation: adaptationRecord
        )

        guard var program = result.program else { return result }
        var issues = result.issues
        program.adaptation = adaptationRecord
        Generate.namespaceProgramIds(
            &program,
            "adaptation-" + fingerprint(.object([
                "source": .string(previousProgram.id),
                "request": requestTree(request),
                "week": preservedWeek.jsonTree,
            ]))
        )

        if mode == .remainingWeek {
            var sourceVolume: [MuscleId: Double] = [:]
            for target in targets {
                sourceVolume[target.muscleId] = source.sessions.reduce(0.0) { total, session in
                    let volume = Volume.sessionVolume(session.exercises, input.index, input.policy)
                    return total + (volume[target.muscleId]?.effective ?? 0)
                }
            }
            let adaptedVolume = Scoring.weekVolume(preservedWeek, input)
            let dropped = targets.contains { target in
                let outstanding = Swift.max(
                    0,
                    (sourceVolume[target.muscleId] ?? 0) - (actual[target.muscleId]?.effective ?? 0)
                )
                return outstanding > (adaptedVolume[target.muscleId] ?? 0) + 1e-6
            }
            if dropped { issues.append(PlanningIssue(.missedVolumeDropped)) }
        }

        let missingSpecific = remainingSpecificTargets
            .filter { plannedSpecificExposures(preservedWeek, $0.exerciseId) < $0.desired }
            .map(\.exerciseId)
        if !missingSpecific.isEmpty {
            issues.append(PlanningIssue(
                .specificityUnavailable,
                context: ["exerciseIds": .strings(missingSpecific)]
            ))
        }
        if preservedWeek.phase == .reducedVolume { issues.append(PlanningIssue(.reducedVolume)) }
        program.diagnostics.warnings = issues

        switch result {
        case .partial: return .partial(program: program, issues: issues)
        default: return .success(program: program, issues: issues)
        }
    }

    private static func requestTree(_ request: ProgramGenerationRequest) -> JSONValue {
        .object([
            "profile": request.profile.jsonTree,
            "preferences": request.preferences.jsonTree,
            "schedule": request.schedule.jsonTree,
            "history": request.history.jsonTree,
            "now": .string(request.now),
            "readiness": request.readiness?.jsonTree ?? .null,
            "policy": request.policy?.jsonTree ?? .null,
        ])
    }
}
