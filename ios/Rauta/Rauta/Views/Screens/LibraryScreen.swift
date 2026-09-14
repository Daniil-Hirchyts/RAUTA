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
    @ObservedObject private var favorites = FavoritesStore.shared
    private let navigation = AppSessionStore.shared
    @State private var browse = LibraryBrowseState()
    @State private var resultsMemo = Memo<LibraryQuery, [ExerciseSummary]>()
    @FocusState private var searchFocused: Bool

    private struct LibraryQuery: Equatable {
        var search: String
        var muscles: [MuscleId]
        var equipment: [String]
        var favorites: [String]?
    }

    /// The page reads this in several places per render and once per card as
    /// the grid scrolls, so it is worked out once per change of the query.
    private var filteredExercises: [ExerciseSummary] {
        let query = LibraryQuery(
            search: browse.search.trimmingCharacters(in: .whitespacesAndNewlines),
            muscles: browse.selectedMuscles,
            equipment: browse.selectedEquipment,
            favorites: browse.favoritesOnly ? favorites.favoriteIds : nil
        )
        return resultsMemo(query) { Self.exercises(matching: query) }
    }

    private static func exercises(matching query: LibraryQuery) -> [ExerciseSummary] {
        let muscleSet = Set(query.muscles)
        let equipmentSet = Set(query.equipment)
        let favoriteSet = query.favorites.map(Set.init)

        // Already in name order, so a plain filter keeps it.
        let matches = ExerciseCatalogue.allByName.filter { exercise in
            (query.search.isEmpty || exercise.name.localizedCaseInsensitiveContains(query.search))
                && (muscleSet.isEmpty || exercise.muscles.contains(where: muscleSet.contains))
                && (equipmentSet.isEmpty || equipmentSet.contains(exercise.equipment))
                && (favoriteSet?.contains(exercise.id) ?? true)
        }
        guard !muscleSet.isEmpty else { return matches }

        // Each exercise scored once, ties kept in name order.
        return matches.enumerated()
            .map { (exercise: $0.element, score: ExerciseCatalogue.relevance($0.element, muscleSet), order: $0.offset) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            .map(\.exercise)
    }

    private var visibleExercises: ArraySlice<ExerciseSummary> {
        filteredExercises.prefix(browse.visibleExerciseCount)
    }

    var body: some View {
        AppTitledPage {
            libraryHeader
        } content: {
            results
        }
        .fullScreenCover(item: $browse.presentedFilter) { filter in
            LibraryFilterPage(
                filter: filter,
                selectedMuscles: $browse.selectedMuscles,
                selectedEquipment: $browse.selectedEquipment,
                onClose: { browse.presentedFilter = nil }
            )
            .presentationBackground(Theme.shell)
        }
        .onChange(of: browse.search) { _, _ in resetPagination() }
        .onChange(of: browse.selectedMuscles) { _, _ in resetPagination() }
        .onChange(of: browse.selectedEquipment) { _, _ in resetPagination() }
        .onChange(of: browse.favoritesOnly) { _, _ in resetPagination() }
        .onChange(of: favorites.favoriteIds) { _, _ in resetPagination() }
    }

    private var libraryHeader: some View {
        AppShellHeader(
            title: "Library",
            left: { Color.clear.frame(width: 44, height: 44) },
            right: { Color.clear.frame(width: 44, height: 44) },
            above: { EmptyView() },
            below: {
                VStack(alignment: .leading, spacing: 10) {
                    if browse.searchOpen {
                        expandedSearchBar
                    } else {
                        compactFilterBar
                    }

                    resultCountLabel
                }
                .animation(Theme.Motion.smoothOut(0.28), value: browse.searchOpen)
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

        if !browse.selectedMuscles.isEmpty {
            parts.append(Wording.countLabel(browse.selectedMuscles.count, "muscle"))
        }

        if !browse.selectedEquipment.isEmpty {
            parts.append("\(browse.selectedEquipment.count) equipment")
        }

        return parts.joined(separator: " · ")
    }

    private var compactFilterBar: some View {
        HStack(spacing: 8) {
            LibraryFilterChip(
                title: "Muscles",
                selected: !browse.selectedMuscles.isEmpty
            ) {
                Haptics.trigger(.selection)
                browse.presentedFilter = .muscles
            }

            LibraryFilterChip(
                title: "Equipment",
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

            Button {
                openSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.primary)
            }
            .buttonStyle(
                .glassControl(.clear, .circle(diameter: 42), legacyFill: Theme.card.opacity(0.24))
            )
            .frame(minWidth: 48, minHeight: 48)
            .accessibilityLabel("Search exercises")
        }
    }

    private var expandedSearchBar: some View {
        HStack(spacing: 8) {
            LibraryRoundButton(
                systemImage: "circle.grid.2x2.fill",
                label: "Return to filters",
                variant: .secondary
            ) {
                closeSearch()
            }

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
                interactive: true,
                border: searchFocused ? Theme.ring : Theme.Glassware.edge,
                legacyFill: Theme.card.opacity(0.24)
            )

            LibraryRoundButton(systemImage: "xmark", label: "Cancel search") {
                closeSearch()
            }
        }
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
                .padding(.bottom, 28)
                .animation(Theme.Motion.smoothOut(0.28), value: browse.searchOpen)

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
            .pageScroll()
        }
    }

    private var emptyState: some View {
        LibraryEmptyState(
            systemImage: emptySystemImage,
            title: emptyTitle,
            message: emptyMessage,
            actionTitle: emptyActionTitle,
            action: emptyAction
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .belowPageHeader()
        .padding(32)
        .offset(y: -30)
        .animation(Theme.Motion.smoothOut(0.28), value: browse.searchOpen)
    }

    private var normalizedSearch: String {
        browse.search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emptySystemImage: String {
        normalizedSearch.isEmpty && browse.favoritesOnly && favorites.favoriteIds.isEmpty
            ? "heart"
            : "magnifyingglass"
    }

    private var emptyTitle: String {
        if !normalizedSearch.isEmpty {
            return "No matches for “\(normalizedSearch)”"
        }
        if browse.favoritesOnly && favorites.favoriteIds.isEmpty {
            return "No favorites yet"
        }
        return "No exercises match"
    }

    private var emptyMessage: String {
        if !normalizedSearch.isEmpty {
            return "Try another exercise name, or clear the search to browse everything again."
        }
        if browse.favoritesOnly && favorites.favoriteIds.isEmpty {
            return "Open any exercise and tap the heart to keep it in your favorites."
        }
        return "Remove one of the selected muscles or equipment filters to widen the results."
    }

    private var emptyActionTitle: String? {
        normalizedSearch.isEmpty ? nil : "Clear search"
    }

    private func emptyAction() {
        Haptics.trigger(.selection)
        browse.search = ""
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
        Button(action: action) {
            Text(title)
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(selected ? Theme.primaryForeground : Theme.secondaryForeground)
                .padding(.horizontal, 16)
        }
        .buttonStyle(
            .glassControl(
                selected ? .tinted(Theme.primary) : .clear,
                .capsule(height: 40),
                legacyFill: selected ? Theme.primary.opacity(0.76) : Theme.card.opacity(0.24)
            )
        )
        .frame(minHeight: 44)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct LibraryRoundButton: View {
    let systemImage: String
    let label: String
    var variant: ButtonVariant = .ghost
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(roundButtonForeground)
        }
        .buttonStyle(
            .glassControl(roundButtonTone, .circle(diameter: 42), legacyFill: Theme.card.opacity(0.24))
        )
        .frame(minWidth: 48, minHeight: 48)
        .accessibilityLabel(label)
    }

    private var roundButtonTone: GlassTone {
        switch variant {
        case .secondary: return .regular
        case .primary: return .tinted(Theme.primary)
        case .ghost, .destructive: return .clear
        }
    }

    private var roundButtonForeground: Color {
        switch variant {
        case .secondary: return Theme.secondaryForeground
        case .primary: return Theme.primaryForeground
        case .ghost, .destructive: return Theme.primary
        }
    }
}

enum LibraryFilterKind: String, Identifiable {
    case muscles
    case equipment

    var id: String { rawValue }
    var title: String { self == .muscles ? "Muscles" : "Equipment" }
}

private struct LibraryEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.primary)
                .frame(height: 42)
                .padding(.bottom, 4)

            Text(title)
                .font(Theme.sans(18, weight: .bold))
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)

            Text(message)
                .font(Theme.sans(14))
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 286)

            if let actionTitle {
                AppButton(actionTitle, variant: .secondary, action: action)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: 320)
    }
}

