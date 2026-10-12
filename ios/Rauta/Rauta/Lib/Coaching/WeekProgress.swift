import Foundation

/// One training week, Monday to Sunday — the week plans are built in — as it
/// stands: what was planned, what was done, which days were meant for rest.
///
/// A plain fold over the workout list and the training records, so the same
/// answer reaches Summary, the weekly review and RAUTA.
struct WeekProgress: Hashable {
    enum DayStatus: Hashable {
        /// Trained, whether it was planned or not.
        case done
        /// Something planned, today or still ahead.
        case planned
        /// Something planned on a day now past, not done.
        case missed
        /// Nothing planned, in a week that has a plan: a rest day, on purpose.
        case rest
        /// Nothing planned and no plan to say otherwise.
        case open
    }

    struct Day: Hashable, Identifiable {
        var date: String
        var status: DayStatus
        var workouts: [Workout]
        var isToday: Bool
        var id: String { date }
    }

    /// "YYYY-MM-DD" of the Monday.
    var monday: String
    var days: [Day]
    /// Workouts scheduled in the week, done or not, and not withdrawn by a
    /// later plan.
    var planned: Int
    /// Of those, the ones done.
    var completedPlanned: Int
    /// Done without having been scheduled for that day: an extra session.
    var extra: Int
    var missed: [Workout]
    var remaining: [Workout]
    /// Whether the week has any planned training at all.
    var hasPlan: Bool

    var sunday: String { CalendarDate.shift(monday, by: 6) }
    var completed: Int { completedPlanned + extra }
    var restDays: Int { days.filter { $0.status == .rest }.count }

    /// "Mon 5 – Sun 11 Oct".
    var label: String { "\(CalendarDate.short(monday)) – \(CalendarDate.short(sunday))" }

    static func mondayOf(_ day: String) -> String {
        String(EngineWorkout.mondayFor(day).prefix(10))
    }

    @MainActor
    static func current(today: String = CalendarDate.today) -> WeekProgress {
        build(
            monday: mondayOf(today),
            today: today,
            workouts: WorkoutsStore.shared.workouts,
            records: TrainingRecordsStore.shared.data,
            activeWorkoutId: ActiveWorkoutStore.shared.session?.workoutId
        )
    }

    @MainActor
    static func week(of day: String, today: String = CalendarDate.today) -> WeekProgress {
        build(
            monday: mondayOf(day),
            today: today,
            workouts: WorkoutsStore.shared.workouts,
            records: TrainingRecordsStore.shared.data,
            activeWorkoutId: ActiveWorkoutStore.shared.session?.workoutId
        )
    }

    static func build(
        monday: String,
        today: String,
        workouts: [Workout],
        records: PersistedTrainingState,
        activeWorkoutId: String?
    ) -> WeekProgress {
        let sunday = CalendarDate.shift(monday, by: 6)
        let recordedPlanned = Set(records.sessions.compactMap(\.plannedSessionId))
        let recordedWorkouts = Set(records.sessions.compactMap(\.sourceWorkoutId))

        func isDone(_ workout: Workout) -> Bool {
            workout.completion != nil
                || recordedWorkouts.contains(workout.id)
                || workout.planned.map { recordedPlanned.contains($0.sessionId) } == true
        }

        let inWeek = workouts.filter { workout in
            guard workout.date >= monday, workout.date <= sunday else { return false }
            // A planned session a later plan withdrew was never "planned" for
            // this week any more — unless it was trained anyway.
            if let planned = workout.planned, !isDone(workout), workout.id != activeWorkoutId,
               ProgramRecords.isSupersededPlannedSession(records, planned.programId, planned.sessionId) {
                return false
            }
            return true
        }

        // Scheduled before the day came: planned. Created on the day it was
        // trained and done that day: an extra session, not a plan kept.
        func wasScheduled(_ workout: Workout) -> Bool {
            if workout.planned != nil { return true }
            return String(workout.createdAt.prefix(10)) < workout.date || !isDone(workout)
        }

        let planned = inWeek.filter(wasScheduled)
        let completedPlanned = planned.filter(isDone).count
        let extra = inWeek.filter { !wasScheduled($0) && isDone($0) }.count
        let missed = planned.filter { !isDone($0) && $0.date < today && $0.id != activeWorkoutId }
        let remaining = planned.filter { !isDone($0) && ($0.date >= today || $0.id == activeWorkoutId) }
        let hasPlan = !planned.isEmpty

        let days = (0..<7).map { offset -> Day in
            let date = CalendarDate.shift(monday, by: offset)
            let onDay = inWeek.filter { $0.date == date }
            let status: DayStatus
            if onDay.contains(where: isDone) {
                status = .done
            } else if onDay.contains(where: { !isDone($0) }) {
                status = date < today ? .missed : .planned
            } else {
                status = hasPlan ? .rest : .open
            }
            return Day(date: date, status: status, workouts: onDay, isToday: date == today)
        }

        return WeekProgress(
            monday: monday,
            days: days,
            planned: planned.count,
            completedPlanned: completedPlanned,
            extra: extra,
            missed: missed.sorted { $0.date < $1.date },
            remaining: remaining.sorted { $0.date < $1.date },
            hasPlan: hasPlan
        )
    }

    /// "2 of 3 planned sessions", or what there is to say without a plan.
    var summary: String {
        if planned == 0 {
            return completed == 0 ? "Nothing planned this week" : "\(Wording.countLabel(completed, "session")) this week"
        }
        var text = "\(completedPlanned) of \(planned) planned"
        if extra > 0 { text += " + \(extra) extra" }
        return text
    }
}
