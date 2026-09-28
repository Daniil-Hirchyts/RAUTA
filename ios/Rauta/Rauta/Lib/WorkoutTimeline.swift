import Foundation

/// Every visible workout, split once into what is still ahead and what is done.
/// A workout is upcoming while it is the one in progress, or not yet completed
/// and not already recorded against its planned session. A planned session a
/// later plan has replaced is not shown at all.
struct WorkoutTimeline {
    var upcoming: [Workout]
    var past: [Workout]

    init(workouts: [Workout], records: PersistedTrainingState, activeWorkoutId: String?) {
        let recordedSessions = Set(records.sessions.compactMap(\.plannedSessionId))
        var upcoming: [Workout] = []
        var past: [Workout] = []
        for workout in workouts {
            if let planned = workout.planned, workout.completion == nil, workout.id != activeWorkoutId,
               ProgramRecords.isSupersededPlannedSession(records, planned.programId, planned.sessionId) {
                continue
            }
            let recorded = workout.planned.map { recordedSessions.contains($0.sessionId) } ?? false
            if workout.id == activeWorkoutId || (workout.completion == nil && !recorded) {
                upcoming.append(workout)
            } else {
                past.append(workout)
            }
        }
        self.upcoming = upcoming.sorted { $0.date < $1.date }
        self.past = past.sorted { $0.date > $1.date }
    }

    /// The workouts more exercises can still go into, soonest first: still to
    /// come, not overdue, and open to editing right now. A planned workout
    /// can't change while another one runs, nor once its plan was replaced.
    static func destinations(
        workouts: [Workout],
        records: PersistedTrainingState,
        activeWorkoutId: String?,
        excluding excludedId: String? = nil,
        today: String = CalendarDate.today
    ) -> [Workout] {
        WorkoutTimeline(workouts: workouts, records: records, activeWorkoutId: activeWorkoutId)
            .upcoming
            .filter { workout in
                if workout.id == excludedId { return false }
                if workout.id == activeWorkoutId { return true }
                guard workout.date >= today else { return false }
                guard let planned = workout.planned else { return true }
                if activeWorkoutId != nil { return false }
                return ProgramRecords.isStartablePlannedSession(records, planned.programId, planned.sessionId)
            }
    }
}
