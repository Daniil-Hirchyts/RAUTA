import Foundation

/// A week looked back on: what was planned and done, what changed in exercises
/// that can be compared like for like, and one thing to do next.
///
/// Every statement comes from recorded sets or the plan. Where the data is
/// thin the review says so instead of filling the gap, and anything estimated
/// is labelled as an estimate.
struct WeeklyReview {
    struct ExerciseChange: Identifiable, Hashable {
        enum Direction: Hashable { case up, same, down }
        var exerciseId: String
        var name: String
        /// What was recorded, set against the last comparable time.
        var text: String
        var direction: Direction
        /// Set when a line rests on an estimated 1RM rather than lifted weight.
        var estimate: String?
        var id: String { exerciseId }
    }

    struct NextAction: Hashable {
        enum Kind: Hashable {
            case start(workoutId: String)
            case adjust
            case nextWeek
            case buildPlan
            case recordEffort
            case none
        }
        var title: String
        var detail: String
        var kind: Kind
    }

    var week: WeekProgress
    var headline: String
    var consistency: [String]
    var changes: [ExerciseChange]
    /// What the review could not say, and why.
    var dataNotes: [String]
    var next: NextAction
    /// No training logged at all, ever: there is nothing to review yet.
    var isEmpty: Bool

    // MARK: Building

    @MainActor
    static func current(weekOf day: String = CalendarDate.today) -> WeeklyReview {
        build(
            week: WeekProgress.week(of: day),
            history: TrainingRecordsStore.shared.trainingHistory(),
            next: NextWorkout.current(),
            hasPlan: TrainingPlan.activeProgramRecord() != nil,
            today: CalendarDate.today
        )
    }

