import Foundation

/// Planned sessions, as the application sees them.
///
/// The deterministic engine decides what to prescribe and the immutable program
/// snapshot keeps that decision. Nothing here re-decides any of it: every value
/// below is read back out of the stored snapshot each time it is asked for.
///
/// The one thing this file does create is a *projection* — an ordinary
/// application workout carrying a `planned` reference back to the program and
/// session it stands for.
struct PlannedExercisePrescription: Hashable, Identifiable {
    var exerciseId: String
    /// Working sets only; warm-ups are prescribed too but are not the target.
    var sets: Int
    var reps: RepRange
    var rir: Double
    /// Present only where the engine could name a load from real history.
    var loadKg: Double?
    /// How that load is carried. A dumbbell prescription of 30 kg is 30 in each
    /// hand, and a plan that failed to say so would be read as half the work.
    var loadBasis: LoadBasis?
    var restSeconds: Double

    /// The rest a timer counts down when nothing was prescribed.
    static let fallbackRestSeconds: Double = 90

    var id: String { exerciseId }
}

struct PlannedSessionView: Hashable, Identifiable {
    var programId: String
    var sessionId: String
    /// Local calendar day, taken from the schedule rather than converted through
    /// a local clock, so the day a plan names is the day it shows.
    var date: String
    var title: String
    var exerciseIds: [String]
    var focus: [MuscleId]
    var workingSets: Int
    var minutes: Int
    var prescription: [PlannedExercisePrescription]

    var id: String { sessionId }
}

/// The existing profile page that owns the answer a refusal is about.
enum PlanBlockPage: String {
    case profileBasics = "profile-basics"
    case profileTraining = "profile-training"
    case profileHealth = "profile-health"
    case profileEquipment = "profile-equipment"
    case profilePriorities = "profile-priorities"
}

/// Why a week could not be built, in the words of the screen that has to say it
/// and the page that can fix it.
struct PlanBlock {
    enum Reason: String {
        case days, health, goal, equipment, duration, volume, input
    }
    var reason: Reason
    var message: String
    var page: PlanBlockPage?
    var issues: [PlanningIssue]
}

enum TrainingWeekOutcome {
    case created(programId: String, sessions: [PlannedSessionView], issues: [PlanningIssue])
    case blocked(PlanBlock)
}

@MainActor
enum TrainingPlan {
    private static let upper = Set(SplitMuscleGroups.upper)
    private static let push = Set(SplitMuscleGroups.push)
    private static let pull = Set(SplitMuscleGroups.pull)

    /// What to call a session, decided from the split the engine chose and the
    /// muscles it gave that session. Both come out of the snapshot, so the name a
    /// session carries cannot drift from the plan it belongs to.
    static func plannedSessionTitle(_ split: String, _ focus: [MuscleId]) -> String {
        guard !focus.isEmpty else { return "Session" }
        func every(_ group: Set<MuscleId>) -> Bool { focus.allSatisfy(group.contains) }
        if split == "upper_lower" { return every(upper) ? "Upper" : "Lower" }
        if split == "push_pull_legs" {
            if every(push) { return "Push" }
            return every(pull) ? "Pull" : "Legs"
        }
        return "Full body"
    }

    private static func prescription(_ session: PlannedSession) -> [PlannedExercisePrescription] {
        session.exercises
            .sorted { $0.order < $1.order }
            .map { exercise in
                let first = exercise.workingSets.first
                return PlannedExercisePrescription(
                    exerciseId: exercise.exerciseId,
                    sets: exercise.workingSets.count,
                    reps: first?.targetReps ?? RepRange(min: 0, max: 0),
                    rir: first?.targetRir ?? 0,
                    loadKg: first?.resistance.kg,
                    loadBasis: first?.resistance.basis,
                    restSeconds: exercise.restSeconds
                )
            }
    }

    private static func toView(
        _ program: TrainingProgram,
        _ session: PlannedSession
    ) -> PlannedSessionView {
        let items = prescription(session)
        return PlannedSessionView(
            programId: program.id,
            sessionId: session.id,
            date: String(session.scheduledAt.prefix(10)),
            title: plannedSessionTitle(program.diagnostics.selectedSplit, session.focus),
            exerciseIds: items.map(\.exerciseId),
            focus: session.focus,
            workingSets: items.reduce(0) { $0 + $1.sets },
            minutes: Int((session.duration.totalSeconds / 60).rounded()),
            prescription: items
        )
    }

