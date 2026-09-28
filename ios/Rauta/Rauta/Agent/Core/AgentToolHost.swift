import Foundation

/// The only path from model arguments to app state. Every value is resolved
/// against current stores again, even when the model supplied an app id.
@MainActor
final class AgentToolHost {
    private(set) var outcome: ToolOutcome?
    private(set) var activity: String? {
        didSet { if let activity { onActivity?(activity) } }
    }
    var onActivity: ((String) -> Void)?
    private(set) var proposals: [String: AgentProposal] = [:]
    private var input = ""
    private var cancelled = false
    private(set) var dismissAfterTurn = false
    var bridge: AgentUIBridge?

    func begin(_ input: String) {
        self.input = input
        cancelled = false
        outcome = nil
        activity = nil
        dismissAfterTurn = false
    }

    func cancel() { cancelled = true }
    func removeProposal(_ id: String) { proposals[id] = nil }

    /// Ends the turn with words only.
    func say(_ text: String) { finish(.reply(text)) }

    /// The next workout still ahead, for a request that names none: "remind me".
    private var nextWorkout: Workout? {
        upcoming.first { $0.date >= today && $0.completion == nil }
    }

    private func finish(_ result: ToolOutcome) {
        outcome = result
        activity = nil
    }

    private var today: String { CalendarDate.today }

    /// A day as RAUTA says it: "today", "tomorrow", or "Thu 1 Oct".
    private func spoken(_ day: String) -> String {
        if day == today { return "today" }
        if day == AgentWords.shift(today, by: 1) { return "tomorrow" }
        return CalendarDate.format(day, "EEEdMMM")
    }

    private var upcoming: [Workout] {
        let data = TrainingRecordsStore.shared.data
        let activeId = ActiveWorkoutStore.shared.session?.workoutId
        return WorkoutTimeline(
            workouts: WorkoutsStore.shared.workouts,
            records: data,
            activeWorkoutId: activeId
        ).upcoming
    }

    private var references: [AgentWorkoutRef] {
        upcoming.map { .init(id: $0.id, name: $0.name, date: $0.date) }
    }

    private func workout(_ phrase: String) -> Workout? {
        let chosen = AgentWords.workout(
            phrase, among: references, today: today,
            activeId: ActiveWorkoutStore.shared.session?.workoutId
        )
        guard case .found(let ref) = chosen else { return nil }
        return WorkoutsStore.shared.workout(ref.id)
    }

    private func namedExercise(_ phrase: String, in workout: Workout) -> ExerciseSummary? {
        let catalogue = workout.exerciseIds.compactMap { ExerciseCatalogue.byId[$0] }
        return ExerciseResolver.resolve(phrase, in: catalogue, limit: 1).first?.exercise
    }

    private func row(_ workout: Workout) -> AgentSessionRow {
        let minutes = workout.planned.flatMap {
            TrainingPlan.plannedSessionView($0.programId, $0.sessionId)?.minutes
        } ?? Int(TrainingProfileStore.shared.profile.preferredSessionDurationMinutes)
        return .init(id: workout.id, date: workout.date, title: workout.name,
                     minutes: minutes, exerciseIds: workout.exerciseIds)
    }

    func schedule() {
        guard !cancelled else { return }
        let range = AgentWords.scheduleRange(input, today: today)
        let rows = upcoming.filter { $0.date >= range.from && $0.date <= range.to }.map(row)
        finish(.init(
            say: rows.isEmpty
                ? "Nothing is planned for \(range.title.lowercased())."
                : "Here's \(range.title.lowercased()): \(Wording.countLabel(rows.count, "workout")).",
            card: rows.isEmpty ? nil : .sessions(title: range.title, rows: rows)
        ))
    }

    func workoutDetails(_ phrase: String) {
        guard !cancelled else { return }
        guard let target = workout(phrase) ?? workout(input) else {
            finish(.reply("Which workout do you want to see?")); return
        }
        let names = target.exerciseIds.compactMap { ExerciseCatalogue.byId[$0]?.name }
        finish(.init(say: "Here's \(target.name).",
                     card: .facts(title: "\(target.name) · \(spoken(target.date))",
                                  lines: names.isEmpty ? ["No exercises yet"] : names)))
    }

    func findExercise(_ phrase: String) {
        guard !cancelled else { return }
        var ids = ExerciseResolver.resolve(phrase, limit: 6).map(\.exercise.id)
        var title = "Exercises"
        if ids.isEmpty {
            // "Something for rear delts with dumbbells": the muscle and the
            // equipment, rather than a name.
            let muscles = Set(AgentWords.muscles(in: phrase))
            if !muscles.isEmpty {
                let named = Set(ExerciseCatalogue.equipmentOptions.filter { AgentWords.mentions($0, in: phrase) })
                let owned = Set(FiltersStore.shared.gymEquipment)
                ids = ExerciseCatalogue.allByName
                    .filter { exercise in
                        guard let primary = exercise.primaryMuscle, muscles.contains(primary),
                              !exercise.name.localizedCaseInsensitiveContains("stretch") else { return false }
                        return named.isEmpty || named.contains(exercise.equipment)
                    }
                    .sorted { lhs, rhs in
                        let lhsOwned = owned.contains(lhs.equipment), rhsOwned = owned.contains(rhs.equipment)
                        return lhsOwned != rhsOwned ? lhsOwned : lhs.name.count < rhs.name.count
                    }
                    .prefix(6).map(\.id)
                title = "For \(muscles.count == 1 ? muscles.first!.label.lowercased() : "those muscles")"
            }
        }
        finish(.init(
            say: ids.isEmpty ? "I couldn't find an exercise for \"\(phrase)\"." : "I found these exercises.",
            card: ids.isEmpty ? nil : .exercises(title: title, ids: ids)
        ))
    }

