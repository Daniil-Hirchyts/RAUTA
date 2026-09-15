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
    @State private var destinationMenuOpen = false
    @State private var visibleExerciseCount = ExerciseCatalogue.pageSize
    @State private var matches = Memo<MatchQuery, [ExerciseSummary]>()

    private struct MatchQuery: Equatable {
        var muscles: [MuscleId]
        var equipment: [String]
        var search: String
        var favorites: [String]?
    }

    private var selectedMuscles: [MuscleId] { store.filters.selectedMuscles }
    private var selectedEquipment: [String] { store.filters.selectedEquipment }

    /// Scored and sorted once per change of the selection: the screen reads it
    /// several times per render, and redraws whenever any store changes.
    private var matchingExercises: [ExerciseSummary] {
        let query = MatchQuery(
            muscles: selectedMuscles,
            equipment: selectedEquipment,
            search: search,
            favorites: favoritesOnly ? store.favorites.favoriteIds : nil
        )
        return matches(query) {
            let favoriteSet = query.favorites.map(Set.init)
            let trimmed = query.search.trimmingCharacters(in: .whitespaces)
            return ExerciseCatalogue.filter(muscles: query.muscles, equipment: query.equipment)
                .filter { exercise in
                    (favoriteSet?.contains(exercise.id) ?? true)
                        && (trimmed.isEmpty || exercise.name.localizedCaseInsensitiveContains(query.search))
                }
        }
    }

    /// Every workout still open to more exercises, soonest first, with the one
    /// being worked on at the top: the workout this flow started from, or else
    /// the one in progress.
    private var destinationWorkouts: [Workout] {
        let currentId = preferredWorkoutId ?? store.activeWorkout.session?.workoutId
        let open = store.workouts.workouts
            .filter { $0.completion == nil }
            .soonestFirst()
        guard let current = open.first(where: { $0.id == currentId }) else { return open }
        return [current] + open.filter { $0.id != current.id }
    }

    /// Rows past this many scroll inside the menu rather than pushing it off
    /// the top of the screen.
    private let destinationRowsVisible = 6
    private let destinationRowHeight: CGFloat = 46

    var body: some View {
        RautaScreen(
            title: title,
            subtitle: subtitle,
            backLabel: "Previous page",
            onBack: store.navigation.pop,
            progressStage: stage.rawValue,
            right: { headerRautaMenu },
            content: { content },
            controls: { controls }
        )
        .onChange(of: matchingExercises.count) { _, _ in
            visibleExerciseCount = ExerciseCatalogue.pageSize
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
            .belowPageHeader()
            .padding(.bottom, 12)

        case .equipment:
            ZStack(alignment: .bottom) {
                ScrollView {
                    EquipmentGrid(
                        options: ExerciseCatalogue.equipmentForMuscles(selectedMuscles),
                        selected: selectedEquipment,
                        onToggle: store.filters.toggleEquipment
                    )
                    .padding(.horizontal, Theme.Metrics.contentInset)
                    .padding(.bottom, Theme.Metrics.contentInset + 96)
                }
                .pageScroll()

                equipmentPresetsDock
            }

        case .exercises:
            exerciseResults
        }
    }

    @ViewBuilder private var exerciseResults: some View {
        if matchingExercises.isEmpty {
            EmptyStatePlaceholder(
                systemImage: emptyExercisesSymbol,
                title: emptyExercisesTitle,
                message: emptyExercisesMessage,
                actionTitle: emptyExercisesActionTitle,
                action: emptyExercisesAction
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            GeometryReader { viewport in
                ScrollView {
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
                                zoomSourceID: "picker-exercise:\(exercise.id)",
                                onOpenDetail: {
                                    store.navigation.push(
                                        .exerciseDetail(exerciseId: $0.id),
                                        from: "picker-exercise:\($0.id)"
                                    )
                                },
                                onToggleSelect: toggleSelected
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Metrics.contentInset)

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
                .pageScroll()
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
    }

    private var emptyExercisesQuery: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emptyExercisesSymbol: String {
        emptyExercisesQuery.isEmpty && favoritesOnly ? "heart" : "magnifyingglass"
    }

    private var emptyExercisesTitle: String {
        if !emptyExercisesQuery.isEmpty { return "No matches for “\(emptyExercisesQuery)”" }
        if favoritesOnly { return "No favorites here" }
        return "No exercises match"
    }

    private var emptyExercisesMessage: String {
        if !emptyExercisesQuery.isEmpty {
            return "Try a shorter word — the search reads exercise names only."
        }
        if favoritesOnly {
            return "Open any exercise and tap the heart to keep it in your favorites."
        }
        return "Nothing uses every muscle and every piece of equipment you picked. Go back and drop one of them."
    }

    private var emptyExercisesActionTitle: String? {
        if !emptyExercisesQuery.isEmpty { return "Clear search" }
        if favoritesOnly { return "Show all exercises" }
        return nil
    }

    private func emptyExercisesAction() {
        Haptics.trigger(.selection)
        if !emptyExercisesQuery.isEmpty {
            search = ""
        } else {
            favoritesOnly = false
        }
    }

    @ViewBuilder private var rautaOptions: some View {
        switch stage {
        case .muscles:
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

        case .equipment:
            if presetEditorOpen {
                Button {
                    presetEditorOpen = false
                } label: {
                    Label("Close preset editor", systemImage: "xmark")
                }
            } else {
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

        case .exercises:
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
                if searchOpen {
                    search = ""
                    searchOpen = false
                } else {
                    searchOpen = true
                }
            } label: {
                Label(
                    searchOpen ? "Close search" : "Search exercises",
                    systemImage: searchOpen ? "xmark" : "magnifyingglass"
                )
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
    }

    private var headerRautaMenu: some View {
        AppMenuButton(
            label: "\(title) actions",
            compact: true
        ) {
            rautaOptions
        }
    }

    @ViewBuilder private var controls: some View {
        switch stage {
        case .muscles:
            AppButton(
                "Choose equipment",
                size: .cta,
                isDisabled: selectedMuscles.isEmpty,
                expands: true
            ) {
                store.navigation.push(.equipment(preferredWorkoutId: preferredWorkoutId))
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
                AppButton(
                    "Show exercises",
                    size: .cta,
                    isDisabled: selectedEquipment.isEmpty || matchingExercises.isEmpty,
                    expands: true
                ) {
                    store.navigation.selectMode = preferredWorkoutId != nil
                    store.navigation.push(.exercises(preferredWorkoutId: preferredWorkoutId))
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
                ZStack(alignment: .bottom) {
                    if destinationMenuOpen {
                        destinationMenu
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)
                    } else {
                        AppButton(
                            store.navigation.selectMode ? "Add to workout" : "Select",
                            size: .cta,
                            isDisabled: store.navigation.selectMode && store.navigation.selectedIds.isEmpty,
                            expands: true
                        ) {
                            if store.navigation.selectMode {
                                Haptics.trigger(.selection)
                                withAnimation(Theme.Motion.smoothOut(0.28)) {
                                    destinationMenuOpen = true
                                }
                            } else {
                                store.navigation.selectMode = true
                            }
                        }
                    }
                }
                .animation(Theme.Motion.smoothOut(0.28), value: destinationMenuOpen)
            }
        }
    }

    private var destinationMenu: some View {
        AppMenuSurface(dismiss: { destinationMenuOpen = false }) {
            Button(action: createNewWorkout) {
                Label("New workout", systemImage: "plus")
            }

            Divider()
                .overlay(Theme.border)
                .padding(.vertical, 4)

            Text("PLANNED WORKOUTS")
                .font(Theme.sans(10, weight: .black))
                .kerning(1.5)
                .foregroundStyle(Theme.mutedForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            if destinationWorkouts.isEmpty {
                Text("No planned workouts")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(destinationWorkouts) { workout in
                            Button {
                                addSelectedExercises(to: workout)
                            } label: {
                                Label(CalendarDate.short(workout.date), systemImage: "calendar")
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(
                    height: CGFloat(min(destinationWorkouts.count, destinationRowsVisible))
                        * destinationRowHeight
                )
            }
        }
    }

    private func createNewWorkout() {
        destinationMenuOpen = false
        store.navigation.push(
            .workoutForm(
                exerciseIds: store.navigation.selectedIds,
                workoutId: nil,
                engineFocusMuscles: nil
            )
        )
    }

    private func addSelectedExercises(to workout: Workout) {
        destinationMenuOpen = false
        var seen = Set<String>()
        let ids = (workout.exerciseIds + store.navigation.selectedIds)
            .filter { seen.insert($0).inserted }

        do {
            if store.activeWorkout.session?.workoutId == workout.id {
                store.workouts.updateWorkout(workout.id, .init(exerciseIds: ids))
                store.activeWorkout.syncExercises(ids)
            } else {
                try TrainingEdits.updateScheduledWorkoutExercises(workout.id, ids)
            }
            store.navigation.selectMode = false
            store.navigation.selectedIds = []
            store.navigation.openWorkout(workout.id)
            Haptics.trigger(.success)
        } catch {
            Haptics.trigger(.warning)
        }
    }

    private func cancelSelectMode() {
        store.navigation.selectMode = false
        store.navigation.selectedIds = []
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
    }
}
