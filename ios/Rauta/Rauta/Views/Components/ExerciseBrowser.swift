import SwiftUI

/// Browsing the catalogue, as one layout.
///
/// The Library and the add-to-workout flow ask the same question — which
/// exercises, out of all of them — so they ask it with the same parts: one strip
/// of glass that holds the filters and morphs into a search field, the same
/// two-column grid of cards, the same paging, and the same full-screen pages
/// behind the Muscles and Equipment chips.
///
/// What differs between the two is passed in: where the muscle and equipment
/// selections live, whether cards are being picked rather than opened, and what
/// RAUTA offers on each filter page.

// MARK: - State

/// Everything a browse holds that is not the selection itself. Muscles and
/// equipment are bound from outside: the Library keeps its own, the add flow
/// shares the store's, because the engine reads them.
struct ExerciseBrowseState {
    var search = ""
    var favoritesOnly = false
    var presentedFilter: ExerciseFilterKind?
    var visibleExerciseCount = ExerciseCatalogue.pageSize
    var searchOpen = false

    var normalizedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One browse, reduced to what actually changes its results — so the matching
/// runs once per change rather than once per render.
struct ExerciseBrowseQuery: Equatable {
    var search: String
    var muscles: [MuscleId]
    var equipment: [String]
    var favorites: [String]?

    init(state: ExerciseBrowseState, muscles: [MuscleId], equipment: [String], favoriteIds: [String]) {
        self.search = state.normalizedSearch
        self.muscles = muscles
        self.equipment = equipment
        self.favorites = state.favoritesOnly ? favoriteIds : nil
    }

