import Combine
import Foundation
import HealthKit

/// Keeps the app running while a workout is, the way a navigation app keeps
/// running while it guides.
///
/// From iOS 26 an iPhone can run a HealthKit workout session, and an app with
/// one running is not suspended when the screen locks or another app opens. That
/// is what lets a rest end with a sound on a locked phone rather than a
/// notification. The session only keeps the app alive: it collects nothing and
/// saves nothing — finished workouts still reach Apple Health the one way they
/// always have, through ``HealthService``.
///
/// Before iOS 26, or if the system will not run one, there is no session; rest
/// alerts always keep a notification scheduled for an app that is suspended.
@MainActor
final class WorkoutBackgroundSession: NSObject {
    static let shared = WorkoutBackgroundSession()

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    /// The workout a session was last tried for: a refused session is not
    /// asked for again on every change the workout goes through.
    private var attemptedWorkoutId: String?
    private var cancellable: AnyCancellable?

    private override init() {}

    func start() {
        let workouts = ActiveWorkoutStore.shared
        sync(workoutId: workouts.session?.workoutId)
        cancellable = workouts.changed
            .sink { [weak self] in self?.sync(workoutId: workouts.session?.workoutId) }
    }

    private func sync(workoutId: String?) {
        if let workoutId {
            guard session == nil, attemptedWorkoutId != workoutId else { return }
            attemptedWorkoutId = workoutId
            begin()
        } else {
            attemptedWorkoutId = nil
            if session != nil { end() }
        }
    }

    private func begin() {
        guard #available(iOS 26.0, *), HKHealthStore.isHealthDataAvailable() else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            session.delegate = self
            self.session = session
            session.startActivity(with: Date())
        } catch {
            session = nil
        }
    }

    private func end() {
        session?.end()
        session = nil
    }

    private func sessionStateChanged(_ state: HKWorkoutSessionState, of changed: HKWorkoutSession) {
        guard changed === session, state == .ended || state == .stopped else { return }
        session = nil
    }

    private func sessionFailed(_ failed: HKWorkoutSession) {
        guard failed === session else { return }
        session = nil
    }
}

extension WorkoutBackgroundSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in self.sessionStateChanged(toState, of: workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.sessionFailed(workoutSession) }
    }
}
