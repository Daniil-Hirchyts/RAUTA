import Foundation

/// A change RAUTA proposes and nobody has kept yet: what it would do, why, and
/// which workouts it touches.
struct CoachingProposal: Identifiable {
    enum Kind: Equatable { case nextWeek, moveMissed, foldMissed, shorter, equipment }

    enum Action {
        /// Sessions the engine built, saved as a revision of `source` that
        /// replaces `replacing` and carries every other pending session over.
        case revise(source: PersistedProgramRecord, replacement: TrainingProgram, replacing: Set<String>)
        /// A first plan, when there is none to revise.
        case newPlan(PlanPreview)
        /// One workout moved to another day; nothing else changes.
        case reschedule(workoutId: String, date: String)
    }

    let id = UUID()
    var kind: Kind
    var title: String
    var summary: String
    /// What a person should know before keeping it: evidence that is thin,
    /// work that did not fit, muscles nothing they have reaches.
    var notes: [String]
    var changes: [PlanSessionChange]
    var action: Action
    var basis: PlanBasis
    /// Completed sessions this week, which no change touches.
    var completedThisWeek: Int

    func isCurrent() -> Bool { basis == PlanBasis.current(readiness: basis.readiness) }
}

/// What a kept proposal changed, to put back exactly — if nothing has changed
/// since.
struct CoachingUndo {
    var title: String
    var recordsBefore: PersistedTrainingState
    var workoutsBefore: [Workout]
    var recordsAfter: PersistedTrainingState
    var workoutsAfter: [Workout]
}

/// The three coaching features' planning — the week ahead and adjustments to
/// this one — built on the engine and explained from its decisions. Nothing is
/// saved until a proposal is applied.
@MainActor
enum CoachingPlanner {
    enum WeekChoice: Equatable {
        /// The engine week after the last one the plan already covers.
        case nextWeek
        /// What is left of this week, from tomorrow.
        case restOfThisWeek
    }

    // MARK: A. My next week

    /// The dates "my next week" would plan for each choice, from the days the
    /// person trains. The week after the plan's own last week when the plan
    /// already reaches into next week.
    static func nextWeekDates(
        _ choice: WeekChoice,
        today: String = CalendarDate.today,
        trainingDays: [Int] = TrainingProfileStore.shared.profile.effectiveTrainingDays
    ) -> [String] {
        let days = Set(trainingDays)
        switch choice {
        case .restOfThisWeek:
            let sunday = CalendarDate.shift(WeekProgress.mondayOf(today), by: 6)
            var dates: [String] = []
            var date = CalendarDate.shift(today, by: 1)
            while date <= sunday {
                if days.contains(PlanStart.isoWeekday(date)) { dates.append(date) }
                date = CalendarDate.shift(date, by: 1)
            }
            return dates
        case .nextWeek:
            var monday = CalendarDate.shift(WeekProgress.mondayOf(today), by: 7)
            if let active = TrainingPlan.activeProgramRecord() {
                let covered = Set(PlanRevision.pendingSessions(active).map {
                    WeekProgress.mondayOf(String($0.scheduledAt.prefix(10)))
                })
                while covered.contains(monday) { monday = CalendarDate.shift(monday, by: 7) }
            }
            return (0..<7).map { CalendarDate.shift(monday, by: $0) }.filter { days.contains(PlanStart.isoWeekday($0)) }
        }
    }