    /// The catalogue, filtered and — when muscles are picked — ordered by how
    /// well each exercise answers them.
    func results() -> [ExerciseSummary] {
        let muscleSet = Set(muscles)
        let equipmentSet = Set(equipment)
        let favoriteSet = favorites.map(Set.init)

        // Already in name order, so a plain filter keeps it.
        let matches = ExerciseCatalogue.allByName.filter { exercise in
            (search.isEmpty || exercise.name.localizedCaseInsensitiveContains(search))
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
}

enum ExerciseFilterKind: String, Identifiable {
    case muscles
    case equipment

    var id: String { rawValue }
    var title: String { self == .muscles ? "Muscles" : "Equipment" }
    /// The chip its page grows out of. Two browses can be open at once — the
    /// Library under a picker — so the chip that opened a page is named by the
    /// browse it belongs to.
    func zoomSourceID(_ prefix: String) -> String { "\(prefix)-filter:\(rawValue)" }
}

// MARK: - Filter bar

/// The filters and the search are one strip of glass that changes shape.
/// Opening the search, the round search button stretches into the field and the
/// Muscles chip draws in to the round filters button, while the chips between
/// them melt away; closing runs the same morph backwards.
///
/// The two ends are the same views in both states, so their glass is reshaped in
/// place rather than swapped for new glass.
struct ExerciseFilterBar: View {
    @Binding var state: ExerciseBrowseState
    @Binding var selectedMuscles: [MuscleId]
    @Binding var selectedEquipment: [String]
    /// Names the chips a filter page grows out of.
    var zoomPrefix: String

    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Chips that make way for the field shrink into the glass beside them.
    private var chipMelt: AnyTransition {
        .motion(.scale(scale: 0.6).combined(with: .opacity), reduced: reduceMotion)
    }
    /// Glass moves best on a spring with a touch of give.
    private static let searchMorphAnimation = Animation.spring(response: 0.42, dampingFraction: 0.82)

    var body: some View {
        let open = state.searchOpen
        return GlassMorphContainer(spacing: 6) {
            HStack(spacing: 8) {
                leadingFilterButton(open: open)

                if !open {
                    ExerciseFilterChip(
                        title: "Equipment",
                        selected: !selectedEquipment.isEmpty
                    ) {
                        Haptics.trigger(.selection)
                        state.presentedFilter = .equipment
                    }
                    .appZoomSource(ExerciseFilterKind.equipment.zoomSourceID(zoomPrefix), cornerRadius: 20)
                    .transition(chipMelt)

                    ExerciseFilterChip(title: "Favorites", selected: state.favoritesOnly) {
                        Haptics.trigger(.selection)
                        state.favoritesOnly.toggle()
                    }
                    .transition(chipMelt)

                    Spacer(minLength: 0)
                }

                // Closing is the round filters button at the front: the field
                // runs to the edge with nothing after it.
                searchField(open: open)
            }
            .frame(height: 48)
        }
        // One row of fixed-height glass controls: labels grow with Dynamic
        // Type while all three still fit beside the search button.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// Muscles while browsing; the round way back to the filters while
    /// searching.
    private func leadingFilterButton(open: Bool) -> some View {
        let musclesSelected = !selectedMuscles.isEmpty
        return Button {
            if open {
                closeSearch()
            } else {
                Haptics.trigger(.selection)
                state.presentedFilter = .muscles
            }
        } label: {
            ZStack {
                if open {
                    Image(systemName: "circle.grid.2x2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.secondaryForeground)
                        .transition(.motion(.scale(scale: 0.5).combined(with: .opacity), reduced: reduceMotion))
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
        .modifier(
            OptionalZoomSource(
                id: open ? nil : ExerciseFilterKind.muscles.zoomSourceID(zoomPrefix),
                cornerRadius: 20
            )
        )
        .glassSurface(
            open ? .regular : (musclesSelected ? .tinted(Theme.primary) : .clear),
            in: Capsule(),
            interactive: true
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
                TextField("Search exercises", text: $state.search)
                    .focused($searchFocused)
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.foreground)
                    .tint(Theme.primary)
                    .submitLabel(.search)
                    .accessibilityLabel("Search exercises by name")
                    .transition(.opacity)

                if !state.search.isEmpty {
                    Button {
                        Haptics.trigger(.selection)
                        state.search = ""
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
            border: open ? (searchFocused ? Theme.ring : Theme.Glassware.edge) : .clear
        )
        .frame(minWidth: 48, minHeight: 48)
        .accessibilityElement(children: open ? .contain : .ignore)
        .accessibilityLabel(open ? "" : "Search exercises")
        .accessibilityAddTraits(open ? [] : .isButton)
        .accessibilityAction { if !open { openSearch() } }
    }

    private func openSearch() {
        Haptics.trigger(.selection)
        withAnimation(Self.searchMorphAnimation) {
            state.searchOpen = true
        }
        Task { @MainActor in
            await Task.yield()
            searchFocused = true
        }
    }

    private func closeSearch() {
        Haptics.trigger(.selection)
        searchFocused = false
        state.search = ""
        withAnimation(Self.searchMorphAnimation) {
            state.searchOpen = false
        }
    }
}

struct ExerciseFilterChip: View {
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
            interactive: true
        )
        .frame(minHeight: 44)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Results

/// The two-column grid a browse shows, one page of cards at a time.
struct ExerciseResultsGrid: View {
    var exercises: [ExerciseSummary]
    @Binding var visibleCount: Int
    /// Names the card a detail page grows out of.
    var zoomPrefix: String
    var selectMode = false
    var selectedIds: [String] = []
    var bottomInset: CGFloat = 28
    var onOpenDetail: (ExerciseSummary) -> Void
    var onToggleSelect: (String) -> Void = { _ in }

    private var visible: ArraySlice<ExerciseSummary> { exercises.prefix(visibleCount) }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible()),
                ],
                spacing: 14
            ) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, exercise in
                    ExerciseCard(
                        exercise: exercise,
                        index: index,
                        selectMode: selectMode,
                        selected: selectedIds.contains(exercise.id),
                        zoomSourceID: "\(zoomPrefix)-exercise:\(exercise.id)",
                        onOpenDetail: onOpenDetail,
                        onToggleSelect: onToggleSelect
                    )
                    .onAppear {
                        guard exercise.id == visible.last?.id else { return }
                        loadMore()
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.contentInset)
            .padding(.bottom, bottomInset)

            if visibleCount < exercises.count {
                MatrixLoader(
                    variant: .scan,
                    label: "Loading more exercises",
                    dot: 3,
                    gap: 3
                )
                .padding(.bottom, bottomInset)
            }
        }
        .pageScroll()
    }

    private func loadMore() {
        guard visibleCount < exercises.count else { return }
        visibleCount = min(visibleCount + ExerciseCatalogue.pageSize, exercises.count)
    }
}

/// What a browse says when nothing matches, in the words of whichever filter
/// emptied it.
struct ExerciseBrowseEmptyState: View {
    var state: ExerciseBrowseState
    var hasFavorites: Bool
    var onClearSearch: () -> Void
    var onShowAll: () -> Void

    private var query: String { state.normalizedSearch }
    private var favoritesEmpty: Bool { state.favoritesOnly && !hasFavorites }

    var body: some View {
        // RAUTA is already on this page, in the tab bar: the empty list shows
        // what is missing rather than a second RAUTA.
        EmptyStatePlaceholder(
            symbol: symbol,
            title: title,
            message: message,
            actionTitle: actionTitle,
            action: action
        )
    }

    private var symbol: String {
        if !query.isEmpty { return "magnifyingglass" }
        if state.favoritesOnly { return "heart" }
        return "line.3.horizontal.decrease"
    }

    private var title: String {
        if !query.isEmpty { return "No matches for “\(query)”" }
        if favoritesEmpty { return "No favorites yet" }
        if state.favoritesOnly { return "No favorites here" }
        return "No exercises match"
    }

    private var message: String {
        if !query.isEmpty {
            return "Try another exercise name, or clear the search to browse everything again."
        }
        if state.favoritesOnly {
            return "Open any exercise and tap the heart to keep it in your favorites."
        }
        return "Remove one of the selected muscles or equipment filters to widen the results."
    }

    private var actionTitle: String? {
        if !query.isEmpty { return "Clear search" }
        if state.favoritesOnly { return "Show all exercises" }
        return nil
    }

    private func action() {
        Haptics.trigger(.selection)
        if !query.isEmpty { onClearSearch() } else { onShowAll() }
    }
}

// MARK: - Filter pages

extension View {
    /// Presents the page behind whichever filter chip was tapped.
    ///
    /// `equipmentOptions` is a closure because narrowing the equipment list to
    /// the picked muscles walks the whole catalogue, and the browse underneath
    /// redraws on every keystroke: the work belongs to opening the page, not to
    /// drawing the one that opens it.
    func exerciseFilterPage(
        state: Binding<ExerciseBrowseState>,
        selectedMuscles: Binding<[MuscleId]>,
        selectedEquipment: Binding<[String]>,
        zoomPrefix: String,
        backLabel: String,
        equipmentOptions: @escaping () -> [String] = { ExerciseCatalogue.equipmentOptions }
    ) -> some View {
        fullScreenCover(item: state.presentedFilter) { filter in
            ExerciseFilterPage(
                filter: filter,
                selectedMuscles: selectedMuscles,
                selectedEquipment: selectedEquipment,
                backLabel: backLabel,
                equipmentOptions: equipmentOptions,
                onClose: { state.wrappedValue.presentedFilter = nil }
            )
            .presentationBackground(Theme.shell)
            .appZoomTransition(from: filter.zoomSourceID(zoomPrefix))
        }
    }
}

/// One filter, full screen: the body map or the equipment grid.
///
/// RAUTA stands in the title bar here exactly as it does on the page that opened
/// it, and its thought bubble carries what this filter can do — flipping the
/// body, clearing the selection, saving a preset — so the page's one command
/// stays "Done".
struct ExerciseFilterPage: View {
    let filter: ExerciseFilterKind
    @Binding var selectedMuscles: [MuscleId]
    @Binding var selectedEquipment: [String]
    var backLabel: String
    var equipmentOptions: () -> [String] = { ExerciseCatalogue.equipmentOptions }
    var onClose: () -> Void

    @State private var bodySide: BodySide = .front
    @State private var presetEditorOpen = false
    /// Worked out once, when the page opens.
    @State private var equipment: [String] = []

    var body: some View {
        RautaScreen(
            title: filter.title,
            subtitle: selectionSubtitle,
            backLabel: backLabel,
            onBack: onClose,
            right: {
                AppMenuButton(label: "\(filter.title) actions", compact: true) { menu }
            },
            content: { pageContent },
            controls: { controls }
        )
        .onAppear { equipment = equipmentOptions() }
    }

    @ViewBuilder
    private var menu: some View {
        if filter == .muscles {
            Button {
                Haptics.trigger(.selection)
                bodySide = bodySide == .front ? .back : .front
            } label: {
                Label(
                    "Show \(bodySide == .front ? "back" : "front")",
                    systemImage: "arrow.left.arrow.right"
                )
            }
        }

        if !selectionIsEmpty {
            Button {
                Haptics.trigger(.selection)
                clearSelection()
            } label: {
                Label("Clear \(filter.title.lowercased())", systemImage: "xmark")
            }
        }

        if filter == .equipment {
            Button {
                presetEditorOpen = true
            } label: {
                Label("Save equipment preset", systemImage: "plus")
            }
            .disabled(selectedEquipment.isEmpty)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if presetEditorOpen {
            HStack(spacing: 10) {
                EquipmentPresetEditor(equipment: selectedEquipment) { presetEditorOpen = false }
                AppControlButton(systemImage: "xmark", label: "Close preset editor") {
                    presetEditorOpen = false
                }
            }
        } else {
            AppButton("Done", size: .cta, expands: true) {
                Haptics.trigger(.selection)
                onClose()
            }
        }
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
            ZStack(alignment: .bottom) {
                ScrollView {
                    EquipmentGrid(
                        options: equipment,
                        selected: selectedEquipment,
                        onToggle: toggleEquipment
                    )
                    .padding(.horizontal, Theme.Metrics.contentInset)
                    .padding(.bottom, Theme.Metrics.contentInset + 96)
                }
                .pageScroll()

                EquipmentPresets(
                    value: selectedEquipment,
                    onChange: { selectedEquipment = $0 }
                )
                .padding(.bottom, 10)
                .padding(.top, 28)
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
        case .muscles: selectedMuscles = []
        case .equipment: selectedEquipment = []
        }
    }
}
