import Foundation

/// What to train next, decided from the workout list, the running session and
/// the plan — the answer at the top of Summary.
///
/// Pure over its inputs, so every case is pinned in a test.
struct NextWorkout: Equatable {
    enum State: Equatable {
        /// A workout is running: go back to it.
        case running(Workout)
        /// A workout is scheduled today and can be started.
        case today(Workout)
        /// Trained today already; `next` is what comes after, if anything.
        case doneToday(next: Workout?)
        /// Nothing today, in a week with a plan: a rest day.
        case restDay(next: Workout?)
        /// Workouts are scheduled ahead, but no plan holds them.
        case upcoming(Workout)
        /// A plan existed and has nothing left in it.
        case planFinished
        /// No plan and nothing scheduled.
        case noPlan
    }

    var state: State

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }
    /// Planned workouts this week on days now past, not done.
    var missed: [Workout]
    var week: WeekProgress

    static func resolve(
        workouts: [Workout],
        records: PersistedTrainingState,
        activeWorkoutId: String?,
        today: String
    ) -> NextWorkout {
        let week = WeekProgress.build(
            monday: WeekProgress.mondayOf(today),
            today: today,
            workouts: workouts,
            records: records,
            activeWorkoutId: activeWorkoutId
        )
        let timeline = WorkoutTimeline(workouts: workouts, records: records, activeWorkoutId: activeWorkoutId)
        let hasPlan = records.activeProgramId != nil

        if let id = activeWorkoutId, let running = workouts.first(where: { $0.id == id }) {
            return NextWorkout(state: .running(running), missed: week.missed, week: week)
        }

        // What can still be trained: today or later, with exercises in it, and
        // — for a planned one — still part of the current plan.
        let ahead = timeline.upcoming.filter { workout in
            guard workout.date >= today, !workout.exerciseIds.isEmpty else { return false }
            guard let planned = workout.planned else { return true }
            return workout.date == today
                || ProgramRecords.isStartablePlannedSession(records, planned.programId, planned.sessionId)
        }
        let next = ahead.first { $0.date > today }

        if let todays = ahead.first(where: { $0.date == today }) {
            return NextWorkout(state: .today(todays), missed: week.missed, week: week)
        }
        if week.days.first(where: \.isToday)?.status == .done {
            return NextWorkout(state: .doneToday(next: next), missed: week.missed, week: week)
        }
        if let next {
            let state: State = (next.planned != nil || week.hasPlan) ? .restDay(next: next) : .upcoming(next)
            return NextWorkout(state: state, missed: week.missed, week: week)
        }
        if hasPlan || !records.programs.isEmpty {
            return NextWorkout(state: .planFinished, missed: week.missed, week: week)
        }
        return NextWorkout(state: .noPlan, missed: week.missed, week: week)
    }

    @MainActor
    static func current() -> NextWorkout {
        resolve(
            workouts: WorkoutsStore.shared.workouts,
            records: TrainingRecordsStore.shared.data,
            activeWorkoutId: ActiveWorkoutStore.shared.session?.workoutId,
            today: CalendarDate.today
        )
    }
}
