import Foundation

/// What a committed session left behind, read back out of the durable records.
///
/// The point of this type is that it cannot be constructed from an intention.
/// It is built after the write, from what the stores actually hold, so a screen
/// that has one is a screen whose workout is genuinely saved.
struct WorkoutReceipt: Equatable, Identifiable, Sendable {
    /// The structured session, when the work produced one. A session with no
    /// logged sets writes only the legacy completion — that is a workout that
    /// recorded nothing, not a failed save.
    var sessionId: String?
    var workoutId: String
    var workoutName: String
    var completedAt: String
    var durationMs: Double
    /// Exercises with at least one recorded set, or checked off by hand.
    var exercisesRecorded: Int
    var exercisesPlanned: Int
    /// Sets with a real observation. Prescribed-but-skipped sets are not work.
    var setsRecorded: Int
    /// Whether every prescribed working set was performed.
    var isComplete: Bool
    /// The local save is done; Apple Health may still be catching up. A sync
    /// that fails later never means the workout was lost.
    var healthSyncPending: Bool

    var id: String { sessionId ?? workoutId }

    var title: String { isComplete ? "Workout saved" : "Session saved" }

    /// Two or three facts, each a count of work that was actually recorded.
    var facts: [(value: String, label: String)] {
        var facts: [(String, String)] = [
            (ActiveWorkout.formatDuration(durationMs), "Duration")
        ]
        if setsRecorded > 0 {
            facts.append(("\(setsRecorded)", setsRecorded == 1 ? "Set recorded" : "Sets recorded"))
        }
        facts.append((
            exercisesPlanned > 0 ? "\(exercisesRecorded)/\(exercisesPlanned)" : "\(exercisesRecorded)",
            "Exercises"
        ))
        return facts
    }

    /// The honest one-liner under the title.
    var summaryLine: String {
        if setsRecorded == 0 {
            return "No sets were logged, so only the session itself is recorded."
        }
        if isComplete { return "Every prescribed set is recorded." }
        return "Your recorded work is saved. Some prescribed sets were not performed."
    }
}

extension WorkoutReceipt {
    /// The same truth in RAUTA's voice, for the moment it celebrates. Warm, but
    /// never more than the records say: a partial session is not called
    /// complete, and nothing logged is not called work.
    var rautaLine: String {
        if setsRecorded == 0 {
            return "No sets logged this time, but you showed up. The session is saved."
        }
        let sets = setsRecorded == 1 ? "1 set" : "\(setsRecorded) sets"
        if isComplete {
            return "Every set on the plan, done. \(sets) in the books!"
        }
        return "\(sets) saved. Not all of the plan got done — we'll pick it up next time."
    }
}

enum WorkoutFinishOutcome: Equatable {
    case saved(WorkoutReceipt)
    /// The commit did not land. The draft, the shell and the last set are all
    /// still there, and finishing can be tried again.
    case failed(String)

    var receipt: WorkoutReceipt? {
        if case .saved(let receipt) = self { return receipt }
        return nil
    }

    var failure: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}