    func progress(_ phrase: String) {
        guard !cancelled else { return }
        activity = "Looking at your training history…"
        let history = TrainingRecordsStore.shared.trainingHistory()
        let performed = Set(history.sessions.flatMap { $0.exercises.map(\.exerciseId) })
        guard let exercise = ExerciseResolver.resolve(phrase, preferred: performed, limit: 1).first?.exercise else {
            finish(.reply("Which exercise do you want to check?")); return
        }
        let state = Strength.analyzePerformance(
            history, exercise.id, ISOTime.now(), DEFAULT_POLICY)
        guard state.exposureCount > 0 else {
            finish(.reply("I don't have any logged working sets for \(exercise.name) yet.")); return
        }
        var lines = ["Logged sessions: \(Int(state.exposureCount))",
                     "Trend: \(state.trend.rawValue.replacingOccurrences(of: "_", with: " "))"]
        if let resistance = state.recentResistance {
            lines.append("Recent load: \(Resistance.format(resistance))")
        }
        if let reps = state.recentRepPerformance {
            lines.append("Recent reps: \(Int(reps.rounded()))")
        }
        finish(.init(say: "Here's how \(exercise.name) is going.",
                     card: .facts(title: exercise.name, lines: lines)))
    }

    func readiness() async {
        guard !cancelled else { return }
        guard HealthService.shared.readinessAccessRequested else {
            finish(.init(say: "I can check your recent sleep and heart trends if you allow Health access.",
                         card: .permission(.health)))
            return
        }
        guard let snapshot = await HealthService.shared.readinessSnapshot(),
              let summary = ReadinessMapper.map(snapshot) else {
            finish(.reply("Health has no recent readiness signals I can use yet.")); return
        }
        let label = summary.readiness.perceivedReadiness == .low ? "Lower than usual" : "Near your usual range"
        finish(.init(say: "Here's what your recent Health data suggests for training.",
                     card: .facts(title: label, lines: summary.reasons)))
    }

    func alternatives(_ phrase: String, workoutPhrase: String?) {
        guard !cancelled else { return }
        let target = workoutPhrase.flatMap(workout) ?? workout(input)
        guard let target, let exercise = namedExercise(phrase, in: target) else {
            finish(.reply("Which exercise and workout do you mean?")); return
        }
        let ids = TrainingWorkflow.replacementIds(exercise.id, workoutId: target.id)
        finish(.init(
            say: ids.isEmpty ? "I couldn't find a fitting alternative for \(exercise.name)." : "These fit \(target.name).",
            card: ids.isEmpty ? nil : .exercises(title: "Alternatives to \(exercise.name)", ids: Array(ids.prefix(6)))
        ))
    }

    func swap(workoutPhrase: String, exercisePhrase: String, replacementPhrase: String?) {
        guard !cancelled else { return }
        guard !Set(AgentWords.words(input)).isDisjoint(with: ["swap", "replace", "substitute"]) else {
            finish(.reply("Tell me which exercise you want to change.")); return
        }
        guard let target = workout(workoutPhrase) ?? workout(input),
              let original = namedExercise(exercisePhrase, in: target) else {
            finish(.reply("Which exercise in which workout should I swap?")); return
        }
        let allowed = TrainingWorkflow.replacementIds(original.id, workoutId: target.id)
        let replacement: ExerciseSummary? = {
            if let replacementPhrase, !replacementPhrase.isEmpty,
               input.localizedCaseInsensitiveContains(replacementPhrase) {
                return ExerciseResolver.resolve(replacementPhrase,
                    in: allowed.compactMap { ExerciseCatalogue.byId[$0] }, limit: 1).first?.exercise
            }
            return allowed.first.flatMap { ExerciseCatalogue.byId[$0] }
        }()
        guard let replacement, allowed.contains(replacement.id) else {
            finish(.reply("I couldn't find a fitting replacement. Ask for alternatives to see what fits.")); return
        }
        let recordsBefore = TrainingRecordsStore.shared.data
        let workoutsBefore = WorkoutsStore.shared.workouts
        let running = ActiveWorkoutStore.shared.session?.workoutId == target.id
        let entryBefore = running ? recordsBefore.activeWorkout?.exercises.first { $0.exerciseId == original.id } : nil
        do {
            try RautaDirector.shared.quietly {
                if running, target.planned != nil {
                    try PlannedSubstitution.substituteRunningPlannedExercise(target.id, original.id, replacement.id)
                } else if running {
                    guard let entryBefore else { throw TrainingPersistenceError("The active exercise is not available.") }
                    try TrainingRecordsStore.shared.substituteExercise(
                        exerciseEntryId: entryBefore.id, exerciseId: replacement.id)
                    var ids = target.exerciseIds
                    guard let index = ids.firstIndex(of: original.id), !ids.contains(replacement.id) else {
                        throw TrainingPersistenceError("That exercise is already in this workout.")
                    }
                    ids[index] = replacement.id
                    WorkoutsStore.shared.updateWorkout(target.id, .init(exerciseIds: ids))
                } else if target.planned != nil {
                    try TrainingEdits.substituteScheduledPlannedExercise(target.id, original.id, replacement.id)
                } else {
                    var ids = target.exerciseIds
                    guard let index = ids.firstIndex(of: original.id), !ids.contains(replacement.id) else {
                        throw TrainingPersistenceError("That exercise is already in this workout.")
                    }
                    ids[index] = replacement.id
                    try TrainingEdits.updateScheduledWorkoutExercises(target.id, ids)
                }
            }
            let recordsAfter = TrainingRecordsStore.shared.data
            let workoutsAfter = WorkoutsStore.shared.workouts
            let undo: AgentUndo? = {
                if running, let entryBefore,
                   let entryAfter = recordsAfter.activeWorkout?.exercises.first(where: { $0.id == entryBefore.id }),
                   let workoutAfter = WorkoutsStore.shared.workout(target.id) {
                    return .exercise(before: entryBefore, after: entryAfter,
                                     workoutBefore: target, workoutAfter: workoutAfter)
                }
                if !running { return .records(before: recordsBefore, after: recordsAfter,
                                               workoutsBefore: workoutsBefore, workoutsAfter: workoutsAfter) }
                return nil
            }()
            finish(.init(say: "Swapped \(original.name) for \(replacement.name) in \(target.name).",
                         card: .change(title: "Exercise swapped", detail: "\(original.name) → \(replacement.name)", systemImage: "arrow.triangle.2.circlepath"),
                         undo: undo))
        } catch { finish(.reply(error.localizedDescription)) }
    }

