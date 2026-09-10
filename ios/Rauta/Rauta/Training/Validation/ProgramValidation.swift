import Foundation

struct ProgramValidationContext {
    var sourceProgram: TrainingProgram?

    init(sourceProgram: TrainingProgram? = nil) {
        self.sourceProgram = sourceProgram
    }
}

struct ProgramValidationResult {
    var valid: Bool
    var issues: [PlanningIssue]
    var warnings: [PlanningIssue]
}

enum ProgramValidation {
    // swiftlint:disable:next cyclomatic_complexity
    static func validate(
        _ program: TrainingProgram,
        _ request: ProgramGenerationRequest,
        suppliedIndex: ExerciseIndex? = nil,
        context: ProgramValidationContext = ProgramValidationContext()
    ) -> ProgramValidationResult {
        let invalid = InputValidation.validateGenerationRequest(request)
        if !invalid.isEmpty { return ProgramValidationResult(valid: false, issues: invalid, warnings: []) }
        let eligibility = InputValidation.planningEligibility(request)
        if !eligibility.isEmpty {
            return ProgramValidationResult(valid: false, issues: eligibility, warnings: [])
        }

        let index = suppliedIndex ?? ExerciseData.createIndex(request.exercises, overrides: request.metadata ?? [])
        if !index.issues.isEmpty {
            return ProgramValidationResult(valid: false, issues: index.issues, warnings: [])
        }

        var issues: [PlanningIssue] = []
        var warnings: [PlanningIssue] = []
        func fail(_ path: String) { issues.append(PlanningIssue(.invalidProgram, path: path)) }

        /// A score is only trusted when its own arithmetic reproduces its total.
        func validScore(_ score: Score, _ path: String) -> Bool {
            guard score.total.isFinite else { fail(path); return false }
            var factors = Set<String>()
            var numerator = 0.0
            var denominator = 0.0
            for contribution in score.contributions {
                let malformed = contribution.factor.isEmpty
                    || factors.contains(contribution.factor)
                    || !contribution.rawValue.isFinite
                    || contribution.rawValue < 0 || contribution.rawValue > 1
                    || !contribution.weight.isFinite
                    || !contribution.contribution.isFinite
                    || abs(contribution.contribution - contribution.rawValue * contribution.weight) > 1e-9
                if malformed { fail(path); return false }
                factors.insert(contribution.factor)
                numerator += contribution.contribution
                denominator += abs(contribution.weight)
            }
            let expected = denominator > 0 ? numerator / denominator : 0
            if abs(score.total - expected) > 1e-9 { fail(path); return false }
            return true
        }

        guard !program.weeks.isEmpty, program.weeks.count <= 12,
              InputValidation.validatePolicy(program.policy).isEmpty
        else {
            return ProgramValidationResult(
                valid: false,
                issues: [PlanningIssue(.invalidProgram)],
                warnings: warnings
            )
        }

        let authoritativePolicy = request.policy ?? (program.adaptation != nil ? nil : DEFAULT_POLICY)

        let headerValid = ISOTime.valid(program.generatedAt)
            && program.generatedAt == request.now
            && program.engineVersion == ENGINE_VERSION
            && program.policyVersion == program.policy.version
            && program.durationWeeks == program.weeks.count
            && program.weeks.count == request.schedule.durationWeeks
            && program.goal == request.preferences.goal
            && program.datasetFingerprint == index.fingerprint
        if !headerValid { fail("program.header") }

        if let authoritativePolicy,
           fingerprint(program.policy.jsonTree) != fingerprint(authoritativePolicy.jsonTree) {
            fail("program.policy")
        }

        if let adaptation = program.adaptation {
            if adaptation.sourceProgramId.isEmpty
                || !ISOTime.valid(adaptation.asOf)
                || adaptation.asOf != request.now {
                fail("program.adaptation")
            }
            validateAdaptationLineage(
                program, adaptation, request, context, fail: fail
            )
        }

        let semanticRequest: ProgramGenerationRequest = {
            var updated = request
            updated.policy = program.policy
            return updated
        }()
        let initialState = TrainingStateAnalysis.analyze(
            semanticRequest, index: index, targets: [], policy: program.policy
        )
        let semanticTargets = Targets.deriveProgramTargets(semanticRequest, initialState, program.policy)
        let semanticState = TrainingStateAnalysis.analyze(
            semanticRequest, index: index, targets: semanticTargets, policy: program.policy
        )
        let semanticInput = OptimizationInput(
            request: semanticRequest,
            index: index,
            state: semanticState,
            targets: semanticTargets,
            policy: program.policy
        )

        let expectedPhase: TrainingWeek.Phase = {
            guard program.adaptation != nil else { return .base }
            let decliningCount = semanticState.exercises.values.filter { $0.trend == .declining }.count
            return (request.readiness?.perceivedReadiness == .low && decliningCount >= 2)
                ? .reducedVolume
                : .base
        }()

        let initialSplitCandidates = program.adaptation == nil
            ? Optimizer.generateSplitCandidates(semanticInput)
            : []

        var ids = Set<String>()
        func unique(_ id: String, _ path: String) {
            if id.isEmpty || ids.contains(id) { fail(path) } else { ids.insert(id) }
        }
        unique(program.id, "program.id")

        let weekStartMillis = ISOTime.parse(request.schedule.weekStart) ?? 0
        let expectedSessionCount = (request.schedule.sessionDays ?? request.schedule.days).count

        for (wi, week) in program.weeks.enumerated() {
            unique(week.id, "weeks.\(wi).id")
            if week.phase != expectedPhase { fail("weeks.\(wi).phase") }

            let weekStart = ISOTime.parse(week.start) ?? .nan
            if !ISOTime.valid(week.start)
                || weekStart != weekStartMillis + Double(wi) * 7 * DAY_MS
                || week.sessions.count != expectedSessionCount {
                fail("weeks.\(wi).schedule")
            }

            var dates: [String: Int] = [:]
            var weekInput = semanticInput
            weekInput.targets = week.targets

            for (si, session) in week.sessions.enumerated() {
                let path = "weeks.\(wi).sessions.\(si)"
                let sessionIssueStart = issues.count

                if session.focus.isEmpty
                    || Set(session.focus).count != session.focus.count
                    || session.exercises.isEmpty {
                    fail(path)
                    continue
                }
                unique(session.id, path + ".id")

                let scheduledAt = ISOTime.parse(session.scheduledAt) ?? .nan
                let dayOffset = (scheduledAt - weekStart) / DAY_MS
                let allowedRepeats = request.schedule.sessionDays?
                    .filter { Double($0) == dayOffset }.count ?? 1
                let alreadySeen = dates[session.scheduledAt] ?? 0
                if !ISOTime.valid(session.scheduledAt)
                    || alreadySeen >= allowedRepeats
                    || !request.schedule.days.contains(where: { Double($0) == dayOffset }) {
                    fail(path + ".scheduledAt")
                }
                dates[session.scheduledAt] = alreadySeen + 1

                var exercises = Set<String>()
                for (ei, planned) in session.exercises.enumerated() {
                    guard let record = index.byId[planned.exerciseId] else {
                        issues.append(PlanningIssue(.unknownExercise, path: path))
                        continue
                    }
                    issues += ExerciseData.exclusionReasons(record, request.preferences, program.policy)
                    if !validScore(planned.rationale, path + ".rationale") { continue }

                    if exercises.contains(planned.exerciseId)
                        || planned.order != ei
                        || planned.workingSets.count < 1
                        || planned.workingSets.count > program.policy.maxSetsPerExercise
                        || !Num.isFinite(planned.restSeconds, min: 30, max: 900) {
                        fail(path + ".exercise")
                    }
                    exercises.insert(planned.exerciseId)

                    let expected = Prescribe.exercise(
                        record,
                        count: planned.workingSets.count,
                        sessionId: session.id,
                        rationale: planned.rationale,
                        input: weekInput
                    )
                    if prescriptionFingerprint(planned) != prescriptionFingerprint(expected) {
                        fail(path + ".prescription")
                    }

                    for (kind, sets) in [("working", planned.workingSets), ("warmup", planned.warmupSets)] {
                        for set in sets {
                            unique(set.id, path + ".set.id")
                            let typeValid = kind == "warmup"
                                ? set.setType == .warmup
                                : (set.setType == .working || set.setType == .backoff)
                            let repsValid = Num.isFinite(set.targetReps.min, min: 1, max: 50)
                                && set.targetReps.min == set.targetReps.min.rounded()
                                && Num.isFinite(set.targetReps.max, min: set.targetReps.min, max: 50)
                                && set.targetReps.max == set.targetReps.max.rounded()
                            if !repsValid
                                || !Num.isFinite(set.targetRir, min: 0, max: 10)
                                || !InputValidation.validResistance(set.resistance)
                                || set.side != "both"
                                || !typeValid {
                                fail(path + ".set")
                                continue
                            }

                            let resistance = set.resistance
                            if resistance.type == .externalLoad || resistance.type == .assistance {
                                let grid = request.preferences.loadGrids?[planned.exerciseId]
                                let loadContext = request.preferences.loadContexts?[planned.exerciseId]
                                let achievable = grid.flatMap { grid in
                                    resistance.kg.map { Progression.isAchievableLoad($0, grid) }
                                } ?? false
                                if grid == nil
                                    || !achievable
                                    || loadContext == nil
                                    || loadContext?.stationId != resistance.stationId
                                    || loadContext?.basis != resistance.basis
                                    || record.metadata.tracking.rawValue != resistance.type.rawValue {
                                    fail(path + ".load")
                                }
                            }
                        }
                    }
                }

                // Only evaluate well-shaped prescriptions.
                if issues.count == sessionIssueStart {
                    let renumbered = session.exercises.enumerated().map { order, exercise -> PlannedExercise in
                        var updated = exercise
                        updated.order = order
                        return updated
                    }
                    let expectedOrder = Scoring.orderExercises(renumbered, weekInput).map(\.exerciseId)
                    if expectedOrder != session.exercises.map(\.exerciseId) { fail(path + ".order") }

                    let duration = SessionTiming.estimateSession(session.exercises, index, program.policy)
                    if duration.totalSeconds != session.duration.totalSeconds
                        || !duration.totalSeconds.isFinite {
                        fail(path + ".duration")
                    }
                    if duration.totalSeconds > request.preferences.maxSessionDurationMinutes * 60 {
                        issues.append(PlanningIssue(
                            .sessionDurationInfeasible,
                            path: path,
                            context: ["seconds": .number(duration.totalSeconds)]
                        ))
                    }
                }
            }

            if program.adaptation == nil {
                let focus = week.sessions.map(\.focus)
                let matchingSplits = initialSplitCandidates.filter { candidate in
                    candidate.sessions.map(\.focus) == focus
                }
                if matchingSplits.isEmpty { fail("weeks.\(wi).focus") }
                if wi == 0, !matchingSplits.contains(where: { $0.name == program.diagnostics.selectedSplit }) {
                    fail("program.diagnostics.selectedSplit")
                }
            }
        }

        if issues.isEmpty && program.adaptation == nil {
            let initial = TrainingStateAnalysis.analyze(request, index: index, targets: [], policy: program.policy)
            let expectedTargets = Targets.deriveProgramTargets(request, initial, program.policy)
            for (wi, week) in program.weeks.enumerated() {
                if week.targets.count != expectedTargets.count {
                    fail("weeks.\(wi).targets")
                    continue
                }
                for expected in expectedTargets {
                    guard let actual = week.targets.first(where: { $0.muscleId == expected.muscleId }),
                          actual == expected
                    else {
                        fail("weeks.\(wi).targets.\(expected.muscleId.rawValue)")
                        continue
                    }
                }
            }
        }

        if issues.isEmpty {
            if validScore(program.diagnostics.score, "program.diagnostics.score") {
                var firstWeekInput = semanticInput
                firstWeekInput.targets = program.weeks[0].targets
                let expectedScore = Scoring.scoreWeek(program.weeks[0], firstWeekInput)
                if fingerprint(program.diagnostics.score.jsonTree) != fingerprint(expectedScore.jsonTree) {
                    fail("program.diagnostics.score")
                }
            }

            let volumes = Volume.programVolume(program, index)
            let frequencies = Volume.programFrequency(program, index)

            for (wi, week) in program.weeks.enumerated() {
                var baseline: MuscleVolumeMap?
                var completedSets = 0.0
                if let adaptation = program.adaptation, adaptation.mode == .remainingWeek {
                    let start = ISOTime.parse(week.start) ?? 0
                    let asOf = ISOTime.parse(adaptation.asOf) ?? 0
                    baseline = Volume.historyVolume(
                        request.history, index, program.policy,
                        from: start, to: asOf, inclusiveStart: true
                    )
                    completedSets = request.history.sessions
                        .filter { session in
                            let at = ISOTime.parse(session.completedAt) ?? .nan
                            return at >= start && at <= asOf
                        }
                        .reduce(0.0) { total, session in
                            total + session.exercises.reduce(0.0) { exerciseTotal, exercise in
                                exerciseTotal + exercise.sets.reduce(0.0) {
                                    $0 + Volume.completedWorkingSetUnits($1)
                                }
                            }
                        }
                }

                let plannedSets = week.sessions.reduce(0) { total, session in
                    total + session.exercises.reduce(0) { $0 + $1.workingSets.count }
                }
                let sets = completedSets + Double(plannedSets)
                if let maxSets = request.preferences.maxWeeklyWorkingSets, sets > maxSets {
                    issues.append(PlanningIssue(.volumeLimit, path: "weeks.\(wi)"))
                }

                for bound in request.preferences.muscleVolumeBounds ?? [] {
                    let value = (volumes[wi].muscles[bound.muscleId]?.effective ?? 0)
                        + (baseline?[bound.muscleId]?.effective ?? 0)
                    let belowMinimum = value < (bound.minimum ?? 0) - 1e-6
                    let aboveMaximum = bound.maximum.map { value > $0 + 1e-6 } ?? false
                    if belowMinimum || aboveMaximum {
                        issues.append(PlanningIssue(
                            .volumeLimit,
                            context: [
                                "muscleId": .string(bound.muscleId.rawValue),
                                "volume": .number(value),
                            ]
                        ))
                    }
                }

                for target in week.targets {
                    guard Num.isFinite(target.minimum),
                          Num.isFinite(target.preferred, min: target.minimum),
                          Num.isFinite(target.upperGuideline, min: target.preferred),
                          let entry = volumes[wi].muscles[target.muscleId]
                    else {
                        fail("weeks.\(wi).targets")
                        continue
                    }
                    let volume = entry.effective
                    if volume < target.preferred - 1e-6 {
                        warnings.append(PlanningIssue(
                            .volumeBelowTarget,
                            path: "weeks.\(wi)",
                            context: [
                                "muscleId": .string(target.muscleId.rawValue),
                                "preferred": .number(target.preferred),
                                "actual": .number(volume),
                            ]
                        ))
                    }
                    if volume > target.upperGuideline + 1e-6 {
                        warnings.append(PlanningIssue(
                            .volumeLimit,
                            path: "weeks.\(wi)",
                            context: [
                                "muscleId": .string(target.muscleId.rawValue),
                                "upperGuideline": .number(target.upperGuideline),
                                "actual": .number(volume),
                            ]
                        ))
                    }
                    if (frequencies[wi].muscles[target.muscleId] ?? 0) < target.preferredExposures {
                        warnings.append(PlanningIssue(
                            .frequencyBelowTarget,
                            context: ["muscleId": .string(target.muscleId.rawValue)]
                        ))
                    }
                }
            }
        }

        _ = semanticInput
        return ProgramValidationResult(valid: issues.isEmpty, issues: issues, warnings: warnings)
    }

