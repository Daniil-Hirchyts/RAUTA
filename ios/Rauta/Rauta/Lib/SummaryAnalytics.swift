import Foundation

/// What the Summary detail pages show, built from the stores in one place so
/// the cards on Summary and the pages behind them count the same way.
///
/// A trained workout is found two ways, as everywhere in the app: a structured
/// session (sets, reps, loads) and the workout's own completion (its time and
/// the exercises checked off). A workout counts once, whichever of the two it
/// has.
enum SummaryAnalytics {
    // MARK: Months

    /// "2026-09" for the month containing `date`.
    static func monthKey(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 2000, parts.month ?? 1)
    }

    static func monthInterval(_ key: String, calendar: Calendar = .current) -> DateInterval {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        let start = parts.count == 2
            ? calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
            : nil
        return calendar.dateInterval(of: .month, for: start ?? Date())
            ?? DateInterval(start: start ?? Date(), duration: 1)
    }

    static func monthTitle(_ key: String) -> String {
        let interval = monthInterval(key)
        let sameYear = Calendar.current.isDate(interval.start, equalTo: Date(), toGranularity: .year)
        return CalendarDate.string(from: interval.start, template: sameYear ? "MMMM" : "MMMMyyyy")
    }

    static func shiftMonth(_ key: String, by months: Int, calendar: Calendar = .current) -> String {
        let start = monthInterval(key).start
        return monthKey(calendar.date(byAdding: .month, value: months, to: start) ?? start)
    }

    /// Which of a month's five week columns a day falls in: the calendar's
    /// weeks of the month, the fifth taking whatever runs past it. The Summary
    /// cards and the pages behind them use this one rule.
    static func weekBin(for date: Date, calendar: Calendar = .current) -> Int {
        max(0, min(4, calendar.component(.weekOfMonth, from: date) - 1))
    }

    /// The days each week column covers in a month, as "1–6".
    static func weekRanges(_ key: String, calendar: Calendar = .current) -> [String] {
        let interval = monthInterval(key)
        var ranges: [(first: Int, last: Int)?] = Array(repeating: nil, count: 5)
        var day = interval.start
        while day < interval.end {
            let bin = weekBin(for: day, calendar: calendar)
            let number = calendar.component(.day, from: day)
            ranges[bin] = (ranges[bin]?.first ?? number, number)
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? interval.end
        }
        return ranges.map { range in
            guard let range else { return "" }
            return range.first == range.last ? "\(range.first)" : "\(range.first)–\(range.last)"
        }
    }

    // MARK: Sessions

    /// One trained workout, as the activity page lists it.
    struct SessionRow: Identifiable, Hashable {
        var id: String
        /// The workout to open, when it still exists.
        var workoutId: String?
        var title: String
        var completedAt: Date
        var durationSeconds: Double
        var sets: Int
        var exerciseIds: [String]
        var partial: Bool
    }

    /// Every trained workout, newest first.
    @MainActor
    static func sessions(
        workouts: [Workout] = WorkoutsStore.shared.workouts,
        data: PersistedTrainingState = TrainingRecordsStore.shared.data
    ) -> [SessionRow] {
        var rows: [SessionRow] = []
        var joined = Set<String>()
        let byWorkout = Dictionary(grouping: data.sessions.filter { $0.sourceWorkoutId != nil }) {
            $0.sourceWorkoutId ?? ""
        }

        for workout in workouts {
            let structured = byWorkout[workout.id] ?? []
            structured.forEach { joined.insert($0.id) }
            guard let completion = workout.completion ?? structured.first.map({ session in
                WorkoutCompletion(
                    startedAt: session.startedAt,
                    completedAt: session.completedAt,
                    durationMs: (session.durationSeconds ?? 0) * 1_000,
                    completedExerciseIds: session.exercises.map(\.exerciseId),
                    activeCalories: 0,
                    healthSyncStatus: .notRequested
                )
            }) else { continue }
            guard let completedMs = ISOTime.parse(completion.completedAt) else { continue }
            let sets = structured.reduce(0) { total, session in
                total + session.exercises.reduce(0) { $0 + $1.sets.filter(Volume.isWorkingSet).count }
            }
            let exerciseIds = structured.first?.exercises.map(\.exerciseId)
                ?? (completion.completedExerciseIds.isEmpty ? workout.exerciseIds : completion.completedExerciseIds)
            rows.append(SessionRow(
                id: workout.id,
                workoutId: workout.id,
                title: workout.name,
                completedAt: Date(epochMillis: completedMs),
                durationSeconds: completion.durationMs / 1_000,
                sets: sets,
                exerciseIds: exerciseIds,
                partial: structured.contains { $0.status == .partial }
            ))
        }

        // Sessions whose workout is gone still happened.
        for session in data.sessions where !joined.contains(session.id) {
            guard let completedMs = ISOTime.parse(session.completedAt) else { continue }
            rows.append(SessionRow(
                id: session.id,
                workoutId: nil,
                title: "Workout",
                completedAt: Date(epochMillis: completedMs),
                durationSeconds: session.durationSeconds ?? 0,
                sets: session.exercises.reduce(0) { $0 + $1.sets.filter(Volume.isWorkingSet).count },
                exerciseIds: session.exercises.map(\.exerciseId),
                partial: session.status == .partial
            ))
        }
        return rows.sorted { $0.completedAt > $1.completedAt }
    }

    struct MonthActivity {
        var key: String
        var sessions: [SessionRow]
        var weeklyCounts: [Double]
        var weeklySeconds: [Double]
        var weekRanges: [String]

        var count: Int { sessions.count }
        var totalSeconds: Double { sessions.reduce(0) { $0 + $1.durationSeconds } }
        var averageSeconds: Double { count > 0 ? totalSeconds / Double(count) : 0 }
        var longest: SessionRow? { sessions.max { $0.durationSeconds < $1.durationSeconds } }
        var totalSets: Int { sessions.reduce(0) { $0 + $1.sets } }
    }

    static func activity(_ key: String, sessions all: [SessionRow], calendar: Calendar = .current) -> MonthActivity {
        let interval = monthInterval(key, calendar: calendar)
        let sessions = all.filter { interval.contains($0.completedAt) }
        var counts = Array(repeating: 0.0, count: 5)
        var seconds = Array(repeating: 0.0, count: 5)
        for session in sessions {
            let bin = weekBin(for: session.completedAt, calendar: calendar)
            counts[bin] += 1
            seconds[bin] += session.durationSeconds
        }
        return MonthActivity(
            key: key,
            sessions: sessions,
            weeklyCounts: counts,
            weeklySeconds: seconds,
            weekRanges: weekRanges(key, calendar: calendar)
        )
    }

    /// The first month anything was trained, so paging back stops there.
    static func firstMonth(_ sessions: [SessionRow]) -> String {
        sessions.map(\.completedAt).min().map { monthKey($0) } ?? monthKey()
    }

    // MARK: Streak

    /// The days trained, as ISO dates, the way the streak counts them.
    static func trainedDays(_ workouts: [Workout]) -> Set<String> {
        Set(workouts.filter { $0.completion != nil }.map(\.date))
    }

    // MARK: Muscles

    struct MuscleLoad: Identifiable, Hashable {
        var muscle: MuscleId
        /// Effective sets across the month.
        var sets: Double
        /// Effective sets a week, over the weeks of the month lived so far.
        var perWeek: Double
        /// What the plan aims for a week, when there is a plan.
        var target: ClosedRange<Double>?
        /// Worked out from the exercises checked off rather than from logged
        /// sets — a month trained without logging.
        var estimated = false

        var id: MuscleId { muscle }
    }

    /// The muscles a month worked, most first. Logged sets count when there
    /// are any; a month of workouts finished without logging sets is estimated
    /// from the exercises checked off — the Summary card and the page behind it
    /// both read this, so they always agree.
    @MainActor
    static func muscles(
        _ key: String,
        history: TrainingHistory,
        workouts: [Workout] = WorkoutsStore.shared.workouts,
        now: Date = Date()
    ) -> [MuscleLoad] {
        let interval = monthInterval(key)
        let end = min(now, interval.end)
        let weeks = max(1, end.timeIntervalSince(interval.start) / (7 * 86_400))
        let precise = Volume.historyVolume(
            history,
            TrainingWorkflow.trainingIndex(),
            DEFAULT_POLICY,
            from: interval.start.timeIntervalSince1970 * 1_000,
            to: end.timeIntervalSince1970 * 1_000,
            inclusiveStart: true
        ).mapValues(\.effective)
        let estimated = precise.values.reduce(0, +) <= 0
        let volume = estimated ? exerciseVolume(workouts, in: interval) : precise
        var targets: [MuscleId: ClosedRange<Double>] = [:]
        if let record = TrainingPlan.activeProgramRecord(),
           let week = ProgramRecords.toEngineProgram(record.snapshot).weeks.first {
            for target in week.targets where target.preferred > 0 {
                targets[target.muscleId] = target.minimum...max(target.minimum, target.upperGuideline)
            }
        }
        return volume
            .filter { $0.value > 0 }
            .map {
                MuscleLoad(
                    muscle: $0.key, sets: $0.value, perWeek: $0.value / weeks,
                    target: targets[$0.key], estimated: estimated
                )
            }
            .sorted { $0.sets == $1.sets ? $0.muscle.label < $1.muscle.label : $0.sets > $1.sets }
    }

    /// Each finished workout's exercises, a set's worth each, weighted by how
    /// much each muscle does in them.
    private static func exerciseVolume(_ workouts: [Workout], in interval: DateInterval) -> [MuscleId: Double] {
        var volume: [MuscleId: Double] = [:]
        for workout in workouts {
            guard let completion = workout.completion,
                  let millis = ISOTime.parse(completion.completedAt),
                  interval.contains(Date(epochMillis: millis))
            else { continue }
            let exerciseIds = completion.completedExerciseIds.isEmpty
                ? workout.exerciseIds
                : completion.completedExerciseIds
            for exerciseId in exerciseIds {
                guard let exercise = ExerciseCatalogue.byId[exerciseId] else { continue }
                for (index, muscle) in exercise.muscles.enumerated() {
                    let involvement = exercise.muscleWeights.indices.contains(index)
                        ? exercise.muscleWeights[index]
                        : 1
                    volume[muscle, default: 0] += involvement
                }
            }
        }
        return volume
    }

    // MARK: Records

    /// The best an exercise has seen: its heaviest set and the one-rep max
    /// that set suggests.
    struct ExerciseRecord: Identifiable, Hashable {
        var exerciseId: String
        var heaviestKg: Double
        var heaviestReps: Double
        var basis: LoadBasis?
        /// Epley's estimate, from the best of all working sets.
        var estimatedMaxKg: Double
        var sets: Int
        var lastDone: Date

        var id: String { exerciseId + (basis?.rawValue ?? "") }
    }

    /// Bests from every working set with a load, one per exercise and way of
    /// holding it: 30 kg in each hand is not a 30 kg bar. Assisted sets are
    /// left out, where less is better.
    static func records(_ sessions: [PersistedCompletedSession]) -> [ExerciseRecord] {
        var best: [String: ExerciseRecord] = [:]
        for session in sessions {
            let done = ISOTime.parse(session.completedAt).map { Date(epochMillis: $0) } ?? .distantPast
            for exercise in session.exercises {
                for set in exercise.sets where Volume.isWorkingSet(set) {
                    guard set.resistance.type == .externalLoad, let kg = set.resistance.kg, kg > 0 else { continue }
                    let basis = set.resistance.basis
                    let key = exercise.exerciseId + "|" + (basis?.rawValue ?? "")
                    let estimate = estimatedMax(kg: kg, reps: set.reps)
                    var record = best[key] ?? ExerciseRecord(
                        exerciseId: exercise.exerciseId, heaviestKg: 0, heaviestReps: 0,
                        basis: basis, estimatedMaxKg: 0, sets: 0, lastDone: .distantPast
                    )
                    if kg > record.heaviestKg || (kg == record.heaviestKg && set.reps > record.heaviestReps) {
                        record.heaviestKg = kg
                        record.heaviestReps = set.reps
                    }
                    record.estimatedMaxKg = max(record.estimatedMaxKg, estimate)
                    record.sets += 1
                    record.lastDone = max(record.lastDone, done)
                    best[key] = record
                }
            }
        }
        return best.values.sorted { $0.estimatedMaxKg > $1.estimatedMaxKg }
    }

    /// Epley's one-rep max for a set, counting at most twelve reps: past that
    /// the estimate says more about endurance than strength.
    static func estimatedMax(kg: Double, reps: Double) -> Double {
        kg * (1 + min(reps, 12) / 30)
    }

    /// Whether the newest set of a workout being trained beats the best its
    /// exercise has seen, held the same way — the history's and this
    /// workout's earlier sets alike. An exercise trained for the first time
    /// has no best to beat yet, so its first sets are not one.
    static func isPersonalBest(_ draft: PersistedActiveWorkoutDraft?, history: [PersistedCompletedSession]) -> Bool {
        struct Logged {
            var exerciseId: String
            var setId: String
            var basis: LoadBasis?
            var estimate: Double
            var at: String
        }
        let logged: [Logged] = (draft?.exercises ?? []).flatMap { exercise in
            exercise.sets.compactMap { set -> Logged? in
                guard set.setType == .working || set.setType == .backoff,
                      let observation = set.observation, observation.completed,
                      let reps = observation.reps, reps > 0,
                      let resistance = observation.resistance, resistance.type == .externalLoad,
                      let kg = resistance.kg, kg > 0
                else { return nil }
                return Logged(
                    exerciseId: exercise.exerciseId, setId: set.id, basis: resistance.basis,
                    estimate: estimatedMax(kg: kg, reps: reps), at: observation.timestamp ?? ""
                )
            }
        }
        guard let latest = logged.max(by: { $0.at < $1.at }),
              let before = records(history).first(where: {
                  $0.exerciseId == latest.exerciseId && $0.basis == latest.basis
              })
        else { return false }
        let earlier = logged
            .filter { $0.setId != latest.setId && $0.exerciseId == latest.exerciseId && $0.basis == latest.basis }
            .map(\.estimate)
        let best = ([before.estimatedMaxKg] + earlier).max() ?? before.estimatedMaxKg
        // A rounding hair is not a best.
        return latest.estimate > best + 0.25
    }

    // MARK: Formatting

    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}