    func editExercises(workoutPhrase: String, exercisePhrase: String, action: String) {
        guard !cancelled else { return }
        let words = Set(AgentWords.words(input))
        let adding = action.lowercased() == "add" && words.contains("add")
        let removing = action.lowercased() == "remove" && words.contains("remove")
        guard adding || removing else {
            finish(.reply("Tell me whether to add or remove an exercise.")); return
        }
        guard ActiveWorkoutStore.shared.session == nil,
              let target = workout(workoutPhrase) ?? workout(input),
              target.completion == nil else {
            finish(.reply("Choose an upcoming workout that isn't running.")); return
        }
        guard input.localizedCaseInsensitiveContains(exercisePhrase) else {
            finish(.reply("Name the exercise you want to edit.")); return
        }
        let exercise: ExerciseSummary?
        if adding {
            exercise = ExerciseResolver.resolve(exercisePhrase, limit: 1).first?.exercise
        } else {
            exercise = namedExercise(exercisePhrase, in: target)
        }
        guard let exercise else {
            finish(.reply("I couldn't match that exercise in the library or workout.")); return
        }
        if adding && !exercise.equipment.isEmpty && exercise.equipment != "bodyweight"
            && !FiltersStore.shared.gymEquipment.contains(exercise.equipment) {
            finish(.reply("Add \(exercise.equipment) to your equipment before I put \(exercise.name) in the workout."))
            return
        }
        var next = target.exerciseIds
        if adding {
            guard !next.contains(exercise.id), next.count < 12 else {
                finish(.reply("That exercise is already there, or the workout is full.")); return
            }
            next.append(exercise.id)
        } else {
            guard next.count > 1 else { finish(.reply("Keep at least one exercise in the workout.")); return }
            next.removeAll { $0 == exercise.id }
        }
        let before = TrainingRecordsStore.shared.data
        let workoutsBefore = WorkoutsStore.shared.workouts
        do {
            try RautaDirector.shared.quietly {
                try TrainingEdits.updateScheduledWorkoutExercises(target.id, next)
            }
            finish(.init(say: adding ? "Added \(exercise.name) to \(target.name)." : "Removed \(exercise.name) from \(target.name).",
                         card: .change(title: adding ? "Exercise added" : "Exercise removed",
                                       detail: exercise.name, systemImage: adding ? "plus.circle" : "minus.circle"),
                         undo: .records(before: before, after: TrainingRecordsStore.shared.data,
                                        workoutsBefore: workoutsBefore, workoutsAfter: WorkoutsStore.shared.workouts)))
        } catch { finish(.reply(error.localizedDescription)) }
    }

    func reschedule(workoutPhrase: String, dayPhrase: String) {
        guard !cancelled else { return }
        guard !Set(AgentWords.words(input)).isDisjoint(with: ["move", "reschedule", "shift", "postpone", "push"]),
              input.localizedCaseInsensitiveContains(dayPhrase) else {
            finish(.reply("Tell me which day you want to move it to.")); return
        }
        guard let target = workout(workoutPhrase) ?? workout(input) else {
            finish(.reply("Which workout should I move?")); return
        }
        guard let date = AgentWords.rescheduledDay(dayPhrase, workoutDate: target.date, today: today),
              AgentWords.isDate(date), date >= today else {
            finish(.reply("Tell me a day from today onward to move it to.")); return
        }
        if target.date == date { finish(.reply("\(target.name) is already on \(spoken(date)).")); return }
        let recordsBefore = TrainingRecordsStore.shared.data
        let workoutsBefore = WorkoutsStore.shared.workouts
        do {
            try RautaDirector.shared.quietly { try TrainingEdits.rescheduleWorkout(target.id, date: date) }
            finish(.init(say: "Moved \(target.name) to \(spoken(date)).",
                         card: .change(title: "Workout moved", detail: "\(spoken(target.date)) → \(spoken(date))", systemImage: "calendar"),
                         undo: .records(before: recordsBefore, after: TrainingRecordsStore.shared.data,
                                        workoutsBefore: workoutsBefore, workoutsAfter: WorkoutsStore.shared.workouts)))
        } catch { finish(.reply(error.localizedDescription)) }
    }

    func proposePlan(daysPerWeek: Int?, sessionMinutes: Int?) async {
        guard !cancelled else { return }
        guard ActiveWorkoutStore.shared.session == nil else {
            finish(.reply("Finish your current workout before rebuilding the plan.")); return
        }
        let saidDays = AgentWords.said(daysPerWeek, in: input)
        let saidMinutes = AgentWords.said(sessionMinutes, in: input)
        guard saidDays == nil || (1...7).contains(saidDays!),
              saidMinutes == nil || ((20...120).contains(saidMinutes!) && saidMinutes! % 5 == 0) else {
            finish(.reply("Choose 1–7 training days and a session length from 20–120 minutes in 5-minute steps.")); return
        }
        let offsets = AgentWords.weekdays(in: input)
        let scheduledThisWeek = upcoming.filter {
            $0.date >= today && $0.date <= AgentWords.shift(today, by: 6)
        }.count
        let days = !offsets.isEmpty ? offsets : AgentWords.offsets(
            daysPerWeek: saidDays ?? max(1, min(7, scheduledThisWeek == 0 ? 3 : scheduledThisWeek))
        )
        let dates = AgentWords.planDates(offsets: days, today: today)
        activity = "Building your plan…"
        let lower = input.lowercased()
        let wantsHealth = ["readiness", "recovery", "sleep", "hrv"].contains(where: lower.contains)
        if wantsHealth && !HealthService.shared.readinessAccessRequested {
            finish(.init(say: "Allow Health access so I can factor in recent readiness signals.",
                         card: .permission(.health)))
            return
        }
        var readiness: Readiness? = nil
        let healthSnapshot = wantsHealth ? await HealthService.shared.readinessSnapshot() : nil
        if let healthSnapshot { readiness = ReadinessMapper.map(healthSnapshot)?.readiness }
        if lower.contains("sore") || lower.contains("soreness") {
            let sore = AgentWords.muscles(in: input).map {
                SorenessEntry(muscleId: $0,
                              level: lower.contains("very") || lower.contains("really") ? .high : .mild)
            }
            if !sore.isEmpty {
                if readiness == nil { readiness = Readiness(perceivedReadiness: nil, soreness: nil, pain: nil) }
                readiness?.soreness = sore
            }
        }
        let preview = await TrainingPlan.previewTrainingPlanForDates(
            dates: dates,
            sourceProgramId: TrainingRecordsStore.shared.data.activeProgramId,
            readiness: readiness,
            overrides: .init(sessionMinutes: saidMinutes.map(Double.init))
        )
        guard !Task.isCancelled, !cancelled else { return }
        guard let preview else { finish(.reply("Planning stopped before a preview was ready.")); return }
        switch preview {
        case .blocked(let block): finish(.reply(block.message))
        case .ready(let plan):
            let id = UUID().uuidString
            proposals[id] = .plan(plan, sessionMinutes: saidMinutes, healthSnapshot: healthSnapshot)
            let rows = plan.sessions.map {
                AgentSessionRow(id: $0.id, date: $0.date, title: $0.title,
                                minutes: $0.minutes, exerciseIds: $0.exerciseIds)
            }
            finish(.init(say: "I built a plan for you to review. It hasn't been saved yet.",
                         card: .proposal(.init(id: id, title: "Your new plan",
                                               detail: "\(rows.count) workouts", rows: rows,
                                               applyTitle: "Apply plan", destructive: false,
                                               state: .pending))))
        }
    }

