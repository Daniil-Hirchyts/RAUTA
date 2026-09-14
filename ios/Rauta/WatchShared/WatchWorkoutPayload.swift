import Foundation

struct RautaWatchWorkoutSnapshot: Codable, Equatable, Sendable {
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
}

struct RautaWatchSnapshotEnvelope: Codable, Equatable, Sendable {
    var snapshot: RautaWatchWorkoutSnapshot?
    /// The accent chosen on iPhone. Sent with every snapshot, workout or not,
    /// so the watch wears it before a session starts. Optional so an envelope
    /// from an older phone build still decodes.
    var accent: RautaWatchAccent? = nil
}

/// The iPhone app's accent, as the watch draws it: `0xRRGGBB` values.
struct RautaWatchAccent: Codable, Equatable, Sendable {
    var primary: UInt32
    var gradientStart: UInt32
    var gradientEnd: UInt32
    /// Whether a label on the accent is white rather than near-black.
    var whiteLabel: Bool

    static let ember = RautaWatchAccent(
        primary: 0xFF5700,
        gradientStart: 0xFF6700,
        gradientEnd: 0xFF3F00,
        whiteLabel: false
    )
}

struct RautaWatchSetAction: Codable, Equatable, Sendable {
    var id: String
    var workoutId: String
    var exerciseEntryId: String
    var setDraftId: String?
    var loadKg: Double
    var reps: Int
    var restSeconds: Double
    var completedAtMilliseconds: Double?
}

enum RautaWatchMessageKey {
    static let snapshot = "rauta.watch.snapshot.v1"
    static let action = "rauta.watch.action.v1"
    static let requestSnapshot = "rauta.watch.request-snapshot.v1"
    static let ok = "rauta.watch.ok.v1"
}
