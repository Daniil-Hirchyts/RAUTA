import Combine
import SwiftUI

/// The one object every screen reaches for. It owns nothing itself: each store
/// remains the authority on its own slice, and this is the wiring that starts
/// them and keeps them observing one another.
///
/// The stores are `@Observable`, so a screen redraws for the properties it
/// actually reads, not for every change anywhere in the app.
@MainActor
final class AppStore {
    static let shared = AppStore()

    let navigation = AppSessionStore.shared
    let filters = FiltersStore.shared
    let favorites = FavoritesStore.shared
    let settings = SettingsStore.shared
    let workouts = WorkoutsStore.shared
    let trainingProfile = TrainingProfileStore.shared
    let trainingRecords = TrainingRecordsStore.shared
    let activeWorkout = ActiveWorkoutStore.shared
    let iCloud = ICloudSync.shared

    private var cancellables = Set<AnyCancellable>()
    private var bootstrapped = false

    private init() {}

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true

        AppearanceController.start()
        // Before anything can make a sound: the app's audio never stops the
        // person's music.
        WorkoutAudio.configure()

        // A session follows the workout it is performing, wherever that workout
        // is edited from.
        activeWorkout.observeWorkouts()
        // One workout, put back together before anything can read it.
        activeWorkout.reconcileRestored()

        LiveActivitySync.start()
        WorkoutBackgroundSession.shared.start()
        RestAlerts.shared.start()
        HealthService.shared.startAutoSync()
        WatchConnectivityService.shared.start()
        iCloud.start()

        applyKeepAwake()
        settings.changed
            .sink { [weak self] in self?.applyKeepAwake() }
            .store(in: &cancellables)
        activeWorkout.changed
            .sink { [weak self] in self?.applyKeepAwake() }
            .store(in: &cancellables)
    }

    /// The screen stays on only while a workout is actually running and the
    /// setting asks for it.
    private func applyKeepAwake() {
        let running = activeWorkout.session != nil
        ScreenAwake.set(settings.keepAwake && running)
    }

    func persistNow() {
        filters.persist()
        favorites.persist()
        settings.persist()
        workouts.persist()
        trainingProfile.persist()
        trainingRecords.persist()
        activeWorkout.persist()
    }
}

private struct AppStoreKey: EnvironmentKey {
    @MainActor static var defaultValue: AppStore { AppStore.shared }
}

extension EnvironmentValues {
    var appStore: AppStore {
        get { self[AppStoreKey.self] }
        set { self[AppStoreKey.self] = newValue }
    }
}