    func proposeAdjustedWeek() async {
        guard !cancelled else { return }
        guard ActiveWorkoutStore.shared.session == nil,
              let source = TrainingPlan.activeProgramRecord() else {
            finish(.reply("You need an active plan and no running workout to adjust the week.")); return
        }
        activity = "Adjusting your week…"
        do {
            let preview = try await TrainingWorkflow.previewAdjustedWeek(source: source)
            guard !Task.isCancelled, !cancelled else { return }
            let id = UUID().uuidString
            proposals[id] = .plan(preview, sessionMinutes: nil, healthSnapshot: nil)
            let rows = preview.sessions.map {
                AgentSessionRow(id: $0.id, date: $0.date, title: $0.title,
                                minutes: $0.minutes, exerciseIds: $0.exerciseIds)
            }
            finish(.init(say: "I reshaped the remaining week for you to review.",
                         card: .proposal(.init(id: id, title: "Adjusted week",
                                               detail: "\(rows.count) remaining workouts", rows: rows,
                                               applyTitle: "Apply changes", destructive: false,
                                               state: .pending))))
        } catch { finish(.reply(error.localizedDescription)) }
    }

    func proposeWorkout(_ phrase: String) async {
        guard !cancelled else { return }
        guard ActiveWorkoutStore.shared.session == nil else {
            finish(.reply("Finish your current workout before creating another.")); return
        }
        let date = AgentWords.day(phrase, today: today) ?? AgentWords.day(input, today: today) ?? today
        guard AgentWords.isDate(date), date >= today else {
            finish(.reply("Choose today or a future day for the workout.")); return
        }
        let focus = AgentWords.muscles(in: input)
        guard !focus.isEmpty else {
            finish(.reply("Which muscles should this workout focus on?")); return
        }
        let basis = PlanBasis.current()
        activity = "Building your workout…"
        do {
            let ids = try await EngineWorkout.propose(date: date, focusMuscles: focus)
            guard !Task.isCancelled, !cancelled else { return }
            guard !ids.isEmpty else { finish(.reply("I couldn't build a workout for that focus.")); return }
            let name = focus.count > 2 ? "Full body" : focus.map { $0.rawValue.capitalized }.joined(separator: " & ")
            let id = UUID().uuidString
            proposals[id] = .workout(date: date, name: name, exerciseIds: ids, focus: focus, basis: basis)
            let row = AgentSessionRow(id: id, date: date, title: name,
                                      minutes: Int(TrainingProfileStore.shared.profile.preferredSessionDurationMinutes),
                                      exerciseIds: ids)
            finish(.init(say: "I built a workout for you to review. It hasn't been saved yet.",
                         card: .proposal(.init(id: id, title: "New workout",
                                               detail: "\(spoken(date)) · \(ids.count) exercises", rows: [row],
                                               applyTitle: "Create workout", destructive: false,
                                               state: .pending))))
        } catch { finish(.reply(error.localizedDescription)) }
    }

    func proposeFinish() {
        guard !cancelled else { return }
        guard let running = ActiveWorkoutStore.shared.session else {
            finish(.reply("There's no workout running.")); return
        }
        let id = UUID().uuidString
        proposals[id] = .finishWorkout(workoutId: running.workoutId, basis: PlanBasis.current())
        finish(.init(say: "Review this before finishing your workout.",
                     card: .proposal(.init(id: id, title: "Finish workout?",
                                           detail: "RAUTA will save the sets you've completed.", rows: [],
                                           applyTitle: "Finish workout", destructive: false,
                                           state: .pending))))
    }

    func proposeDiscard() {
        guard !cancelled else { return }
        guard let running = ActiveWorkoutStore.shared.session else {
            finish(.reply("There's no workout running.")); return
        }
        let id = UUID().uuidString
        proposals[id] = .discardWorkout(workoutId: running.workoutId, basis: PlanBasis.current())
        finish(.init(say: "Review this before leaving your workout.",
                     card: .proposal(.init(id: id, title: "Discard workout?",
                                           detail: "Logged sets remain in your history as a partial session.", rows: [],
                                           applyTitle: "Discard workout", destructive: true,
                                           state: .pending))))
    }

    func proposeDelete(_ phrase: String) {
        guard !cancelled else { return }
        let words = Set(AgentWords.words(input))
        guard !words.isDisjoint(with: ["delete", "remove"]),
              !words.isDisjoint(with: ["workout", "session"]),
              !words.contains("from") else {
            finish(.reply("Say which workout you want to delete.")); return
        }
        guard ActiveWorkoutStore.shared.session == nil,
              let target = workout(phrase) ?? workout(input), target.completion == nil else {
            finish(.reply("Which upcoming workout should I delete?")); return
        }
        let id = UUID().uuidString
        proposals[id] = .deleteWorkout(.init(id: target.id, name: target.name, date: target.date),
                                       basis: PlanBasis.current())
        finish(.init(say: "Review this workout before I delete it.",
                     card: .proposal(.init(id: id, title: "Delete workout?",
                                           detail: "\(target.name) · \(spoken(target.date))", rows: [row(target)],
                                           applyTitle: "Delete workout", destructive: true,
                                           state: .pending))))
    }

    func startWorkout(_ phrase: String) {
        guard !cancelled else { return }
        guard !Set(AgentWords.words(input)).isDisjoint(with: ["start", "begin"]) else {
            finish(.reply("Say which workout you want to start.")); return
        }
        guard let target = workout(phrase) ?? workout(input) else {
            finish(.reply("Which workout should I start?")); return
        }
        guard let bridge else { finish(.reply("Open the workout screen to start this session.")); return }
        let result = bridge.startWorkout(target)
        if let refusal = result.refusal {
            finish(.reply(refusal))
        } else {
            finish(.reply("Starting \(target.name)."))
            dismissAfterTurn = true
        }
    }

