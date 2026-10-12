import SwiftUI

/// The app's navigation, drawn from ``AppSessionStore/pages``.
///
/// The root page is the tabs (or first-run setup). Every page opened over it is
/// a real presentation: a full-screen modal that grows out of what was tapped
/// and can be dragged back into it. Steps taken inside a modal push within its
/// own navigation stack, with the system's swipe back. Modals opened from
/// inside a modal stack on top of it.
@MainActor
struct RootView: View {
    private let navigation = AppSessionStore.shared
    @Namespace private var zoomNamespace

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let rootEntry = navigation.pages.first {
                    AppPageView(entry: rootEntry)
                        .id(rootEntry.id)
                } else {
                    WorkoutsScreen()
                }
            }
            .modifier(ModalPresenter(index: 0))
            .environment(\.appSafeAreaInsets, proxy.safeAreaInsets)
        }
        .environment(\.appZoomNamespace, zoomNamespace)
        .background(AppearanceWindowAnchor().allowsHitTesting(false))
        .tint(Theme.primary)
    }
}

/// Presents the modal at `index` in ``AppSessionStore/modals`` over the view it
/// is attached to.
private struct ModalPresenter: ViewModifier {
    let index: Int
    private let navigation = AppSessionStore.shared

    func body(content: Content) -> some View {
        content.fullScreenCover(
            item: Binding(
                get: { navigation.modals.indices.contains(index) ? navigation.modals[index].first : nil },
                // Dragged down, or closed by the system.
                set: { if $0 == nil { navigation.dismissModal(at: index) } }
            )
        ) { root in
            ModalStack(index: index, root: root)
        }
    }
}

/// One modal: its first page, the steps pushed inside it, and any modal opened
/// over it.
private struct ModalStack: View {
    let index: Int
    let root: AppPageEntry
    private let navigation = AppSessionStore.shared

    private var steps: Binding<[AppPageEntry]> {
        Binding(
            get: {
                navigation.modals.indices.contains(index)
                    ? Array(navigation.modals[index].dropFirst())
                    : []
            },
            set: { navigation.setSteps($0, inModal: index) }
        )
    }

    var body: some View {
        NavigationStack(path: steps) {
            AppPageView(entry: root)
                .navigationDestination(for: AppPageEntry.self) { entry in
                    AppPageView(entry: entry)
                }
        }
        .modifier(ModalPresenter(index: index + 1))
        .presentationBackground(Theme.shell)
        .appZoomTransition(from: root.zoomSource)
    }
}

/// A page, as the navigation shows it.
struct AppPageView: View {
    let entry: AppPageEntry
    private let navigation = AppSessionStore.shared

    var body: some View {
        page
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.shell.ignoresSafeArea())
            // Every page draws its own title bar.
            .toolbar(.hidden, for: .navigationBar)
            .swipeBackEnabled()
            // A page something has been opened over keeps its place in the
            // stack, but its RAUTA must not keep performing unseen.
            .environment(\.rautaOnStage, navigation.activeEntry?.id == entry.id)
    }

    @ViewBuilder
    private var page: some View {
        switch entry.page {
        case .workouts:
            WorkoutsScreen()
        case .settings:
            SettingsScreen()
        case .onboarding:
            OnboardingScreen()
        case .profileBasics:
            ProfileBasicsScreen()
        case .profileTraining:
            TrainingPreferencesScreen()
        case .profileHealth:
            HealthEligibilityScreen()
        case .profileEquipment:
            ProfileEquipmentScreen()
        case .profileLoadSteps:
            EquipmentLoadScreen()
        case .profilePriorities:
            MusclePrioritiesScreen()
        case .planWeek(let sourceProgramId):
            PlanWeekScreen(sourceProgramId: sourceProgramId)
        case .addExercises(let preferredWorkoutId):
            AddExercisesScreen(preferredWorkoutId: preferredWorkoutId)
        case .exerciseDetail(let exerciseId):
            ExerciseDetailScreen(exerciseId: exerciseId)
        case .workoutDestination(let exerciseIds, let preferredWorkoutId):
            WorkoutDestinationScreen(mode: .exercises(exerciseIds, preferredWorkoutId: preferredWorkoutId))
        case .reuseWorkout(let sourceWorkoutId):
            WorkoutDestinationScreen(mode: .reuse(sourceWorkoutId: sourceWorkoutId))
        case .plannedWorkout(let workoutId):
            WorkoutDetailScreen(
                workoutId: workoutId,
                onBackToWorkouts: navigation.pop
            )
        case .equipmentPreset:
            EquipmentPresetScreen()
        case .exerciseAlternatives(let exerciseId, let workoutId):
            ExerciseAlternativesScreen(exerciseId: exerciseId, workoutId: workoutId)
        case .policies:
            PoliciesScreen()
        case .backup:
            BackupScreen()
        case .coachNextWeek:
            NextWeekScreen()
        case .coachAdjust:
            AdjustWeekScreen()
        case .coachReview:
            WeeklyReviewScreen()
        case .summaryStreak:
            SummaryStreakScreen()
        case .summaryActivity(let month, let metric):
            SummaryActivityScreen(month: month, metric: metric)
        case .summaryMuscles(let month):
            SummaryMusclesScreen(month: month)
        case .summaryRecords:
            SummaryRecordsScreen()
        }
    }
}
