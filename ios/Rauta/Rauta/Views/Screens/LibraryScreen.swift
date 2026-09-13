import SwiftUI

private struct LibraryBrowseState {
    var search = ""
    var selectedMuscles: [MuscleId] = []
    var selectedEquipment: [String] = []
    var favoritesOnly = false
    var presentedFilter: LibraryFilterKind?
    var visibleExerciseCount = ExerciseCatalogue.pageSize
    var searchOpen = false
}

/// Browse the complete exercise catalogue without borrowing the workout-builder
/// filters. Browse state is isolated from the app shell so typing and filtering
/// cannot invalidate the native tab host.
struct LibraryScreen: View {
    @Environment(\.appSafeAreaInsets) private var safeAreaInsets
    @ObservedObject private var favorites = FavoritesStore.shared
    private let navigation = AppSessionStore.shared
    @State private var browse = LibraryBrowseState()
    @FocusState private var searchFocused: Bool

    private var filteredExercises: [ExerciseSummary] {
        let query = browse.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let muscleSet = Set(browse.selectedMuscles)
        let equipmentSet = Set(browse.selectedEquipment)

        let matches = ExerciseCatalogue.all.filter { exercise in
            (query.isEmpty || exercise.name.localizedCaseInsensitiveContains(query))
                && (muscleSet.isEmpty || exercise.muscles.contains(where: muscleSet.contains))
                && (equipmentSet.isEmpty || equipmentSet.contains(exercise.equipment))
                && (!browse.favoritesOnly || favorites.isFavorite(exercise.id))
        }

        guard !muscleSet.isEmpty else {
            return matches.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        return matches.sorted { left, right in
            let leftScore = ExerciseCatalogue.relevance(left, muscleSet)
            let rightScore = ExerciseCatalogue.relevance(right, muscleSet)
            if leftScore != rightScore { return leftScore > rightScore }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    private var hasActiveFilters: Bool {
        !browse.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !browse.selectedMuscles.isEmpty
            || !browse.selectedEquipment.isEmpty
            || browse.favoritesOnly
    }

    private var visibleExercises: ArraySlice<ExerciseSummary> {
        filteredExercises.prefix(browse.visibleExerciseCount)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                libraryHeader
                results
            }

            if let presentedFilter = browse.presentedFilter {
                LibraryFilterOverlay(
                    filter: presentedFilter,
                    selectedMuscles: $browse.selectedMuscles,
                    selectedEquipment: $browse.selectedEquipment,
                    onClose: {
                        withAnimation(Theme.Motion.smoothOut(0.2)) {
                            browse.presentedFilter = nil
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(50)
            }
        }
        .onChange(of: browse.search) { _, _ in resetPagination() }
        .onChange(of: browse.selectedMuscles) { _, _ in resetPagination() }
        .onChange(of: browse.selectedEquipment) { _, _ in resetPagination() }
        .onChange(of: browse.favoritesOnly) { _, _ in resetPagination() }
        .onChange(of: favorites.favoriteIds) { _, _ in resetPagination() }
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: browse.searchOpen ? 10 : 12) {
            if !browse.searchOpen {
                Text("Library")
                    .font(Theme.sans(31, weight: .black))
                    .kerning(-0.8)
                    .foregroundStyle(Theme.foreground)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if browse.searchOpen {
                expandedSearchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                compactFilterBar
                    .transition(.opacity)
            }

            Text(Wording.countLabel(filteredExercises.count, "exercise"))
                .font(Theme.sans(12, weight: .medium))
                .foregroundStyle(Theme.mutedForeground)
                .padding(.leading, 2)
        }
        .padding(.horizontal, Theme.Metrics.contentInset)
        .padding(.top, safeAreaInsets.top + (browse.searchOpen ? 8 : 10))
        .padding(.bottom, 8)
    }

    private var compactFilterBar: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                LibraryFilterChip(
                    title: browse.selectedMuscles.isEmpty ? "Muscles" : "Muscles · \(browse.selectedMuscles.count)",
                    selected: !browse.selectedMuscles.isEmpty
                ) {
                    Haptics.trigger(.selection)
                    browse.presentedFilter = .muscles
                }

                LibraryFilterChip(
                    title: browse.selectedEquipment.isEmpty ? "Equipment" : "Equipment · \(browse.selectedEquipment.count)",
                    selected: !browse.selectedEquipment.isEmpty
                ) {
                    Haptics.trigger(.selection)
                    browse.presentedFilter = .equipment
                }

                LibraryFilterChip(title: "Favorites", selected: browse.favoritesOnly) {
                    Haptics.trigger(.selection)
                    browse.favoritesOnly.toggle()
                }

                Spacer(minLength: 0)

                LibraryRoundButton(systemImage: "magnifyingglass", label: "Search exercises") {
                    openSearch()
                }
            }
        }
    }

    private var expandedSearchBar: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                filterMenu

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.secondaryForeground)