    static func previewNextWeek(dates rawDates: [String], now: String = ISOTime.now()) async throws -> CoachingProposal {
        let dates = Array(Set(rawDates)).sorted()
        guard let first = dates.first else {
            throw TrainingPersistenceError("Pick at least one day to train.")
        }
        guard ActiveWorkoutStore.shared.session == nil else {
            throw TrainingPersistenceError("Finish your current workout first, then plan the week.")
        }
        let basis = PlanBasis.current(now: now)
        let weekStart = WeekProgress.mondayOf(first)
        guard dates.allSatisfy({ WeekProgress.mondayOf($0) == weekStart }) else {
            throw TrainingPersistenceError("Choose days within one week.")
        }

        guard let active = TrainingPlan.activeProgramRecord() else {
            // Nothing to carry on from: a first plan, from the profile.
            guard let outcome = await TrainingPlan.previewTrainingPlanForDates(dates: dates, now: now) else {
                throw CancellationError()
            }
            switch outcome {
            case .blocked(let block): throw TrainingPersistenceError(block.message)
            case .ready(let preview):
                let context = PlanChanges.currentContext()
                let changes = PlanChanges.compare(
                    before: [], after: preview.program.weeks.flatMap(\.sessions),
                    afterProgram: preview.program, context: context, pairByDate: true
                )
                var notes = ["Built from your profile: there's no logged training to tailor it to yet, so first loads are calibration suggestions."]
                notes += coverageNotes(preview.program)
                return CoachingProposal(
                    kind: .nextWeek,
                    title: "Your week",
                    summary: "\(Wording.countLabel(preview.sessions.count, "session")): \(PlanStart.describe(dates)).",
                    notes: notes, changes: changes, action: .newPlan(preview), basis: basis,
                    completedThisWeek: WeekProgress.current().completed
                )
            }
        }

        let previous = ProgramRecords.toEngineProgram(active.snapshot)
        let setup = TrainingEngineAdapter.buildEngineInputs()
        var request = TrainingWorkflow.buildTrainingRequest(
            setup, now: now, source: active,
            availableDays: offsets(dates, from: weekStart),
            adaptationMode: .nextWeek
        )
        request.schedule.weekStart = "\(weekStart)T00:00:00.000Z"
        request.schedule.days = offsets(dates, from: weekStart)
        let result = try await adapt(AdaptationRequest(previousProgram: previous, request: request, mode: .nextWeek))
        try Task.checkCancellation()
        let program: TrainingProgram
        if let adapted = result.program {
            program = adapted
        } else if result.issues.contains(where: { $0.code == .invalidProgram }) {
            // A plan the engine can't continue from (an old or hand-edited
            // shape): a fresh week from the same profile and history instead,
            // which still favours exercises with logged history.
            guard let outcome = await TrainingPlan.previewTrainingPlanForDates(dates: dates, now: now) else {
                throw CancellationError()
            }
            switch outcome {
            case .blocked(let block): throw TrainingPersistenceError(block.message)
            case .ready(let preview): program = preview.program
            }
        } else {
            throw TrainingPersistenceError(TrainingPlan.toPlanBlock(result.issues).message)
        }

        let lastWeek = previous.weeks.last?.sessions ?? []
        let context = PlanChanges.currentContext()
        let changes = PlanChanges.compare(
            before: lastWeek, after: program.weeks.flatMap(\.sessions),
            afterProgram: program, context: context, pairByDate: false
        )
        var notes = evidenceNotes(lastWeek, weekStart: previous.weeks.last?.start, history: request.history)
        notes += durationNotes(program)
        notes += coverageNotes(program)
        let keptExercises = Set(lastWeek.flatMap { $0.exercises.map(\.exerciseId) })
            .intersection(program.weeks.flatMap(\.sessions).flatMap { $0.exercises.map(\.exerciseId) })
        let progressed = program.weeks.flatMap(\.sessions).flatMap(\.exercises)
            .contains { $0.progression.action != .calibrate && $0.progression.action != .hold }
        var summary = "\(Wording.countLabel(program.weeks.flatMap(\.sessions).count, "session")) on \(PlanStart.describe(dates))."
        let nextMonday = CalendarDate.shift(WeekProgress.mondayOf(CalendarDate.today), by: 7)
        if weekStart > nextMonday {
            summary += " Your plan already runs to \(CalendarDate.short(CalendarDate.shift(weekStart, by: -1))), so this is the week after."
        }
        if !keptExercises.isEmpty {
            summary += " \(Wording.countLabel(keptExercises.count, "exercise")) carried on from the week before"
            summary += progressed ? ", with loads progressed where your log supports it." : "."
        }
        return CoachingProposal(
            kind: .nextWeek,
            title: "Your next week",
            summary: summary,
            notes: notes, changes: changes,
            action: .revise(source: active, replacement: program, replacing: []),
            basis: basis,
            completedThisWeek: WeekProgress.current().completed
        )
    }

