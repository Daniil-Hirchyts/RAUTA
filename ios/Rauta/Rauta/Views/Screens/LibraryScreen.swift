import SwiftUI

/// Browse the complete exercise catalogue without borrowing the workout-builder
/// filters. Browse state is isolated from the app shell so typing and filtering
/// cannot invalidate the native tab host.
struct LibraryScreen: View {
    @ObservedObject private var favorites = FavoritesStore.shared
    private let navigation = AppSessionStore.shared
    @State private var browse = ExerciseBrowseState()
    @State private var selectedMuscles: [MuscleId] = []
    @State private var selectedEquipment: [String] = []
    @State private var resultsMemo = Memo<ExerciseBrowseQuery, [ExerciseSummary]>()

    /// The page reads this in several places per render and once per card as
    /// the grid scrolls, so it is worked out once per change of the query.
    private var filteredExercises: [ExerciseSummary] {
        let query = ExerciseBrowseQuery(
            state: browse,
            muscles: selectedMuscles,
            equipment: selectedEquipment,
            favoriteIds: favorites.favoriteIds
        )
        return resultsMemo(query) { query.results() }
    }

    var body: some View {
        AppTitledPage {
            libraryHeader
        } content: {
            results
        }
        .exerciseFilterPage(
            state: $browse,
            selectedMuscles: $selectedMuscles,
            selectedEquipment: $selectedEquipment,
            zoomPrefix: Self.zoomPrefix,
            backLabel: "Library"
        )
        .onChange(of: browse.search) { _, _ in resetPagination() }
        .onChange(of: selectedMuscles) { _, _ in resetPagination() }
        .onChange(of: selectedEquipment) { _, _ in resetPagination() }
        .onChange(of: browse.favoritesOnly) { _, _ in resetPagination() }
        .onChange(of: favorites.favoriteIds) { _, _ in resetPagination() }
    }

    private static let zoomPrefix = "library"

    private var libraryHeader: some View {
        AppShellHeader(
            title: "Library",
            left: { Color.clear.frame(width: 44, height: 44) },
            right: { Color.clear.frame(width: 44, height: 44) },
            above: { EmptyView() },
            below: {
                VStack(alignment: .leading, spacing: 10) {
                    ExerciseFilterBar(
                        state: $browse,
                        selectedMuscles: $selectedMuscles,
                        selectedEquipment: $selectedEquipment,
                        zoomPrefix: Self.zoomPrefix
                    )
                    resultCountLabel
                }
            }
        )
    }

    private var resultCountLabel: some View {
        Text(resultSummary)
            .font(Theme.sans(12, weight: .medium))
            .foregroundStyle(Theme.mutedForeground)
            .padding(.leading, 2)
            .lineLimit(1)
    }

    private var resultSummary: String {
        var parts = [Wording.countLabel(filteredExercises.count, "exercise")]

        if !selectedMuscles.isEmpty {
            parts.append(Wording.countLabel(selectedMuscles.count, "muscle"))
        }

        if !selectedEquipment.isEmpty {
            parts.append("\(selectedEquipment.count) equipment")
        }

        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var results: some View {
        if filteredExercises.isEmpty {
            emptyState
        } else {
            ExerciseResultsGrid(
                exercises: filteredExercises,
                visibleCount: $browse.visibleExerciseCount,
                zoomPrefix: Self.zoomPrefix,
                onOpenDetail: { exercise in
                    navigation.push(
                        .exerciseDetail(exerciseId: exercise.id),
                        from: "\(Self.zoomPrefix)-exercise:\(exercise.id)"
                    )
                }
            )
            .animation(Theme.Motion.smoothOut(0.28), value: browse.searchOpen)
        }
    }

    private var emptyState: some View {
        ExerciseBrowseEmptyState(
            state: browse,
            hasFavorites: !favorites.favoriteIds.isEmpty,
            onClearSearch: { browse.search = "" },
            onShowAll: { browse.favoritesOnly = false }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .belowPageHeader()
        .padding(32)
        .offset(y: -30)
        .animation(Theme.Motion.smoothOut(0.28), value: browse.searchOpen)
    }

    private func resetPagination() {
        browse.visibleExerciseCount = ExerciseCatalogue.pageSize
    }
}