                    TextField("Search exercises", text: $browse.search)
                        .focused($searchFocused)
                        .font(Theme.sans(16))
                        .foregroundStyle(Theme.foreground)
                        .tint(Theme.primary)
                        .submitLabel(.search)
                        .accessibilityLabel("Search exercises by name")

                    if !browse.search.isEmpty {
                        Button {
                            Haptics.trigger(.selection)
                            browse.search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .glassSurface(
                    .regular,
                    in: Capsule(),
                    border: searchFocused ? Theme.ring : Theme.Glassware.edge,
                    legacyFill: Theme.card.opacity(0.74)
                )

                LibraryRoundButton(systemImage: "xmark", label: "Cancel search") {
                    closeSearch()
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Button {
                searchFocused = false
                browse.presentedFilter = .muscles
            } label: {
                Label(
                    browse.selectedMuscles.isEmpty ? "Muscles" : "Muscles (\(browse.selectedMuscles.count))",
                    systemImage: "figure.strengthtraining.traditional"
                )
            }

            Button {
                searchFocused = false
                browse.presentedFilter = .equipment
            } label: {
                Label(
                    browse.selectedEquipment.isEmpty ? "Equipment" : "Equipment (\(browse.selectedEquipment.count))",
                    systemImage: "dumbbell"
                )
            }

            Button {
                Haptics.trigger(.selection)
                browse.favoritesOnly.toggle()
            } label: {
                Label(
                    browse.favoritesOnly ? "Show all exercises" : "Favorites only",
                    systemImage: browse.favoritesOnly ? "heart.slash" : "heart"
                )
            }

            if hasActiveFilters {
                Divider()
                Button(role: .destructive) {
                    clearFilters()
                } label: {
                    Label("Clear filters", systemImage: "xmark")
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 46, height: 46)

                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(Theme.sans(9, weight: .black))
                        .foregroundStyle(Theme.primaryForeground)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Theme.primary, in: Circle())
                        .offset(x: 3, y: -3)
                }
            }
            .glassSurface(
                activeFilterCount > 0 ? .tinted(Theme.primary.opacity(0.34)) : .regular,
                in: Circle(),
                border: activeFilterCount > 0 ? Theme.Glassware.brightEdge : Theme.Glassware.edge,
                legacyFill: Theme.card.opacity(0.74)
            )
        }
        .accessibilityLabel("Filters")
    }

    private var activeFilterCount: Int {
        browse.selectedMuscles.count
            + browse.selectedEquipment.count
            + (browse.favoritesOnly ? 1 : 0)
    }

    private func openSearch() {
        Haptics.trigger(.selection)
        withAnimation(Theme.Motion.smoothOut(0.28)) {
            browse.searchOpen = true
        }
        Task { @MainActor in
            await Task.yield()
            searchFocused = true
        }
    }

    private func closeSearch() {
        Haptics.trigger(.selection)
        searchFocused = false
        browse.search = ""
        withAnimation(Theme.Motion.smoothOut(0.28)) {
            browse.searchOpen = false
        }
    }

    @ViewBuilder
    private var results: some View {
        if filteredExercises.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible()),
                    ],
                    spacing: 14
                ) {
                    ForEach(Array(visibleExercises.enumerated()), id: \.element.id) { index, exercise in
                        ExerciseCard(
                            exercise: exercise,
                            index: index,
                            onOpenDetail: {
                                navigation.push(.exerciseDetail(exerciseId: $0.id))
                            },
                            onToggleSelect: { _ in }
                        )
                        .onAppear {
                            guard exercise.id == visibleExercises.last?.id else { return }
                            loadMoreExercises()
                        }
                    }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.top, 8)
                .padding(.bottom, 28)

                if browse.visibleExerciseCount < filteredExercises.count {
                    MatrixLoader(
                        variant: .scan,
                        label: "Loading more exercises",
                        dot: 3,
                        gap: 3
                    )
                    .padding(.bottom, 28)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: browse.favoritesOnly ? "heart" : "magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.primary)

            Text(emptyTitle)
                .font(Theme.sans(17, weight: .bold))
                .foregroundStyle(Theme.foreground)

            Text(emptyMessage)
                .font(Theme.sans(14))
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            if hasActiveFilters {
                AppButton("Clear filters", variant: .secondary) {
                    clearFilters()
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var emptyTitle: String {
        browse.favoritesOnly && favorites.favoriteIds.isEmpty ? "No favorites yet" : "No exercises found"
    }

    private var emptyMessage: String {
        if browse.favoritesOnly && favorites.favoriteIds.isEmpty {
            return "Favorite an exercise from its detail page and it will appear here."
        }
        return "Try another name, muscle, or equipment combination."
    }

    private func clearFilters() {
        Haptics.trigger(.selection)
        browse.search = ""
        browse.selectedMuscles = []
        browse.selectedEquipment = []
        browse.favoritesOnly = false
    }

    private func resetPagination() {
        browse.visibleExerciseCount = ExerciseCatalogue.pageSize
    }

    private func loadMoreExercises() {
        guard browse.visibleExerciseCount < filteredExercises.count else { return }
        browse.visibleExerciseCount = min(
            browse.visibleExerciseCount + ExerciseCatalogue.pageSize,
            filteredExercises.count
        )
    }

}

private struct LibraryFilterChip: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        AppButton(
            variant: selected ? .primary : .secondary,
            size: .standard,
            accessibilityLabel: title,
            action: action
        ) {
            Text(title)
                .font(Theme.sans(13, weight: .semibold))
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct LibraryRoundButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        AppButton(
            variant: .ghost,
            size: .iconCTA,
            accessibilityLabel: label,
            action: action
        ) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
        }
    }
}