    // MARK: B. Help me adjust

    /// Days a missed workout could move to: today and the rest of the week,
    /// on days with nothing else on them.
    static func moveTargets(for workout: Workout, today: String = CalendarDate.today) -> [String] {
        let busy = Set(WorkoutsStore.shared.workouts.filter { $0.id != workout.id }.map(\.date))
        let sunday = CalendarDate.shift(WeekProgress.mondayOf(today), by: 6)
        let end = Swift.max(sunday, CalendarDate.shift(today, by: 2))
        var dates: [String] = []
        var date = today
        while date <= end, dates.count < 3 {
            if !busy.contains(date) { dates.append(date) }
            date = CalendarDate.shift(date, by: 1)
        }
        return dates
    }

    static func previewMove(_ workout: Workout, to date: String) -> CoachingProposal {
        let line = PlanChangeLine(
            kind: .moved,
            text: "\(workout.name): \(CalendarDate.short(workout.date)) → \(spoken(date)). Same exercises and targets."
        )
        let minutes = workout.planned.flatMap {
            TrainingPlan.plannedSessionView($0.programId, $0.sessionId)?.minutes
        } ?? Int(TrainingProfileStore.shared.profile.preferredSessionDurationMinutes)
        return CoachingProposal(
            kind: .moveMissed,
            title: "Move it to \(spoken(date))",
            summary: "Train \(workout.name) \(spoken(date)) instead. Nothing else in your week changes.",
            notes: [],
            changes: [PlanSessionChange(
                id: workout.id, date: date, previousDate: workout.date, title: workout.name,
                minutes: minutes, previousMinutes: nil, exerciseIds: workout.exerciseIds, lines: [line]
            )],
            action: .reschedule(workoutId: workout.id, date: date),
            basis: PlanBasis.current(),
            completedThisWeek: WeekProgress.current().completed
        )
    }

    /// Folds a missed session's work into the rest of the week, where it fits.
    static func previewFoldMissed(_ workout: Workout, now: String = ISOTime.now()) async throws -> CoachingProposal {
        var proposal = try await previewRemainingWeek(.init(), kind: .foldMissed, now: now, alsoReplacing: workout.planned?.sessionId)
        proposal.title = "Fit it into the rest of the week"
        proposal.summary = "\(workout.name) comes off your list, and the sessions left this week pick up what they can of its work."
        return proposal
    }

    static func previewShorter(minutes: Int, now: String = ISOTime.now()) async throws -> CoachingProposal {
        var proposal = try await previewRemainingWeek(
            .init(sessionMinutes: Double(minutes)), kind: .shorter, now: now, alsoReplacing: nil
        )
        proposal.title = "Sessions of about \(minutes) min"
        proposal.summary = "The rest of this week's sessions, cut to fit about \(minutes) minutes each. Your usual session length stays as it is for later weeks."
        return proposal
    }

    static func previewWithout(equipment: [String], fixtures: [String], now: String = ISOTime.now()) async throws -> CoachingProposal {
        let filters = FiltersStore.shared
        let remainingEquipment = filters.gymEquipment.filter { !equipment.contains($0) }
        let remainingFixtures = filters.effectiveFixtures.filter { !fixtures.contains($0) }
        var proposal = try await previewRemainingWeek(
            .init(equipment: remainingEquipment, fixtures: remainingFixtures),
            kind: .equipment, now: now, alsoReplacing: nil
        )
        let missing = (equipment + fixtures).map { TrainingEngineAdapter.fixtureLabel($0).lowercased() }
        proposal.title = "This week without \(Wording.list(missing, conjunction: "or"))"
        proposal.summary = "Exercises that need it are swapped for ones that train the same muscles. Your equipment list stays as it is for later weeks."
        return proposal
    }

