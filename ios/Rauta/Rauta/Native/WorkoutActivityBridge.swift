import ActivityKit
import Foundation

/// The ActivityKit half of the Live Activity: one card per workout, adopted
/// rather than duplicated when the app is relaunched into a session that is
/// still running.
///
/// A Live Activity is an accessory to the workout, never a reason to break it,
/// so every failure here is swallowed.
@MainActor
enum WorkoutActivityBridge {
    /// One thing to do to the cards on screen, described in values only.
    /// ActivityKit's `Activity` is not `Sendable`, so a change names the
    /// cards it is for, and the cards are looked up where it is applied.
    enum Change: Sendable {
        case update(ids: [String], state: WorkoutActivityAttributes.ContentState, at: Date)
        case end(
            ids: [String],
            state: WorkoutActivityAttributes.ContentState?,
            policy: ActivityUIDismissalPolicy,
            at: Date
        )
    }

    /// The last change handed off. Each new one waits for it, so frames reach
    /// the card in the order they were made; the timestamp also lets the
    /// system drop a frame older than one it already shows.
    private static var pending: Task<Void, Never>?

    private static func enqueue(_ change: Change) {
        let previous = pending
        pending = Task {
            await previous?.value
            await apply(change)
        }
    }

    @concurrent
    private static func apply(_ change: Change) async {
        switch change {
        case let .update(ids, state, date):
            for activity in Activity<WorkoutActivityAttributes>.activities where ids.contains(activity.id) {
                await activity.update(
                    ActivityContent(state: state, staleDate: nil),
                    alertConfiguration: nil,
                    timestamp: date
                )
            }
        case let .end(ids, state, policy, date):
            for activity in Activity<WorkoutActivityAttributes>.activities where ids.contains(activity.id) {
                await activity.end(
                    state.map { ActivityContent(state: $0, staleDate: nil) },
                    dismissalPolicy: policy,
                    timestamp: date
                )
            }
        }
    }

    /// False when the user has switched Live Activities off for the app, which
    /// makes every request throw.
    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private static var activities: [Activity<WorkoutActivityAttributes>] {
        Activity<WorkoutActivityAttributes>.activities
    }

    private static func attributes(_ content: LiveActivityContent) -> WorkoutActivityAttributes {
        WorkoutActivityAttributes(
            workoutId: content.workoutId,
            workoutName: content.workoutName,
            workoutDate: content.workoutDate
        )
    }

    private static func state(_ content: LiveActivityContent) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            exerciseName: content.exerciseName,
            completedCount: content.completedCount,
            totalCount: content.totalCount,
            timerStart: content.timerStartEpochMs > 0
                ? Date(epochMillis: content.timerStartEpochMs)
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
        guard isSupported else { return }
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
        enqueue(.update(ids: activities.map(\.id), state: state(content), at: Date()))
    }

    /// A finished workout is worth a last glance; a discarded one is not, and
    /// lingering would leave a card the user has to dismiss by hand.
    static func end(_ content: LiveActivityContent, dismissImmediately: Bool) {
        let state = state(content)
        let policy: ActivityUIDismissalPolicy = dismissImmediately
            ? .immediate
            : .after(Date().addingTimeInterval(120))

        enqueue(.end(ids: activities.map(\.id), state: state, policy: policy, at: Date()))
    }

    /// Clears cards without touching their content — used when replacing one
    /// workout's activity with another's.
    private static func dismissAll() {
        // The cards on screen now, not the one about to be requested.
        enqueue(.end(ids: activities.map(\.id), state: nil, policy: .immediate, at: Date()))
    }
}
