import Foundation

// MARK: - Text

enum Wording {
    static func titleCase(_ value: String) -> String {
        var result = ""
        var atWordStart = true
        for character in value {
            if character.isLetter || character.isNumber {
                result.append(atWordStart ? Character(character.uppercased()) : character)
                atWordStart = false
            } else {
                result.append(character)
                atWordStart = true
            }
        }
        return result
    }

    /// "1 workout", "3 workouts". The app counts things in a lot of places and
    /// they should all read the same way.
    static func countLabel(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

// MARK: - Memo

/// Remembers the last answer to an expensive question until it is asked with
/// different inputs.
///
/// Meant for `@State`: as a reference, filling it never triggers a redraw — it
/// only spares the next render the same work. A screen that reads a derived
/// list in several places per render, and once per cell while scrolling, then
/// pays for it once per change of what it is derived from.
final class Memo<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?

    func callAsFunction(_ key: Key, _ compute: () -> Value) -> Value {
        if let value, self.key == key { return value }
        let computed = compute()
        self.key = key
        value = computed
        return computed
    }
}

// MARK: - Calendar dates

/// Local calendar dates as "YYYY-MM-DD", with no time-of-day or timezone
/// shifting — the shape every workout is filed under.
enum CalendarDate {
    private static let calendar = Calendar.current

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func toISO(_ date: Date) -> String { isoFormatter.string(from: date) }

    static func parse(_ iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0, parts[1] > 0, parts[2] > 0 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    static func shift(_ iso: String, by days: Int) -> String {
        guard let date = parse(iso), let shifted = calendar.date(byAdding: .day, value: days, to: date)
        else { return iso }
        return toISO(shifted)
    }

    /// One formatter per template and locale. Building a `DateFormatter` costs
    /// far more than using one, and date labels are drawn on every row of every
    /// list.
    private static let formatters: NSCache<NSString, DateFormatter> = {
        let cache = NSCache<NSString, DateFormatter>()
        cache.countLimit = 32
        return cache
    }()

    /// `date` in the current locale's own rendering of `template` ("MMMM",
    /// "EEEMMMd"…).
    static func string(from date: Date, template: String) -> String {
        let locale = Locale.current
        let key = "\(locale.identifier)|\(template)" as NSString
        let formatter: DateFormatter
        if let cached = formatters.object(forKey: key) {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(template)
            formatters.setObject(formatter, forKey: key)
        }
        return formatter.string(from: date)
    }

    static func format(_ iso: String, _ template: String) -> String {
        guard let date = parse(iso) else { return iso }
        return string(from: date, template: template)
    }

    static func short(_ iso: String) -> String { format(iso, "EEEMMMd") }
    static func long(_ iso: String) -> String { format(iso, "EEEEMMMMd") }
    static func weekdayShort(_ iso: String) -> String { format(iso, "EEE") }
    static func monthShort(_ iso: String) -> String { format(iso, "MMM") }
    /// The day of the month on its own, for a date stamp that shows the weekday
    /// above it and the month below.
    static func dayOfMonth(_ iso: String) -> String { format(iso, "d") }

    static var today: String { toISO(Date()) }
}

// MARK: - Active session

/// A workout being performed right now. The timer is stored as a running
/// stretch plus banked time rather than a tick count, so it survives a relaunch,
/// a backgrounded app and a suspended process without drifting — and so the
/// Live Activity can be handed a single start instant and left to count on its
/// own.
struct ActiveWorkoutSession: Codable, Hashable, Sendable {
    var workoutId: String
    var workoutName: String
    var workoutDate: String
    var exerciseIds: [String]
    var completedIds: [String]
    var currentExerciseId: String?
    /// Epoch ms the current running stretch began; nil while paused.
    var runningSince: Double?
    /// Elapsed time banked by every stretch before the current one.
    var accumulatedMs: Double
    var startedAt: Double
    /// Epoch ms when the current set phase began. Unlike a view-local timer,
    /// this survives tab changes, backgrounding and relaunches with the session.
    var setPhaseStartedAt: Double?
    /// Epoch ms when the current rest period ends. While this is in the future
    /// the UI counts down; afterwards the next set counts up from that instant.
    var restUntil: Double?
    /// Epoch ms when the warm-up that opens the workout ends. Set only while
    /// the warm-up is on; the first set is due when it is cleared.
    var warmupUntil: Double? = nil
}

enum ExerciseStatus: String { case pending, active, completed }

enum ActiveWorkout {
    /// JavaScript's `Date.now()` — used by the React app and persisted transition
    /// journal — is an integer millisecond timestamp. Keep the native port on the
    /// same precision so an ISO-8601 round trip compares exactly in validation.
    static func nowMillis() -> Double {
        (Date().timeIntervalSince1970 * 1000).rounded(.down)
    }

    static func elapsedMs(_ session: ActiveWorkoutSession, now: Double = ActiveWorkout.nowMillis()) -> Double {
        let running = session.runningSince.map { now - $0 } ?? 0
        return Swift.max(0, session.accumulatedMs + running)
    }

