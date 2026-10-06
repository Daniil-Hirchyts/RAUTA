import Foundation
import Testing
@testable import Rauta

@Suite("HealthKit workout ownership")
struct HealthWorkoutOwnershipTests {
    @Test func phoneSavesWhatNoWatchRecorded() {
        #expect(RautaHealthWorkout.phoneDecision(workoutId: "w1", watchClaims: [], alreadyInHealth: false) == .save)
    }

    @Test func watchOwnsWhatItClaimed() {
        #expect(
            RautaHealthWorkout.phoneDecision(workoutId: "w1", watchClaims: ["w1"], alreadyInHealth: false)
                == .watchOwns
        )
    }

    @Test func nothingIsSavedTwice() {
        #expect(
            RautaHealthWorkout.phoneDecision(workoutId: "w1", watchClaims: ["w1"], alreadyInHealth: true)
                == .alreadySaved
        )
        #expect(
            RautaHealthWorkout.phoneDecision(workoutId: "w1", watchClaims: [], alreadyInHealth: true)
                == .alreadySaved
        )
        #expect(RautaHealthWorkout.watchShouldSave(alreadyInHealth: true) == false)
        #expect(RautaHealthWorkout.watchShouldSave(alreadyInHealth: false))
    }

    @Test func externalIdentifierIsStableAndDistinct() {
        #expect(RautaHealthWorkout.externalID(forWorkout: "w1") == RautaHealthWorkout.externalID(forWorkout: "w1"))
        #expect(RautaHealthWorkout.externalID(forWorkout: "w1") != RautaHealthWorkout.externalID(forWorkout: "w2"))
    }

    @Test func claimsDoNotAffectOtherWorkouts() {
        #expect(RautaHealthWorkout.phoneDecision(workoutId: "w2", watchClaims: ["w1"], alreadyInHealth: false) == .save)
    }
}

@Suite("Watch connectivity")
struct WatchConnectivityTests {
    @Test func recentIdsKeepTheNewestInOrder() {
        var ids: [String] = []
        for index in 0..<70 { ids = RecentIDs.recording("a\(index)", in: ids, limit: 64) }
        #expect(ids.count == 64)
        #expect(ids.first == "a6")
        #expect(ids.last == "a69")
    }

    @Test func recordingAnIdTwiceDoesNotDuplicateIt() {
        let ids = RecentIDs.recording("a", in: ["a", "b"], limit: 64)
        #expect(ids == ["b", "a"])
    }

    /// A set arrives as a message, then again as context and user info; only
    /// the first may be applied.
    @Test func duplicateDeliveriesAreRecognised() {
        var processed: [String] = []
        var applied = 0
        for id in ["set-1", "set-1", "set-2", "set-1"] {
            guard !processed.contains(id) else { continue }
            applied += 1
            processed = RecentIDs.recording(id, in: processed, limit: 64)
        }
        #expect(applied == 2)
    }

    @Test func messagesRoundTrip() throws {
        let action = RautaWatchSetAction(
            id: "set-1", workoutId: "w1", exerciseEntryId: "e1", setDraftId: "s1",
            loadKg: 42.5, reps: 8, restSeconds: 90, completedAtMilliseconds: 1_780_000_000_000
        )
        let decodedAction = try JSONDecoder().decode(
            RautaWatchSetAction.self, from: JSONEncoder().encode(action)
        )
        #expect(decodedAction == action)

        let result = RautaWatchActionResult(actionId: "set-1", ok: false)
        #expect(try JSONDecoder().decode(RautaWatchActionResult.self, from: JSONEncoder().encode(result)) == result)

        let claim = RautaWatchHealthClaim(workoutId: "w1", claimedAtMilliseconds: 1)
        #expect(try JSONDecoder().decode(RautaWatchHealthClaim.self, from: JSONEncoder().encode(claim)) == claim)
    }

