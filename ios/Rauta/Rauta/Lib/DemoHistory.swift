#if DEBUG
import Foundation

/// Ten weeks of believable training for an empty simulator, so the pages that
/// show history have something to show in screenshots: `--demo-history`.
///
/// Debug builds only. It adds to what is there, once: the workouts it writes
/// carry its prefix, and a later launch finds them and leaves the stores be.
/// Everything goes through the validator first, like any other write.
enum DemoHistory {
    static let prefix = "demo-history-"

    static func seedIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains("--demo-history"),
              !WorkoutsStore.shared.workouts.contains(where: { $0.id.hasPrefix(prefix) })
        else { return }
        let (workouts, sessions) = build()
        var next = TrainingRecordsStore.shared.data
        next.sessions += sessions
        next = PersistenceValidation.normalize(next)
        let issues = PersistenceValidation.validate(next)
        guard issues.isEmpty else {
            print("DemoHistory: not seeded —", issues.prefix(5).map { "\($0.path): \($0.message)" })
            return
        }
        WorkoutsStore.shared.replaceAll(WorkoutsStore.shared.workouts + workouts)
        TrainingRecordsStore.shared.replaceAll(next)
    }

    private struct Lift {
        var name: String
        var startKg: Double
        var reps: Double
    }

    /// A push, pull, legs rotation. The loads climb a little week by week.
    private static let rotation: [(name: String, lifts: [Lift])] = [
        ("Push", [
            Lift(name: "barbell bench press", startKg: 60, reps: 8),
            Lift(name: "dumbbell shoulder press", startKg: 16, reps: 10),
            Lift(name: "cable triceps pushdown", startKg: 25, reps: 12),
        ]),
        ("Pull", [
            Lift(name: "pull up", startKg: 0, reps: 8),
            Lift(name: "barbell bent over row", startKg: 50, reps: 10),
            Lift(name: "dumbbell biceps curl", startKg: 12, reps: 12),
        ]),
        ("Legs", [
            Lift(name: "barbell full squat", startKg: 80, reps: 6),
            Lift(name: "barbell romanian deadlift", startKg: 70, reps: 8),
            Lift(name: "dumbbell lunge", startKg: 14, reps: 10),
        ]),
    ]

    private static func build(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ([Workout], [PersistedCompletedSession]) {
        var random = SplitMix(seed: 0x5EED)
        var workouts: [Workout] = []
        var sessions: [PersistedCompletedSession] = []
        let today = calendar.startOfDay(for: now)
        var count = 0

        for daysAgo in stride(from: 70, through: 1, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            // Monday, Wednesday and Friday, now and then a Saturday, and now and
            // then a day missed.
            let weekday = calendar.component(.weekday, from: day)
            let usual = [2, 4, 6].contains(weekday)
            let extra = weekday == 7 && random.unit() < 0.3
            guard (usual || extra), random.unit() > 0.15 else { continue }

            let template = rotation[count % rotation.count]
            let weeks = Double(70 - daysAgo) / 7
            let startMinute = 17 * 60 + Int(random.unit() * 150)
            guard let started = calendar.date(byAdding: .minute, value: startMinute, to: day) else { continue }
            let minutes = 42 + random.unit() * 30
            let completed = started.addingTimeInterval(minutes * 60)

            let workoutId = "\(prefix)\(count)"
            var exercises: [PersistedCompletedExercise] = []
            var clock = started.addingTimeInterval(4 * 60)
            for (index, lift) in template.lifts.enumerated() {
                guard let exercise = ExerciseResolver.resolve(lift.name).first?.exercise,
                      let mode = Resistance.modes(for: exercise).first
                else { continue }
                let context = Resistance.loadContext(for: exercise, mode: mode)
                let step = context.grid.incrementKg ?? 2.5
                let working = (lift.startKg * (1 + 0.02 * weeks) / step).rounded() * step
                var sets: [CompletedSet] = []
                for number in 0..<4 {
                    // A lighter warm-up first, then three working sets.
                    let warmup = number == 0 && lift.startKg > 0
                    let kg = warmup ? (working * 0.6 / step).rounded() * step : working
                    let reps = warmup ? lift.reps : max(1, lift.reps - Double(max(0, number - 1)) + (random.unit() < 0.3 ? 1 : 0))
                    clock = clock.addingTimeInterval(warmup ? 90 : 150)
                    sets.append(CompletedSet(
                        id: "\(workoutId)-e\(index)-s\(number)",
                        plannedSetId: nil,
                        reps: reps,
                        resistance: Resistance.makeResistance(mode, kg, context),
                        rir: warmup ? nil : 2,
                        rpe: nil,
                        completed: true,
                        setType: warmup ? .warmup : .working,
                        side: .both,
                        timestamp: ISOTime.string(from: min(clock, completed))
                    ))
                }
                exercises.append(PersistedCompletedExercise(
                    id: "\(workoutId)-e\(index)",
                    exerciseId: exercise.id,
                    plannedExerciseId: nil,
                    exerciseNameSnapshot: nil,
                    sets: sets
                ))
            }
            guard !exercises.isEmpty else { continue }

            let startedISO = ISOTime.string(from: started)
            let completedISO = ISOTime.string(from: completed)
            workouts.append(Workout(
                id: workoutId,
                name: template.name,
                date: CalendarDate.toISO(day),
                exerciseIds: exercises.map(\.exerciseId),
                completion: WorkoutCompletion(
                    startedAt: startedISO,
                    completedAt: completedISO,
                    durationMs: minutes * 60_000,
                    completedExerciseIds: exercises.map(\.exerciseId),
                    activeCalories: (minutes * 5.5).rounded(),
                    healthSyncStatus: .notRequested
                ),
                createdAt: startedISO,
                updatedAt: completedISO
            ))
            sessions.append(PersistedCompletedSession(
                id: "\(workoutId)-session",
                sourceWorkoutId: workoutId,
                plannedProgramId: nil,
                plannedSessionId: nil,
                startedAt: startedISO,
                completedAt: completedISO,
                durationSeconds: minutes * 60,
                status: .completed,
                exercises: exercises
            ))
            count += 1
        }
        return (workouts, sessions)
    }

    /// The same "random" history on every simulator.
    private struct SplitMix {
        var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func unit() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }
}
#endif