    /// The instant a stopwatch would have to have been started for it to read
    /// `elapsedMs` right now. `Text(timerInterval:)` counts from a date entirely
    /// on its own, so shifting that date is how a paused and resumed workout
    /// stays correct without pushing an update every second.
    static func timerStartEpochMs(
        _ session: ActiveWorkoutSession,
        now: Double = ActiveWorkout.nowMillis()
    ) -> Double {
        now - elapsedMs(session, now: now)
    }

    static func formatDuration(_ ms: Double) -> String {
        ElapsedClock.format(seconds: Int(Swift.max(0, ms) / 1000))
    }

    static func status(_ session: ActiveWorkoutSession, _ exerciseId: String) -> ExerciseStatus {
        if session.completedIds.contains(exerciseId) { return .completed }
        return session.currentExerciseId == exerciseId ? .active : .pending
    }

    struct Progress {
        var completed: Int
        var total: Int
        var isComplete: Bool
    }

    static func progress(_ session: ActiveWorkoutSession) -> Progress {
        let completed = session.exerciseIds.filter { session.completedIds.contains($0) }.count
        return Progress(
            completed: completed,
            total: session.exerciseIds.count,
            isComplete: !session.exerciseIds.isEmpty && completed == session.exerciseIds.count
        )
    }

    /// The exercise to move to after `fromId` is done: the next one still
    /// pending in list order, wrapping past the end so an exercise skipped
    /// earlier is picked up rather than stranded. Nil once nothing is left.
    static func nextPendingExerciseId(
        _ session: ActiveWorkoutSession,
        from fromId: String? = nil
    ) -> String? {
        let target = fromId ?? session.currentExerciseId
        let ids = session.exerciseIds
        guard !ids.isEmpty else { return nil }
        let start = target.flatMap { ids.firstIndex(of: $0) } ?? -1

        for step in 1...ids.count {
            let index = ((start + step) % ids.count + ids.count) % ids.count
            let id = ids[index]
            if id != target && !session.completedIds.contains(id) { return id }
        }
        return nil
    }

    static func currentExercise(_ session: ActiveWorkoutSession) -> ExerciseSummary? {
        session.currentExerciseId.flatMap { ExerciseCatalogue.byId[$0] }
    }
}

// MARK: - Workout statistics

enum WorkoutStats {
    /// Moderate-to-vigorous resistance training, expressed as a MET estimate.
    private static let strengthTrainingMET = 6.0
    private static let fallbackBodyWeightKg = 75.0

    /// Standard MET energy estimate: MET × 3.5 × kilograms / 200 × minutes.
    /// HealthKit weight is used when available; the conservative fallback keeps
    /// history useful without pretending the number is a measurement.
    static func estimateStrengthCalories(_ durationMs: Double, bodyWeightKg: Double?) -> Double {
        let minutes = Swift.max(0, durationMs) / 60_000
        let kilograms: Double = {
            if let bodyWeightKg, bodyWeightKg >= 30, bodyWeightKg <= 300 { return bodyWeightKg }
            return fallbackBodyWeightKg
        }()
        let estimate = (strengthTrainingMET * 3.5 * kilograms * minutes / 200).rounded()
        return Swift.max(durationMs > 0 ? 1 : 0, estimate)
    }
}

// MARK: - Streak

/// The strip is the week being lived in: Monday first, Sunday last.
let STREAK_DAYS = 7

struct StreakDay: Identifiable, Hashable {
    var date: String
    var workouts: Int
    var exercises: Int
    /// Still ahead this week: drawn cold, and never counted as a day missed.
    var isFuture: Bool
    var isToday: Bool

    var id: String { date }
}

struct Streak: Hashable {
    var week: [StreakDay]
    /// Consecutive trained days, counted back from today.
    var currentStreak: Int
    var longestStreak: Int
    var weekWorkouts: Int

    static let empty = Streak(week: [], currentStreak: 0, longestStreak: 0, weekWorkouts: 0)
}

enum StreakBuilder {
    private static func startOfWeek(_ date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let start = calendar.date(from: components) ?? date
        // Monday-first, so the strip reads the way a training week is planned.
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: start) ?? start
    }

    struct DayTotal { var workouts: Int; var exercises: Int }

    private static func dailyTotals(_ workouts: [Workout]) -> [String: DayTotal] {
        var totals: [String: DayTotal] = [:]
        for workout in workouts {
            var day = totals[workout.date] ?? DayTotal(workouts: 0, exercises: 0)
            day.workouts += 1
            day.exercises += workout.exerciseIds.count
            totals[workout.date] = day
        }
        return totals
    }