    static func build(
        week: WeekProgress,
        history: TrainingHistory,
        next: NextWorkout,
        hasPlan: Bool,
        today: String
    ) -> WeeklyReview {
        let from = ISOTime.parse("\(week.monday)T00:00:00.000Z") ?? 0
        let to = from + 7 * DAY_MS
        func local(_ iso: String) -> Double? { ISOTime.wallClock(iso) }
        let inWeek = history.sessions.filter { session in
            guard let at = local(session.completedAt) else { return false }
            return at >= from && at < to
        }
        let before = history.sessions.filter { session in
            guard let at = local(session.completedAt) else { return false }
            return at < from
        }
        let structured = inWeek.filter { !$0.exercises.flatMap(\.sets).isEmpty }
        let isCurrentWeek = today >= week.monday && today <= week.sunday

        // Consistency, in the plan's terms.
        var consistency: [String] = []
        if week.planned > 0 {
            consistency.append("You completed \(week.completedPlanned) of \(week.planned) planned sessions\(isCurrentWeek ? " so far" : "").")
        } else if week.completed > 0 {
            consistency.append("You trained \(Wording.countLabel(week.completed, "time")) without a plan for the week.")
        }
        if week.extra > 0, week.planned > 0 {
            consistency.append("Plus \(Wording.countLabel(week.extra, "extra session")).")
        }
        if week.restDays > 0, week.planned > 0 {
            consistency.append("\(Wording.countLabel(week.restDays, "day")) were planned rest — rest days count as part of the plan, not as misses.")
        }
        if !week.missed.isEmpty {
            let names = week.missed.map { "\($0.name) (\(CalendarDate.short($0.date)))" }
            consistency.append("Missed: \(Wording.list(names)).")
        }
        if isCurrentWeek, !week.remaining.isEmpty {
            consistency.append("Still to come: \(Wording.countLabel(week.remaining.count, "session")).")
        }

        // Comparable performance.
        var changes: [ExerciseChange] = []
        var firstTimes = 0
        var exercisesSeen: [String] = []
        for session in structured {
            for exercise in session.exercises where !exercisesSeen.contains(exercise.exerciseId) {
                exercisesSeen.append(exercise.exerciseId)
            }
        }
        for exerciseId in exercisesSeen {
            let thisWeek = structured.flatMap { session in
                session.exercises.filter { $0.exerciseId == exerciseId }.flatMap(\.sets)
            }.filter(Volume.isWorkingSet)
            let previous = before.reversed().lazy.compactMap { session -> [CompletedSet]? in
                let sets = session.exercises.filter { $0.exerciseId == exerciseId }
                    .flatMap(\.sets).filter(Volume.isWorkingSet)
                return sets.isEmpty ? nil : sets
            }.first
            guard let best = topSet(thisWeek) else { continue }
            guard let previous, let last = topSet(previous) else {
                firstTimes += 1
                continue
            }
            if let change = compare(exerciseId, best, last) { changes.append(change) }
        }
        changes.sort { left, right in
            func rank(_ direction: ExerciseChange.Direction) -> Int {
                switch direction { case .up: return 0; case .down: return 1; case .same: return 2 }
            }
            return rank(left.direction) < rank(right.direction)
        }

        // What the data can't support.
        var dataNotes: [String] = []
        let everTrained = !history.sessions.isEmpty
        if !everTrained {
            dataNotes.append("No workouts logged yet. After your first one, this review shows what you did and what changed.")
        } else if structured.isEmpty {
            dataNotes.append(week.completed > 0
                ? "This week's workouts were saved without set details, so there's nothing to compare."
                : "No workouts logged this week\(isCurrentWeek ? " yet" : "").")
        } else {
            if changes.isEmpty && firstTimes > 0 {
                dataNotes.append("Every exercise this week was new to your log. Comparisons start the second time you do one.")
            } else if firstTimes > 0 {
                dataNotes.append("\(Wording.countLabel(firstTimes, "exercise")) had no earlier session to compare with yet.")
            }
            let sets = structured.flatMap(\.exercises).flatMap(\.sets).filter(Volume.isWorkingSet)
            let withEffort = sets.filter { Strength.observedRir($0) != nil }.count
            if !sets.isEmpty, withEffort < sets.count {
                dataNotes.append("Reps left was recorded on \(withEffort) of \(sets.count) working sets. Without it RAUTA can't tell how hard a set was, so it holds those loads.")
            }
        }

        let headline: String = {
            if !everTrained { return "Your first week starts with one workout" }
            if week.planned > 0 {
                if week.completedPlanned == week.planned { return "Every planned session done" }
                return "\(week.completedPlanned) of \(week.planned) planned sessions"
            }
            if week.completed > 0 { return "\(Wording.countLabel(week.completed, "session")) this week" }
            return "A quiet week so far"
        }()

        return WeeklyReview(
            week: week,
            headline: headline,
            consistency: consistency,
            changes: Array(changes.prefix(5)),
            dataNotes: dataNotes,
            next: nextAction(week: week, next: next, hasPlan: hasPlan, structured: structured, everTrained: everTrained,
                             isCurrentWeek: isCurrentWeek),
            isEmpty: !everTrained
        )
    }

    /// The heaviest set, then the one with most reps at it.
    static func topSet(_ sets: [CompletedSet]) -> CompletedSet? {
        sets.max { left, right in
            let a = left.resistance.kg ?? 0, b = right.resistance.kg ?? 0
            return a != b ? a < b : left.reps < right.reps
        }
    }