    func logSet(exercisePhrase: String, reps: Int?, kilograms: Double?) {
        guard !cancelled else { return }
        guard !Set(AgentWords.words(input)).isDisjoint(with: ["log", "record", "save"]) else {
            finish(.reply("Ask me to log the set, with the reps and load you actually used.")); return
        }
        guard let running = ActiveWorkoutStore.shared.session,
              let draft = TrainingRecordsStore.shared.data.activeWorkout,
              draft.sourceWorkoutId == running.workoutId else {
            finish(.reply("Start a workout before logging a set.")); return
        }
        guard let reps = AgentWords.said(reps, in: input), (1...100).contains(reps) else {
            finish(.reply("Tell me how many reps you completed.")); return
        }
        let catalogue = running.exerciseIds.compactMap { ExerciseCatalogue.byId[$0] }
        guard let exercise = ExerciseResolver.resolve(exercisePhrase, in: catalogue, limit: 1).first?.exercise,
              let entry = draft.exercises.first(where: { $0.exerciseId == exercise.id }) else {
            finish(.reply("Which exercise are you logging?")); return
        }
        let mode = Resistance.modes(for: exercise).first ?? .bodyweight
        let load = AgentWords.said(kilograms, in: input)
        if Resistance.isMeasuredInKg(mode), load == nil {
            finish(.reply("Tell me the kilograms you used so I don't guess your load.")); return
        }
        if let load, !(0...500).contains(load) {
            finish(.reply("That load is outside the range I can log.")); return
        }
        let context = Resistance.resolveLoadContext(
            for: exercise, mode: mode, settings: TrainingRecordsStore.shared.data.settings,
            equipmentIncrementKg: FiltersStore.shared.equipmentLoadIncrements[exercise.equipment])
        let observation = PersistedSetObservation(
            reps: Double(reps), resistance: Resistance.makeResistance(mode, load ?? 0, context),
            completed: true, timestamp: ISOTime.now())
        let existing = entry.sets.first { $0.observation?.completed != true }
        do {
            let undo: AgentUndo = try RautaDirector.shared.quietly {
                if let existing {
                    try TrainingRecordsStore.shared.recordSet(
                        exerciseEntryId: entry.id, setDraftId: existing.id, observation: observation)
                    return .set(entryId: entry.id, setId: existing.id,
                                before: existing.observation, after: observation)
                }
                let id = try TrainingRecordsStore.shared.addUnplannedSet(
                    exerciseEntryId: entry.id, setType: .working, side: .both,
                    observation: observation)
                return .addedSet(entryId: entry.id, setId: id)
            }
            let loadLine = Resistance.isMeasuredInKg(mode)
                ? " at \((load ?? 0).formatted(.number.precision(.fractionLength(0...2)))) kg" : ""
            finish(.init(say: "Logged \(reps) reps\(loadLine) for \(exercise.name).",
                         card: .change(title: "Set logged", detail: "\(exercise.name): \(reps) reps\(loadLine)", systemImage: "checkmark.circle"),
                         undo: undo))
        } catch { finish(.reply(error.localizedDescription)) }
    }

    func startRest(seconds proposed: Int?) {
        guard !cancelled else { return }
        guard !Set(AgentWords.words(input)).isDisjoint(with: ["start", "begin", "set", "take", "rest", "timer", "break"]) else {
            finish(.reply("Tell me to start a rest timer when you're ready.")); return
        }
        guard ActiveWorkoutStore.shared.session != nil else {
            finish(.reply("Start a workout before starting rest.")); return
        }
        let numbers = AgentWords.numbers(in: input)
        let mentionsMinutes = input.localizedCaseInsensitiveContains("minute")
            || input.localizedCaseInsensitiveContains(" min")
        let seconds: Int
        if mentionsMinutes {
            let minutes = numbers.filter { (1...10).contains($0) }.min()
                ?? (input.localizedCaseInsensitiveContains("a minute") ? 1 : 0)
            seconds = minutes > 0 ? minutes * 60 : 90
        } else {
            seconds = AgentWords.said(proposed, in: input)
                ?? numbers.filter { (15...600).contains($0) }.min() ?? 90
        }
        guard (15...600).contains(seconds) else {
            finish(.reply("Choose a rest between 15 seconds and 10 minutes.")); return
        }
        ActiveWorkoutStore.shared.startRest(seconds: Double(seconds), exerciseName: nil)
        finish(.init(say: "Rest started for \(seconds) seconds.",
                     card: .change(title: "Rest started", detail: "\(seconds) seconds", systemImage: "timer")))
    }

    func setPaused(_ pause: Bool) {
        guard !cancelled else { return }
        guard !Set(AgentWords.words(input)).isDisjoint(with: pause ? ["pause"] : ["resume", "continue"]) else {
            finish(.reply("Tell me whether to pause or resume your workout.")); return
        }
        guard let running = ActiveWorkoutStore.shared.session else {
            finish(.reply("There's no workout running.")); return
        }
        if pause {
            guard running.runningSince != nil else { finish(.reply("Your workout is already paused.")); return }
            ActiveWorkoutStore.shared.pause()
        } else {
            guard running.runningSince == nil else { finish(.reply("Your workout is already running.")); return }
            ActiveWorkoutStore.shared.resume()
        }
        finish(.init(say: pause ? "Workout paused." : "Workout resumed.",
                     card: .change(title: pause ? "Paused" : "Resumed", detail: running.workoutName,
                                   systemImage: pause ? "pause.circle" : "play.circle"),
                     undo: pause ? .pause(workoutId: running.workoutId) : .resume(workoutId: running.workoutId)))
    }