    /// The run ending now. A day still being lived in has not broken anything
    /// yet: with nothing logged today the count picks up from yesterday, so the
    /// streak only lapses once a whole day has passed untrained.
    private static func currentRun(_ dates: Set<String>, _ todayISO: String) -> Int {
        var date = dates.contains(todayISO) ? todayISO : CalendarDate.shift(todayISO, by: -1)
        var streak = 0
        while dates.contains(date) {
            streak += 1
            date = CalendarDate.shift(date, by: -1)
        }
        return streak
    }

    private static func longestRun(_ dates: Set<String>) -> Int {
        var longest = 0
        var run = 0
        var previous: String?
        for date in dates.sorted() {
            run = (previous.map { CalendarDate.shift($0, by: 1) == date } ?? false) ? run + 1 : 1
            previous = date
            longest = Swift.max(longest, run)
        }
        return longest
    }

    static func build(_ workouts: [Workout], today: Date = Date()) -> Streak {
        let totals = dailyTotals(workouts)
        let trained = Set(totals.keys)
        let todayISO = CalendarDate.toISO(today)
        let monday = CalendarDate.toISO(startOfWeek(today))

        let week = (0..<STREAK_DAYS).map { index -> StreakDay in
            let date = CalendarDate.shift(monday, by: index)
            let day = totals[date] ?? DayTotal(workouts: 0, exercises: 0)
            return StreakDay(
                date: date,
                workouts: day.workouts,
                exercises: day.exercises,
                isFuture: date > todayISO,
                isToday: date == todayISO
            )
        }

        return Streak(
            week: week,
            currentStreak: currentRun(trained, todayISO),
            longestStreak: longestRun(trained),
            weekWorkouts: week.reduce(0) { $0 + $1.workouts }
        )
    }
}

// MARK: - Progression notes

/// The engine's recommendation, in one line RAUTA can say. Every line is a
/// translation of a reason the engine actually returned, and nothing is added
/// on top. If a reason is ever added to the engine and not here, the line is
/// simply omitted: silence is the only honest fallback.
struct ProgressionNote {
    /// The load to put on, when the engine could name one.
    var kg: Double?
    /// Whether that load is measured on one implement or on the pair.
    var basis: LoadBasis?
    var text: String
}

enum ProgressionNotes {
    private static func delta(_ recommendation: ProgressionRecommendation, _ previousKg: Double) -> String? {
        guard let kg = recommendation.resistance.kg else { return nil }
        let difference = abs(kg - previousKg)
        return difference > 0 ? "\(Resistance.formatKg(difference)) kg" : nil
    }

    /// - Parameter previousKg: The load the recommendation moved away from,
    ///   when the caller knows it. Only used to say how large the step is.
    static func note(
        _ recommendation: ProgressionRecommendation,
        previousKg: Double? = nil
    ) -> ProgressionNote? {
        let action = recommendation.action
        let reason = recommendation.reasons.first
        let kg = recommendation.resistance.kg
        let basis = recommendation.resistance.basis
        let targetReps = recommendation.targetReps
        let step = previousKg.flatMap { delta(recommendation, $0) }

        func note(_ text: String) -> ProgressionNote {
            ProgressionNote(kg: kg, basis: basis, text: text)
        }

        switch action {
        case .increaseLoad:
            if reason == .coarseLoadGrid {
                return note("Smallest step here is\(step.map { " \($0)" } ?? ""). Take it.")
            }
            return note("You hit the top of the range last time.\(step.map { " +\($0)." } ?? "")")

        case .decreaseLoad:
            return note(
                "Two sessions short of the range.\(step.map { " −\($0)." } ?? "") Rebuild from here."
            )

        case .reduceAssistance:
            return note("Top of the range last time.\(step.map { " \($0) less assist." } ?? "")")

        case .increaseAssistance:
            return note("Short of the range twice.\(step.map { " \($0) more assist." } ?? "")")

        case .increaseReps:
            if reason == .coarseLoadGrid {
                return note(
                    "Next load up is a big jump. Add reps first — up to \(Num.trimmed(targetReps.max))."
                )
            }
            return note("Top of the range last time. Go for \(Num.trimmed(targetReps.max)) reps.")

        case .coarseGridProgression:
            return note(
                "This station jumps too far in one step. Hold the load and work to "
                    + "\(Num.trimmed(targetReps.max)) reps."
            )

        case .hold:
            switch reason {
            case .incompleteSets: return note("Last session came up short. Same load again.")
            case .missingEffort: return note("No RIR logged last time, so nothing to progress from.")
            case .incrementTooLarge: return note("A step down here is too big. Hold this load.")
            case .gridUnavailable: return note("I do not know this station's steps yet. Hold this load.")
            case .withinRange: return note("Keep this load until you reach the top of the range.")
            default: return nil
            }

        case .calibrate:
            switch reason {
            case .contextChanged: return note("Different station today — recalibrating.")
            case .staleHistory: return note("It has been a while. Find the load again, easy first set.")
            case .gridUnavailable: return note("Set this station's load step and I can progress it.")
            // No history is not a remark. The card already opens on the plan's
            // reps with the load at zero, which says the same thing.
            default: return nil
            }
        }
    }
}