    /// Like for like only: the same exercise, the same kind of resistance,
    /// and for weights the same station and basis.
    static func compare(_ exerciseId: String, _ now: CompletedSet, _ then: CompletedSet) -> ExerciseChange? {
        let name = ExerciseCatalogue.name(exerciseId)?.capitalized ?? "Exercise"
        guard now.resistance.type == then.resistance.type else { return nil }
        func change(_ text: String, _ direction: ExerciseChange.Direction, estimate: String? = nil) -> ExerciseChange {
            ExerciseChange(exerciseId: exerciseId, name: name, text: text, direction: direction, estimate: estimate)
        }
        switch now.resistance.type {
        case .externalLoad, .assistance:
            guard now.resistance.stationId == then.resistance.stationId,
                  now.resistance.basis == then.resistance.basis,
                  let kg = now.resistance.kg, let lastKg = then.resistance.kg
            else { return nil }
            let each = now.resistance.basis == .perImplement ? " each" : ""
            let assisted = now.resistance.type == .assistance
            var estimate: String?
            if let a = Strength.estimate(now, using: .epley), let b = Strength.estimate(then, using: .epley) {
                estimate = "Estimated 1RM \(Resistance.formatKg(b.estimated1RMKg)) → \(Resistance.formatKg(a.estimated1RMKg)) kg — an estimate from hard sets, not a lift."
            }
            if kg != lastKg {
                // Less assistance is progress on an assisted machine.
                let better = assisted ? kg < lastKg : kg > lastKg
                let word = assisted ? "assistance" : "top set"
                return change(
                    "\(word.capitalizedFirst) \(Resistance.formatKg(lastKg)) → \(Resistance.formatKg(kg)) kg\(each), \(Num.trimmed(now.reps)) reps.",
                    better ? .up : .down, estimate: estimate
                )
            }
            if now.reps != then.reps {
                let more = now.reps > then.reps
                return change(
                    "\(Num.trimmed(abs(now.reps - then.reps))) \(more ? "more" : "fewer") reps at \(Resistance.formatKg(kg)) kg\(each) (\(Num.trimmed(then.reps)) → \(Num.trimmed(now.reps))).",
                    more ? .up : .down, estimate: estimate
                )
            }
            return change("Same as last time: \(Num.trimmed(now.reps)) reps at \(Resistance.formatKg(kg)) kg\(each).", .same)
        case .bodyweight, .bandResistance:
            guard now.reps != then.reps else {
                return change("Same as last time: \(Num.trimmed(now.reps)) reps.", .same)
            }
            let more = now.reps > then.reps
            return change("Best set \(Num.trimmed(then.reps)) → \(Num.trimmed(now.reps)) reps.", more ? .up : .down)
        case .unknown:
            return nil
        }
    }

    static func nextAction(
        week: WeekProgress,
        next: NextWorkout,
        hasPlan: Bool,
        structured: [CompletedSession],
        everTrained: Bool,
        isCurrentWeek: Bool
    ) -> NextAction {
        if !hasPlan && !everTrained {
            return NextAction(title: "Build a starter plan", detail: "Tell RAUTA when you can train and it builds your first week.", kind: .buildPlan)
        }
        if isCurrentWeek, !week.missed.isEmpty, !week.remaining.isEmpty || hasPlan {
            return NextAction(
                title: "Adjust the rest of your week",
                detail: "You missed \(Wording.countLabel(week.missed.count, "session")). Move it, or fold its work into what's left.",
                kind: .adjust
            )
        }
        let sets = structured.flatMap(\.exercises).flatMap(\.sets).filter(Volume.isWorkingSet)
        let withEffort = sets.filter { Strength.observedRir($0) != nil }.count
        if sets.count >= 3, Double(withEffort) < Double(sets.count) * 0.5 {
            return NextAction(
                title: "Record reps left on your sets",
                detail: "One tap after each set. It's how RAUTA knows when a load is ready to go up.",
                kind: .recordEffort
            )
        }
        switch next.state {
        case .today(let workout):
            return NextAction(title: "Start \(workout.name) today", detail: "It's on your plan for today.", kind: .start(workoutId: workout.id))
        case .restDay(let workout?), .doneToday(let workout?), .upcoming(let workout):
            if isCurrentWeek, week.remaining.isEmpty || workout.date > week.sunday {
                return NextAction(title: "Plan your next week", detail: "Same exercises carried on where they're working, loads progressed from what you logged.", kind: .nextWeek)
            }
            return NextAction(title: "Next: \(workout.name), \(CalendarDate.short(workout.date))", detail: "Rest until then — that's part of the plan.", kind: .none)
        case .planFinished, .restDay(nil), .doneToday(nil):
            return NextAction(title: "Plan your next week", detail: "Same exercises carried on where they're working, loads progressed from what you logged.", kind: .nextWeek)
        case .noPlan:
            return NextAction(title: "Build a plan", detail: "Pick the days you can train and RAUTA builds the week.", kind: .buildPlan)
        case .running:
            return NextAction(title: "Finish your workout", detail: "Your review updates when it's saved.", kind: .none)
        }
    }
}