    func updateProfile(goalPhrase: String?, minutes: Int?) {
        guard !cancelled else { return }
        let lower = input.lowercased()
        guard !Set(AgentWords.words(input)).isDisjoint(with: ["set", "change", "update", "prefer", "want", "make"]) else {
            finish(.reply("Tell me what you want to change in your profile.")); return
        }
        let before = TrainingProfileStore.shared.profile
        let saidMinutes = AgentWords.said(minutes, in: input)
        if let saidMinutes,
           (!(20...120).contains(saidMinutes) || saidMinutes % 5 != 0) {
            finish(.reply("Choose 20–120 minutes in 5-minute steps.")); return
        }
        let goal: TrainingGoal? = {
            guard goalPhrase != nil else { return nil }
            if lower.contains("build muscle") || lower.contains("hypertrophy") { return .hypertrophy }
            if lower.contains("strength and size") || lower.contains("strength & size") { return .strengthHypertrophy }
            if lower.contains("stronger") || lower.contains("strength") { return .strength }
            if lower.contains("general fitness") { return .generalFitness }
            if lower.contains("muscular endurance") { return .muscularEndurance }
            if lower.contains("fat loss") { return .fatLossSupport }
            return nil
        }()
        guard goal != nil || saidMinutes != nil else {
            finish(.reply("Tell me which training goal or session length to change.")); return
        }
        RautaDirector.shared.quietly {
            TrainingProfileStore.shared.updateProfile(.init(
                goal: goal, preferredSessionDurationMinutes: saidMinutes.map(Double.init)))
        }
        let after = TrainingProfileStore.shared.profile
        finish(.init(say: "Updated your training profile.",
                     card: .change(title: "Profile updated",
                                   detail: "\(ProfileVocabulary.goalLabel(after.goal)) · \(Int(after.preferredSessionDurationMinutes)) min",
                                   systemImage: "person.crop.circle"),
                     undo: .profile(before: before, after: after)))
    }

    func setMusclePriority(_ phrase: String) {
        guard !cancelled else { return }
        guard !Set(AgentWords.words(input)).isDisjoint(with: ["set", "change", "prioritize", "emphasize", "focus", "increase", "reduce"]) else {
            finish(.reply("Tell me how to change that muscle's priority.")); return
        }
        let named = AgentWords.muscles(in: phrase)
        guard named.count == 1, AgentWords.muscles(in: input).contains(named[0]) else {
            finish(.reply("Name one muscle group to prioritize.")); return
        }
        let words = Set(AgentWords.words(input))
        let level: MusclePriorityLevel
        if !words.isDisjoint(with: ["less", "lower", "reduce"]) { level = .low }
        else if !words.isDisjoint(with: ["focus", "specialize", "specialise"]) { level = .specialization }
        else if !words.isDisjoint(with: ["priority", "prioritize", "more", "emphasize"]) { level = .high }
        else { finish(.reply("Tell me whether you want more or less focus on that muscle.")); return }
        let before = TrainingProfileStore.shared.profile
        RautaDirector.shared.quietly {
            TrainingProfileStore.shared.setMusclePriority(named[0], level)
        }
        let after = TrainingProfileStore.shared.profile
        finish(.init(say: "Updated your muscle priorities.",
                     card: .change(title: "Priority updated", detail: "\(named[0].rawValue): \(ProfileVocabulary.label(for: level))",
                                   systemImage: "scope"),
                     undo: .profile(before: before, after: after)))
    }

    func setEquipment(_ names: [String]) {
        guard !cancelled else { return }
        guard !Set(AgentWords.words(input)).isDisjoint(with: ["have", "add", "remove", "only", "replace", "use", "available"]) else {
            finish(.reply("Tell me which equipment you have or no longer have.")); return
        }
        let said = Set(ExerciseResolver.words(input))
        var found: [String] = []
        for name in names {
            guard let option = ExerciseCatalogue.equipmentOptions.first(where: {
                Set(ExerciseResolver.words($0)) == Set(ExerciseResolver.words(name))
            }), !Set(ExerciseResolver.words(option)).isDisjoint(with: said) else { continue }
            if !found.contains(option) { found.append(option) }
        }
        guard !found.isEmpty else {
            finish(.reply("Name equipment from the gym list, such as dumbbell or barbell.")); return
        }
        let before = FiltersStore.shared.snapshot
        let lower = input.lowercased()
        let removing = lower.contains("don't have") || lower.contains("do not have")
            || lower.contains("remove") || lower.contains("no longer")
        let replacing = lower.contains("only") || lower.contains("just") || lower.contains("replace")
        let next: [String] = removing ? before.gymEquipment.filter { !found.contains($0) }
            : replacing ? found : Array(Set(before.gymEquipment + found)).sorted()
        RautaDirector.shared.quietly { FiltersStore.shared.setGymEquipment(next) }
        finish(.init(say: "Updated the equipment I plan around.",
                     card: .change(title: "Equipment updated", detail: "\(next.count) items available", systemImage: "dumbbell"),
                     undo: .equipment(before: before, after: FiltersStore.shared.snapshot)))
    }

    func freeSlots(_ phrase: String) {
        guard !cancelled else { return }
        guard CalendarService.shared.hasAccess else {
            finish(.init(say: "Allow Calendar access so I can find free training times.",
                         card: .permission(.calendar)))
            return
        }
        let day = AgentWords.day(phrase, today: today) ?? AgentWords.day(input, today: today) ?? today
        guard day >= today else {
            finish(.reply("Choose today or a later day to check.")); return
        }
        let slots = CalendarService.shared.freeSlots(on: day,
            minutes: Int(TrainingProfileStore.shared.profile.preferredSessionDurationMinutes))
        let lines = slots.prefix(6).map {
            DateFormatter.localizedString(from: $0.start, dateStyle: .none, timeStyle: .short)
        }
        let when = ["today", "tomorrow"].contains(spoken(day)) ? spoken(day) : "on \(spoken(day))"
        finish(.init(say: lines.isEmpty ? "I didn't find a free training slot \(when)." : "These times are free \(when).",
                     card: lines.isEmpty ? nil : .facts(title: "Available times", lines: lines)))
    }

    func proposeCalendar(_ phrase: String) {
        guard !cancelled else { return }
        guard CalendarService.shared.hasAccess else {
            finish(.init(say: "Allow Calendar access so I can prepare a workout event.",
                         card: .permission(.calendar)))
            return
        }
        guard let target = workout(phrase) ?? workout(input) ?? nextWorkout, target.completion == nil else {
            finish(.reply("There's no upcoming workout to add to Calendar.")); return
        }
        let minutes = row(target).minutes
        guard let slot = CalendarService.shared.suggestedSlot(for: target, minutes: minutes) else {
            finish(.reply("I couldn't find a free time on \(spoken(target.date)). Ask me to check another day.")); return
        }
        let id = UUID().uuidString
        proposals[id] = .calendar(workout: .init(id: target.id, name: target.name, date: target.date),
                                  start: slot.start, end: slot.end)
        let time = DateFormatter.localizedString(from: slot.start, dateStyle: .none, timeStyle: .short)
        finish(.init(say: "Review this Calendar event before I add it.",
                     card: .proposal(.init(id: id, title: "Add to Calendar",
                                           detail: "\(target.name) · \(spoken(target.date)) at \(time)",
                                           rows: [row(target)], applyTitle: "Add event",
                                           destructive: false, state: .pending))))
    }

