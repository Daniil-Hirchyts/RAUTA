import SwiftUI

/// Picking exercises to add to a workout.
///
/// One page, not a wizard. Muscles and equipment narrow the same grid the
/// Library browses, from the same strip of glass, and each opens full screen
/// only when you ask for it — so choosing three exercises never costs three
/// pages, and changing your mind about the equipment does not restart anything.
///
/// The selection lives in the session store because the pages this flow ends on
/// — a new workout, or an existing one — are the ones that spend it.
struct AddExercisesScreen: View {
    private let store = AppStore.shared
    /// The workout this was started from, offered first when the exercises are
    /// finally filed somewhere.
    let preferredWorkoutId: String?

    @State private var browse = ExerciseBrowseState()
    @State private var resultsMemo = Memo<ExerciseBrowseQuery, [ExerciseSummary]>()
    /// A workout being proposed, off the main actor.
    @State private var proposal: Task<Void, Never>?

    private static let zoomPrefix = "picker"

    private var selectedMuscles: Binding<[MuscleId]> {
        Binding(
            get: { store.filters.selectedMuscles },
            set: { store.filters.setMuscles($0) }
        )
    }

    private var selectedEquipment: Binding<[String]> {
        Binding(
            get: { store.filters.selectedEquipment },
            set: { store.filters.setEquipment($0) }
        )
    }

    /// Worked out once per change of the browse: the page reads it for the
    /// count, the grid and the empty state, and redraws whenever any store does.
    private var matchingExercises: [ExerciseSummary] {
        let query = ExerciseBrowseQuery(
            state: browse,
            muscles: store.filters.selectedMuscles,
            equipment: store.filters.selectedEquipment,
            favoriteIds: store.favorites.favoriteIds
        )
        return resultsMemo(query) { query.results() }
    }

    private var selectedIds: [String] { store.navigation.selectedIds }

    var body: some View {
        AppShell(commandsVisible: true) {
            AppTitledPage {
                header
            } content: {
                results
            }
        } controls: {
            controls
        }
        .exerciseFilterPage(
            state: $browse,
            selectedMuscles: selectedMuscles,
            selectedEquipment: selectedEquipment,
            zoomPrefix: Self.zoomPrefix,
            backLabel: "Exercises",
            equipmentOptions: { ExerciseCatalogue.equipmentForMuscles(store.filters.selectedMuscles) }
        )
        .onChange(of: browse.search) { _, _ in resetPagination() }
        .onChange(of: store.filters.selectedMuscles) { _, _ in resetPagination() }
        .onChange(of: store.filters.selectedEquipment) { _, _ in resetPagination() }
        .onChange(of: browse.favoritesOnly) { _, _ in resetPagination() }
    }

    private var header: some View {
        AppShellHeader(
            title: "Exercises",
            subtitle: subtitle,
            left: {
                AppHeaderButton(
                    systemImage: "chevron.left",
                    label: "Back",
                    action: store.navigation.pop
                )
            },
            right: {
                AppMenuButton(label: "Exercise actions", compact: true) { rautaOptions }
            },
            above: { EmptyView() },
            below: {
                ExerciseFilterBar(
                    state: $browse,
                    selectedMuscles: selectedMuscles,
                    selectedEquipment: selectedEquipment,
                    zoomPrefix: Self.zoomPrefix
                )
            }
        )
    }

    private var subtitle: String {
        guard selectedIds.isEmpty else {
            return "\(Wording.countLabel(selectedIds.count, "exercise")) selected"
        }
        return Wording.countLabel(matchingExercises.count, "exercise")
    }

    @ViewBuilder
    private var results: some View {
        if matchingExercises.isEmpty {
            ExerciseBrowseEmptyState(
                state: browse,
                hasFavorites: !store.favorites.favoriteIds.isEmpty,
                onClearSearch: { browse.search = "" },
                onShowAll: { browse.favoritesOnly = false }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .belowPageHeader()
            .padding(32)
            .offset(y: -30)
        } else {
            ExerciseResultsGrid(
                exercises: matchingExercises,
                visibleCount: $browse.visibleExerciseCount,
                zoomPrefix: Self.zoomPrefix,
                selectMode: true,
                selectedIds: selectedIds,
                onOpenDetail: { exercise in
                    store.navigation.push(
                        .exerciseDetail(exerciseId: exercise.id),
                        from: "\(Self.zoomPrefix)-exercise:\(exercise.id)"
                    )
                },
                onToggleSelect: toggleSelected
            )
            .animation(Theme.Motion.smoothOut(0.28), value: browse.searchOpen)
        }
    }

    /// One command: where the picked exercises go. Choosing which workout is a
    /// page of its own, so the list can be as long as it is.
    private var controls: some View {
        AppButton(
            selectedIds.isEmpty ? "Add to workout" : "Add \(Wording.countLabel(selectedIds.count, "exercise"))",
            size: .cta,
            isDisabled: selectedIds.isEmpty,
            expands: true
        ) {
            Haptics.trigger(.selection)
            store.navigation.push(
                .workoutDestination(
                    exerciseIds: selectedIds,
                    preferredWorkoutId: preferredWorkoutId
                )
            )
        }
    }

    @ViewBuilder
    private var rautaOptions: some View {
        if preferredWorkoutId == nil {
            Button(action: buildWorkoutWithRauta) {
                Label("Build workout with RAUTA", systemImage: "sparkles")
            }
            .disabled(store.filters.selectedMuscles.isEmpty || proposal != nil)
        }

        if !selectedIds.isEmpty {
            Button {
                Haptics.trigger(.selection)
                store.navigation.selectedIds = []
            } label: {
                Label("Clear selection", systemImage: "xmark")
            }
        }

        if !store.filters.selectedMuscles.isEmpty || !store.filters.selectedEquipment.isEmpty
            || browse.favoritesOnly || !browse.normalizedSearch.isEmpty {
            Button(action: clearFilters) {
                Label("Clear filters", systemImage: "line.3.horizontal.decrease")
            }
        }

        Button {
            Haptics.trigger(.selection)
            browse.favoritesOnly.toggle()
        } label: {
            Label(
                browse.favoritesOnly ? "Show all exercises" : "Show favorites only",
                systemImage: browse.favoritesOnly ? "heart.slash" : "heart"
            )
        }
    }

    private func clearFilters() {
        Haptics.trigger(.selection)
        store.filters.setMuscles([])
        store.filters.setEquipment([])
        browse.favoritesOnly = false
        browse.search = ""
    }

    private func buildWorkoutWithRauta() {
        guard proposal == nil else { return }
        let focus = store.filters.selectedMuscles
        proposal = Task {
            defer { proposal = nil }
            do {
                let exerciseIds = try await EngineWorkout.propose(
                    date: CalendarDate.today,
                    focusMuscles: focus,
                    availableEquipment: store.filters.selectedEquipment
                )
                guard !exerciseIds.isEmpty else {
                    Haptics.trigger(.warning)
                    return
                }
                Haptics.trigger(.medium)
                store.navigation.push(
                    .workoutForm(exerciseIds: exerciseIds, workoutId: nil, engineFocusMuscles: focus)
                )
            } catch is CancellationError {
            } catch {
                Haptics.trigger(.warning)
            }
        }
    }

    private func toggleSelected(_ id: String) {
        store.navigation.selectedIds = Sanitize.toggle(store.navigation.selectedIds, id)
    }

    private func resetPagination() {
        browse.visibleExerciseCount = ExerciseCatalogue.pageSize
    }
}