private struct LibraryFilterPage: View {
    let filter: LibraryFilterKind
    @Binding var selectedMuscles: [MuscleId]
    @Binding var selectedEquipment: [String]
    var onClose: () -> Void

    @State private var bodySide: BodySide = .front

    var body: some View {
        RautaScreen(
            title: filter.title,
            subtitle: selectionSubtitle,
            backLabel: "Library",
            onBack: onClose,
            content: { pageContent },
            controls: {
                HStack(spacing: 10) {
                    if !selectionIsEmpty {
                        AppControlButton(systemImage: "xmark", label: "Clear selection") {
                            Haptics.trigger(.selection)
                            clearSelection()
                        }
                    }

                    if filter == .muscles {
                        AppControlButton(
                            systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                            label: "Show \(bodySide == .front ? "back" : "front")"
                        ) {
                            Haptics.trigger(.selection)
                            bodySide = bodySide == .front ? .back : .front
                        }
                    }

                    AppButton("Done", size: .cta, expands: true) {
                        Haptics.trigger(.selection)
                        onClose()
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var pageContent: some View {
        switch filter {
        case .muscles:
            ZStack {
                DotPattern(
                    color: Theme.mix(
                        Theme.mutedForeground,
                        Theme.primary,
                        min(Double(selectedMuscles.count) / 8, 1)
                    ),
                    opacity: 0.42
                )
                BodyMap(
                    selectedMuscles: selectedMuscles,
                    onToggle: toggleMuscle,
                    onSideChange: { bodySide = $0 },
                    showCornerCount: false,
                    showFlipButton: false,
                    side: bodySide
                )
            }
            .padding(.horizontal, Theme.Metrics.contentInset)
            .belowPageHeader()
            .padding(.bottom, 8)

        case .equipment:
            ScrollView {
                EquipmentGrid(
                    options: ExerciseCatalogue.equipmentOptions,
                    selected: selectedEquipment,
                    onToggle: toggleEquipment
                )
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, 24)
            }
            .pageScroll()
        }
    }

    private var selectionIsEmpty: Bool {
        filter == .muscles ? selectedMuscles.isEmpty : selectedEquipment.isEmpty
    }

    private var selectionSubtitle: String? {
        let count = filter == .muscles ? selectedMuscles.count : selectedEquipment.count
        guard count > 0 else {
            return filter == .muscles ? "All muscles" : "All equipment"
        }
        return "\(count) selected"
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
        case .muscles:
            selectedMuscles = []
        case .equipment:
            selectedEquipment = []
        }
    }
}
