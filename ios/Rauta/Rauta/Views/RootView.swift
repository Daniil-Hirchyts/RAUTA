import SwiftUI

@MainActor
struct RootView: View {
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var navigation = AppSessionStore.shared
    @State private var renderedEntry: AppPageEntry?

    var body: some View {
        ZStack {
            if let rootEntry = navigation.pages.first {
                page(for: rootEntry.page)
                    .id(rootEntry.id)
            } else {
                WorkoutsScreen()
            }

            if let renderedEntry,
               renderedEntry.id != navigation.pages.first?.id {
                page(for: renderedEntry.page)
                    .id(renderedEntry.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.shell.ignoresSafeArea())
                    .zIndex(100)
            }
        }
        .environment(\.appStore, store)
        .simultaneousGesture(edgeBackGesture)
        .preferredColorScheme(.dark)
        .onAppear {
            renderedEntry = navigation.activeEntry
        }
        .onReceive(navigation.$pages) { pages in
            renderedEntry = pages.last ?? pages.first
#if DEBUG
            UserDefaults.standard.set(renderedEntry?.page.key ?? "nil", forKey: "rautaDebugRenderedRoute")
#endif
        }
    }

    @ViewBuilder
    private func page(for page: AppPage) -> some View {
        switch page {
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
        case .workoutDetail(let workoutId):
            WorkoutDetailScreen(workoutId: workoutId)
        case .planWeek(let sourceProgramId):
            PlanWeekScreen(sourceProgramId: sourceProgramId)
        case .muscles(let preferredWorkoutId):
            ExercisePickerScreen(stage: .muscles, preferredWorkoutId: preferredWorkoutId)
        case .equipment(let preferredWorkoutId):
            ExercisePickerScreen(stage: .equipment, preferredWorkoutId: preferredWorkoutId)
        case .exercises(let preferredWorkoutId):
            ExercisePickerScreen(stage: .exercises, preferredWorkoutId: preferredWorkoutId)
        case .exerciseDetail(let exerciseId):
            ExerciseDetailScreen(exerciseId: exerciseId)
        case .workoutDestination(let preferredWorkoutId):
            WorkoutDestinationScreen(preferredWorkoutId: preferredWorkoutId)
        case .workoutForm(let exerciseIds, let workoutId, let focusMuscles):
            WorkoutFormScreen(
                initialExerciseIds: exerciseIds,
                workoutId: workoutId,
                focusMuscles: focusMuscles
            )
        case .equipmentPreset:
            EquipmentPresetScreen()
        case .exerciseAlternatives(let exerciseId, let workoutId):
            ExerciseAlternativesScreen(exerciseId: exerciseId, workoutId: workoutId)
        }
    }

    private var edgeBackGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard navigation.pages.count > 1,
                      value.startLocation.x < 24,
                      value.translation.width > 90,
                      abs(value.translation.height) < 80
                else { return }
                Haptics.trigger(.selection)
                navigation.pop()
            }
    }
}
