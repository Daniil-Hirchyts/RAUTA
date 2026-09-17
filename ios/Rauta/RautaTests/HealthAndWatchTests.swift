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
