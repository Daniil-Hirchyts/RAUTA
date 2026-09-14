import SwiftUI

@MainActor
struct RootView: View {
    @ObservedObject private var navigation = AppSessionStore.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let rootEntry = navigation.pages.first {
                    page(for: rootEntry.page)
                        .id(rootEntry.id)
                        // The root page stays mounted under whatever is pushed
                        // over it; its RAUTA must not keep performing unseen.
                        .environment(\.rautaOnStage, navigation.activeEntry?.id == rootEntry.id)
                } else {
                    WorkoutsScreen()
                }

                if let activeEntry = navigation.activeEntry,
                   activeEntry.id != navigation.pages.first?.id {
                    page(for: activeEntry.page)
                        .id(activeEntry.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.shell.ignoresSafeArea())
                        .zIndex(100)
                }
            }
            .environment(\.appSafeAreaInsets, proxy.safeAreaInsets)
        }
        .simultaneousGesture(edgeBackGesture)
        .background(AppearanceWindowAnchor().allowsHitTesting(false))
        .tint(Theme.primary)
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
