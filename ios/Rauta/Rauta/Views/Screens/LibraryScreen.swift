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
    @Namespace private var libraryChromeNamespace

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

    private var visibleExercises: ArraySlice<ExerciseSummary> {
        filteredExercises.prefix(browse.visibleExerciseCount)
    }

    var body: some View {
        ZStack(alignment: .top) {
            results

            libraryTopScrim
                .zIndex(20)

            libraryChrome
                .zIndex(30)
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

    private var libraryTopScrim: some View {
        AppGradientBlur(edge: .top, radiusScale: 1.05)
            .frame(height: chromeClearance)
            .frame(maxWidth: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea(edges: .top)
    }

    private var libraryChrome: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !browse.searchOpen {
                Text("Library")
                    .font(Theme.sans(20, weight: .heavy))
                    .kerning(-0.5)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .transition(.opacity)
            }

            GlassGroup(spacing: 8) {
                if browse.searchOpen {
                    expandedSearchBar
                } else {
                    compactFilterBar
                }
            }

            resultCountLabel
        }
        .padding(.horizontal, Theme.Metrics.contentInset)
        .padding(.top, safeAreaInsets.top + 12)
        .padding(.bottom, 12)
        .animation(Theme.Motion.smoothOut(0.28), value: browse.searchOpen)
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

    private var chromeClearance: CGFloat {
        safeAreaInsets.top + (browse.searchOpen ? 104 : 158)
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
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
                    .glassSurface(
                        .clear,
                        in: Circle(),
                        interactive: true,
                        border: Theme.Glassware.edge,
                        legacyFill: Theme.card.opacity(0.24)
                    )
                    .glassMorph("library-search", in: libraryChromeNamespace)
            }
            .buttonStyle(.plain)
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
            .glassMorph("library-search", in: libraryChromeNamespace)

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
                .padding(.top, chromeClearance + 8)
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
        .padding(.top, chromeClearance)
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
                .frame(height: 40)
                .contentShape(Capsule())
                .glassSurface(
                    selected ? .tinted(Theme.primary) : .clear,
                    in: Capsule(),
                    interactive: true,
                    border: selected ? Theme.Glassware.brightEdge : Theme.Glassware.edge,
                    legacyFill: selected ? Theme.primary.opacity(0.76) : Theme.card.opacity(0.24)
                )
                .overlay {
                    if selected {
                        Capsule()
                            .fill(Theme.primaryGradient)
                            .opacity(Theme.Glassware.primaryWash)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
                .frame(width: 42, height: 42)
                .contentShape(Circle())
                .glassSurface(
                    roundButtonTone,
                    in: Circle(),
                    interactive: true,
                    border: Theme.Glassware.edge,
                    legacyFill: Theme.card.opacity(0.24)
                )
        }
        .buttonStyle(.plain)
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
    @Environment(\.appSafeAreaInsets) private var safeAreaInsets
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
            .padding(.top, Theme.Metrics.headerHeight + safeAreaInsets.top)
            .padding(.bottom, 8)

        case .equipment:
            ScrollView {
                EquipmentGrid(
                    options: ExerciseCatalogue.equipmentOptions,
                    selected: selectedEquipment,
                    onToggle: toggleEquipment
                )
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
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