    func setReminder(_ phrase: String) async {
        guard !cancelled else { return }
        guard !Set(AgentWords.words(input)).isDisjoint(with: ["remind", "reminder", "notify"]) else {
            finish(.reply("Tell me which workout needs a reminder.")); return
        }
        guard let target = workout(phrase) ?? workout(input) ?? nextWorkout, target.completion == nil else {
            finish(.reply("There's no upcoming workout to remind you about.")); return
        }
        guard !WorkoutReminders.shared.hasReminder(target.id) else {
            finish(.reply("That workout already has a reminder.")); return
        }
        guard WorkoutReminders.shared.hasRequestedAccess else {
            finish(.init(say: "Allow notifications so I can set a workout reminder.",
                         card: .permission(.notifications)))
            return
        }
        do {
            let fire = try await WorkoutReminders.shared.schedule(target)
            let time = DateFormatter.localizedString(from: fire, dateStyle: .medium, timeStyle: .short)
            finish(.init(say: "I'll remind you about \(target.name) on \(time).",
                         card: .change(title: "Reminder set", detail: time, systemImage: "bell"),
                         undo: .reminder(id: target.id, fireDate: fire)))
        } catch { finish(.reply(error.localizedDescription)) }
    }

    func removeReminder(_ phrase: String) {
        guard !cancelled else { return }
        guard let target = workout(phrase) ?? workout(input),
              let fire = WorkoutReminders.shared.fireDate(for: target.id) else {
            finish(.reply("I couldn't find a reminder for that workout.")); return
        }
        WorkoutReminders.shared.remove(target.id)
        finish(.init(say: "Removed the reminder for \(target.name).",
                     card: .change(title: "Reminder removed", detail: target.name, systemImage: "bell.slash"),
                     undo: .removedReminder(id: target.id, fireDate: fire)))
    }

    func apply(_ id: String) async -> ToolOutcome {
        guard let proposal = proposals[id] else { return .reply("That preview has expired. Ask me to make a fresh one.") }
        switch proposal {
        case .plan(let preview, let minutes, let healthSnapshot):
            guard ActiveWorkoutStore.shared.session == nil else {
                return .reply("Finish your current workout before applying this.")
            }
            guard preview.isCurrent() else {
                proposals[id] = nil
                return .reply("Your training changed since I made this plan. Ask me to refresh it.")
            }
            if let healthSnapshot, await HealthService.shared.readinessSnapshot() != healthSnapshot {
                proposals[id] = nil
                return .reply("Health data changed since I made this plan. Ask me to refresh it.")
            }
            let before = TrainingRecordsStore.shared.data
            let workoutsBefore = WorkoutsStore.shared.workouts
            let profileBefore = TrainingProfileStore.shared.profile
            do {
                try RautaDirector.shared.quietly {
                    try TrainingPlan.commit(preview)
                    if let minutes {
                        TrainingProfileStore.shared.updateProfile(.init(preferredSessionDurationMinutes: Double(minutes)))
                    }
                }
                proposals[id] = nil
                WorkoutAudio.play(.planBuilt)
                return .init(say: "Your new plan is ready.",
                             card: .change(title: "Plan applied", detail: "\(preview.sessions.count) workouts", systemImage: "checkmark.circle"),
                             undo: .plan(before: before, after: TrainingRecordsStore.shared.data,
                                         workoutsBefore: workoutsBefore, workoutsAfter: WorkoutsStore.shared.workouts,
                                         profileBefore: profileBefore, profileAfter: TrainingProfileStore.shared.profile),
                             proposalApplied: true)
            } catch { return .reply(error.localizedDescription) }
        case .workout(let date, let name, let ids, let focus, let basis):
            guard ActiveWorkoutStore.shared.session == nil, PlanBasis.current() == basis else {
                proposals[id] = nil
                return .reply("Training changed since I built that workout. Ask me to refresh it.")
            }
            let before = TrainingRecordsStore.shared.data
            let workoutsBefore = WorkoutsStore.shared.workouts
            do {
                _ = try await RautaDirector.shared.quietly {
                    try await EngineWorkout.createWorkout(date: date, name: name,
                                                          exerciseIds: ids, focusMuscles: focus,
                                                          rautaBuilt: true, expectedBasis: basis)
                }
                proposals[id] = nil
                return .init(say: "Created \(name) for \(spoken(date)).",
                             card: .change(title: "Workout created", detail: name,
                                           systemImage: "plus.circle"),
                             undo: .records(before: before, after: TrainingRecordsStore.shared.data,
                                            workoutsBefore: workoutsBefore, workoutsAfter: WorkoutsStore.shared.workouts),
                             proposalApplied: true)
            } catch { return .reply(error.localizedDescription) }
        case .finishWorkout(let workoutId, let basis):
            guard ActiveWorkoutStore.shared.session?.workoutId == workoutId,
                  PlanBasis.current() == basis else {
                proposals[id] = nil
                return .reply("The running workout changed. Ask me again before finishing it.")
            }
            guard let bridge, bridge.finishWorkout() else {
                return .reply("I couldn't finish that workout. Your logged sets are still here.")
            }
            proposals[id] = nil
            return .init(say: "Workout finished and saved.", proposalApplied: true)
        case .discardWorkout(let workoutId, let basis):
            guard ActiveWorkoutStore.shared.session?.workoutId == workoutId,
                  PlanBasis.current() == basis else {
                proposals[id] = nil
                return .reply("The running workout changed. Ask me again before discarding it.")
            }
            ActiveWorkoutStore.shared.cancel()
            guard ActiveWorkoutStore.shared.session == nil else {
                return .reply("I couldn't discard that workout.")
            }
            proposals[id] = nil
            return .init(say: "Workout closed. Any logged sets remain in your history.",
                         proposalApplied: true)
        case .deleteWorkout(let ref, let basis):
            guard ActiveWorkoutStore.shared.session == nil, PlanBasis.current() == basis,
                  let workout = WorkoutsStore.shared.workout(ref.id),
                  workout.name == ref.name, workout.date == ref.date,
                  workout.completion == nil else {
                proposals[id] = nil
                return .reply("That workout changed. Ask me again before deleting it.")
            }
            let before = TrainingRecordsStore.shared.data
            let workoutsBefore = WorkoutsStore.shared.workouts
            do {
                try RautaDirector.shared.quietly { try TrainingEdits.deleteScheduledWorkout(ref.id) }
                proposals[id] = nil
                return .init(say: "Deleted \(ref.name) from \(spoken(ref.date)).",
                             card: .change(title: "Workout deleted", detail: ref.name,
                                           systemImage: "trash"),
                             undo: .records(before: before, after: TrainingRecordsStore.shared.data,
                                            workoutsBefore: workoutsBefore, workoutsAfter: WorkoutsStore.shared.workouts),
                             proposalApplied: true)
            } catch { return .reply(error.localizedDescription) }
        case .calendar(let ref, let start, let end):
            guard ActiveWorkoutStore.shared.session == nil else {
                return .reply("Finish your current workout before adding a calendar event.")
            }
            guard let target = WorkoutsStore.shared.workout(ref.id),
                  target.name == ref.name, target.date == ref.date,
                  CalendarService.shared.hasAccess,
                  CalendarService.shared.freeSlots(on: target.date,
                      minutes: Int(end.timeIntervalSince(start) / 60))
                    .contains(where: { $0.start == start && $0.end == end }) else {
                proposals[id] = nil
                return .reply("That Calendar time is no longer free. Ask me to find another.")
            }
            do {
                let eventId = try CalendarService.shared.add(target, at: .init(start: start, end: end))
                proposals[id] = nil
                return .init(say: "Added \(target.name) to Calendar.",
                             card: .change(title: "Calendar event added", detail: target.date,
                                           systemImage: "calendar.badge.checkmark"),
                             undo: .calendarEvent(id: eventId), proposalApplied: true)
            } catch { return .reply(error.localizedDescription) }
        }
    }

