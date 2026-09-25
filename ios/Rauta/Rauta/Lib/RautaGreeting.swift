import Foundation

/// What RAUTA says when the app opens: the one thing worth doing next, and that
/// tapping RAUTA will do it.
///
/// Every line that offers something names a job RAUTA's menu leads with at that
/// moment, so "tap me" is always a promise the menu keeps. Nothing here invents
/// a reason to train: a rest day is called one.
enum RautaGreeting {
    struct Day: Equatable {
        var name: String
        var date: String
    }

    struct Input {
        /// The workout being performed, if one is.
        var activeWorkout: String?
        var today: String
        /// Workouts not yet done, in any order. Days already gone are ignored.
        var upcoming: [Day]
        var trainedToday: Bool
        var hasPlan: Bool
    }

    static func line(_ input: Input) -> String {
        if let active = input.activeWorkout {
            return "\(active) is still going. Tap me to jump back in."
        }
        let ahead = input.upcoming
            .filter { $0.date >= input.today }
            .sorted { $0.date < $1.date }
        if let today = ahead.first(where: { $0.date == input.today }) {
            return "\(today.name) is on for today. Tap me and we'll start."
        }
        if input.trainedToday {
            return "Done for today. Nice work."
        }
        if let next = ahead.first {
            return "Rest day. Next up: \(next.name) \(when(next.date, today: input.today))."
        }
        if input.hasPlan {
            return "That plan is done. Tap me and I'll build the next one."
        }
        return "No plan yet. Tap me and I'll build your week."
    }

    private static func when(_ date: String, today: String) -> String {
        if date == CalendarDate.shift(today, by: 1) { return "tomorrow" }
        return "on \(CalendarDate.format(date, "EEEE"))"
    }
}
