import ActivityKit
import Foundation

/// The ActivityKit half of the Live Activity: one card per workout, adopted
/// rather than duplicated when the app is relaunched into a session that is
/// still running.
@available(iOS 16.2, *)
enum WorkoutLiveActivity {
    typealias Attributes = WorkoutActivityAttributes
    typealias State = WorkoutActivityAttributes.ContentState

    /// False when the user has switched Live Activities off for the app, which
    /// makes every request throw.
    static var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private static var activities: [Activity<Attributes>] {
        Activity<Attributes>.activities
    }

    /// Begins following `attributes`. A card started by a previous launch is
    /// adopted, so a session restored from storage reconnects to what the Lock
    /// Screen already shows instead of stacking a second card on top of it.
    static func start(attributes: Attributes, state: State) throws {
        let isSameWorkout = activities.contains {
            $0.attributes.workoutId == attributes.workoutId
        }
        if isSameWorkout {
            update(state: state)
            return
        }

        // Attributes are fixed for the life of an activity, so moving to a
        // different workout means replacing the card rather than updating it.
        dismissAll()

        _ = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    static func update(state: State) {
        for activity in activities {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        }
    }

    /// A finished workout is worth a last glance; a discarded one is not, and
    /// lingering would leave a card the user has to dismiss by hand.
    static func end(state: State, dismissImmediately: Bool) {
        let policy: ActivityUIDismissalPolicy =
            dismissImmediately ? .immediate : .after(Date().addingTimeInterval(120))

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
    private static func dismissAll() {
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