    static func sessionViews(_ program: TrainingProgram) -> [PlannedSessionView] {
        program.weeks
            .flatMap(\.sessions)
            .sorted { $0.scheduledAt.compare($1.scheduledAt) == .orderedAscending }
            .map { toView(program, $0) }
    }

    static func activeProgramRecord(
        _ data: PersistedTrainingState? = nil
    ) -> PersistedProgramRecord? {
        let data = data ?? TrainingRecordsStore.shared.data
        guard let activeProgramId = data.activeProgramId else { return nil }
        return data.programs.first { $0.id == activeProgramId }
    }

    /// Every planned session of the active program, oldest first.
    static func activePlannedSessions(
        _ data: PersistedTrainingState? = nil
    ) -> [PlannedSessionView] {
        let data = data ?? TrainingRecordsStore.shared.data
        guard let record = activeProgramRecord(data) else { return [] }
        return sessionViews(ProgramRecords.toEngineProgram(record.snapshot)).filter {
            !ProgramRecords.isSupersededPlannedSession(data, record.id, $0.sessionId)
        }
    }

    /// One planned session, read straight back out of its own program snapshot.
    static func plannedSessionView(
        _ programId: String,
        _ sessionId: String,
        _ data: PersistedTrainingState? = nil
    ) -> PlannedSessionView? {
        let data = data ?? TrainingRecordsStore.shared.data
        guard let planned = ProgramRecords.plannedSession(data, programId, sessionId) else { return nil }
        return toView(planned.program, planned.session)
    }

    /// Whether the structured history already holds this planned session.
    static func isPlannedSessionRecorded(
        _ sessionId: String,
        _ data: PersistedTrainingState? = nil
    ) -> Bool {
        let data = data ?? TrainingRecordsStore.shared.data
        return data.sessions.contains { $0.plannedSessionId == sessionId }
    }

    static func plannedWorkoutFor(
        programId: String,
        sessionId: String,
        workouts: [Workout]? = nil
    ) -> Workout? {
        let workouts = workouts ?? WorkoutsStore.shared.workouts
        return workouts.first {
            $0.planned?.programId == programId && $0.planned?.sessionId == sessionId
        }
    }

    /// The application workout a planned session is performed through, created if
    /// it is not there yet. The projection holds only what the existing screens
    /// need to route and draw; the prescription itself stays in the snapshot.
    @discardableResult
    static func ensurePlannedWorkout(_ view: PlannedSessionView) -> String {
        if let existing = plannedWorkoutFor(programId: view.programId, sessionId: view.sessionId) {
            return existing.id
        }
        return WorkoutsStore.shared.createWorkout(
            name: view.title,
            date: view.date,
            exerciseIds: view.exerciseIds,
            planned: PlannedWorkoutReference(
                programId: view.programId, sessionId: view.sessionId
            )
        )
    }

    /// Projects every session of a program in one pass, so a freshly created week
    /// is on the workout list before anybody taps anything.
    @discardableResult
    static func projectPlannedWorkouts(_ views: [PlannedSessionView]) -> [String] {
        views.map(ensurePlannedWorkout)
    }

    private static let issueBlocks: [PlanningIssueCode: (PlanBlock.Reason, String, PlanBlockPage?)] = [
        .unsupportedPopulation: (
            .health,
            "Your health answers mean I do not program automatically. "
                + "Update them, or build the workout yourself.",
            .profileHealth
        ),
        .unsupportedGoal: (
            .goal, "I cannot plan for that training goal. Pick another one.", .profileTraining
        ),
        .noValidExercises: (
            .equipment,
            "Your plan needs an equipment update before I can build it. "
                + "Nothing saved covers a full session.",
            .profileEquipment
        ),
        .unavailableEquipment: (
            .equipment,
            "Your plan needs an equipment update before I can build it.",
            .profileEquipment
        ),
        .sessionDurationInfeasible: (
            .duration,
            "There is not enough time in a session for this week. "
                + "Allow more minutes, or fewer days.",
            .profileTraining
        ),
        .volumeLimit: (
            .volume,
            "The volume this asks for leaves no room for a week that works. "
                + "Ease your priorities and ask again.",
            .profilePriorities
        ),
    ]

