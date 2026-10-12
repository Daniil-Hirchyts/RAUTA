import Foundation

/// Saves sessions the engine built as a revision of the active plan.
///
/// Every session of the plan still to be trained that the new sessions do not
/// replace is carried into the revision exactly as it was prescribed; the ones
/// they replace are withdrawn. Completed sessions stay in the plan they were
/// trained from, untouched. The workout list follows: a workout keeps its id
/// and is re-pointed at its session in the revision, a replaced one takes the
/// new prescription for its day, and a new day gets a workout of its own.
///
/// It is the same shape of revision a calendar edit makes (see
/// `TrainingEdits`), generalised to any number of replaced and added sessions.
@MainActor
enum PlanRevision {
    /// The sessions of `source` still to be trained: not withdrawn, not on
    /// record, not completed, and either on screen or not yet past.
    static func pendingSessions(
        _ source: PersistedProgramRecord,
        data: PersistedTrainingState? = nil,
        workouts: [Workout]? = nil,
        today: String = CalendarDate.today
    ) -> [PlannedSession] {
        let data = data ?? TrainingRecordsStore.shared.data
        let workouts = workouts ?? WorkoutsStore.shared.workouts
        return ProgramRecords.toEngineProgram(source.snapshot).weeks
            .flatMap(\.sessions)
            .filter { session in
                !ProgramRecords.isSupersededPlannedSession(data, source.id, session.id)
                    && !data.sessions.contains { $0.plannedSessionId == session.id }
                    && !workouts.contains { $0.planned?.sessionId == session.id && $0.completion != nil }
                    && (workouts.contains { $0.planned?.sessionId == session.id }
                        || String(session.scheduledAt.prefix(10)) >= today)
            }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    /// The revision `commit` would save, built and not saved: the carried and
    /// new sessions, renamed into one program.
    static func revisedProgram(
        source: PersistedProgramRecord,
        replacement: TrainingProgram,
        replacing replacedIds: Set<String>,
        pending: [PlannedSession]
    ) -> (program: TrainingProgram, renamed: [String: String]) {
        let newProgramId = "program-\(UUID().uuidString.lowercased())"
        let carried = pending.filter { !replacedIds.contains($0.id) }
        let incoming = replacement.weeks.flatMap(\.sessions)
        let template = replacement.weeks.first
        let all = (carried + incoming).sorted { left, right in
            left.scheduledAt != right.scheduledAt
                ? left.scheduledAt < right.scheduledAt
                : left.id < right.id
        }

        var weeks: [String: TrainingWeek] = [:]
        var order: [String] = []
        var renamed: [String: String] = [:]
        for var session in all {
            let start = EngineWorkout.mondayFor(String(session.scheduledAt.prefix(10)))
            if weeks[start] == nil {
                // A week's targets come from whichever program planned it.
                let owner = replacement.weeks.first { $0.start == start }
                    ?? ProgramRecords.toEngineProgram(source.snapshot).weeks.first { $0.start == start }
                    ?? template
                weeks[start] = TrainingWeek(
                    id: "\(newProgramId)/week-\(order.count)",
                    start: start,
                    phase: owner?.phase ?? .base,
                    sessions: [],
                    targets: owner?.targets ?? []
                )
                order.append(start)
            }
            guard var week = weeks[start] else { continue }
            let newId = "\(week.id)/session-\(week.sessions.count)"
            renamed[session.id] = newId
            session.id = newId
            for index in session.exercises.indices {
                let exerciseId = session.exercises[index].exerciseId
                for set in session.exercises[index].workingSets.indices {
                    session.exercises[index].workingSets[set].id = "\(newId)/\(exerciseId)/work/\(set)"
                }
                for set in session.exercises[index].warmupSets.indices {
                    session.exercises[index].warmupSets[set].id = "\(newId)/\(exerciseId)/warm/\(set)"
                }
            }
            week.sessions.append(session)
            weeks[start] = week
        }

        var program = replacement
        program.id = newProgramId
        program.generatedAt = ISOTime.now()
        program.adaptation = nil
        program.weeks = order.compactMap { weeks[$0] }
        program.durationWeeks = program.weeks.count
        return (program, renamed)
    }

    /// Saves the revision and moves the workout list onto it. Throws, and
    /// changes nothing, when the save is refused.
    @discardableResult
    static func commit(
        source: PersistedProgramRecord,
        replacement: TrainingProgram,
        replacing replacedIds: Set<String>
    ) throws -> [PlannedSessionView] {
        guard ActiveWorkoutStore.shared.session == nil,
              TrainingRecordsStore.shared.data.activeWorkout == nil
        else {
            throw TrainingPersistenceError("Finish or end your current workout before changing the plan.")
        }
        let previous = WorkoutsStore.shared.workouts
        let pending = pendingSessions(source)
        let pendingIds = Set(pending.map(\.id))
        let (program, renamed) = revisedProgram(
            source: source, replacement: replacement, replacing: replacedIds, pending: pending
        )
        let views = TrainingPlan.sessionViews(program)
        let byId = Dictionary(uniqueKeysWithValues: views.map { ($0.sessionId, $0) })
        let incomingIds = Set(replacement.weeks.flatMap(\.sessions).compactMap { renamed[$0.id] })
        let now = ISOTime.now()

        var claimed = Set<String>()
        var projected: [Workout] = []
        for workout in previous {
            guard let reference = workout.planned, reference.programId == source.id,
                  pendingIds.contains(reference.sessionId)
            else {
                projected.append(workout)
                continue
            }
            if let newId = renamed[reference.sessionId], let view = byId[newId] {
                // Carried: the same session, re-pointed.
                var updated = workout
                updated.planned = PlannedWorkoutReference(programId: program.id, sessionId: newId)
                updated.date = view.date
                updated.updatedAt = now
                claimed.insert(newId)
                projected.append(updated)
            } else if let view = views.first(where: {
                $0.date == workout.date && incomingIds.contains($0.sessionId) && !claimed.contains($0.sessionId)
            }) {
                // Replaced by a new prescription on the same day: the workout
                // stays, with what that day now holds.
                var updated = workout
                updated.planned = PlannedWorkoutReference(programId: program.id, sessionId: view.sessionId)
                updated.name = view.title
                updated.exerciseIds = view.exerciseIds
                updated.updatedAt = now
                claimed.insert(view.sessionId)
                projected.append(updated)
            }
            // Replaced with nothing on its day: the workout goes with it.
        }
        for view in views where !claimed.contains(view.sessionId)
            && !projected.contains(where: { $0.planned?.sessionId == view.sessionId }) {
            projected.append(Workout(
                id: "planned-\(view.sessionId)",
                name: view.title,
                date: view.date,
                exerciseIds: view.exerciseIds,
                completion: nil,
                createdAt: now,
                updatedAt: now,
                planned: PlannedWorkoutReference(programId: program.id, sessionId: view.sessionId)
            ))
        }

        let removed = previous.filter { old in !projected.contains { $0.id == old.id } }
        WorkoutsStore.shared.replaceAll(projected)
        do {
            try TrainingRecordsStore.shared.saveProgram(
                program,
                activate: true,
                kind: source.kind,
                manualSourceProgramId: source.id,
                replacedSessionIds: Array(pendingIds)
            )
        } catch {
            WorkoutsStore.shared.replaceAll(previous)
            throw error
        }
        // Deletions are remembered so another device's copy of the list does
        // not bring withdrawn sessions back.
        for workout in removed { WorkoutsStore.shared.rememberDeletion(workout.id) }
        return views
    }
}
