import Foundation

nonisolated enum Generate {
    static func preparation(
        _ request: ProgramGenerationRequest,
        previousProgram: TrainingProgram? = nil,
        index: ExerciseIndex? = nil
    ) -> OptimizationInput {
        let policy = request.policy ?? DEFAULT_POLICY
        let exerciseIndex = index ?? ExerciseData.createIndex(
            request.exercises,
            overrides: request.metadata ?? []
        )
        let initial = TrainingStateAnalysis.analyze(
            request, index: exerciseIndex, targets: [], policy: policy, previousProgram: previousProgram
        )
        let targets = Targets.deriveProgramTargets(request, initial, policy)
        let state = TrainingStateAnalysis.analyze(
            request, index: exerciseIndex, targets: targets, policy: policy, previousProgram: previousProgram
        )
        return OptimizationInput(
            request: request,
            index: exerciseIndex,
            state: state,
            targets: targets,
            policy: policy
        )
    }

    /// Week 0 rolled forward: the same prescription, one week later, with every
    /// identity renamed so no two weeks share a set id.
    static func replicateWeek(_ week: TrainingWeek, _ number: Int) -> TrainingWeek {
        func replace(_ id: String) -> String {
            guard let range = id.range(of: #"^week-\d+"#, options: .regularExpression) else { return id }
            return id.replacingCharacters(in: range, with: "week-\(number)")
        }

        var copy = week
        copy.id = "week-\(number)"
        copy.start = ISOTime.addDays(week.start, Double(number) * 7)
        copy.sessions = week.sessions.map { session in
            var updated = session
            updated.id = replace(session.id)
            updated.scheduledAt = ISOTime.addDays(session.scheduledAt, Double(number) * 7)
            updated.exercises = session.exercises.map { exercise in
                var planned = exercise
                planned.workingSets = exercise.workingSets.map { set in
                    var copy = set
                    copy.id = replace(set.id)
                    return copy
                }
                planned.warmupSets = exercise.warmupSets.map { set in
                    var copy = set
                    copy.id = replace(set.id)
                    return copy
                }
                return planned
            }
            return updated
        }
        return copy
    }

    static func generateTrainingProgram(
        _ request: ProgramGenerationRequest,
        optimize: ((OptimizationInput) -> OptimizationResult)? = nil,
        adaptation: ProgramAdaptation? = nil
    ) -> ProgramGenerationResult {
        let invalid = InputValidation.validateGenerationRequest(request)
        if !invalid.isEmpty { return .invalid(issues: invalid, suggestions: [.reviewInput]) }

        let unsupported = InputValidation.planningEligibility(request)
        if !unsupported.isEmpty { return .unsupported(issues: unsupported, suggestions: [.reviewInput]) }

        let input = preparation(request)
        if !input.index.issues.isEmpty {
            return .invalid(issues: input.index.issues, suggestions: [.curateMetadata])
        }

        let result = (optimize ?? Optimizer.optimize)(input)
        guard let baseWeek = result.week else {
            let hasVolumeLimits = (request.preferences.muscleVolumeBounds?.isEmpty == false)
                || request.preferences.maxWeeklyWorkingSets != nil
            let code: PlanningIssueCode = result.candidates > 0
                ? (hasVolumeLimits ? .volumeLimit : .sessionDurationInfeasible)
                : .noValidExercises
            return .infeasible(
                issues: [PlanningIssue(code, context: ["candidates": .number(Double(result.candidates))])],
                suggestions: [.addEquipment, .increaseDuration, .relaxVolumeBounds]
            )
        }

        let weeks = (0..<request.schedule.durationWeeks).map { replicateWeek(baseWeek, $0) }

        var scoreInput = input
        scoreInput.targets = baseWeek.targets

        var program = TrainingProgram(
            id: "program-" + programFingerprint(request, input),
            engineVersion: ENGINE_VERSION,
            policyVersion: input.policy.version,
            policy: input.policy,
            datasetFingerprint: input.index.fingerprint,
            generatedAt: request.now,
            goal: request.preferences.goal,
            durationWeeks: weeks.count,
            weeks: weeks,
            diagnostics: ProgramDiagnostics(
                splits: result.splits,
                candidateCount: result.candidates,
                optimizerIterations: result.iterations,
                selectedSplit: result.split,
                score: Scoring.scoreWeek(baseWeek, scoreInput),
                warnings: []
            ),
            adaptation: adaptation
        )
        namespaceProgramIds(&program, program.id)

        let validation = ProgramValidation.validate(program, request, suppliedIndex: input.index)
        if !validation.valid {
            return .infeasible(issues: validation.issues, suggestions: [.reviewInput, .relaxVolumeBounds])
        }

        var issues = input.state.issues + validation.warnings

        var missingLoads: [String] = []
        var seenMissing = Set<String>()
        for week in program.weeks {
            for session in week.sessions {
                for exercise in session.exercises where exercise.progression.action == .calibrate {
                    if seenMissing.insert(exercise.exerciseId).inserted {
                        missingLoads.append(exercise.exerciseId)
                    }
                }
            }
        }
        if !missingLoads.isEmpty {
            issues.append(PlanningIssue(
                .insufficientHistoryForLoad,
                context: ["exerciseIds": .strings(missingLoads)]
            ))
        }

        let selectedIds = Set(program.weeks.flatMap { week in
            week.sessions.flatMap { $0.exercises.map(\.exerciseId) }
        })
        let missingSpecific = (request.preferences.strengthExerciseIds ?? [])
            .filter { !selectedIds.contains($0) }
        if !missingSpecific.isEmpty {
            issues.append(PlanningIssue(
                .specificityUnavailable,
                context: ["exerciseIds": .strings(missingSpecific)]
            ))
        }

        program.diagnostics.warnings = issues

        let partialCodes: Set<PlanningIssueCode> = [
            .volumeBelowTarget, .frequencyBelowTarget, .specificityUnavailable, .volumeLimit,
        ]
        let partial = issues.contains { partialCodes.contains($0.code) }
        return partial ? .partial(program: program, issues: issues) : .success(program: program, issues: issues)
    }

    private static func programFingerprint(
        _ request: ProgramGenerationRequest,
        _ input: OptimizationInput
    ) -> String {
        var sortedSchedule = request.schedule
        sortedSchedule.days = request.schedule.days.sorted()
        var sortedHistory = request.history
        sortedHistory.sessions = request.history.sessions.sorted { compareIds($0.id, $1.id) < 0 }

        let requestTree = JSONValue.object([
            "profile": request.profile.jsonTree,
            "preferences": request.preferences.jsonTree,
            "schedule": sortedSchedule.jsonTree,
            "history": sortedHistory.jsonTree,
            "now": .string(request.now),
            "readiness": request.readiness?.jsonTree ?? .null,
            "policy": request.policy?.jsonTree ?? .null,
        ])

        return fingerprint(.object([
            "request": requestTree,
            "policy": input.policy.jsonTree,
            "index": .string(input.index.fingerprint),
        ]))
    }

    /// Scope planned identities to a revision, so historical matches cannot
    /// cross programs.
    static func namespaceProgramIds(_ program: inout TrainingProgram, _ id: String) {
        func scoped(_ value: String) -> String {
            guard let range = value.range(of: "week-") else { return id + "/" + value }
            return id + "/" + String(value[range.lowerBound...])
        }

        program.id = id
        for weekIndex in program.weeks.indices {
            program.weeks[weekIndex].id = scoped(program.weeks[weekIndex].id)
            for sessionIndex in program.weeks[weekIndex].sessions.indices {
                program.weeks[weekIndex].sessions[sessionIndex].id =
                    scoped(program.weeks[weekIndex].sessions[sessionIndex].id)
                for exerciseIndex in program.weeks[weekIndex].sessions[sessionIndex].exercises.indices {
                    for setIndex in program.weeks[weekIndex].sessions[sessionIndex]
                        .exercises[exerciseIndex].workingSets.indices {
                        let current = program.weeks[weekIndex].sessions[sessionIndex]
                            .exercises[exerciseIndex].workingSets[setIndex].id
                        program.weeks[weekIndex].sessions[sessionIndex]
                            .exercises[exerciseIndex].workingSets[setIndex].id = scoped(current)
                    }
                    for setIndex in program.weeks[weekIndex].sessions[sessionIndex]
                        .exercises[exerciseIndex].warmupSets.indices {
                        let current = program.weeks[weekIndex].sessions[sessionIndex]
                            .exercises[exerciseIndex].warmupSets[setIndex].id
                        program.weeks[weekIndex].sessions[sessionIndex]
                            .exercises[exerciseIndex].warmupSets[setIndex].id = scoped(current)
                    }
                }
            }
        }
    }
}
