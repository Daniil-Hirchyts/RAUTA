import Foundation

/// A set the watch logged that the phone has not applied yet.
nonisolated struct RautaWatchPendingSet: Codable, Equatable, Sendable {
    var actionId: String
    var workoutId: String
    var exerciseEntryId: String
    var setDraftId: String?
    var loadKg: Double
    var reps: Int
    var completedAtMilliseconds: Double
}

/// The rules both devices follow to agree on the workout, as pure functions
/// so they can be tested on either side.
///
/// The phone owns the workout. The watch shows the phone's last word with
/// what it has done since laid over it, so a set logged out of the phone's
/// reach moves the watch on to the next set at once, and the next "done"
/// can never land on the set already logged.
nonisolated enum RautaWatchSync {
    // MARK: Ordering

    /// Whether an envelope is newer than the one shown. Messages, the
    /// application context and replies can arrive out of order; an older one
    /// would put a finished set back. One without a revision comes from an
    /// older phone and is always taken.
    static func isNewer(_ incoming: Int64?, than current: Int64?) -> Bool {
        guard let incoming, let current else { return true }
        return incoming > current
    }

    /// The phone's revision for its next envelope: always above the last, and
    /// tied to the clock, so a reinstalled phone app never starts below what a
    /// watch has already seen.
    static func nextRevision(after last: Int64, nowMilliseconds: Double) -> Int64 {
        max(last + 1, Int64(nowMilliseconds.rounded(.down)))
    }

    // MARK: The watch's view

    /// The snapshot with the watch's waiting sets laid over it: each marks its
    /// set done — or, when the phone already has that one, the next — and the
    /// set the next "done" is for moves on.
    static func merged(
        _ snapshot: RautaWatchWorkoutSnapshot,
        pending: [RautaWatchPendingSet]
    ) -> RautaWatchWorkoutSnapshot {
        let mine = pending.filter {
            $0.workoutId == snapshot.workoutId && $0.exerciseEntryId == snapshot.exerciseEntryId
        }
        guard var sets = snapshot.sets else { return snapshot }
        for set in mine {
            let slot = sets.firstIndex { $0.id == set.setDraftId && !$0.done }
                ?? sets.firstIndex { !$0.done }
            guard let slot else { continue }
            sets[slot].done = true
            sets[slot].loggedLoadKg = set.loadKg
            sets[slot].loggedReps = set.reps
        }
        var view = snapshot
        view.sets = sets
        let cursor = sets.firstIndex { !$0.done }
        view.setDraftId = cursor.map { sets[$0].id }
        view.setIndex = (cursor ?? sets.count) + 1
        view.setCount = sets.count
        if let cursor {
            let previous = sets[..<cursor].last { $0.done }
            view.loadKg = sets[cursor].targetLoadKg ?? previous?.loggedLoadKg ?? snapshot.loadKg
            view.reps = sets[cursor].targetReps ?? previous?.loggedReps ?? snapshot.reps
        }
        return view
    }

    /// The waiting sets still worth keeping: those the phone has applied, and
    /// those for a workout no longer running, are let go.
    static func stillPending(
        _ pending: [RautaWatchPendingSet],
        applied: [String],
        runningWorkoutId: String?
    ) -> [RautaWatchPendingSet] {
        pending.filter { !applied.contains($0.actionId) && $0.workoutId == runningWorkoutId }
    }

    // MARK: The phone's side

    /// Whether a set the watch sent is one the phone already has: logged on
    /// both, within half a rest of each other. Anything further apart is
    /// another set — the watch was a set behind — and goes on the next one.
    static func isSameSet(
        phoneLoggedAtMilliseconds: Double?,
        watchCompletedAtMilliseconds: Double?,
        restSeconds: Double
    ) -> Bool {
        guard let phone = phoneLoggedAtMilliseconds, let watch = watchCompletedAtMilliseconds else { return false }
        return abs(phone - watch) < max(10, restSeconds / 2) * 1000
    }

    /// Where the workout is up to, from its deadlines at `nowMilliseconds`.
    static func phase(
        warmupUntil: Double?,
        restUntil: Double?,
        hasCurrentExercise: Bool,
        nowMilliseconds: Double
    ) -> RautaWatchPhase {
        if let warmupUntil, warmupUntil > nowMilliseconds { return .warmup }
        if !hasCurrentExercise { return .done }
        if let restUntil, restUntil > nowMilliseconds { return .rest }
        return .set
    }
}
