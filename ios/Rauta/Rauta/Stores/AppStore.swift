import Combine
import SwiftUI

/// The one object every screen reaches for. It owns nothing itself: each store
/// remains the authority on its own slice, and this is the wiring that starts
/// them, keeps them observing one another, and hands SwiftUI a single publisher
/// to redraw from.
@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()
    // This aggregator has no @Published storage to anchor the synthesized
    // publisher. Keep a stable instance for forwarding child-store changes.
    nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()

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

    private init() {
        // One publisher for the whole app: SwiftUI's `@ObservedObject` on a child
        // store would work, but every screen reads across two or three of them.
        for store in [
            navigation.objectWillChange,
            filters.objectWillChange,
            favorites.objectWillChange,
            settings.objectWillChange,
            workouts.objectWillChange,
            trainingProfile.objectWillChange,
            trainingRecords.objectWillChange,
            activeWorkout.objectWillChange,
            iCloud.objectWillChange,
        ] {
            store
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true

        // A session follows the workout it is performing, wherever that workout
        // is edited from.
        activeWorkout.observeWorkouts()
        // One workout, put back together before anything can read it.
        activeWorkout.reconcileRestored()

        LiveActivitySync.start()
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
        navigation.persist()
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