enum LibraryFilterKind: String, Identifiable {
    case muscles
    case equipment

    var id: String { rawValue }
    var title: String { self == .muscles ? "Filter by muscle" : "Filter by equipment" }
}

private struct LibraryFilterOverlay: View {
    @Environment(\.appSafeAreaInsets) private var safeAreaInsets
    let filter: LibraryFilterKind
    @Binding var selectedMuscles: [MuscleId]
    @Binding var selectedEquipment: [String]
    var onClose: () -> Void

    @State private var bodySide: BodySide = .front

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
                .ignoresSafeArea()

            Group {
                switch filter {
                case .muscles:
                    ZStack {
                        DotPattern(
                            color: Theme.mix(
                                Theme.mutedForeground,
                                Theme.primary,
                                Double(selectedMuscles.count) / 8
                            ),
                            opacity: 0.42
                        )
                        BodyMap(
                            selectedMuscles: selectedMuscles,
                            onToggle: toggleMuscle,
                            onSideChange: { bodySide = $0 },
                            showCornerCount: false,
                            showFlipButton: true,
                            side: bodySide
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, safeAreaInsets.top + 72)
                    .padding(.bottom, 76)

                case .equipment:
                    ScrollView {
                        EquipmentGrid(
                            options: ExerciseCatalogue.equipmentOptions,
                            selected: selectedEquipment,
                            onToggle: toggleEquipment
                        )
                        .padding(.horizontal, Theme.Metrics.contentInset)
                        .padding(.top, safeAreaInsets.top + 82)
                        .padding(.bottom, 92)
                    }
                }
            }

            filterHeader
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                AppButton("Clear", variant: .ghost, isDisabled: selectionIsEmpty, expands: true) {
                    Haptics.trigger(.selection)
                    clearSelection()
                }
                AppButton("Done", variant: .primary, expands: true) {
                    Haptics.trigger(.selection)
                    onClose()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var filterHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(filter.title)
                    .font(Theme.sans(18, weight: .black))
                    .foregroundStyle(Theme.foreground)
                Text(selectionSubtitle)
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
            }

            Spacer(minLength: 8)

            AppHeaderButton(systemImage: "xmark", label: "Close filter") {
                onClose()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, safeAreaInsets.top)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var selectionIsEmpty: Bool {
        filter == .muscles ? selectedMuscles.isEmpty : selectedEquipment.isEmpty
    }

    private var selectionSubtitle: String {
        let count = filter == .muscles ? selectedMuscles.count : selectedEquipment.count
        return count == 0 ? "All" : "\(count) selected"
    }

    private func toggleMuscle(_ muscle: MuscleId) {
        Haptics.trigger(.selection)
        if let index = selectedMuscles.firstIndex(of: muscle) {
            selectedMuscles.remove(at: index)
        } else {
            selectedMuscles.append(muscle)
        }
    }

    private func toggleEquipment(_ equipment: String) {
        if let index = selectedEquipment.firstIndex(of: equipment) {
            selectedEquipment.remove(at: index)
        } else {
            selectedEquipment.append(equipment)
        }
    }

    private func clearSelection() {
        switch filter {
        case .muscles: selectedMuscles = []
        case .equipment: selectedEquipment = []
        }
    }
}