    private static func previewRemainingWeek(
        _ overrides: TrainingEngineAdapter.PreferenceOverrides,
        kind: CoachingProposal.Kind,
        now: String,
        alsoReplacing extra: String?
    ) async throws -> CoachingProposal {
        guard ActiveWorkoutStore.shared.session == nil else {
            throw TrainingPersistenceError("Finish your current workout first, then adjust the week.")
        }
        guard let active = TrainingPlan.activeProgramRecord() else {
            throw TrainingPersistenceError("There's no plan to adjust yet. Build one first, and RAUTA can reshape it when your week changes.")
        }
        let remaining = TrainingWorkflow.remainingTrainingSlots(active, now)
        guard !remaining.sessions.isEmpty else {
            throw TrainingPersistenceError("No planned sessions are left this week to adjust. Use My next week to plan ahead instead.")
        }
        let basis = PlanBasis.current(now: now)
        let setup = TrainingEngineAdapter.buildEngineInputs(overrides: overrides)
        let attempt = try await TrainingWorkflow.planTrainingWeek(
            setup: setup, now: now, source: active, adaptationMode: .remainingWeek
        )
        try Task.checkCancellation()
        guard let program = attempt.result.program else {
            throw TrainingPersistenceError(TrainingPlan.toPlanBlock(attempt.result.issues).message)
        }

        var replacing = Set(remaining.sessions.map(\.id))
        if let extra { replacing.insert(extra) }
        let context = PlanChanges.currentContext(overrides: overrides)
        let changes = PlanChanges.compare(
            before: remaining.sessions, after: program.weeks.flatMap(\.sessions),
            afterProgram: program, context: context, pairByDate: true
        )
        var notes: [String] = []
        let codes = Set(attempt.result.issues.map(\.code))
        if codes.contains(.missedVolumeDropped) {
            notes.append("Not all of the week's planned work fits in what's left, so some is left out rather than crammed into the remaining sessions.")
        }
        if codes.contains(.reducedVolume) {
            notes.append("Your recent sessions and readiness point to a lighter week, so a few sets come off.")
        }
        notes += coverageNotes(program)
        let week = WeekProgress.current()
        if week.completed > 0 {
            notes.append("Your \(Wording.countLabel(week.completed, "completed session")) this week stay exactly as logged.")
        }
        return CoachingProposal(
            kind: kind, title: "", summary: "", notes: notes, changes: changes,
            action: .revise(source: active, replacement: program, replacing: replacing),
            basis: basis, completedThisWeek: week.completed
        )
    }

    // MARK: Applying

    static func apply(_ proposal: CoachingProposal) throws -> CoachingUndo {
        guard ActiveWorkoutStore.shared.session == nil else {
            throw TrainingPersistenceError("Finish your current workout before changing the plan.")
        }
        guard proposal.isCurrent() else {
            throw TrainingPersistenceError("Your training changed since this was prepared. Prepare it again to see what it would do now.")
        }
        let recordsBefore = TrainingRecordsStore.shared.data
        let workoutsBefore = WorkoutsStore.shared.workouts
        try RautaDirector.shared.quietly {
            switch proposal.action {
            case .revise(let source, let replacement, let replacing):
                try PlanRevision.commit(source: source, replacement: replacement, replacing: replacing)
            case .newPlan(let preview):
                try TrainingPlan.commit(preview)
            case .reschedule(let workoutId, let date):
                try TrainingEdits.rescheduleWorkout(workoutId, date: date)
            }
        }
        WorkoutAudio.play(.planBuilt)
        return CoachingUndo(
            title: proposal.title,
            recordsBefore: recordsBefore,
            workoutsBefore: workoutsBefore,
            recordsAfter: TrainingRecordsStore.shared.data,
            workoutsAfter: WorkoutsStore.shared.workouts
        )
    }

    /// Puts back what a kept proposal changed, if nothing has changed since.
    static func undo(_ undo: CoachingUndo) throws {
        guard ActiveWorkoutStore.shared.session == nil,
              TrainingRecordsStore.shared.data == undo.recordsAfter,
              WorkoutsStore.shared.workouts == undo.workoutsAfter
        else {
            throw TrainingPersistenceError("Your training changed since, so RAUTA can't undo this safely.")
        }
        try RautaDirector.shared.quietly {
            try TrainingRecordsStore.shared.restore(undo.recordsBefore)
            WorkoutsStore.shared.replaceAll(undo.workoutsBefore)
        }
    }

