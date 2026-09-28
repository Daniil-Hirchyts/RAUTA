import Foundation

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
