import SwiftUI

/// Browse the complete exercise catalogue without borrowing the workout-builder
/// filters. Library state is deliberately local so a casual lookup cannot change
/// the next RAUTA exercise-selection flow.
struct LibraryScreen: View {
    @ObservedObject private var store = AppStore.shared

    @State private var search = ""
    @State private var selectedMuscles: [MuscleId] = []
    @State private var selectedEquipment: [String] = []
    @State private var favoritesOnly = false
    @State private var presentedFilter: LibraryFilterKind?
    @State private var visibleExerciseCount = ExerciseCatalogue.pageSize

    private var filteredExercises: [ExerciseSummary] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let muscleSet = Set(selectedMuscles)
        let equipmentSet = Set(selectedEquipment)

        let matches = ExerciseCatalogue.all.filter { exercise in
            (query.isEmpty || exercise.name.localizedCaseInsensitiveContains(query))
                && (muscleSet.isEmpty || exercise.muscles.contains(where: muscleSet.contains))
                && (equipmentSet.isEmpty || equipmentSet.contains(exercise.equipment))
                && (!favoritesOnly || store.favorites.isFavorite(exercise.id))
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

    private var visibleExercises: ArraySlice<ExerciseSummary> {
        filteredExercises.prefix(visibleExerciseCount)
    }

    private var hasActiveFilters: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedMuscles.isEmpty
            || !selectedEquipment.isEmpty
            || favoritesOnly
    }

    var body: some View {
        ZStack(alignment: .top) {
            results

            filterBar
                .zIndex(20)

            if let presentedFilter {
                LibraryFilterOverlay(
                    filter: presentedFilter,
                    selectedMuscles: $selectedMuscles,
                    selectedEquipment: $selectedEquipment,
                    onClose: {
                        withAnimation(Theme.Motion.smoothOut(0.2)) {
                            self.presentedFilter = nil
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(50)
            }
        }
        .onChange(of: search) { _, _ in resetPagination() }
        .onChange(of: selectedMuscles) { _, _ in resetPagination() }
        .onChange(of: selectedEquipment) { _, _ in resetPagination() }
        .onChange(of: favoritesOnly) { _, _ in resetPagination() }
        .onChange(of: store.favorites.favoriteIds) { _, _ in resetPagination() }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)

                TextField("Search exercises", text: $search)
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.foreground)
                    .tint(Theme.primary)
                    .submitLabel(.search)
                    .accessibilityLabel("Search exercises by name")

                if !search.isEmpty {
                    Button {
                        Haptics.trigger(.selection)
                        search = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Glassware.edge, lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 14, y: 8)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    LibraryFilterChip(
                        title: selectedMuscles.isEmpty ? "Muscles" : "Muscles · \(selectedMuscles.count)",
                        selected: !selectedMuscles.isEmpty
                    ) {
                        Haptics.trigger(.selection)
                        presentedFilter = .muscles
                    }

                    LibraryFilterChip(
                        title: selectedEquipment.isEmpty ? "Equipment" : "Equipment · \(selectedEquipment.count)",
                        selected: !selectedEquipment.isEmpty
                    ) {
                        Haptics.trigger(.selection)
                        presentedFilter = .equipment
                    }

                    LibraryFilterChip(title: "Favorites", selected: favoritesOnly) {
                        Haptics.trigger(.selection)
                        favoritesOnly.toggle()
                    }

                    if hasActiveFilters {
                        LibraryFilterChip(title: "Clear") {
                            clearFilters()
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            Text(Wording.countLabel(filteredExercises.count, "exercise"))
                .font(Theme.sans(12, weight: .medium))
                .foregroundStyle(Theme.mutedForeground)
                .padding(.leading, 2)
        }
        .padding(.horizontal, Theme.Metrics.contentInset)
        .padding(.top, DeviceScreen.safeAreaInsets.top + 8)
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
                                store.navigation.push(.exerciseDetail(exerciseId: $0.id))
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
                .padding(.top, DeviceScreen.safeAreaInsets.top + 154)
                .padding(.bottom, 28)

                if visibleExerciseCount < filteredExercises.count {
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
            Image(systemName: favoritesOnly ? "heart" : "magnifyingglass")
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
        .padding(.top, DeviceScreen.safeAreaInsets.top + 120)
        .padding(32)
    }

    private var emptyTitle: String {
        favoritesOnly && store.favorites.favoriteIds.isEmpty ? "No favorites yet" : "No exercises found"
    }

    private var emptyMessage: String {
        if favoritesOnly && store.favorites.favoriteIds.isEmpty {
            return "Favorite an exercise from its detail page and it will appear here."
        }
        return "Try another name, muscle, or equipment combination."
    }

    private func clearFilters() {
        Haptics.trigger(.selection)
        search = ""
        selectedMuscles = []
        selectedEquipment = []
        favoritesOnly = false
    }

    private func resetPagination() {
        visibleExerciseCount = ExerciseCatalogue.pageSize
    }

    private func loadMoreExercises() {
        guard visibleExerciseCount < filteredExercises.count else { return }
        visibleExerciseCount = min(
            visibleExerciseCount + ExerciseCatalogue.pageSize,
            filteredExercises.count
        )
    }
}

private struct LibraryFilterChip: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(selected ? Theme.primaryForeground : Theme.secondaryForeground)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    if selected {
                        Capsule()
                            .fill(Theme.primaryGradient)
                            .opacity(0.76)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Theme.Glassware.brightEdge : Theme.Glassware.edge,
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private enum LibraryFilterKind: String, Identifiable {
    case muscles
    case equipment

    var id: String { rawValue }
    var title: String { self == .muscles ? "Filter by muscle" : "Filter by equipment" }
}

private struct LibraryFilterOverlay: View {
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
                    .padding(.top, DeviceScreen.safeAreaInsets.top + 72)
                    .padding(.bottom, 76)

                case .equipment:
                    ScrollView {
                        EquipmentGrid(
                            options: ExerciseCatalogue.equipmentOptions,
                            selected: selectedEquipment,
                            onToggle: toggleEquipment
                        )
                        .padding(.horizontal, Theme.Metrics.contentInset)
                        .padding(.top, DeviceScreen.safeAreaInsets.top + 82)
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
        .padding(.top, DeviceScreen.safeAreaInsets.top)
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