    func forgetProposals() { proposals.removeAll() }

    func undo(_ action: AgentUndo) async -> ToolOutcome {
        if case .removedReminder(let id, let fire) = action {
            guard WorkoutReminders.shared.fireDate(for: id) == nil,
                  let workout = WorkoutsStore.shared.workout(id), fire > Date() else {
                return .reply("Reminder changed since. I can't restore it safely.")
            }
            do {
                _ = try await WorkoutReminders.shared.schedule(workout, fireDate: fire)
                return .reply("Undone.")
            } catch { return .reply(error.localizedDescription) }
        }
        do {
            try RautaDirector.shared.quietly {
                switch action {
                case .records(let before, let after, let workoutsBefore, let workoutsAfter):
                    guard ActiveWorkoutStore.shared.session == nil,
                          TrainingRecordsStore.shared.data == after,
                          WorkoutsStore.shared.workouts == workoutsAfter else {
                        throw TrainingPersistenceError("Training changed since. I can't undo this safely.")
                    }
                    try TrainingRecordsStore.shared.restore(before)
                    WorkoutsStore.shared.replaceAll(workoutsBefore)
                case .plan(let before, let after, let workoutsBefore, let workoutsAfter,
                           let profileBefore, let profileAfter):
                    guard ActiveWorkoutStore.shared.session == nil,
                          TrainingRecordsStore.shared.data == after,
                          WorkoutsStore.shared.workouts == workoutsAfter,
                          TrainingProfileStore.shared.profile == profileAfter else {
                        throw TrainingPersistenceError("Training changed since. I can't undo this safely.")
                    }
                    try TrainingRecordsStore.shared.restore(before)
                    WorkoutsStore.shared.replaceAll(workoutsBefore)
                    TrainingProfileStore.shared.restoreProfile(profileBefore)
                case .exercise(let before, let after, let workoutBefore, let workoutAfter):
                    guard ActiveWorkoutStore.shared.session?.workoutId == workoutAfter.id,
                          WorkoutsStore.shared.workout(workoutAfter.id) == workoutAfter else {
                        throw TrainingPersistenceError("Workout changed since. I can't undo this safely.")
                    }
                    try TrainingRecordsStore.shared.restoreActiveExercise(before, expected: after)
                    WorkoutsStore.shared.updateWorkout(workoutBefore.id,
                        .init(exerciseIds: workoutBefore.exerciseIds))
                case .set(let entryId, let setId, let before, let after):
                    try TrainingRecordsStore.shared.revertSetObservation(
                        exerciseEntryId: entryId, setDraftId: setId, expected: after, restoring: before)
                case .addedSet(let entryId, let setId):
                    try TrainingRecordsStore.shared.discardLoggedSet(exerciseEntryId: entryId, setDraftId: setId)
                case .profile(let before, let after):
                    guard TrainingProfileStore.shared.profile == after else { throw TrainingPersistenceError("Profile changed since.") }
                    TrainingProfileStore.shared.restoreProfile(before)
                case .equipment(let before, let after):
                    guard FiltersStore.shared.snapshot == after else { throw TrainingPersistenceError("Equipment changed since.") }
                    FiltersStore.shared.apply(before)
                case .pause(let workoutId):
                    guard let session = ActiveWorkoutStore.shared.session,
                          session.workoutId == workoutId, session.runningSince == nil else {
                        throw TrainingPersistenceError("Workout state changed since.")
                    }
                    ActiveWorkoutStore.shared.resume()
                case .resume(let workoutId):
                    guard let session = ActiveWorkoutStore.shared.session,
                          session.workoutId == workoutId, session.runningSince != nil else {
                        throw TrainingPersistenceError("Workout state changed since.")
                    }
                    ActiveWorkoutStore.shared.pause()
                case .reminder(let id, let fire):
                    guard WorkoutReminders.shared.fireDate(for: id) == fire else {
                        throw TrainingPersistenceError("Reminder changed since.")
                    }
                    WorkoutReminders.shared.remove(id)
                case .removedReminder:
                    break
                case .calendarEvent(let id):
                    try CalendarService.shared.removeEvent(id)
                }
            }
            return .reply("Undone.")
        } catch { return .reply(error.localizedDescription) }
    }
}
