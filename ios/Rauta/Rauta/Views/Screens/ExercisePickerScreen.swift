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
    @StateObject private var scrollTracker = ScrollHideTracker()
    @Namespace private var destinationMenuNamespace

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

    private var destinationWorkouts: [Workout] {
        Array(
            store.workouts.workouts
                .filter { $0.completion == nil }
                .sorted {
                    if $0.id == preferredWorkoutId { return true }
                    if $1.id == preferredWorkoutId { return false }
                    return $0.date > $1.date
                }
                .prefix(3)
        )
    }

    var body: some View {
        RautaScreen(
            title: title,
            subtitle: subtitle,
            backLabel: "Previous page",
            onBack: store.navigation.pop,
            progressStage: stage.rawValue,
            hidden: (stage == .equipment || stage == .exercises) && scrollTracker.hidden,
            right: { headerRautaMenu },
            content: { content },
            controls: { controls }
        )
        .onChange(of: stage) { _, _ in
            scrollTracker.reset()
        }
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
                ScrollView {
                    ScrollOffsetObserver { offset, isScrollable in
                        scrollTracker.update(offset: offset, isScrollable: isScrollable)
                    }
                    .frame(height: 0)

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

    private var emptyExercisesMessage: String {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return "Nothing matches \"\(query)\". Try a shorter word — the search reads exercise names only."
        }
        if favoritesOnly {
            return "No favorites yet. Add favorites from an exercise's detail page."
        }
        return "Nothing uses every muscle and every piece of equipment you picked. Go back and drop one of them."
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
            arrowEdge: .top,
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
                    store.navigation.persist()
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
                GlassGroup(spacing: 12) {
                    ZStack(alignment: .bottom) {
                        if destinationMenuOpen {
                            destinationMenu
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                                .glassMorph("destination-control", in: destinationMenuNamespace)
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
                                    store.navigation.persist()
                                }
                            }
                            .glassMorph("destination-control", in: destinationMenuNamespace)
                        }
                    }
                    .animation(Theme.Motion.smoothOut(0.28), value: destinationMenuOpen)
                }
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
                ForEach(destinationWorkouts) { workout in
                    Button {
                        addSelectedExercises(to: workout)
                    } label: {
                        Label(
                            "\(CalendarDate.short(workout.date)) · \(Wording.countLabel(workout.exerciseIds.count, "exercise"))",
                            systemImage: "calendar"
                        )
                    }
                }
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
            store.navigation.reset([.workouts, .workoutDetail(workoutId: workout.id)])
            Haptics.trigger(.success)
        } catch {
            Haptics.trigger(.warning)
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
