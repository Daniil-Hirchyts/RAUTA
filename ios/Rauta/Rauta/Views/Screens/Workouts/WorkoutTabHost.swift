import SwiftUI

struct WorkoutTabHost: View {
    private let activeWorkout = ActiveWorkoutStore.shared
    let upcoming: [Workout]
    let past: [Workout]
    let activeWorkoutId: String?
    @Binding var liveWorkoutPresented: Bool
    @Binding var detailActionState: WorkoutDetailActionState
    @Binding var detailActionRequest: WorkoutDetailExternalAction?
    @Binding var listSelection: Int
    @Binding var selectedWorkoutId: String?
    let onOpenExercisePlayer: () -> Void

    private var hasWorkouts: Bool {
        !upcoming.isEmpty || !past.isEmpty
    }

    /// A workout opened from the list, or the one running.
    private enum Route: Hashable {
        case workout(String)
        case live(String)

        var workoutId: String {
            switch self {
            case .workout(let id), .live(let id): return id
            }
        }
    }

    /// The tab's stack, read from the selection this host is given: opening a
    /// workout pushes it, and swiping back or dragging it down closes it.
    private var path: Binding<[Route]> {
        Binding(
            get: {
                if let selectedWorkoutId { return [.workout(selectedWorkoutId)] }
                if liveWorkoutPresented, let session = activeWorkout.session {
                    return [.live(session.workoutId)]
                }
                return []
            },
            set: { routes in
                guard routes.isEmpty else { return }
                detailActionState = .none
                detailActionRequest = nil
                selectedWorkoutId = nil
                liveWorkoutPresented = false
            }
        )
    }

    var body: some View {
        NavigationStack(path: path) {
            workoutListPage
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    detail(route)
                        .toolbar(.hidden, for: .navigationBar)
                        .swipeBackEnabled()
                        .background(Theme.shell.ignoresSafeArea())
                        // The workout grows out of its row, and a drag down
                        // throws it back there.
                        .appZoomTransition(from: WorkoutRow.zoomSourceID(route.workoutId))
                }
        }
    }

    @ViewBuilder
    private func detail(_ route: Route) -> some View {
        switch route {
        case .workout(let id):
            WorkoutDetailScreen(
                workoutId: id,
                onOpenExercisePlayer: onOpenExercisePlayer,
                onBackToWorkouts: closeWorkout,
                externalActionRequest: $detailActionRequest,
                onActionStateChange: { detailActionState = $0 }
            )
        case .live(let id):
            WorkoutDetailScreen(
                workoutId: id,
                onOpenExercisePlayer: onOpenExercisePlayer,
                onBackToWorkouts: closeWorkout
            )
        }
    }

    private var workoutListPage: some View {
        AppShell(commandsVisible: false) {
            AppTitledPage {
                AppShellHeader(
                    title: "Workout",
                    left: { Color.clear.frame(width: 44, height: 44) },
                    right: { Color.clear.frame(width: 44, height: 44) },
                    above: { EmptyView() },
                    below: {
                        if hasWorkouts {
                            WorkoutsModeSwitcher(
                                selection: $listSelection,
                                workouts: upcoming + past
                            )
                        }
                    }
                )
            } content: {
                WorkoutListContent(
                    upcoming: upcoming,
                    past: past,
                    activeWorkoutId: activeWorkoutId,
                    selection: $listSelection,
                    onOpen: openWorkout
                )
            }
        } controls: {
            EmptyView()
        }
    }

    private func openWorkout(_ workout: Workout) {
        _ = EngineWorkout.ensureEngineWorkout(workout.id)
        Haptics.trigger(.selection)
        detailActionState = .none
        detailActionRequest = nil
        if activeWorkoutId == workout.id {
            selectedWorkoutId = nil
            liveWorkoutPresented = true
        } else {
            liveWorkoutPresented = false
            selectedWorkoutId = workout.id
        }
    }

    private func closeWorkout() {
        detailActionState = .none
        detailActionRequest = nil
        selectedWorkoutId = nil
        liveWorkoutPresented = false
    }
}
