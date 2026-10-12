import Foundation

/// What RAUTA says while it plans a week with you: asking, working, and
/// handing over what it built.
///
/// Pure over dates and counts, so every line can be pinned in a test. A line
/// never claims more than the plan holds: the result names the sessions that
/// were actually created.
enum PlanTalk {
    static func asking(selected: [String], minutes: Int, continuing: Bool) -> String {
        guard !selected.isEmpty else {
            return continuing
                ? "Pick the next days. I'll pick up from what you've logged."
                : "Pick the days you can train, and I'll build the week around them."
        }
        return "\(days(selected)). About \(minutes) min each, warm-up and rest included."
    }

    static func working(selected: [String]) -> String {
        "Building your week around \(days(selected))…"
    }

    static func built(dates: [String]) -> String {
        let sorted = dates.sorted()
        guard let first = sorted.first, let last = sorted.last else {
            return "Done, but there was nothing to schedule."
        }
        let count = sorted.count == 1 ? "1 session" : "\(sorted.count) sessions"
        if first == last {
            return "Done! \(count), on \(CalendarDate.format(first, "EEEEMMMd")). Here it is."
        }
        return "Done! \(count), \(CalendarDate.short(first)) to \(CalendarDate.short(last)). Here's your week."
    }

    /// "Mon, Wed and Fri"; past four days it is simply how many.
    static func days(_ dates: [String]) -> String {
        let sorted = dates.sorted()
        guard sorted.count <= 4 else { return "\(sorted.count) days" }
        let names = sorted.map { CalendarDate.weekdayShort($0) }
        guard let last = names.last else { return "" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
    }
}
