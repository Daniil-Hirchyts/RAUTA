import Foundation

/// A workout as the agent refers to it: what the person calls it and when.
nonisolated struct AgentWorkoutRef: Sendable, Equatable, Hashable {
    var id: String
    var name: String
    /// YYYY-MM-DD.
    var date: String
}

/// Turns what a person said into the things the app works with.
///
/// The model repeats words — "thursday", "leg day", "twice a week" — and these
/// functions decide what they mean. A small model gets weekday arithmetic
/// wrong often enough that it must never be trusted with it, and a number it
/// was not given is one it made up.
nonisolated enum AgentWords {
    // MARK: Days

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    static func isDate(_ text: String) -> Bool {
        text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
            && formatter.date(from: text) != nil
    }

    static func shift(_ day: String, by days: Int) -> String {
        guard let date = formatter.date(from: day),
              let shifted = calendar.date(byAdding: .day, value: days, to: date)
        else { return day }
        return formatter.string(from: shifted)
    }

    /// 0 for Monday through 6 for Sunday.
    static func weekdayIndex(of day: String) -> Int? {
        guard let date = formatter.date(from: day) else { return nil }
        return (calendar.component(.weekday, from: date) + 5) % 7
    }

    /// The Monday of the week holding `day`.
    static func monday(of day: String) -> String {
        shift(day, by: -(weekdayIndex(of: day) ?? 0))
    }

    private static let weekdayNames = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    /// Which weekday a word names: "thu", "thurs" and "Thursday" are all 3.
    static func weekday(in text: String) -> Int? {
        for word in words(text) where word.count >= 3 {
            if let index = weekdayNames.firstIndex(where: { $0.hasPrefix(word) || word.hasPrefix($0) }) {
                return index
            }
        }
        return nil
    }

    /// The day a person means by `text`, counted from `today`: a date, "today",
    /// "tomorrow", or a weekday — the coming one, today included. "Next friday"
    /// is the Friday of next week.
    static func day(_ text: String, today: String) -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if isDate(lower) { return lower }
        if lower.contains("day after tomorrow") { return shift(today, by: 2) }
        if lower.contains("tomorrow") { return shift(today, by: 1) }
        if lower.contains("today") || lower.contains("tonight") { return today }
        guard let weekday = weekday(in: lower), let current = weekdayIndex(of: today) else { return nil }
        if words(lower).contains("next") { return shift(monday(of: today), by: 7 + weekday) }
        return shift(today, by: (weekday - current + 7) % 7)
    }

    /// Where a workout moves when a person names a day for it: a weekday means
    /// that day in the workout's own Monday-to-Sunday week, or the week after
    /// when that day has already gone.
    static func rescheduledDay(_ text: String, workoutDate: String, today: String) -> String? {
        let lower = text.lowercased()
        if isDate(lower.trimmingCharacters(in: .whitespaces)) || lower.contains("today") || lower.contains("tomorrow") {
            return day(lower, today: today)
        }
        guard let weekday = weekday(in: lower) else { return nil }
        var date = shift(monday(of: max(workoutDate, today)), by: weekday)
        if lower.contains("next") { date = shift(date, by: 7) }
        while date < today { date = shift(date, by: 7) }
        return date
    }

    /// The days a schedule question covers, and what to call them: today,
    /// tomorrow, a weekday, this week (to Sunday), next week, or else the next
    /// seven days.
    static func scheduleRange(_ text: String, today: String) -> (from: String, to: String, title: String) {
        let lower = text.lowercased()
        let sunday = shift(monday(of: today), by: 6)
        if lower.contains("next week") {
            let start = shift(monday(of: today), by: 7)
            return (start, shift(start, by: 6), "Next week")
        }
        if lower.contains("this week") || lower.contains("rest of the week") {
            return (today, sunday, "This week")
        }
        if lower.contains("tomorrow") { let day = shift(today, by: 1); return (day, day, "Tomorrow") }
        if lower.contains("today") || lower.contains("tonight") { return (today, today, "Today") }
        if weekday(in: lower) != nil, let day = day(lower, today: today) {
            let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            return (day, day, names[weekdayIndex(of: day) ?? 0])
        }
        return (today, shift(today, by: 6), "The next 7 days")
    }

    // MARK: Workouts

    enum Resolution: Equatable {
        case found(AgentWorkoutRef)
        case none
    }

    private static let nameWords: [String: String] = [
        "leg": "legs", "lower body": "lower", "upper body": "upper",
        "full": "full body", "fullbody": "full body", "whole body": "full body",
    ]

    /// The workout a person means, among those still ahead (earliest first).
    /// A day picks the workout on it; a name picks the next workout carrying
    /// it; "this one" is the workout in progress.
    static func workout(
        _ text: String,
        among upcoming: [AgentWorkoutRef],
        today: String,
        activeId: String? = nil
    ) -> Resolution {
        let lower = text.lowercased()
        if let exact = upcoming.first(where: { $0.id == text }) { return .found(exact) }
        if let activeId, let active = upcoming.first(where: { $0.id == activeId }),
           ["current", "this workout", "this one", "now", "running", "in progress"].contains(where: lower.contains) {
            return .found(active)
        }
        if let date = day(lower, today: today) {
            if let match = upcoming.first(where: { $0.date == date }) { return .found(match) }
            // "Wednesday's workout" still means the one on a Wednesday.
            if let weekday = weekday(in: lower),
               let match = upcoming.first(where: { weekdayIndex(of: $0.date) == weekday }) {
                return .found(match)
            }
        }
        var wanted = Set(words(lower))
        for (said, meant) in nameWords where lower.contains(said) { wanted.insert(meant) }
        let ignored: Set<String> = ["a", "b", "c", "day", "workout", "session", "the", "my"]
        let match = upcoming.first { ref in
            let name = ref.name.lowercased()
            let tokens = Set(words(name)).subtracting(ignored)
            return !tokens.isEmpty && (tokens.isSubset(of: wanted) || wanted.contains(where: { name.hasPrefix($0) && $0.count > 3 }))
        }
        if let match { return .found(match) }
        if upcoming.count == 1, ["workout", "session", "it"].contains(where: lower.contains) {
            return .found(upcoming[0])
        }
        return .none
    }

    // MARK: Numbers

    private static let numberWords: [String: Int] = [
        "once": 1, "one": 1, "twice": 2, "two": 2, "thrice": 3, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "twelve": 12, "fifteen": 15,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "ninety": 90,
    ]

    /// Every number `text` states, in digits or words.
    static func numbers(in text: String) -> Set<Int> {
        var found = Set<Int>()
        let lower = text.lowercased()
        let digits = try? NSRegularExpression(pattern: #"\d+"#)
        let range = NSRange(lower.startIndex..., in: lower)
        for match in digits?.matches(in: lower, range: range) ?? [] {
            if let span = Range(match.range, in: lower), let value = Int(lower[span]) { found.insert(value) }
        }
        for word in words(lower) {
            if let value = numberWords[word] { found.insert(value) }
        }
        if lower.contains("an hour") || lower.contains("one hour") { found.insert(60) }
        if lower.contains("half an hour") || lower.contains("half hour") { found.insert(30) }
        return found
    }

    /// A number the model passed, kept only when the person actually said it.
    static func said(_ value: Int?, in text: String) -> Int? {
        guard let value, numbers(in: text).contains(value) else { return nil }
        return value
    }

    static func said(_ value: Double?, in text: String) -> Double? {
        guard let value, value.isFinite else { return nil }
        if value.rounded() == value, value >= Double(Int.min), value < Double(Int.max),
           numbers(in: text).contains(Int(value)) { return value }
        let regex = try? NSRegularExpression(pattern: #"(?<!\d)\d+(?:[.,]\d+)?(?!\d)"#)
        let range = NSRange(text.startIndex..., in: text)
        for match in regex?.matches(in: text, range: range) ?? [] {
            guard let span = Range(match.range, in: text),
                  let said = Double(text[span].replacingOccurrences(of: ",", with: "."))
            else { continue }
            if said == value { return value }
        }
        return nil
    }

    // MARK: Muscles

    private static let muscleWords: [(String, [MuscleId])] = [
        ("chest", [.chest]), ("pec", [.chest]),
        ("back", [.upperBack]), ("lats", [.upperBack]), ("trap", [.trapezius]),
        ("shoulder", [.deltoids]), ("delt", [.deltoids]),
        ("bicep", [.biceps]), ("tricep", [.triceps]), ("arm", [.biceps, .triceps]),
        ("forearm", [.forearm]), ("grip", [.forearm]),
        ("abs", [.abs, .obliques]), ("core", [.abs, .obliques]), ("oblique", [.obliques]),
        ("glute", [.gluteal]), ("butt", [.gluteal]),
        ("quad", [.quadriceps]), ("hamstring", [.hamstring]), ("calf", [.calves]), ("calves", [.calves]),
        ("adductor", [.adductors]), ("hip", [.hipFlexors]),
        ("leg", [.quadriceps, .hamstring, .gluteal, .calves]),
        ("push", [.chest, .deltoids, .triceps]), ("pull", [.upperBack, .biceps]),
        ("upper", [.chest, .upperBack, .deltoids, .biceps, .triceps]),
        ("lower", [.quadriceps, .hamstring, .gluteal, .calves]),
    ]

    /// The muscles a phrase like "legs and core" names, in the order said.
    /// Words match whole or by their start, so "arms" is arms and "warm" is not.
    static func muscles(in text: String) -> [MuscleId] {
        let lower = text.lowercased()
        if lower.contains("full body") || lower.contains("whole body") || lower.contains("everything") {
            return [.chest, .upperBack, .deltoids, .quadriceps, .hamstring, .gluteal]
        }
        var tokens = words(lower)
        var result: [MuscleId] = []
        func add(_ muscles: [MuscleId]) {
            for muscle in muscles where !result.contains(muscle) { result.append(muscle) }
        }
        // Two-word names first, then their words are spent.
        for (phrase, muscles) in [("upper back", [MuscleId.upperBack]), ("lower back", [.lowerBack])]
        where lower.contains(phrase) {
            add(muscles)
            let spent = phrase.split(separator: " ").map(String.init)
            tokens.removeAll { spent.contains($0) }
        }
        for token in tokens {
            if let entry = muscleWords.first(where: { token.hasPrefix($0.0) }) { add(entry.1) }
        }
        return result
    }

    // MARK: Planning days

    /// Training days spread across a week for a count of sessions, as offsets
    /// from Monday: rest falls between sessions wherever it can.
    static func offsets(daysPerWeek: Int) -> [Int] {
        switch max(1, min(7, daysPerWeek)) {
        case 1: [0]
        case 2: [0, 3]
        case 3: [0, 2, 4]
        case 4: [0, 1, 3, 4]
        case 5: [0, 1, 2, 3, 4]
        case 6: [0, 1, 2, 3, 4, 5]
        default: [0, 1, 2, 3, 4, 5, 6]
        }
    }

    /// The weekdays named in `text`, as offsets from Monday.
    static func weekdays(in text: String) -> [Int] {
        var result: [Int] = []
        for word in words(text) where word.count >= 3 {
            if let index = weekdayNames.firstIndex(where: { $0.hasPrefix(word) }), !result.contains(index) {
                result.append(index)
            }
        }
        return result.sorted()
    }

    /// Dates for a new plan: from next Monday — or today, on a Monday — on the
    /// given weekday offsets.
    static func planDates(offsets: [Int], today: String) -> [String] {
        let start = weekdayIndex(of: today) == 0 ? today : shift(monday(of: today), by: 7)
        return offsets.map { shift(start, by: $0) }.filter { $0 >= today }
    }

    // MARK: Helpers

    static func words(_ text: String) -> [String] {
        let cleaned = text.lowercased().map { (character: Character) -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(cleaned).split(separator: " ").map(String.init)
    }
}

// MARK: - Quantities and names said with their units

nonisolated extension AgentWords {
    /// The number said right before one of `units`: "3 days", "three times",
    /// "4x a week".
    static func count(of units: Set<String>, in text: String) -> Int? {
        let list = words(text)
        for (index, word) in list.enumerated() {
            if let glued = word.firstMatch(of: #/^(\d+)x$/#), units.contains("x") { return Int(glued.1) }
            guard index + 1 < list.count, units.contains(list[index + 1]) else { continue }
            if let value = Int(word) ?? numberWords[word] { return value }
        }
        return nil
    }

    /// Session minutes as said: "45 minutes", "40 min", "an hour", "half an hour".
    static func minutes(in text: String) -> Int? {
        let lower = text.lowercased()
        if lower.contains("hour and a half") || lower.contains("an hour and half") { return 90 }
        if lower.contains("half an hour") || lower.contains("half hour") { return 30 }
        if let said = count(of: ["min", "mins", "minute", "minutes"], in: lower) { return said }
        if lower.contains("an hour") || lower.contains("one hour") || lower.contains("1 hour") { return 60 }
        return nil
    }

    /// Reps as said: "8 reps", "10 x 60 kg", or a lone number beside a load.
    static func reps(in text: String) -> Int? {
        let lower = text.lowercased()
        if let said = count(of: ["rep", "reps", "repetitions", "times"], in: lower) { return said }
        if let times = lower.firstMatch(of: #/(\d+)\s*[x×]\s*\d/#) { return Int(times.1) }
        let loads = kilograms(in: lower).map { Set([Int($0)]) } ?? []
        let rest = numbers(in: lower).subtracting(loads)
        return rest.count == 1 ? rest.first : nil
    }

    /// A load in kilograms as said: "60 kg", "22.5 kilos".
    static func kilograms(in text: String) -> Double? {
        let lower = text.lowercased()
        guard let match = lower.firstMatch(of: #/(\d+(?:[.,]\d+)?)\s*(?:kg|kgs|kilo|kilos|kilogram|kilograms)\b/#)
        else { return nil }
        return Double(String(match.1).replacingOccurrences(of: ",", with: "."))
    }

    /// Whether every word of a catalogue name such as "ez barbell" is in `text`,
    /// plurals and shorthand folded the way exercise names are.
    static func mentions(_ name: String, in text: String) -> Bool {
        let said = Set(ExerciseResolver.words(text))
        let wanted = ExerciseResolver.words(name)
        return !wanted.isEmpty && wanted.allSatisfy(said.contains)
    }

    /// Whether `text` names any gym equipment other than body weight.
    static func mentionsEquipment(_ text: String) -> Bool {
        ExerciseCatalogue.equipmentOptions.contains { $0 != "body weight" && mentions($0, in: text) }
    }
}