    /// Turns the engine's own refusal into one thing to say and one place to fix
    /// it. Nothing is guessed and no weaker plan is offered in its place.
    static func toPlanBlock(_ issues: [PlanningIssue]) -> PlanBlock {
        for issue in issues {
            if let known = issueBlocks[issue.code] {
                return PlanBlock(
                    reason: known.0, message: known.1, page: known.2, issues: issues
                )
            }
        }
        return PlanBlock(
            reason: .input,
            message: "I could not build a week from what I know. "
                + "Check your training profile and try again.",
            page: .profileTraining,
            issues: issues
        )
    }

    /// Creates one plan from exact calendar dates. Dates may span several weeks;
    /// each week is solved by the engine, then stored as one immutable plan.
    /// Nil when the caller went away before the plan was ready; nothing is
    /// saved then.
    static func createTrainingPlanForDates(
        dates rawDates: [String],
        now: String? = nil,
        sourceProgramId: String? = nil
    ) async -> TrainingWeekOutcome? {
        guard let outcome = await previewTrainingPlanForDates(
            dates: rawDates, now: now, sourceProgramId: sourceProgramId
        ) else { return nil }
        switch outcome {
        case .blocked(let block):
            return .blocked(block)
        case .ready(let preview):
            do {
                let sessions = try commit(preview)
                let programId = sessions.first?.programId ?? preview.program.id
                return .created(programId: programId, sessions: sessions, issues: preview.issues)
            } catch {
                return .blocked(PlanBlock(
                    reason: .input,
                    message: (error as? TrainingPersistenceError)?.message
                        ?? "The plan could not be saved.",
                    page: nil,
                    issues: []
                ))
            }
        }
    }

    /// The same plan `createTrainingPlanForDates` would keep, built but not kept.
    /// Nil when the caller went away before the plan was ready.
    static func previewTrainingPlanForDates(
        dates rawDates: [String],
        now: String? = nil,
        sourceProgramId: String? = nil,
        readiness: Readiness? = nil,
        overrides: TrainingEngineAdapter.PreferenceOverrides = .init()
    ) async -> PlanPreviewOutcome? {
        let now = now ?? ISOTime.now()
        let basis = PlanBasis.current(now: now, readiness: readiness)
        // The person's own today: the dates they picked are local days.
        let today = ISOTime.localDay(now)
        var seen = Set<String>()
        let dates = rawDates
            .filter { date in
                date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
                    && date >= today
                    && seen.insert(date).inserted
            }
            .sorted()

        guard !dates.isEmpty else {
            return .blocked(PlanBlock(
                reason: .days,
                message: "Pick at least one training date.",
                page: nil,
                issues: []
            ))
        }

        var groupOrder: [String] = []
        var groups: [String: [String]] = [:]
        for date in dates {
            let monday = EngineWorkout.mondayFor(date)
            if groups[monday] == nil { groupOrder.append(monday) }
            groups[monday, default: []].append(date)
        }

        // Requests are read from the stores here; the engine's search — seconds
        // of work — runs off the main actor, one week after another.
        let requests = groupOrder.map { weekStart -> ProgramGenerationRequest in
            let weekDates = groups[weekStart] ?? []
            let weekStartMillis = ISOTime.parse(weekStart) ?? 0
            let offsets = weekDates.map { date -> Int in
                let at = ISOTime.parse("\(date)T00:00:00.000Z") ?? 0
                return Int(((at - weekStartMillis) / DAY_MS).rounded())
            }
            return PlanGeneration.request(
                weekStart: weekStart, offsets: offsets, now: now,
                readiness: readiness, overrides: overrides
            )
        }
        guard let results = await PlanGeneration.generate(requests) else { return nil }

        var programs: [TrainingProgram] = []
        var issues: [PlanningIssue] = []
        for result in results {
            guard let program = result.program else { return .blocked(toPlanBlock(result.issues)) }
            programs.append(program)
            issues += result.issues
        }

        guard var program = programs.first else {
            return .blocked(toPlanBlock([]))
        }
        program.id = "program-\(UUID().uuidString.lowercased())"
        program.generatedAt = now
        program.weeks = programs.enumerated().compactMap { index, item -> TrainingWeek? in
            guard var week = item.weeks.first else { return nil }
            let oldWeekId = week.id
            week.id = "week-\(index)"
            for sessionIndex in week.sessions.indices {
                let oldSessionId = week.sessions[sessionIndex].id
                let newSessionId = "\(week.id)/session-\(sessionIndex)"
                week.sessions[sessionIndex].id = newSessionId
                for exerciseIndex in week.sessions[sessionIndex].exercises.indices {
                    func rename(_ id: String) -> String {
                        id.replacingOccurrences(of: oldSessionId, with: newSessionId)
                            .replacingOccurrences(of: oldWeekId, with: week.id)
                    }
                    for setIndex in week.sessions[sessionIndex]
                        .exercises[exerciseIndex].workingSets.indices {
                        let current = week.sessions[sessionIndex]
                            .exercises[exerciseIndex].workingSets[setIndex].id
                        week.sessions[sessionIndex]
                            .exercises[exerciseIndex].workingSets[setIndex].id = rename(current)
                    }
                    for setIndex in week.sessions[sessionIndex]
                        .exercises[exerciseIndex].warmupSets.indices {
                        let current = week.sessions[sessionIndex]
                            .exercises[exerciseIndex].warmupSets[setIndex].id
                        week.sessions[sessionIndex]
                            .exercises[exerciseIndex].warmupSets[setIndex].id = rename(current)
                    }
                }
            }
            return week
        }
        program.durationWeeks = program.weeks.count
        Generate.namespaceProgramIds(&program, program.id)

        return .ready(PlanPreview(
            kind: .newPlan,
            program: program,
            sessions: sessionViews(program),
            issues: issues,
            sourceProgramId: sourceProgramId,
            basis: basis
        ))
    }

