import Foundation

/// Finds catalogue exercises from the way people name them.
///
/// The browser's search is a plain substring match, which is right for typing
/// into a field but misses how exercises are said: "RDLs", "pull ups", "DB
/// bench". Names are compared as words instead — plural and hyphen forms
/// folded, common gym shorthand expanded — and the closest, plainest name wins.
nonisolated enum ExerciseResolver {
    struct Match: Hashable {
        var exercise: ExerciseSummary
        var score: Double
    }

    /// Shorthand as people say it, read as the words the catalogue uses.
    private static let aliases: [String: String] = [
        "rdl": "romanian deadlift",
        "sldl": "stiff leg deadlift",
        "ohp": "overhead press",
        "military": "overhead",
        "db": "dumbbell",
        "dbs": "dumbbell",
        "bb": "barbell",
        "kb": "kettlebell",
        "bw": "body weight",
        "bodyweight": "body weight",
        "pullup": "pull up",
        "pushup": "push up",
        "chinup": "chin up",
        "situp": "sit up",
        "skullcrusher": "skull crusher",
        "tricep": "triceps",
        "bicep": "biceps",
    ]

    /// Lower-cased words, punctuation dropped, hyphens split, plurals folded and
    /// shorthand expanded, so "Pull-Ups" and "pullup" read as "pull up".
    static func words(_ text: String) -> [String] {
        let cleaned = text.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(cleaned)
            .split(separator: " ")
            .flatMap { raw -> [String] in
                let word = singular(String(raw))
                return (aliases[word] ?? word).split(separator: " ").map(String.init)
            }
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 2, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        let stem = String(word.dropLast())
        // "biceps" and "triceps" are singular already.
        return stem.hasSuffix("cep") ? word : stem
    }

    /// The best matches for `query`, closest first. A query that is itself an
    /// exercise id returns that exercise. `preferred` breaks ties towards
    /// exercises the person actually does.
    static func resolve(
        _ query: String,
        in catalogue: [ExerciseSummary] = ExerciseCatalogue.allByName,
        equipment: Set<String>? = nil,
        muscles: Set<MuscleId>? = nil,
        preferred: Set<String> = [],
        limit: Int = 5
    ) -> [Match] {
        if let exact = catalogue.first(where: { $0.id == query }) {
            return [Match(exercise: exact, score: .infinity)]
        }
        let wanted = words(query)
        guard !wanted.isEmpty, limit > 0 else { return [] }

        var matches: [(match: Match, order: Int)] = []
        for (order, exercise) in catalogue.enumerated() {
            if let equipment, !equipment.contains(exercise.equipment) { continue }
            if let muscles, !exercise.muscles.contains(where: muscles.contains) { continue }
            guard let score = score(wanted, against: words(exercise.name)) else { continue }
            let bonus = preferred.contains(exercise.id) ? 1.5 : 0
            matches.append((Match(exercise: exercise, score: score + bonus), order))
        }
        return matches
            .sorted { $0.match.score != $1.match.score ? $0.match.score > $1.match.score : $0.order < $1.order }
            .prefix(limit)
            .map(\.match)
    }

    /// How well a name answers the query, or nil when it does not. Every query
    /// word must appear, as a whole word or, at a cost, the start of one; each
    /// extra word in the name costs a little, so "barbell bench press" beats
    /// "barbell close grip bench press" for "bench press". A partial word costs
    /// more than several extra ones: "lat" is its own word before it is the
    /// start of "lateral".
    private static func score(_ wanted: [String], against name: [String]) -> Double? {
        var unused = name
        var partial = 0.0
        for word in wanted {
            if let index = unused.firstIndex(of: word) {
                unused.remove(at: index)
            } else if word.count >= 3, let index = unused.firstIndex(where: { $0.hasPrefix(word) }) {
                unused.remove(at: index)
                partial += 2.5
            } else {
                return nil
            }
        }
        let exact = unused.isEmpty && partial == 0 ? 2.0 : 0
        return 10 + exact - Double(unused.count) * 0.5 - partial
    }
}
