import ActivityKit
import Foundation

/// The ActivityKit half of the Live Activity: one card per workout, adopted
/// rather than duplicated when the app is relaunched into a session that is
/// still running.
///
/// A Live Activity is an accessory to the workout, never a reason to break it,
/// so every failure here is swallowed.
enum WorkoutActivityBridge {
    /// False when the user has switched Live Activities off for the app, which
    /// makes every request throw.
    static var isSupported: Bool {
        if #available(iOS 16.2, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    @available(iOS 16.2, *)
    private static var activities: [Activity<WorkoutActivityAttributes>] {
        Activity<WorkoutActivityAttributes>.activities
    }

    @available(iOS 16.2, *)
    private static func attributes(_ content: LiveActivityContent) -> WorkoutActivityAttributes {
        WorkoutActivityAttributes(
            workoutId: content.workoutId,
            workoutName: content.workoutName,
            workoutDate: content.workoutDate
        )
    }

    @available(iOS 16.2, *)
    private static func state(_ content: LiveActivityContent) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            exerciseName: content.exerciseName,
            completedCount: content.completedCount,
            totalCount: content.totalCount,
            timerStart: content.timerStartEpochMs > 0
                ? Date(timeIntervalSince1970: content.timerStartEpochMs / 1000)
                : nil,
            elapsed: content.elapsedMs / 1000,
            isPaused: content.isPaused,
            accentHex: content.accentHex
        )
    }

    /// Begins following this workout. A card started by a previous launch is
    /// adopted, so a session restored from storage reconnects to what the Lock
    /// Screen already shows instead of stacking a second card on top of it.
    static func start(_ content: LiveActivityContent) {
        guard #available(iOS 16.2, *), isSupported else { return }
        let attributes = attributes(content)
        let state = state(content)

        if activities.contains(where: { $0.attributes.workoutId == attributes.workoutId }) {
            update(content)
            return
        }

        // Attributes are fixed for the life of an activity, so moving to a
        // different workout means replacing the card rather than updating it.
        dismissAll()

        _ = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    static func update(_ content: LiveActivityContent) {
        guard #available(iOS 16.2, *) else { return }
        let state = state(content)
        for activity in activities {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        }
    }

    /// A finished workout is worth a last glance; a discarded one is not, and
    /// lingering would leave a card the user has to dismiss by hand.
    static func end(_ content: LiveActivityContent, dismissImmediately: Bool) {
        guard #available(iOS 16.2, *) else { return }
        let state = state(content)
        let policy: ActivityUIDismissalPolicy = dismissImmediately
            ? .immediate
            : .after(Date().addingTimeInterval(120))

        for activity in activities {
            Task {
                await activity.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: policy
                )
            }
        }
    }

    /// Clears cards without touching their content — used when replacing one
    /// workout's activity with another's.
    @available(iOS 16.2, *)
    private static func dismissAll() {
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
