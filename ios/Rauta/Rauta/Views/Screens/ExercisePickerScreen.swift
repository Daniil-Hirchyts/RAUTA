import SwiftUI

struct ExercisePickerScreen: View {
    enum Stage: Int { case muscles = 1, equipment, exercises }

    @ObservedObject private var store = AppStore.shared
    let stage: Stage
    let preferredWorkoutId: String?

    @State private var side: BodySide = .front
    @State private var search = ""
    @State private var searchOpen = false
    @State private var favoritesOnly = false
    @State private var presetEditorOpen = false
    @State private var visibleExerciseCount = ExerciseCatalogue.pageSize
    @State private var showBackToTop = false
    @StateObject private var scrollTracker = ScrollHideTracker()

    private let exercisesTopAnchor = "exercises-top"

    private var selectedMuscles: [MuscleId] { store.filters.selectedMuscles }
    private var selectedEquipment: [String] { store.filters.selectedEquipment }
    private var matchingExercises: [ExerciseSummary] {
        let filtered = ExerciseCatalogue.filter(
            muscles: selectedMuscles,
            equipment: selectedEquipment
        )
        return filtered.filter { exercise in
            (!favoritesOnly || store.favorites.isFavorite(exercise.id))
                && (search.trimmingCharacters(in: .whitespaces).isEmpty
                    || exercise.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        RautaScreen(
            title: title,
            subtitle: subtitle,
            backLabel: "Previous page",
            onBack: store.navigation.pop,
            progressStage: stage.rawValue,
            hidden: (stage == .equipment || stage == .exercises) && scrollTracker.hidden,
            content: { content },
            controls: { controls }
        )
        .onChange(of: stage) { _, _ in
            scrollTracker.reset()
        }
        .onChange(of: matchingExercises.count) { _, _ in
            visibleExerciseCount = ExerciseCatalogue.pageSize
            showBackToTop = false
        }
    }

    private var title: String {
        switch stage {
        case .muscles: return "Muscles"
        case .equipment: return "Equipment"
        case .exercises: return "Exercises"
        }
    }

    private var subtitle: String? {
        switch stage {
        case .muscles:
            return selectedMuscles.isEmpty ? nil : "\(selectedMuscles.count) selected"
        case .equipment:
            return selectedEquipment.isEmpty ? nil : "\(matchingExercises.count) exercises"
        case .exercises:
            return store.navigation.selectMode ? "\(store.navigation.selectedIds.count) selected" : nil
        }
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .muscles:
            ZStack {
                DotPattern(
                    color: Theme.mix(Theme.mutedForeground, Theme.primary, Double(selectedMuscles.count) / 8),
                    opacity: 0.42
                )
                BodyMap(
                    selectedMuscles: selectedMuscles,
                    onToggle: store.filters.toggleMuscle,
                    onSideChange: { side = $0 },
                    showCornerCount: false,
                    showFlipButton: false,
                    side: side
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, Theme.Metrics.headerHeight + DeviceScreen.safeAreaInsets.top)
            .padding(.bottom, 12)

        case .equipment:
            ZStack(alignment: .bottom) {
                ScrollView {
                    ScrollOffsetObserver { offset, isScrollable in
                        scrollTracker.update(offset: offset, isScrollable: isScrollable)
                    }
                    .frame(height: 0)

                    EquipmentGrid(
                        options: ExerciseCatalogue.equipmentForMuscles(selectedMuscles),
                        selected: selectedEquipment,
                        onToggle: store.filters.toggleEquipment
                    )
                    .padding(Theme.Metrics.contentInset)
                    .padding(.bottom, 96)
                }

                equipmentPresetsDock
            }

        case .exercises:
            exerciseResults
        }
    }

    @ViewBuilder private var exerciseResults: some View {
        if matchingExercises.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                Text(emptyExercisesMessage)
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 256)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            GeometryReader { viewport in
                ScrollViewReader { scrollProxy in
                    ZStack(alignment: .bottom) {
                        ScrollView {
                            ScrollOffsetObserver { offset, isScrollable in
                                scrollTracker.update(offset: offset, isScrollable: isScrollable)
                                let shouldShow = offset > Swift.max(480, viewport.size.height)
                                if shouldShow != showBackToTop {
                                    withAnimation(Theme.Motion.smoothOut(0.52)) {
                                        showBackToTop = shouldShow
                                    }
                                }
                            }
                                .frame(height: 0)
                                .id(exercisesTopAnchor)

                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
                                spacing: 14
                            ) {
                                ForEach(
                                    Array(matchingExercises.prefix(visibleExerciseCount).enumerated()),
                                    id: \.element.id
                                ) { index, exercise in
                                    ExerciseCard(
                                        exercise: exercise,
                                        index: index,
                                        selectMode: store.navigation.selectMode,
                                        selected: store.navigation.selectedIds.contains(exercise.id),
                                        onOpenDetail: {
                                            store.navigation.push(.exerciseDetail(exerciseId: $0.id))
                                        },
                                        onToggleSelect: toggleSelected
                                    )
                                }
                            }
                            .padding(.horizontal, Theme.Metrics.contentInset)
                            .padding(.top, Theme.Metrics.contentInset)

                            if visibleExerciseCount < matchingExercises.count {
                                MatrixLoader(
                                    variant: .scan,
                                    label: "Loading more exercises",
                                    dot: 3,
                                    gap: 3
                                )
                                .padding(.vertical, 24)

                                loadMoreTrigger(viewportHeight: viewport.size.height)
                            }

                            Color.clear
                                .frame(height: searchOpen || store.navigation.selectMode ? 112 : 24)
                        }
                        .coordinateSpace(name: "exercisesScroll")

                        Button {
                            Haptics.trigger(.light)
                            withAnimation(Theme.Motion.smoothOut(0.52)) {
                                scrollProxy.scrollTo(exercisesTopAnchor, anchor: .top)
                            }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                                .frame(width: 48, height: 48)
                                .glassSurface(
                                    .regular,
                                    in: Circle(),
                                    interactive: true,
                                    border: Theme.mix(Theme.border, Theme.primary, 0.55),
                                    legacyFill: Theme.card.opacity(0.78)
                                )
                                .shadow(color: .black.opacity(0.4), radius: 14, y: 12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to top")
                        .opacity(showBackToTop ? 1 : 0)
                        .offset(y: showBackToTop ? 0 : 8)
                        .scaleEffect(showBackToTop ? 1 : 0.9)
                        .padding(.bottom, Swift.max(0, Theme.Metrics.surfaceRadius - 24))
                        .allowsHitTesting(showBackToTop)
                    }
                }
            }
        }
    }

    private func loadMoreTrigger(viewportHeight: CGFloat) -> some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named("exercisesScroll")).minY
            Color.clear
                .onAppear {
                    loadMoreExercisesIfNeeded(triggerY: minY, viewportHeight: viewportHeight)
                }
                .onChange(of: minY) { _, newY in
                    loadMoreExercisesIfNeeded(triggerY: newY, viewportHeight: viewportHeight)
                }
        }
        .frame(height: 1)
    }

    private func loadMoreExercisesIfNeeded(triggerY: CGFloat, viewportHeight: CGFloat) {
        guard triggerY <= viewportHeight + 600,
              visibleExerciseCount < matchingExercises.count else { return }
        visibleExerciseCount = Swift.min(
            visibleExerciseCount + ExerciseCatalogue.pageSize,
            matchingExercises.count
        )
    }

    private var equipmentPresetsDock: some View {
        VStack(spacing: 0) {
            EquipmentPresets(value: nil, onChange: nil)
                .padding(.bottom, 10)
        }
        .padding(.top, 28)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Theme.background.opacity(0.75), location: 0.35),
                    .init(color: Theme.background.opacity(0.96), location: 0.65),
                    .init(color: Theme.background, location: 0.85),
                    .init(color: Theme.background, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
    }

    private var emptyExercisesMessage: String {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return "Nothing matches \"\(query)\". Try a shorter word — the search reads exercise names only."
        }
        if favoritesOnly {
            return "No favorites yet. Tap the heart on an exercise to keep it here."
        }
        return "Nothing uses every muscle and every piece of equipment you picked. Go back and drop one of them."
    }

    @ViewBuilder private var controls: some View {
        switch stage {
        case .muscles:
            HStack(spacing: 8) {
                AppMenuButton(label: "Muscle actions") {
                    Button {
                        Haptics.trigger(.selection)
                        side = side == .front ? .back : .front
                    } label: {
                        Label(
                            "Show \(side == .front ? "back" : "front")",
                            systemImage: "arrow.left.arrow.right"
                        )
                    }

                    if !selectedMuscles.isEmpty {
                        Button {
                            Haptics.trigger(.selection)
                            store.filters.setMuscles([])
                        } label: {
                            Label("Clear muscle selection", systemImage: "xmark")
                        }
                    }
                }

                AppButton(
                    "Choose equipment",
                    size: .cta,
                    isDisabled: selectedMuscles.isEmpty,
                    expands: true
                ) {
                    store.navigation.push(.equipment(preferredWorkoutId: preferredWorkoutId))
                }
            }

        case .equipment:
            if presetEditorOpen {
                HStack(spacing: 10) {
                    EquipmentPresetEditor { presetEditorOpen = false }
                    AppControlButton(systemImage: "xmark", label: "Close preset editor") {
                        presetEditorOpen = false
                    }
                }
            } else {
                HStack(spacing: 8) {
                    AppMenuButton(label: "Equipment actions") {
                        if !selectedEquipment.isEmpty {
                            Button {
                                Haptics.trigger(.selection)
                                store.filters.setEquipment([])
                            } label: {
                                Label("Clear equipment selection", systemImage: "xmark")
                            }
                        }

                        Button {
                            presetEditorOpen = true
                        } label: {
                            Label("Save equipment preset", systemImage: "plus")
                        }
                        .disabled(selectedEquipment.isEmpty)
                    }

                    AppButton(
                        "Show exercises",
                        size: .cta,
                        isDisabled: selectedEquipment.isEmpty || matchingExercises.isEmpty,
                        expands: true
                    ) {
                        store.navigation.selectMode = preferredWorkoutId != nil
                        store.navigation.persist()
                        store.navigation.push(.exercises(preferredWorkoutId: preferredWorkoutId))
                    }
                }
            }

        case .exercises:
            if searchOpen {
                ExerciseSearchField(value: $search) {
                    Haptics.trigger(.medium)
                    search = ""
                    searchOpen = false
                }
            } else {
                HStack(spacing: 8) {
                    AppMenuButton(label: "Exercise actions") {
                        if store.navigation.selectMode {
                            Button {
                                cancelSelectMode()
                            } label: {
                                Label("Cancel selection", systemImage: "xmark")
                            }
                        } else if preferredWorkoutId == nil {
                            Button {
                                buildWorkoutWithRauta()
                            } label: {
                                Label("Build workout with RAUTA", systemImage: "sparkles")
                            }
                        }

                        Button {
                            Haptics.trigger(.medium)
                            searchOpen = true
                        } label: {
                            Label("Search exercises", systemImage: "magnifyingglass")
                        }

                        Button {
                            Haptics.trigger(.selection)
                            favoritesOnly.toggle()
                        } label: {
                            Label(
                                favoritesOnly ? "Show all exercises" : "Show favorites only",
                                systemImage: favoritesOnly ? "heart.slash" : "heart"
                            )
                        }
                    }

                    AppButton(
                        store.navigation.selectMode ? "Add to workout" : "Select",
                        size: .cta,
                        isDisabled: store.navigation.selectMode && store.navigation.selectedIds.isEmpty,
                        expands: true
                    ) {
                        if store.navigation.selectMode {
                            store.navigation.push(
                                .workoutDestination(preferredWorkoutId: preferredWorkoutId)
                            )
                        } else {
                            store.navigation.selectMode = true
                            store.navigation.persist()
                        }
                    }
                }
            }
        }
    }

    private func cancelSelectMode() {
        store.navigation.selectMode = false
        store.navigation.selectedIds = []
        store.navigation.persist()
        Haptics.trigger(.selection)
    }

    private func buildWorkoutWithRauta() {
        do {
            let exerciseIds = try EngineWorkout.propose(
                date: CalendarDate.today,
                focusMuscles: selectedMuscles,
                availableEquipment: selectedEquipment
            )
            guard !exerciseIds.isEmpty else {
                Haptics.trigger(.warning)
                return
            }
            Haptics.trigger(.medium)
            store.navigation.push(
                .workoutForm(
                    exerciseIds: exerciseIds,
                    workoutId: nil,
                    engineFocusMuscles: selectedMuscles
                )
            )
        } catch {
            Haptics.trigger(.warning)
        }
    }

    private func toggleSelected(_ id: String) {
        store.navigation.selectedIds = Sanitize.toggle(store.navigation.selectedIds, id)
        store.navigation.persist()
    }
}
