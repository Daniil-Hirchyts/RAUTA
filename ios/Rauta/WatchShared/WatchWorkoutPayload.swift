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