    @Test func envelopeFromAnOlderPhoneStillDecodes() throws {
        let data = Data(#"{"snapshot":null}"#.utf8)
        let envelope = try JSONDecoder().decode(RautaWatchSnapshotEnvelope.self, from: data)
        #expect(envelope.snapshot == nil)
        #expect(envelope.accent == nil)
        #expect(envelope.revision == nil)
    }

    /// A version 1 snapshot — no phase, deadlines or sets — still decodes.
    @Test func snapshotFromAnOlderPhoneStillDecodes() throws {
        let data = Data(#"""
        {"workoutId":"w1","workoutName":"Upper","exerciseName":"Bench","setIndex":1,"setCount":3,
         "loadKg":60,"reps":8,"restSeconds":90,"accumulatedSeconds":120,"isPaused":false}
        """#.utf8)
        let snapshot = try JSONDecoder().decode(RautaWatchWorkoutSnapshot.self, from: data)
        #expect(snapshot.workoutId == "w1")
        #expect(snapshot.sets == nil)
        #expect(snapshot.phase == nil)
    }

    @Test func controlActionsRoundTrip() throws {
        let control = RautaWatchControlAction(id: "c1", workoutId: "w1", kind: .extendRest, seconds: 30)
        #expect(try JSONDecoder().decode(RautaWatchControlAction.self, from: JSONEncoder().encode(control)) == control)
        let ended = RautaWatchEndedWorkout(workoutId: "w1", outcome: .cancelled)
        #expect(try JSONDecoder().decode(RautaWatchEndedWorkout.self, from: JSONEncoder().encode(ended)) == ended)
    }

    // MARK: Agreeing on the workout

    /// Messages, the context and replies arrive out of order: an older
    /// envelope never replaces a newer one.
    @Test func olderEnvelopesAreIgnored() {
        #expect(RautaWatchSync.isNewer(5, than: 4))
        #expect(!RautaWatchSync.isNewer(4, than: 5))
        #expect(!RautaWatchSync.isNewer(5, than: 5))
        #expect(RautaWatchSync.isNewer(nil, than: 5))
        #expect(RautaWatchSync.isNewer(1, than: nil))
        // Always above the last, even with a clock behind it.
        #expect(RautaWatchSync.nextRevision(after: 10, nowMilliseconds: 3) == 11)
        #expect(RautaWatchSync.nextRevision(after: 10, nowMilliseconds: 2_000) == 2_000)
    }

    private func snapshot(sets: [RautaWatchSetSlot]) -> RautaWatchWorkoutSnapshot {
        RautaWatchWorkoutSnapshot(
            workoutId: "w1", workoutName: "Upper", exerciseId: "bench", exerciseEntryId: "e1",
            exerciseName: "Bench", setDraftId: sets.first { !$0.done }?.id,
            setIndex: (sets.firstIndex { !$0.done } ?? sets.count) + 1, setCount: sets.count,
            loadKg: 60, reps: 8, restSeconds: 90, accumulatedSeconds: 0, runningSinceMilliseconds: nil,
            isPaused: false, sets: sets
        )
    }

    private func pending(_ id: String, set: String?, load: Double = 62.5) -> RautaWatchPendingSet {
        RautaWatchPendingSet(actionId: id, workoutId: "w1", exerciseEntryId: "e1", setDraftId: set,
                             loadKg: load, reps: 8, completedAtMilliseconds: 1)
    }

    /// Two sets logged out of the phone's reach go on two sets: the watch
    /// moves on by itself, so the second never lands on the first.
    @Test func setsLoggedOutOfReachMoveTheWatchOn() {
        let slots = ["s1", "s2", "s3"].map { RautaWatchSetSlot(id: $0, targetLoadKg: 60, targetReps: 8, done: false) }
        let first = RautaWatchSync.merged(snapshot(sets: slots), pending: [pending("a1", set: "s1")])
        #expect(first.setDraftId == "s2")
        #expect(first.setIndex == 2)
        let second = RautaWatchSync.merged(
            snapshot(sets: slots), pending: [pending("a1", set: "s1"), pending("a2", set: first.setDraftId)]
        )
        #expect(second.setDraftId == "s3")
        #expect(second.sets?.filter(\.done).count == 2)
        #expect(second.sets?.first?.loggedLoadKg == 62.5)
    }

    /// A waiting set whose set the phone already has goes on the next one, as
    /// the phone will put it.
    @Test func aWaitingSetForADoneSetTakesTheNext() {
        var slots = ["s1", "s2"].map { RautaWatchSetSlot(id: $0, targetLoadKg: 60, targetReps: 8, done: false) }
        slots[0].done = true
        let view = RautaWatchSync.merged(snapshot(sets: slots), pending: [pending("a1", set: "s1")])
        #expect(view.sets?.allSatisfy(\.done) == true)
        #expect(view.setDraftId == nil)
    }

    @Test func appliedAndEndedSetsStopWaiting() {
        let waiting = [pending("a1", set: "s1"), pending("a2", set: "s2")]
        #expect(RautaWatchSync.stillPending(waiting, applied: ["a1"], runningWorkoutId: "w1").map(\.actionId) == ["a2"])
        #expect(RautaWatchSync.stillPending(waiting, applied: [], runningWorkoutId: nil).isEmpty)
    }

    /// One set logged on both devices is one set; a set the watch sent long
    /// after the phone's is another.
    @Test func aSetLoggedOnBothDevicesCountsOnce() {
        #expect(RautaWatchSync.isSameSet(phoneLoggedAtMilliseconds: 100_000, watchCompletedAtMilliseconds: 104_000, restSeconds: 90))
        #expect(!RautaWatchSync.isSameSet(phoneLoggedAtMilliseconds: 100_000, watchCompletedAtMilliseconds: 200_000, restSeconds: 90))
        #expect(!RautaWatchSync.isSameSet(phoneLoggedAtMilliseconds: nil, watchCompletedAtMilliseconds: 100_000, restSeconds: 90))
    }

    @Test func thePhaseFollowsTheDeadlines() {
        #expect(RautaWatchSync.phase(warmupUntil: 10, restUntil: nil, hasCurrentExercise: true, nowMilliseconds: 5) == .warmup)
        #expect(RautaWatchSync.phase(warmupUntil: 1, restUntil: 10, hasCurrentExercise: true, nowMilliseconds: 5) == .rest)
        #expect(RautaWatchSync.phase(warmupUntil: nil, restUntil: 1, hasCurrentExercise: true, nowMilliseconds: 5) == .set)
        #expect(RautaWatchSync.phase(warmupUntil: nil, restUntil: nil, hasCurrentExercise: false, nowMilliseconds: 5) == .done)
    }
}

@Suite("Rest notifications")
struct RestNotificationTests {
    private let deadline = Date(timeIntervalSince1970: 1_780_000_000)

    @Test func notificationForTheCurrentRestStays() {
        #expect(RestAlerts.isStale(scheduledFor: deadline, now: deadline, hasTrigger: true) == false)
    }

    @Test func notificationForASkippedRestIsWithdrawn() {
        #expect(RestAlerts.isStale(scheduledFor: deadline, now: nil, hasTrigger: true))
    }

    @Test func notificationForAReplacedRestIsWithdrawn() {
        let later = deadline.addingTimeInterval(30)
        #expect(RestAlerts.isStale(scheduledFor: deadline, now: later, hasTrigger: true))
    }

    @Test func immediateBannersAreNeverWithdrawn() {
        #expect(RestAlerts.isStale(scheduledFor: deadline, now: nil, hasTrigger: false) == false)
    }
}
