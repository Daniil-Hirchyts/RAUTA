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
            .appZoomTransition(from: filter.zoomSourceID)
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
                    filterBar
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

        if !browse.selectedMuscles.isEmpty {
            parts.append(Wording.countLabel(browse.selectedMuscles.count, "muscle"))
        }

        if !browse.selectedEquipment.isEmpty {
            parts.append("\(browse.selectedEquipment.count) equipment")
        }

        return parts.joined(separator: " · ")
    }

    /// The filters and the search are one strip of glass that changes shape.
    /// Opening the search, the round search button stretches into the field
    /// and the Muscles chip draws in to the round filters button, while the
    /// chips between them melt away; closing runs the same morph backwards.
    ///
    /// The two ends are the same views in both states, so their glass is
    /// reshaped in place rather than swapped for new glass.
    private var filterBar: some View {
        let open = browse.searchOpen
        return GlassMorphContainer(spacing: 6) {
            HStack(spacing: 8) {
                leadingFilterButton(open: open)

                if !open {
                    LibraryFilterChip(
                        title: "Equipment",
                        selected: !browse.selectedEquipment.isEmpty
                    ) {
                        Haptics.trigger(.selection)
                        browse.presentedFilter = .equipment
                    }
                    .appZoomSource(LibraryFilterKind.equipment.zoomSourceID, cornerRadius: 20)
                    .transition(Self.chipMelt)

                    LibraryFilterChip(title: "Favorites", selected: browse.favoritesOnly) {
                        Haptics.trigger(.selection)
                        browse.favoritesOnly.toggle()
                    }
                    .transition(Self.chipMelt)

                    Spacer(minLength: 0)
                }

                searchField(open: open)

                if open {
                    Button(action: closeSearch) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 42, height: 42)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassSurface(.clear, in: Circle(), interactive: true, legacyFill: Theme.card.opacity(0.24))
                    .frame(minWidth: 48, minHeight: 48)
                    .accessibilityLabel("Cancel search")
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(height: 48)
        }
    }

    /// Muscles while browsing; the round way back to the filters while
    /// searching.
    private func leadingFilterButton(open: Bool) -> some View {
        let musclesSelected = !browse.selectedMuscles.isEmpty
        return Button {
            if open {
                closeSearch()
            } else {
                Haptics.trigger(.selection)
                browse.presentedFilter = .muscles
            }
        } label: {
            ZStack {
                if open {
                    Image(systemName: "circle.grid.2x2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.secondaryForeground)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    Text("Muscles")
                        .font(Theme.sans(13, weight: .semibold))
                        .foregroundStyle(musclesSelected ? Theme.primaryForeground : Theme.secondaryForeground)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                }
            }
            .frame(width: open ? 42 : nil, height: open ? 42 : 40)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(OptionalZoomSource(id: open ? nil : LibraryFilterKind.muscles.zoomSourceID, cornerRadius: 20))
        .glassSurface(
            open ? .regular : (musclesSelected ? .tinted(Theme.primary) : .clear),
            in: Capsule(),
            interactive: true,
            legacyFill: !open && musclesSelected ? Theme.primary.opacity(0.76) : Theme.card.opacity(0.24)
        )
        .frame(minWidth: 48, minHeight: 44)
        .accessibilityLabel(open ? "Return to filters" : "Muscles")
        .accessibilityAddTraits(!open && musclesSelected ? .isSelected : [])
    }

    /// A round button until it is opened, then the field itself. The glyph is
    /// the same one throughout: it travels from the middle of the circle to the
    /// front of the field.
    private func searchField(open: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(open ? Theme.secondaryForeground : Theme.primary)

            if open {
                TextField("Search exercises", text: $browse.search)
                    .focused($searchFocused)
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.foreground)
                    .tint(Theme.primary)
                    .submitLabel(.search)
                    .accessibilityLabel("Search exercises by name")
                    .transition(.opacity)

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
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, open ? 14 : 0)
        .frame(width: open ? nil : 42, height: open ? 46 : 42)
        .frame(maxWidth: open ? .infinity : nil, alignment: .leading)
        .contentShape(Capsule())
        .onTapGesture {
            if open { searchFocused = true } else { openSearch() }
        }
        .glassSurface(
            open ? .regular : .clear,
            in: Capsule(),
            interactive: true,
            // Present in both states, so the ring grows with the glass
            // instead of appearing at the field's final size.
            border: open ? (searchFocused ? Theme.ring : Theme.Glassware.edge) : .clear,
            legacyFill: Theme.card.opacity(0.24)
        )
        .frame(minWidth: 48, minHeight: 48)
        .accessibilityElement(children: open ? .contain : .ignore)
        .accessibilityLabel(open ? "" : "Search exercises")
        .accessibilityAddTraits(open ? [] : .isButton)
        .accessibilityAction { if !open { openSearch() } }
    }

    /// Chips that make way for the field shrink into the glass beside them.
    private static let chipMelt = AnyTransition.scale(scale: 0.6).combined(with: .opacity)

    /// Glass moves best on a spring with a touch of give.
    private static let searchMorphAnimation = Animation.spring(response: 0.42, dampingFraction: 0.82)

    private func openSearch() {
        Haptics.trigger(.selection)
        withAnimation(Self.searchMorphAnimation) {
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
        withAnimation(Self.searchMorphAnimation) {
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
                            zoomSourceID: "library-exercise:\(exercise.id)",
                            onOpenDetail: {
                                navigation.push(
                                    .exerciseDetail(exerciseId: $0.id),
                                    from: "library-exercise:\($0.id)"
                                )
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
        EmptyStatePlaceholder(
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
        // Glass applied as an effect rather than a button style, so the filter
        // bar can morph it — a style's glass cannot be named.
        Button(action: action) {
            Text(title)
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(selected ? Theme.primaryForeground : Theme.secondaryForeground)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassSurface(
            selected ? .tinted(Theme.primary) : .clear,
            in: Capsule(),
            interactive: true,
            legacyFill: selected ? Theme.primary.opacity(0.76) : Theme.card.opacity(0.24)
        )
        .frame(minHeight: 44)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum LibraryFilterKind: String, Identifiable {
    case muscles
    case equipment

    var id: String { rawValue }
    var title: String { self == .muscles ? "Muscles" : "Equipment" }
    /// The chip its page grows out of.
    var zoomSourceID: String { "library-filter:\(rawValue)" }
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
