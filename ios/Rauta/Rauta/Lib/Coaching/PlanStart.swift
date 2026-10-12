import Foundation

/// When a new plan starts: today, or next week — each with the actual dates it
/// would put sessions on, from the days the person usually trains.
///
/// "Next week" begins on the first day of the week as the person's calendar
/// counts it — Monday in most of Europe, Sunday in the US — while sessions
/// still land only on their chosen weekdays.
enum PlanStart: String, CaseIterable, Identifiable {
    case today
    case nextWeek

    var id: String { rawValue }

    /// ISO weekday of `day`: Monday = 1 … Sunday = 7.
    static func isoWeekday(_ day: String) -> Int {
        let monday = WeekProgress.mondayOf(day)
        guard let start = CalendarDate.parse(monday), let date = CalendarDate.parse(day) else { return 1 }
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: start, to: date).day ?? 0
        return ((days % 7) + 7) % 7 + 1
    }

    /// The dates this start would plan, soonest first.
    func dates(
        trainingDays: [Int],
        today: String = CalendarDate.today,
        firstWeekday: Int = Calendar.current.firstWeekday
    ) -> [String] {
        let days = Set(trainingDays.isEmpty ? TrainingProfile.defaultTrainingDays : trainingDays)
        switch self {
        case .today:
            // Today, then the next chosen weekdays until the week's sessions
            // are there: the first session is not a week away.
            var dates = [today]
            var offset = 1
            while dates.count < days.count, offset <= 13 {
                let date = CalendarDate.shift(today, by: offset)
                if days.contains(Self.isoWeekday(date)) { dates.append(date) }
                offset += 1
            }
            return dates
        case .nextWeek:
            let start = Self.startOfNextWeek(after: today, firstWeekday: firstWeekday)
            return (0..<7)
                .map { CalendarDate.shift(start, by: $0) }
                .filter { days.contains(Self.isoWeekday($0)) }
        }
    }

    /// The first day of the coming week in the person's own calendar.
    /// `firstWeekday` is the `Calendar` convention: 1 = Sunday, 2 = Monday.
    static func startOfNextWeek(after today: String, firstWeekday: Int) -> String {
        // Calendar weekday of today (1 = Sunday … 7 = Saturday).
        let isoToday = isoWeekday(today)
        let calendarToday = isoToday == 7 ? 1 : isoToday + 1
        let ahead = (firstWeekday - calendarToday + 7) % 7
        return CalendarDate.shift(today, by: ahead == 0 ? 7 : ahead)
    }

    func title(_ dates: [String]) -> String {
        switch self {
        case .today: return "Start today"
        case .nextWeek: return "Start next week"
        }
    }

    /// "Sat 10, Mon 12 and Wed 14 Oct".
    static func describe(_ dates: [String]) -> String {
        let sorted = dates.sorted()
        guard let last = sorted.last else { return "No days chosen" }
        let names = sorted.map { CalendarDate.format($0, "EEEd") }
        let month = CalendarDate.monthShort(last)
        return Wording.list(names) + " " + month
    }
}