    // MARK: Notes

    /// How much of last week's plan the new week can lean on.
    static func evidenceNotes(_ lastWeek: [PlannedSession], weekStart: String?, history: TrainingHistory) -> [String] {
        guard !lastWeek.isEmpty, let weekStart, let from = ISOTime.parse(weekStart) else { return [] }
        let to = from + 7 * DAY_MS
        // Sessions trained in that week, by when they happened: a revised plan
        // renames its sessions, but what was trained when does not change.
        let logged = history.sessions.filter { session in
            guard let at = ISOTime.parse(session.completedAt) else { return false }
            return at >= from && at < to && !session.exercises.flatMap(\.sets).isEmpty
        }
        if logged.isEmpty {
            return ["None of last week's planned sessions were logged, so this week repeats its structure and keeps loads as calibration suggestions — nothing is progressed on a guess."]
        }
        var notes = ["Built on the \(Wording.countLabel(logged.count, "session")) you logged that week (\(lastWeek.count) were planned)."]
        let sets = logged.flatMap(\.exercises).flatMap(\.sets).filter(Volume.isWorkingSet)
        let withEffort = sets.filter { Strength.observedRir($0) != nil }.count
        if !sets.isEmpty, withEffort < sets.count {
            notes.append("Reps left was recorded on \(withEffort) of \(sets.count) working sets. Loads only progress where it was.")
        }
        return notes
    }

    /// Sessions well under the session length: said, never padded.
    static func durationNotes(_ program: TrainingProgram) -> [String] {
        let target = TrainingProfileStore.shared.profile.preferredSessionDurationMinutes
        let minutes = program.weeks.flatMap(\.sessions).map { $0.duration.totalSeconds / 60 }
        guard let longest = minutes.max(), longest < target * 0.75 else { return [] }
        let shortest = minutes.min() ?? longest
        let range = Int(shortest.rounded()) == Int(longest.rounded())
            ? "about \(Int(longest.rounded())) min"
            : "\(Int(shortest.rounded()))–\(Int(longest.rounded())) min"
        return ["Sessions run \(range), under your \(Int(target))-minute target: the week's target sets are covered by then, and RAUTA doesn't add filler sets to reach a time."]
    }

    /// Muscles nothing the person can do reaches, and what would.
    static func coverageNotes(_ program: TrainingProgram) -> [String] {
        guard let week = program.weeks.last else { return [] }
        let setup = TrainingEngineAdapter.buildEngineInputs()
        let request = TrainingWorkflow.buildTrainingRequest(setup, now: ISOTime.now())
        let gaps = Coverage.gaps(
            week: week, request: request, index: TrainingWorkflow.trainingIndex(), policy: program.policy,
            candidates: TrainingEngineAdapter.unlockCandidates
        )
        return gaps.filter { !$0.hasEligibleExercise }.prefix(3).map { gap in
            let unlock = gap.unlockedBy.prefix(2).map { PlanChanges.withArticle(TrainingEngineAdapter.fixtureLabel($0).lowercased()) }
            let muscle = gap.muscleId.label.lowercased()
            return unlock.isEmpty
                ? "Nothing you can do right now trains your \(muscle) directly."
                : "Nothing you have trains your \(muscle) directly. \(Wording.list(unlock, conjunction: "or").capitalizedFirst) would — add it under Equipment."
        }
    }

    // MARK: Helpers

    private static func offsets(_ dates: [String], from monday: String) -> [Int] {
        dates.map { date in
            let start = CalendarDate.parse(monday) ?? Date()
            let day = CalendarDate.parse(date) ?? start
            return Calendar(identifier: .gregorian).dateComponents([.day], from: start, to: day).day ?? 0
        }
    }

    private static func spoken(_ date: String) -> String {
        let today = CalendarDate.today
        if date == today { return "today" }
        if date == CalendarDate.shift(today, by: 1) { return "tomorrow" }
        return CalendarDate.short(date)
    }

    @concurrent
    private static func adapt(_ request: AdaptationRequest) async throws -> ProgramGenerationResult {
        try Task.checkCancellation()
        return Adapt.adaptTrainingProgram(request)
    }
}
