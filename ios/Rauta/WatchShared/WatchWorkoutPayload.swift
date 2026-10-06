import Foundation

// Wire formats shared by the phone and the watch: plain values, decoded and
// encoded wherever a WatchConnectivity callback lands, so none of them take
// the targets' main-actor default.

nonisolated struct RautaWatchWorkoutSnapshot: Codable, Equatable, Sendable {
    var workoutId: String
    var workoutName: String
    var exerciseId: String?
    var exerciseEntryId: String?
    var exerciseName: String
    var setDraftId: String?
    var setIndex: Int
    var setCount: Int
    var loadKg: Double
    var reps: Int
    var restSeconds: Double
    var accumulatedSeconds: Double
    var runningSinceMilliseconds: Double?
    var isPaused: Bool

    // Version 2. Optional, so a snapshot from an older phone still decodes.

    /// Where the workout is up to.
    var phase: RautaWatchPhase? = nil
    /// Epoch ms the opening warm-up ends, while it runs.
    var warmupUntilMilliseconds: Double? = nil
    /// Epoch ms the rest ends, while it runs.
    var restUntilMilliseconds: Double? = nil
    /// The current exercise's place in the workout, from 1.
    var exerciseNumber: Int? = nil
    var exerciseCount: Int? = nil
    var nextExerciseName: String? = nil
    /// Every set of the current exercise, so the watch can move on to the
    /// next one by itself when a set is logged out of the phone's reach.
    var sets: [RautaWatchSetSlot]? = nil
}

nonisolated enum RautaWatchPhase: String, Codable, Sendable {
    case warmup, set, rest, done
}

/// One set of the current exercise, as the watch shows it.
nonisolated struct RautaWatchSetSlot: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var targetLoadKg: Double?
    var targetReps: Int?
    var done: Bool
    var loggedLoadKg: Double? = nil
    var loggedReps: Int? = nil
}

nonisolated struct RautaWatchSnapshotEnvelope: Codable, Equatable, Sendable {
    var snapshot: RautaWatchWorkoutSnapshot?
    /// The accent chosen on iPhone. Sent with every snapshot, workout or not,
    /// so the watch wears it before a session starts. Optional so an envelope
    /// from an older phone build still decodes.
    var accent: RautaWatchAccent? = nil
    /// Which envelope this is: higher is newer. Messages, the application
    /// context and replies can arrive out of order; an older one is ignored.
    var revision: Int64? = nil
    /// The workout that ended last and how, carried until the next one starts,
    /// so the watch saves a finished workout and discards a cancelled one.
    var ended: RautaWatchEndedWorkout? = nil
    /// The newest watch actions the phone has applied, so the watch can stop
    /// counting them as waiting.
    var appliedActionIds: [String]? = nil
}

nonisolated struct RautaWatchEndedWorkout: Codable, Equatable, Sendable {
    nonisolated enum Outcome: String, Codable, Sendable {
        case finished, cancelled
    }

    var workoutId: String
    var outcome: Outcome
}

/// Something the watch asks of the workout other than logging a set.
nonisolated struct RautaWatchControlAction: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case pause, resume, endRest, extendRest, endWarmup
    }

    var id: String
    var workoutId: String
    var kind: Kind
    /// For `extendRest`: how much longer.
    var seconds: Double? = nil
}

/// The iPhone app's accent, as the watch draws it: `0xRRGGBB` values.
nonisolated struct RautaWatchAccent: Codable, Equatable, Sendable {
    var primary: UInt32
    var gradientStart: UInt32
    var gradientEnd: UInt32
    /// Whether a label on the accent is white rather than near-black.
    var whiteLabel: Bool

    static let ember = RautaWatchAccent(
        primary: RautaBrand.primary,
        gradientStart: RautaBrand.gradientStart,
        gradientEnd: RautaBrand.gradientEnd,
        whiteLabel: false
    )
}

nonisolated struct RautaWatchSetAction: Codable, Equatable, Sendable {
    var id: String
    var workoutId: String
    var exerciseEntryId: String
    var setDraftId: String?
    var loadKg: Double
    var reps: Int
    var restSeconds: Double
    var completedAtMilliseconds: Double?
    /// 2 from a watch that moves on to the next set by itself. A version 1
    /// watch could send the same set twice, out of reach of the phone.
    var version: Int? = nil
}

/// What became of a set the watch sent: sent by the phone once its stores have
/// applied it, as a message of its own. The reply to the send itself only says
/// the message arrived, so it can be given on WatchConnectivity's own queue.
nonisolated struct RautaWatchActionResult: Codable, Equatable, Sendable {
    var actionId: String
    var ok: Bool
}

/// The watch is recording this workout with a HealthKit session of its own and
/// will save it to Health itself. Sent as user info, so it arrives even when
/// the phone is not reachable at that moment.
nonisolated struct RautaWatchHealthClaim: Codable, Equatable, Sendable {
    var workoutId: String
    var claimedAtMilliseconds: Double
}

nonisolated enum RautaWatchMessageKey {
    static let snapshot = "rauta.watch.snapshot.v1"
    static let action = "rauta.watch.action.v1"
    static let requestSnapshot = "rauta.watch.request-snapshot.v1"
    /// The reply to any message: it arrived. Nothing about its outcome.
    static let received = "rauta.watch.received.v1"
    static let actionResult = "rauta.watch.action-result.v1"
    static let healthClaim = "rauta.watch.health-claim.v1"
    static let control = "rauta.watch.control.v1"
}

/// Who writes a workout to Apple Health. Exactly one device does.
///
/// - While the watch records a workout with its own HealthKit session, the
///   watch saves it: it has the heart rate and energy the phone can only
///   estimate. It tells the phone with a ``RautaWatchHealthClaim``.
/// - The phone saves only workouts no watch has claimed.
/// - Both stamp ``externalID(forWorkout:)`` on what they save, and both skip a
///   save when a workout with that identifier is already in Health, so a retry,
///   a relaunch or a claim that arrives late cannot add a second copy.
nonisolated enum RautaHealthWorkout {
    enum PhoneDecision: Equatable, Sendable {
        case save
        /// The watch recorded it and saves it.
        case watchOwns
        /// Health already has it.
        case alreadySaved
    }

    /// The value of `HKMetadataKeyExternalUUID` on the Health workout for one
    /// app workout. The same on both devices, so either can find the other's.
    static func externalID(forWorkout workoutId: String) -> String {
        "rauta-workout-\(workoutId)"
    }

    static func phoneDecision(
        workoutId: String,
        watchClaims: Set<String>,
        alreadyInHealth: Bool
    ) -> PhoneDecision {
        if alreadyInHealth { return .alreadySaved }
        if watchClaims.contains(workoutId) { return .watchOwns }
        return .save
    }

    /// The watch keeps what it recorded unless Health already has the workout.
    static func watchShouldSave(alreadyInHealth: Bool) -> Bool {
        !alreadyInHealth
    }

}

/// A bounded, ordered record of identifiers already handled — watch actions
/// that must not be applied twice, workouts the watch has claimed.
nonisolated enum RecentIDs {
    /// `ids` with `id` added as the newest, keeping only the last `limit`.
    /// Adding one already there moves it to the end rather than repeating it.
    static func recording(_ id: String, in ids: [String], limit: Int) -> [String] {
        Array((ids.filter { $0 != id } + [id]).suffix(Swift.max(0, limit)))
    }
}