    /// Keeps a previewed plan: saved as the active program, its sessions put on
    /// the workout list. Keeping the same preview twice changes nothing more.
    @discardableResult
    static func commit(_ preview: PlanPreview) throws -> [PlannedSessionView] {
        let store = TrainingRecordsStore.shared
        switch preview.kind {
        case .newPlan:
            // A new plan takes over from its first day. The current plan's
            // sessions before that are carried into it unchanged, the ones from
            // then on are withdrawn, and nothing already trained is touched —
            // so no old session lingers as a workout from a replaced plan.
            if let active = activeProgramRecord(),
               let start = preview.sessions.map(\.date).min() {
                let pending = PlanRevision.pendingSessions(active)
                if !pending.isEmpty {
                    let replacing = Set(pending.filter { String($0.scheduledAt.prefix(10)) >= start }.map(\.id))
                    return try PlanRevision.commit(source: active, replacement: preview.program, replacing: replacing)
                }
            }
            let source = preview.sourceProgramId.flatMap { id in
                store.data.programs.first { $0.id == id }
            }
            try store.saveProgram(preview.program, manualSourceProgramId: source?.id)
        case .adjustWeek:
            // The rest of the week, reshaped: it replaces only the week's
            // remaining sessions, and every later week of the plan is carried.
            if let source = preview.sourceProgramId.flatMap({ id in store.data.programs.first { $0.id == id } }) {
                let replacing = Set(TrainingWorkflow.remainingTrainingSlots(source, ISOTime.now()).sessions.map(\.id))
                return try PlanRevision.commit(source: source, replacement: preview.program, replacing: replacing)
            }
            try store.saveProgram(preview.program)
        }
        projectPlannedWorkouts(preview.sessions)
        return preview.sessions
    }

}

/// Plan generation, split at the actor boundary: the request is read from the
/// stores on the main actor, and the engine's search runs away from it on a
/// value copy.
enum PlanGeneration {
    /// One week's request, from the profile, equipment and history as they are
    /// now.
    static func request(
        weekStart: String?,
        offsets: [Int],
        now: String,
        readiness: Readiness? = nil,
        overrides: TrainingEngineAdapter.PreferenceOverrides = .init()
    ) -> ProgramGenerationRequest {
        var request = TrainingWorkflow.buildTrainingRequest(
            TrainingEngineAdapter.buildEngineInputs(overrides: overrides),
            now: now,
            availableDays: offsets,
            readiness: readiness
        )
        if let weekStart { request.schedule.weekStart = weekStart }
        return request
    }

    /// Generates the weeks in order, stopping at the first that cannot be
    /// planned. Nil when the caller has gone.
    @concurrent
    static func generate(_ requests: [ProgramGenerationRequest]) async -> [ProgramGenerationResult]? {
        var results: [ProgramGenerationResult] = []
        for request in requests {
            if Task.isCancelled { return nil }
            let result = Generate.generateTrainingProgram(request)
            results.append(result)
            if result.program == nil { break }
        }
        return Task.isCancelled ? nil : results
    }
}
