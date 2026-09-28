import Foundation

/// The warm-up that opens a workout: a few moves from the library, picked for
/// what the workout trains, sharing the warm-up's time between them.
///
/// It starts with something to raise the pulse, then loosens what is about to
/// work — shoulders and chest before an upper-body day, hips and legs before a
/// lower one. The moves are shown, never logged: they are not part of the
/// workout and never enter its record.
enum WarmupRoutine {
    enum Region: Equatable { case upper, lower, full }

    struct Move: Hashable, Identifiable {
        var exerciseId: String
        /// When the move starts and ends, in seconds from the warm-up's start.
        var start: Double
        var end: Double

        var id: String { exerciseId }
        var seconds: Double { end - start }
    }

    /// Something to raise the pulse: every warm-up opens with one.
    static let pulse = ["3224", "3636", "3223"]
    static let upper = ["3318", "1167", "3021", "1471", "1428"]
    static let lower = ["1604", "1686", "3655", "3561", "0257", "1368"]
    static let full = ["1471", "1604", "1686", "3318", "0276"]

    static var allIds: [String] { pulse + upper + lower + full }

    private static let upperMuscles: Set<MuscleId> = [
        .chest, .upperBack, .deltoids, .biceps, .triceps, .trapezius, .forearm, .serratus,
    ]
    /// The trunk works on both kinds of day, so it says nothing about which.
    private static let trunk: Set<MuscleId> = [.abs, .obliques, .lowerBack]

    /// Upper when seven in ten of the muscles the exercises train are upper
    /// body, lower when seven in ten are lower, the whole body otherwise.
    static func region(for exerciseIds: [String]) -> Region {
        var upperCount = 0
        var lowerCount = 0
        for id in exerciseIds {
            for muscle in ExerciseCatalogue.byId[id]?.muscles ?? [] where !trunk.contains(muscle) {
                if upperMuscles.contains(muscle) { upperCount += 1 } else { lowerCount += 1 }
            }
        }
        let total = upperCount + lowerCount
        guard total > 0 else { return .full }
        let share = Double(upperCount) / Double(total)
        if share >= 0.7 { return .upper }
        if share <= 0.3 { return .lower }
        return .full
    }

    /// The moves for a warm-up of `seconds` before these exercises: four, or
    /// five for a long one. `seed` varies the picks from workout to workout
    /// while keeping one workout's warm-up the same each time it is shown.
    static func moves(for exerciseIds: [String], seconds: Double, seed: String) -> [Move] {
        guard seconds > 0 else { return [] }
        let count = seconds >= 600 ? 5 : 4
        var hash = seed.stableHash
        func pick(_ pool: [String], avoiding taken: [String]) -> String? {
            let open = pool.filter { !taken.contains($0) && ExerciseCatalogue.has($0) }
            guard !open.isEmpty else { return nil }
            hash = hash &* 1_099_511_628_211 &+ 7
            return open[Int(hash % UInt64(open.count))]
        }

        let pool: [String]
        switch region(for: exerciseIds) {
        case .upper: pool = upper
        case .lower: pool = lower
        case .full: pool = full
        }
        var ids: [String] = []
        if let first = pick(pulse, avoiding: ids) { ids.append(first) }
        while ids.count < count, let next = pick(pool, avoiding: ids) { ids.append(next) }

        let share = seconds / Double(max(1, ids.count))
        return ids.enumerated().map { index, id in
            Move(exerciseId: id, start: Double(index) * share, end: Double(index + 1) * share)
        }
    }

    /// The move for `elapsed` seconds into the warm-up; past the end, the last.
    static func current(_ moves: [Move], elapsed: Double) -> (index: Int, move: Move)? {
        guard !moves.isEmpty else { return nil }
        let index = moves.firstIndex { elapsed < $0.end } ?? moves.count - 1
        return (index, moves[index])
    }
}