    /// The prescription fields a program is allowed to be re-derived against;
    /// order and rationale are checked separately.
    private static func prescriptionFingerprint(_ planned: PlannedExercise) -> String {
        fingerprint(.object([
            "exerciseId": .string(planned.exerciseId),
            "workingSets": .array(planned.workingSets.map { $0.jsonTree }),
            "warmupSets": .array(planned.warmupSets.map { $0.jsonTree }),
            "restSeconds": .number(planned.restSeconds),
            "targetMuscles": .array(planned.targetMuscles.map { .string($0.rawValue) }),
            "progression": planned.progression.jsonTree,
        ]))
    }

    private static func validateAdaptationLineage(
        _ program: TrainingProgram,
        _ adaptation: ProgramAdaptation,
        _ request: ProgramGenerationRequest,
        _ context: ProgramValidationContext,
        fail: (String) -> Void
    ) {
        guard let sourceProgram = context.sourceProgram else { return }

        let sourceInvalid = sourceProgram.id != adaptation.sourceProgramId
            || !InputValidation.validatePolicy(sourceProgram.policy).isEmpty
            || sourceProgram.policyVersion != program.policyVersion
            || fingerprint(sourceProgram.policy.jsonTree) != fingerprint(program.policy.jsonTree)
            || sourceProgram.datasetFingerprint != program.datasetFingerprint
            || sourceProgram.weeks.isEmpty
        if sourceInvalid {
            fail("program.adaptation.source")
            return
        }

        let adaptedWeek = program.weeks.first
        let sourceWeek = adaptation.mode == .remainingWeek
            ? sourceProgram.weeks.first { $0.start == adaptedWeek?.start }
            : sourceProgram.weeks.last
        guard let adaptedWeek, let sourceWeek else {
            fail("program.adaptation.lineage")
            return
        }

        let asOf = ISOTime.parse(adaptation.asOf) ?? 0
        let sourceStart = ISOTime.parse(sourceWeek.start) ?? 0
        let adaptedStart = ISOTime.parse(adaptedWeek.start) ?? 0

        let lineageBroken: Bool = {
            if adaptation.mode == .remainingWeek {
                return adaptedStart != sourceStart
                    || asOf < sourceStart
                    || asOf >= sourceStart + 7 * DAY_MS
                    || adaptedWeek.sessions.contains { (ISOTime.parse($0.scheduledAt) ?? 0) <= asOf }
            }
            return adaptedStart != sourceStart + 7 * DAY_MS || asOf >= adaptedStart
        }()
        if lineageBroken { fail("program.adaptation.lineage") }

        let sourceSessions = Dictionary(
            sourceWeek.sessions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for completed in request.history.sessions {
            guard let plannedSessionId = completed.plannedSessionId else { continue }
            let completedAt = ISOTime.parse(completed.completedAt) ?? .nan
            if completedAt < sourceStart || completedAt >= sourceStart + 7 * DAY_MS { continue }
            guard let plannedSession = sourceSessions[plannedSessionId] else {
                fail("program.adaptation.completedLineage")
                continue
            }
            for completedExercise in completed.exercises {
                let plannedExercise = plannedSession.exercises.first {
                    $0.exerciseId == completedExercise.exerciseId
                }
                for completedSet in completedExercise.sets {
                    guard let plannedSetId = completedSet.plannedSetId else { continue }
                    let plannedSets = plannedExercise.map { $0.workingSets + $0.warmupSets } ?? []
                    if !plannedSets.contains(where: { $0.id == plannedSetId }) {
                        fail("program.adaptation.completedLineage")
                    }
                }
            }
        }
    }
}
