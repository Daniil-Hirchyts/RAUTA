import SwiftUI
import UIKit

enum MainTab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case workout = "Workout"
    case library = "Library"
    case profile = "Profile"
    case rauta = "Rauta"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .summary: return "chart.bar"
        case .workout: return "figure.strengthtraining.traditional"
        case .library: return "books.vertical"
        case .profile: return "person.crop.circle"
        case .rauta: return "circle.fill"
        }
    }
}

enum NativeTabIcons {
    static let summary = make(MainTab.summary.systemImage)
    static let workout = make(MainTab.workout.systemImage)
    static let library = make(MainTab.library.systemImage)
    static let profile = make(MainTab.profile.systemImage)
    static let transparentPlaceholder = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { _ in }

    static func image(for tab: MainTab) -> UIImage {
        switch tab {
        case .summary: return summary
        case .workout: return workout
        case .library: return library
        case .profile: return profile
        case .rauta: return UIImage()
        }
    }

    private static func make(_ systemName: String) -> UIImage {
        let canvasSize = CGSize(width: 28, height: 28)
        let visibleSize = CGSize(width: 20, height: 20)
        let configuration = UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: configuration) else {
            return UIImage()
        }

        let scale = min(visibleSize.width / symbol.size.width, visibleSize.height / symbol.size.height)
        let drawingSize = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let drawingRect = CGRect(
            x: (canvasSize.width - drawingSize.width) / 2,
            y: (canvasSize.height - drawingSize.height) / 2,
            width: drawingSize.width,
            height: drawingSize.height
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: canvasSize, format: format).image { _ in
            symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: drawingRect)
        }
        return rendered.withRenderingMode(.alwaysTemplate)
    }
}

struct WorkoutsScreen: View {
    @ObservedObject private var store = AppStore.shared
    @State private var mainTab: MainTab = .summary
    @State private var nativeTabSelection: MainTab = .summary
    @State private var rautaMenuPresented = false
    @State private var rautaCompact = false
    @State private var exercisePlayerOpen = false
    @State private var liveWorkoutPresented = false
    @State private var workoutDetailActionState = WorkoutDetailActionState.none
    @State private var workoutDetailActionRequest: WorkoutDetailExternalAction?
    @State private var workoutListSelection = 0
    @State private var selectedWorkoutId: String?

    private var visibleWorkouts: [Workout] {
        store.workouts.workouts.filter { workout in
            guard let p = workout.planned, workout.completion == nil,
                  store.activeWorkout.session?.workoutId != workout.id else { return true }
            return !ProgramRecords.isSupersededPlannedSession(store.trainingRecords.data, p.programId, p.sessionId)
        }
    }
    private var upcoming: [Workout] {
        visibleWorkouts.filter {
            store.activeWorkout.session?.workoutId == $0.id ||
            ($0.completion == nil && !($0.planned.map { TrainingPlan.isPlannedSessionRecorded($0.sessionId) } ?? false))
        }.sorted { $0.date < $1.date }
    }
    private var past: [Workout] {
        visibleWorkouts.filter { w in !upcoming.contains { $0.id == w.id } }.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if #available(iOS 27.0, *) {
                activeWorkoutPlayerShell(nativeProminentTabView)
            } else if #available(iOS 26.0, *) {
                activeWorkoutPlayerShell(nativeAccessoryTabView)
            } else if #available(iOS 18.4, *) {
                nativeTabView
            } else {
                legacyTabView
            }
        }
        .fullScreenCover(isPresented: $exercisePlayerOpen) {
            if let session = store.activeWorkout.session {
                if let exercise = ActiveWorkout.currentExercise(session) {
                    ActiveExerciseDrawer(
                        exercise: exercise,
                        session: session,
                        restSeconds: restSeconds(for: exercise.id),
                        onDetail: {
                            closeExercisePlayer()
                            store.navigation.push(.exerciseDetail(exerciseId: exercise.id))
                        },
                        hasNextExercise: session.exerciseIds.contains { id in
                            id != session.currentExerciseId && !session.completedIds.contains(id)
                        },
                        onFinishExercise: {
                            Haptics.trigger(.success)
                            store.activeWorkout.completeCurrent()
                        },
                        onFinish: finishActiveWorkout,
                        onDismiss: closeExercisePlayer
                    )
                    .interactiveDismissDisabled(false)
                    .presentationBackground(.clear)
                } else if ActiveWorkout.progress(session).isComplete {
                    CompletedWorkoutDrawer(
                        session: session,
                        onFinish: finishActiveWorkout,
                        onDismiss: closeExercisePlayer
                    )
                    .interactiveDismissDisabled(false)
                    .presentationBackground(.clear)
                } else {
                    Color.clear
                        .onAppear { exercisePlayerOpen = false }
                }
            } else {
                Color.clear
                    .onAppear { exercisePlayerOpen = false }
            }
        }
        .onChange(of: store.activeWorkout.session?.workoutId) { _, workoutId in
            if workoutId == nil {
                exercisePlayerOpen = false
                liveWorkoutPresented = false
                rautaCompact = false
            }
        }
        .onChange(of: mainTab) { _, tab in
            if tab != .workout {
                liveWorkoutPresented = false
            }
        }
        .onChange(of: rautaMenuPresented) { _, presented in
            if !presented {
                syncNativeSelection(to: mainTab)
            }
        }
        .task {
            // Restore any missing lightweight projection from its authoritative plan.
            for view in TrainingPlan.activePlannedSessions() where !TrainingPlan.isPlannedSessionRecorded(view.sessionId) {
                TrainingPlan.ensurePlannedWorkout(view)
            }
        }
    }

    @available(iOS 26.0, *)
    private func activeWorkoutPlayerShell<Content: View>(_ content: Content) -> some View {
        content
            // The compact tab-bar layout only has a job while a live workout
            // can supply the exercise accessory. Returning to idle should also
            // return the native tab bar to its normal, expanded presentation.
            .tabBarMinimizeBehavior(store.activeWorkout.session == nil ? .never : .onScrollDown)
            // UIKit can retain the previous bottom-accessory chrome after the
            // accessory disappears. Rebuild the native tab host at the workout
            // lifecycle boundary so an ended workout cannot leave an empty pill.
            .id(store.activeWorkout.session?.workoutId ?? "idle-native-tabs")
    }

    @available(iOS 27.0, *)
    private var nativeProminentTabView: some View {
        TabView(selection: navigationSelection) {
            Tab(value: MainTab.summary) {
                page(for: .summary)
            } label: {
                tabLabel(.summary)
            }
            Tab(value: MainTab.workout) {
                workoutTabContent
            } label: {
                tabLabel(.workout)
            }
            Tab(value: MainTab.library) {
                page(for: .library)
            } label: {
                tabLabel(.library)
            }
            Tab(value: MainTab.profile) {
                page(for: .profile)
            } label: {
                tabLabel(.profile)
            }
            Tab(value: MainTab.rauta, role: .prominent) {
                rautaCurrentPage
            } label: {
                Image(uiImage: NativeTabIcons.transparentPlaceholder)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.primary)
        .modifier(
            ConditionalNativeBottomAccessory(isVisible: shouldShowNativeExerciseAccessory) {
                nativeExerciseAccessory
            }
        )
        .onChange(of: mainTab) { _, selection in
            syncNativeSelection(to: selection)
        }
        .overlay(alignment: .bottomTrailing) {
            ZStack(alignment: .bottomTrailing) {
                NativeRautaTabTapInterceptor(onTap: presentRautaMenu)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                nativeRautaControl
            }
        }
    }

    @available(iOS 26.0, *)
    private var nativeAccessoryTabView: some View {
        TabView(selection: navigationSelection) {
            Tab(value: MainTab.summary) {
                page(for: .summary)
            } label: {
                tabLabel(.summary)
            }
            Tab(value: MainTab.workout) {
                workoutTabContent
            } label: {
                tabLabel(.workout)
            }
            Tab(value: MainTab.library) {
                page(for: .library)
            } label: {
                tabLabel(.library)
            }
            Tab(value: MainTab.profile) {
                page(for: .profile)
            } label: {
                tabLabel(.profile)
            }
            Tab(value: MainTab.rauta, role: .search) {
                rautaCurrentPage
            } label: {
                Image(uiImage: NativeTabIcons.transparentPlaceholder)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.primary)
        .modifier(
            ConditionalNativeBottomAccessory(isVisible: shouldShowNativeExerciseAccessory) {
                nativeExerciseAccessory
            }
        )
        .onChange(of: mainTab) { _, selection in
            syncNativeSelection(to: selection)
        }
        .overlay(alignment: .bottomTrailing) {
            ZStack(alignment: .bottomTrailing) {
                NativeRautaTabTapInterceptor(onTap: presentRautaMenu)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                nativeRautaControl
            }
        }
    }

    @available(iOS 18.4, *)
    private var nativeTabView: some View {
        TabView(selection: navigationSelection) {
            Tab(value: MainTab.summary) {
                page(for: .summary)
            } label: {
                tabLabel(.summary)
            }
            Tab(value: MainTab.workout) {
                workoutTabContent
            } label: {
                tabLabel(.workout)
            }
            Tab(value: MainTab.library) {
                page(for: .library)
            } label: {
                tabLabel(.library)
            }
            Tab(value: MainTab.profile) {
                page(for: .profile)
            } label: {
                tabLabel(.profile)
            }
            Tab(value: MainTab.rauta, role: .search) {
                rautaCurrentPage
            } label: {
                Image(uiImage: NativeTabIcons.transparentPlaceholder)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.primary)
        .onChange(of: mainTab) { _, selection in
            syncNativeSelection(to: selection)
        }
        .overlay(alignment: .bottomTrailing) {
            ZStack(alignment: .bottomTrailing) {
                NativeRautaTabTapInterceptor(onTap: presentRautaMenu)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                nativeRautaControl
            }
        }
    }

    private var legacyTabView: some View {
        TabView(selection: $mainTab) {
            page(for: .summary)
                .tabItem { Label("Summary", systemImage: MainTab.summary.systemImage) }
                .tag(MainTab.summary)
            page(for: .workout)
                .tabItem { Label("Workout", systemImage: MainTab.workout.systemImage) }
                .tag(MainTab.workout)
            page(for: .library)
                .tabItem { Label("Library", systemImage: MainTab.library.systemImage) }
                .tag(MainTab.library)
            page(for: .profile)
                .tabItem { Label("Profile", systemImage: MainTab.profile.systemImage) }
                .tag(MainTab.profile)
        }
        .tint(Theme.primary)
    }

    private var navigationSelection: Binding<MainTab> {
        Binding(
            get: { nativeTabSelection },
            set: { selection in
                if selection == .rauta {
                    // Let UIKit enter its auxiliary slot long enough for the
                    // Rauta popover to attach. `rautaCurrentPage` mirrors the
                    // page the person was already viewing.
                    nativeTabSelection = .rauta
                    presentRautaMenu()
                    return
                }
                // iOS 27 can publish the first regular tab immediately after
                // selecting a prominent auxiliary tab. That is an internal
                // fallback, not a navigation request. Keep `mainTab` stable
                // and drive the native host back to the page underneath the
                // open Rauta menu.
                if rautaMenuPresented {
                    syncNativeSelection(to: mainTab)
                    return
                }
                // A modal exercise sheet can cause UIKit's backing tab bar to
                // briefly publish its default tab while presentation chrome is
                // being rebuilt. A modal cannot be used to change tabs anyway,
                // so keep the person's current tab stable until it closes.
                guard !exercisePlayerOpen else { return }
                nativeTabSelection = selection
                mainTab = selection
            }
        )
    }

    private func syncNativeSelection(to selection: MainTab) {
        guard nativeTabSelection != selection else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            nativeTabSelection = selection
        }
    }

    private func tabLabel(_ tab: MainTab) -> some View {
        Label {
            Text(tab.rawValue)
        } icon: {
            Image(uiImage: NativeTabIcons.image(for: tab))
                .renderingMode(.template)
        }
    }

    private var nativeRautaControl: some View {
        RautaNativeTabControl(
            mood: store.activeWorkout.session == nil ? .calm : .focused,
            activeTab: $mainTab,
            actionsForTab: companionActions(for:),
            compact: rautaCompact,
            isPresented: $rautaMenuPresented,
            onPresent: presentRautaMenu
        )
        .padding(.trailing, 8)
        .padding(.bottom, Swift.max(7, DeviceScreen.safeAreaInsets.bottom))
        .offset(x: -3, y: rautaCompact ? 34 : 46)
        .zIndex(1_000)
    }

    private func presentRautaMenu() {
        Haptics.trigger(.selection)
        rautaMenuPresented = true
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private var nativeExerciseAccessory: some View {
        if let session = store.activeWorkout.session {
            if let exercise = ActiveWorkout.currentExercise(session) {
                NativeExerciseBottomAccessory(
                    exercise: exercise,
                    isPresented: $exercisePlayerOpen,
                    onCompactChange: updateRautaCompactState
                )
            } else if ActiveWorkout.progress(session).isComplete {
                NativeWorkoutCompleteAccessory(
                    session: session,
                    isPresented: $exercisePlayerOpen,
                    onCompactChange: updateRautaCompactState
                )
            }
        }
    }

    private var shouldShowNativeExerciseAccessory: Bool {
        guard let session = store.activeWorkout.session else { return false }
        return ActiveWorkout.currentExercise(session) != nil
            || ActiveWorkout.progress(session).isComplete
    }

    @ViewBuilder
    private var workoutTabContent: some View {
        WorkoutTabHost(
            upcoming: upcoming,
            past: past,
            activeWorkoutId: store.activeWorkout.session?.workoutId,
            liveWorkoutPresented: $liveWorkoutPresented,
            detailActionState: $workoutDetailActionState,
            detailActionRequest: $workoutDetailActionRequest,
            listSelection: $workoutListSelection,
            selectedWorkoutId: $selectedWorkoutId,
            onOpenExercisePlayer: exercisePlayerOpener
        )
    }

    @ViewBuilder
    private var rautaCurrentPage: some View {
        if mainTab == .workout {
            workoutTabContent
        } else {
            page(for: mainTab)
        }
    }

    @ViewBuilder
    private func page(for pageTab: MainTab) -> some View {
        if pageTab == .workout,
           let session = store.activeWorkout.session {
            WorkoutDetailScreen(
                workoutId: session.workoutId,
                embeddedInMainTabs: true,
                onOpenExercisePlayer: exercisePlayerOpener
            )
        } else {
            AppShell(commandsVisible: false) {
                ZStack(alignment: .top) {
                    Group {
                        if pageTab == .summary {
                            summaryContent
                        } else if pageTab == .workout {
                            noActiveWorkout
                                .padding(.top, DeviceScreen.safeAreaInsets.top + 56)
                        } else {
                            Spacer(minLength: 0)
                        }
                    }

                    AppTopScrim()
                        .zIndex(20)

                    AppShellHeader(
                        title: pageTab.rawValue,
                        left: { Color.clear.frame(width: 44, height: 44) },
                        right: {
                            if pageTab == .summary {
                                AppHeaderButton(systemImage: "gearshape", label: "Settings") {
                                    store.navigation.push(.settings)
                                }
                            } else {
                                Color.clear.frame(width: 44, height: 44)
                            }
                        },
                        above: { EmptyView() },
                        below: { EmptyView() }
                    )
                    .zIndex(30)
                }
            } controls: {
                EmptyView()
            }
        }
    }

    private var noActiveWorkout: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.primary)
            Text("No workout in progress")
                .font(Theme.sans(17, weight: .bold))
                .foregroundStyle(Theme.foreground)
            Text("Start one from Summary to see the live workout here.")
                .font(Theme.sans(13))
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private var summaryContent: some View {
        SummaryWorkoutsContent(
            completedWorkouts: past.filter { $0.completion != nil },
            history: store.trainingRecords.trainingHistory()
        )
    }

    private func companionActions(for tab: MainTab) -> [CompanionAction] {
        switch tab {
        case .workout:
            return workoutCompanionActions
        case .library:
            return [
                CompanionAction(title: "Choose exercises", systemImage: "list.bullet.rectangle", primary: true, action: startExerciseFlow)
            ]
        case .profile:
            return [
                CompanionAction(title: "Settings", systemImage: "gearshape", primary: true) {
                    store.navigation.push(.settings)
                }
            ]
        case .summary, .rauta:
            return summaryCompanionActions
        }
    }

    private var summaryCompanionActions: [CompanionAction] {
        var actions: [CompanionAction] = []
        if store.activeWorkout.session != nil {
            actions.append(CompanionAction(title: "Continue workout", systemImage: "figure.strengthtraining.traditional", primary: true) {
                withAnimation(Theme.Motion.smoothOut(0.28)) {
                    liveWorkoutPresented = true
                    selectMainTab(.workout)
                }
            })
        }
        if let source = TrainingPlan.activeProgramRecord(), store.activeWorkout.session == nil {
            let remaining = TrainingWorkflow.remainingTrainingSlots(source, ISOTime.now())
            if !remaining.sessions.isEmpty && store.trainingRecords.data.sessions.contains(where: { $0.plannedProgramId == source.id }) {
                actions.append(CompanionAction(title: "Adjust remaining week", systemImage: "arrow.triangle.2.circlepath", primary: true) {
                    do {
                        let result = try TrainingWorkflow.generateAndSavePlan(source: source)
                        if let program = result.result.program { TrainingPlan.projectPlannedWorkouts(TrainingPlan.sessionViews(program)) }
                        Haptics.trigger(.success)
                    } catch { Haptics.trigger(.warning) }
                })
            } else if remaining.sessions.isEmpty {
                actions.append(CompanionAction(title: "Extend training plan", systemImage: "calendar.badge.plus", primary: true) {
                    store.navigation.push(.planWeek(sourceProgramId: source.id))
                })
            }
        }
        actions.append(CompanionAction(title: store.trainingRecords.data.activeProgramId == nil ? "Create training plan" : "New training plan", systemImage: "calendar.badge.plus", primary: actions.isEmpty) {
            store.navigation.push(.planWeek(sourceProgramId: nil))
        })
        actions.append(CompanionAction(title: "Choose exercises", systemImage: "list.bullet.rectangle", action: startExerciseFlow))
        return actions
    }

    private var workoutCompanionActions: [CompanionAction] {
        if workoutDetailActionState.workoutId != nil {
            var actions: [CompanionAction] = []

            if workoutDetailActionState.canStart {
                actions.append(
                    CompanionAction(
                        title: workoutDetailActionState.isEmpty ? "Add exercise" : "Start workout",
                        systemImage: workoutDetailActionState.isEmpty ? "plus" : "play.fill",
                        primary: true
                    ) {
                        workoutDetailActionRequest = workoutDetailActionState.isEmpty ? .addExercise : .start
                    }
                )
            }

            actions.append(
                CompanionAction(
                    title: "Share workout",
                    systemImage: "square.and.arrow.up",
                    primary: actions.isEmpty
                ) {
                    workoutDetailActionRequest = .share
                }
            )
            actions.append(
                CompanionAction(title: "Copy to today", systemImage: "doc.on.doc") {
                    workoutDetailActionRequest = .duplicate
                }
            )

            if !workoutDetailActionState.isEmpty, workoutDetailActionState.canEdit {
                actions.append(
                    CompanionAction(title: "Add exercise", systemImage: "plus") {
                        workoutDetailActionRequest = .addExercise
                    }
                )
            }

            if workoutDetailActionState.canDelete {
                actions.append(
                    CompanionAction(title: "Delete workout", systemImage: "trash") {
                        workoutDetailActionRequest = .delete
                    }
                )
            }

            return actions
        }

        guard let session = store.activeWorkout.session else {
            return [
                CompanionAction(title: "Choose exercises", systemImage: "list.bullet.rectangle", primary: true, action: startExerciseFlow)
            ]
        }

        var actions: [CompanionAction] = [
            CompanionAction(
                title: session.runningSince == nil ? "Resume workout" : "Pause workout",
                systemImage: session.runningSince == nil ? "play.fill" : "pause.fill",
                primary: true
            ) {
                if session.runningSince == nil {
                    store.activeWorkout.resume()
                } else {
                    store.activeWorkout.pause()
                }
            }
        ]
        if ActiveWorkout.currentExercise(session) != nil {
            actions.append(
                CompanionAction(
                    title: "Current exercise",
                    systemImage: "figure.strengthtraining.traditional",
                    action: exercisePlayerOpener
                )
            )
        }
        actions.append(CompanionAction(title: "Finish workout", systemImage: "flag.checkered") {
            Haptics.trigger(.success)
            closeExercisePlayer()
            store.activeWorkout.finish()
            selectMainTab(.summary)
        })
        return actions
    }
    private func startExerciseFlow() {
        store.filters.reset(); store.filters.setEquipment(store.filters.gymEquipment)
        store.navigation.selectMode = false; store.navigation.selectedIds = []
        store.navigation.push(.muscles(preferredWorkoutId: nil))
    }
    private func selectMainTab(_ tab: MainTab) {
        mainTab = tab
        nativeTabSelection = tab
    }

    private var exercisePlayerOpener: () -> Void {
        let appStore = store
        return {
            DispatchQueue.main.async {
                guard let session = appStore.activeWorkout.session else { return }
                if session.currentExerciseId == nil,
                   let exercise = ActiveWorkout.currentExercise(session) {
                    appStore.activeWorkout.setCurrentExercise(exercise.id)
                }
                Haptics.trigger(.selection)
                withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                    exercisePlayerOpen = true
                }
            }
        }
    }

    private func closeExercisePlayer() {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.90)) {
                exercisePlayerOpen = false
            }
        }
    }

    private func finishActiveWorkout() {
        Haptics.trigger(.success)
        closeExercisePlayer()
        store.activeWorkout.finish()
        selectMainTab(.summary)
    }

    private func updateRautaCompactState(_ compact: Bool) {
        guard compact != rautaCompact else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            rautaCompact = compact
        }
    }

    private func restSeconds(for exerciseId: String) -> Double {
        guard let workoutId = store.activeWorkout.session?.workoutId,
              let workout = store.workouts.workout(workoutId),
              let reference = workout.planned,
              let planned = TrainingPlan.plannedSessionView(reference.programId, reference.sessionId)
        else { return 90 }
        return planned.prescription.first { $0.exerciseId == exerciseId }?.restSeconds ?? 90
    }
}

@available(iOS 26.0, *)
private struct ConditionalNativeBottomAccessory<Accessory: View>: ViewModifier {
    let isVisible: Bool
    let accessory: () -> Accessory

    init(
        isVisible: Bool,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.isVisible = isVisible
        self.accessory = accessory
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isVisible {
            content.tabViewBottomAccessory {
                accessory()
            }
        } else {
            content
        }
    }
}

@available(iOS 26.0, *)
private struct NativeExerciseBottomAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let exercise: ExerciseSummary
    @Binding var isPresented: Bool
    let onCompactChange: (Bool) -> Void

    private var compact: Bool { placement == .inline }

    var body: some View {
        CurrentExerciseAccessory(
            exercise: exercise,
            onOpen: {
                Haptics.trigger(.selection)
                withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                    isPresented = true
                }
            },
            compact: compact
        )
        .padding(.horizontal, compact ? 4 : Theme.Metrics.contentInset)
        .onAppear { onCompactChange(compact) }
        .onChange(of: placement) { _, _ in onCompactChange(compact) }
    }
}

@available(iOS 26.0, *)
private struct NativeWorkoutCompleteAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let session: ActiveWorkoutSession
    @Binding var isPresented: Bool
    let onCompactChange: (Bool) -> Void

    private var compact: Bool { placement == .inline }

    var body: some View {
        Button {
            Haptics.trigger(.selection)
            withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                isPresented = true
            }
        } label: {
            HStack(spacing: compact ? 8 : 10) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: compact ? 18 : 22, weight: .semibold))
                    .foregroundStyle(Theme.primary)

                VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                    Text(session.workoutName)
                        .font(Theme.sans(compact ? 13 : 16, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    Text("All exercises complete")
                        .font(Theme.sans(compact ? 10 : 11, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(ActiveWorkout.formatDuration(ActiveWorkout.elapsedMs(session)))
                        .font(Theme.sans(compact ? 11 : 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                }
            }
            .padding(.horizontal, compact ? 10 : 12)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .frame(height: compact ? 50 : 62)
        .padding(.horizontal, compact ? 4 : Theme.Metrics.contentInset)
        .accessibilityLabel("Workout complete, open workout summary")
        .onAppear { onCompactChange(compact) }
        .onChange(of: placement) { _, _ in onCompactChange(compact) }
    }
}

private struct WorkoutTabHost: View {
    @ObservedObject private var store = AppStore.shared
    let upcoming: [Workout]
    let past: [Workout]
    let activeWorkoutId: String?
    @Binding var liveWorkoutPresented: Bool
    @Binding var detailActionState: WorkoutDetailActionState
    @Binding var detailActionRequest: WorkoutDetailExternalAction?
    @Binding var listSelection: Int
    @Binding var selectedWorkoutId: String?
    let onOpenExercisePlayer: () -> Void

    var body: some View {
        Group {
            if let selectedId = selectedWorkoutId {
                WorkoutDetailScreen(
                    workoutId: selectedId,
                    embeddedInMainTabs: true,
                    onOpenExercisePlayer: onOpenExercisePlayer,
                    onBackToWorkouts: closeWorkout,
                    onReplaceWorkout: { self.selectedWorkoutId = $0 },
                    externalActionRequest: $detailActionRequest,
                    onActionStateChange: { detailActionState = $0 }
                )
            } else if liveWorkoutPresented,
               let session = store.activeWorkout.session {
                WorkoutDetailScreen(
                    workoutId: session.workoutId,
                    embeddedInMainTabs: true,
                    onOpenExercisePlayer: onOpenExercisePlayer,
                    onBackToWorkouts: closeWorkout
                )
            } else {
                workoutListPage
            }
        }
    }

    private var workoutListPage: some View {
        AppShell(commandsVisible: false) {
            ZStack(alignment: .top) {
                WorkoutListContent(
                    upcoming: upcoming,
                    past: past,
                    activeWorkoutId: activeWorkoutId,
                    selection: $listSelection,
                    onOpen: openWorkout
                )

                AppTopScrim()
                    .zIndex(20)

                WorkoutsModeSwitcher(selection: $listSelection)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .padding(.horizontal, Theme.Metrics.contentInset)
                    .padding(.top, 12 + DeviceScreen.safeAreaInsets.top)
                    .zIndex(30)
            }
        } controls: {
            EmptyView()
        }
    }

    private func openWorkout(_ workout: Workout) {
        _ = EngineWorkout.ensureEngineWorkout(workout.id)
        Haptics.trigger(.selection)
        withAnimation(Theme.Motion.smoothOut(0.28)) {
            detailActionState = .none
            detailActionRequest = nil
            if activeWorkoutId == workout.id {
                selectedWorkoutId = nil
                liveWorkoutPresented = true
            } else {
                liveWorkoutPresented = false
                selectedWorkoutId = workout.id
            }
        }
    }

    private func closeWorkout() {
        withAnimation(Theme.Motion.smoothOut(0.28)) {
            detailActionState = .none
            detailActionRequest = nil
            selectedWorkoutId = nil
            liveWorkoutPresented = false
        }
    }
}

struct RautaNativeTabControl: View {
    var mood: RautaMood
    @Binding var activeTab: MainTab
    var actionsForTab: (MainTab) -> [CompanionAction]
    var compact = false
    @Binding var isPresented: Bool
    var onPresent: () -> Void
    @State private var reactionKey = ""
    // The native bottom accessory changes its placement when the tab bar wraps.
    // Give the Rive view a genuinely different layout size in each state: a
    // transform alone can leave the representable rendering at its old bounds.
    private var controlSize: CGFloat { compact ? 88 : 80 }
    private var characterSize: CGFloat { compact ? 74 : 62 }

    var body: some View {
        let actions = actionsForTab(activeTab)

        ZStack {
            RautaCharacter(
                mood: mood,
                reactionKey: reactionKey
            )
            .frame(width: characterSize, height: characterSize)
            .offset(y: 7)
            .allowsHitTesting(false)
        }
        .frame(width: controlSize, height: controlSize)
        .allowsHitTesting(false)
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            AppMenuSurface(dismiss: { isPresented = false }) {
                ForEach(actions) { action in
                    Button {
                        isPresented = false
                        action.action()
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.clear)
        }
        .onChange(of: isPresented) { _, presented in
            if presented, !actions.isEmpty {
                reactionKey = UUID().uuidString
            }
        }
        .accessibilityHidden(true)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: compact)
    }
}

private struct NativeRautaTabTapInterceptor: UIViewRepresentable {
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.onTap = onTap
        uiView.coordinator = context.coordinator
        uiView.scheduleInstall()
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: Coordinator) {
        coordinator.removeButton()
    }

    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleInstall()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleInstall()
        }

        func scheduleInstall() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                coordinator?.install(from: self)
            }
        }
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void
        weak var tabBar: UITabBar?
        weak var hostWindow: UIWindow?
        weak var button: UIButton?

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        func install(from probe: UIView) {
            guard let window = probe.window,
                  let tabBar = findTabBar(in: window)
            else { return }

            if self.tabBar !== tabBar || hostWindow !== window || button == nil {
                removeButton()
                let button = UIButton(type: .custom)
                button.backgroundColor = .clear
                button.accessibilityLabel = "Rauta actions"
                button.accessibilityTraits = .button
                button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
                window.addSubview(button)
                self.tabBar = tabBar
                hostWindow = window
                self.button = button
            }

            guard let button else { return }
            button.frame = tabBar.convert(auxiliarySlotFrame(in: tabBar), to: window)
            window.bringSubviewToFront(button)
        }

        func removeButton() {
            button?.removeFromSuperview()
            button = nil
            tabBar = nil
            hostWindow = nil
        }

        @objc private func tapped() {
            onTap()
        }

        private func findTabBar(in view: UIView) -> UITabBar? {
            if let tabBar = view as? UITabBar { return tabBar }
            for subview in view.subviews {
                if let tabBar = findTabBar(in: subview) { return tabBar }
            }
            return nil
        }

        private func auxiliarySlotFrame(in tabBar: UITabBar) -> CGRect {
            let candidates = tabBar.subviews.filter { subview in
                let frame = subview.frame
                return frame.minX > tabBar.bounds.midX
                    && frame.width >= 56
                    && frame.width <= 72
                    && frame.height >= 56
                    && frame.height <= 72
            }
            if let slot = candidates.max(by: { $0.frame.minX < $1.frame.minX }) {
                return slot.frame
            }
            let size: CGFloat = 62
            let trailingInset: CGFloat = 21
            return CGRect(
                x: tabBar.bounds.width - trailingInset - size,
                y: 0,
                width: size,
                height: size
            )
        }
    }
}

private struct SummaryWorkoutsContent: View {
    let completedWorkouts: [Workout]
    let history: TrainingHistory

    private var month: MonthlySummarySnapshot {
        MonthlySummarySnapshot(workouts: completedWorkouts, history: history)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                StreakStrip(workouts: completedWorkouts)
                    .allowsHitTesting(false)

                MonthlySummaryDashboard(snapshot: month)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 220)
        }
        .contentMargins(
            .top,
            Theme.Metrics.headerHeight + DeviceScreen.safeAreaInsets.top + 36,
            for: .scrollContent
        )
        .scrollIndicators(.hidden)
    }
}

private struct WorkoutListContent: View {
    let upcoming: [Workout]
    let past: [Workout]
    let activeWorkoutId: String?
    @Binding var selection: Int
    let onOpen: (Workout) -> Void

    @State private var upcomingLimit = 6
    @State private var pastLimit = 6

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                Group {
                    if selection == 0 {
                        workoutList(
                            items: upcoming,
                            itemLimit: upcomingLimit,
                            isPast: false,
                            emptyMessage: "No upcoming workouts",
                            onMore: { upcomingLimit += 6 },
                            onLess: { upcomingLimit = 6 }
                        )
                        .id("upcoming-workouts")
                    } else {
                        workoutList(
                            items: past,
                            itemLimit: pastLimit,
                            isPast: true,
                            emptyMessage: "No past workouts yet",
                            onMore: { pastLimit += 6 },
                            onLess: { pastLimit = 6 }
                        )
                        .id("past-workouts")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 92)
        }
        .contentMargins(
            .top,
            Theme.Metrics.headerHeight + DeviceScreen.safeAreaInsets.top + 36,
            for: .scrollContent
        )
        .scrollIndicators(.hidden)
        .animation(Theme.Motion.smoothOut(0.24), value: selection)
    }

    @ViewBuilder
    private func workoutList(
        items: [Workout],
        itemLimit: Int,
        isPast: Bool,
        emptyMessage: String,
        onMore: @escaping () -> Void,
        onLess: @escaping () -> Void
    ) -> some View {
        let remaining = Swift.max(0, items.count - itemLimit)
        let showLess = itemLimit > 6

        if items.isEmpty {
            Text(emptyMessage)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        }

        ForEach(items.prefix(itemLimit)) { workout in
            WorkoutRow(
                workout: workout,
                isPast: isPast,
                isRunning: activeWorkoutId == workout.id,
                onOpen: { onOpen(workout) }
            )
        }

        sectionFooter(
            remaining: remaining,
            showLess: showLess,
            onMore: onMore,
            onLess: onLess
        )
    }

    @ViewBuilder
    private func sectionFooter(
        remaining: Int,
        showLess: Bool,
        onMore: @escaping () -> Void,
        onLess: @escaping () -> Void
    ) -> some View {
        if remaining > 0 || showLess {
            HStack(spacing: 8) {
                if remaining > 0 {
                    AppButton(
                        variant: .ghost,
                        expands: true,
                        accessibilityLabel: "Load more (\(remaining))",
                        action: onMore
                    ) {
                        HStack(spacing: 6) {
                            Text("Load more")
                            Text("(\(remaining))")
                                .foregroundStyle(Theme.mutedForeground)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
                if showLess {
                    AppButton(
                        variant: .ghost,
                        expands: remaining == 0,
                        accessibilityLabel: "Show less",
                        action: onLess
                    ) {
                        HStack(spacing: 6) {
                            Text("Show less")
                            Image(systemName: "chevron.up")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
            }
        }
    }
}

private struct WorkoutsModeSwitcher: View {
    @Binding var selection: Int

    var body: some View {
        Picker("Workout list", selection: $selection) {
            Text("Next").tag(0)
            Text("Past").tag(1)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 214)
        .tint(Theme.primary)
        .glassSurface(
            .tinted(Theme.primary.opacity(0.30)),
            in: Capsule(),
            border: Theme.primary.opacity(0.34),
            legacyFill: Theme.primary.opacity(0.16)
        )
        .onChange(of: selection) { _, _ in
            Haptics.trigger(.selection)
        }
    }
}

private struct StreakStrip: View {
    let workouts: [Workout]
    private var streak: Streak { StreakBuilder.build(workouts) }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 36, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT STREAK")
                        .font(Theme.sans(9, weight: .black))
                        .kerning(1.45)
                        .foregroundStyle(Theme.lime)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(streak.currentStreak)")
                            .font(Theme.readout(30))
                            .foregroundStyle(Theme.foreground)
                        Text(streak.currentStreak == 1 ? "day" : "days")
                            .font(Theme.sans(15, weight: .bold))
                            .foregroundStyle(Theme.foreground.opacity(0.78))
                    }
                }
                .padding(.leading, 10)

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    streakMetric(value: streak.weekWorkouts, label: "THIS WEEK", color: Theme.lime)

                    Rectangle()
                        .fill(Theme.foreground.opacity(0.10))
                        .frame(width: 1, height: 30)

                    streakMetric(value: streak.longestStreak, label: "BEST", color: Theme.gold)
                }
                .padding(.trailing, 4)
            }

            HStack(spacing: 4) {
                ForEach(streak.week) { day in
                    VStack(spacing: 6) {
                        Flame(lit: day.workouts > 0)
                            .frame(width: day.isToday ? 38.4 : 30.4, height: day.isToday ? 48 : 38)
                            .frame(height: 48, alignment: .bottom).opacity(day.isFuture ? 0.6 : 1)
                        Text(CalendarDate.weekdayShort(day.date)).font(Theme.sans(10, weight: .semibold))
                            .foregroundStyle(day.isToday ? Theme.primaryForeground : Theme.mutedForeground)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(day.isToday ? Theme.primary : .clear, in: Capsule())
                    }.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background {
            shape
                .fill(Theme.card)
        }
    }

    private func streakMetric(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(Theme.readout(15))
                .foregroundStyle(color)
            Text(label)
                .font(Theme.sans(7, weight: .black))
                .kerning(0.9)
                .foregroundStyle(Theme.mutedForeground)
        }
        .frame(minWidth: 42)
    }
}

private struct Flame: View {
    var lit: Bool

    var body: some View {
        ZStack {
            FlameShape()
                .fill(lit ? Theme.rust : Theme.muted)
                .overlay(
                    FlameShape()
                        .strokeBorder(
                            lit ? Theme.ember.opacity(0.72) : Theme.border.opacity(0.55),
                            lineWidth: 1
                        )
                )

            Canvas { context, size in
                var ctx = context
                ctx.scaleBy(x: size.width / 32, y: size.height / 40)

                if lit, let outer = SVGPath.parse(FlameShape.definition) {
                    ctx.fill(
                        outer,
                        with: .linearGradient(
                            Gradient(colors: [
                                Theme.primaryGradientStart.opacity(0.64),
                                Theme.primaryGradientEnd.opacity(0.28)
                            ]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: 0, y: 40)
                        )
                    )
                }

                if lit, let inner = SVGPath.parse("M16.2 15.8c0 4 6.1 6.1 6.1 11a6.2 6.2 0 0 1-12.4 0c0-4.9 6.3-7 6.3-11Z") {
                    ctx.fill(
                        inner,
                        with: .linearGradient(
                            Gradient(colors: [
                                .white.opacity(0.42),
                                Theme.primaryGradientEnd.opacity(0.18)
                            ]),
                            startPoint: CGPoint(x: 16, y: 16),
                            endPoint: CGPoint(x: 16, y: 34)
                        )
                    )
                }

                if lit, let highlight = SVGPath.parse("M13.2 21.6c-1.2 1.6-1.8 3-1.9 4.6") {
                    ctx.stroke(
                        highlight,
                        with: .color(.white.opacity(0.72)),
                        style: StrokeStyle(lineWidth: 1.55, lineCap: .round)
                    )
                }

                if lit, let ember = SVGPath.parse("M17.2 24.3c1.9 1.7 2.7 3.2 2.7 4.8a3.7 3.7 0 0 1-7.4 0c0-1.5 1.2-3.2 4.7-4.8Z") {
                    ctx.fill(ember, with: .color(.white.opacity(0.15)))
                }
            }
            .allowsHitTesting(false)
        }
        .shadow(
            color: lit ? Theme.primary.opacity(0.25) : .clear,
            radius: lit ? 7 : 0,
            y: lit ? 3 : 0
        )
    }
}

private struct FlameShape: InsettableShape {
    static let definition = "M16.6 1.6c.6 6.4 9.9 10.4 9.9 22.1a10.5 10.5 0 0 1-21 0c0-5.4 2.1-9 4.9-11.9.1 3.1 1.3 5.3 3.1 6.4 1.8-1.7 3-8.6 3.1-16.6Z"

    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        guard let source = SVGPath.parse(Self.definition) else { return Path() }
        let target = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let scaleX = target.width / 32
        let scaleY = target.height / 40
        let transform = CGAffineTransform(translationX: target.minX, y: target.minY)
            .scaledBy(x: scaleX, y: scaleY)
        return source.applying(transform)
    }

    func inset(by amount: CGFloat) -> FlameShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct WorkoutRow: View {
    let workout: Workout
    let isPast: Bool
    let isRunning: Bool
    let onOpen: () -> Void
    private var muscles: [MuscleId] { ExerciseCatalogue.musclesForExerciseIds(workout.exerciseIds) }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                dateStamp
                VStack(alignment: .leading, spacing: 5) {
                    title
                    detail
                    progressBars
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                BodyPreview(selectedMuscles: muscles, width: 70, height: 60)
                    .opacity(isPast ? 0.9 : 1)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(
                Theme.card.opacity(0.92),
                in: RoundedRectangle(cornerRadius: 30, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var dateStamp: some View {
        VStack(spacing: 2) {
            Text(CalendarDate.weekdayShort(workout.date).uppercased())
                .font(Theme.sans(8, weight: .black))
                .tracking(1.15)
            Text(CalendarDate.dayOfMonth(workout.date))
                .font(Theme.readout(20))
            if isPast {
                Text(CalendarDate.monthShort(workout.date).uppercased())
                    .font(Theme.sans(8, weight: .black))
                    .tracking(0.8)
                    .opacity(0.66)
            }
        }
        .foregroundStyle(isRunning ? Theme.primary : isPast ? Theme.mutedForeground : Theme.foreground)
        .frame(width: 52)
        .frame(minHeight: 58)
    }

    private var title: some View {
        Text("\(workout.name) · \(Wording.countLabel(workout.exerciseIds.count, "exercise"))")
            .font(Theme.sans(16, weight: .heavy))
            .tracking(-0.2)
            .foregroundStyle(Theme.foreground)
            .lineLimit(1)
    }

    @ViewBuilder private var detail: some View {
        if isRunning, let session = ActiveWorkoutStore.shared.session {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                HStack(spacing: 6) {
                    Circle().fill(Theme.primary).frame(width: 6, height: 6)
                    Text("\(session.runningSince == nil ? "Paused" : "In progress") · \(minutes(ActiveWorkout.elapsedMs(session)))")
                }
                .font(Theme.sans(11, weight: .black))
                .tracking(0.35)
                .foregroundStyle(Theme.primary)
                .textCase(.uppercase)
            }
        } else if let completion = workout.completion {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
                Text("Completed")
                Text(minutes(completion.durationMs))
                if completion.activeCalories > 0 {
                    Text("\(Int(completion.activeCalories)) kcal")
                        .foregroundStyle(Theme.gold)
                }
            }
            .font(Theme.sans(12, weight: .semibold))
            .foregroundStyle(Theme.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        } else if isPast {
            Text("Not completed")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
        } else {
            Text(muscleSummary)
                .font(Theme.sans(11, weight: .medium))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
        }
    }

    private var progressBars: some View {
        let completed = completedExerciseIds
        let current = isRunning ? ActiveWorkoutStore.shared.session?.currentExerciseId : nil

        return HStack(spacing: 4) {
            ForEach(workout.exerciseIds, id: \.self) { id in
                Capsule()
                    .fill(progressFill(id: id, completed: completed, current: current))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 3)
    }

    private var completedExerciseIds: Set<String> {
        if isRunning, let session = ActiveWorkoutStore.shared.session {
            return Set(session.completedIds)
        }
        return Set(workout.completion?.completedExerciseIds ?? [])
    }

    private func progressFill(id: String, completed: Set<String>, current: String?) -> AnyShapeStyle {
        if completed.contains(id) {
            if isPast { return AnyShapeStyle(Theme.success) }
            return AnyShapeStyle(Theme.primaryGradient)
        }
        if id == current { return AnyShapeStyle(Theme.primary.opacity(0.48)) }
        return AnyShapeStyle(Theme.foreground.opacity(0.10))
    }

    private var muscleSummary: String {
        muscles.prefix(3).map(\.label).joined(separator: " · ")
            + (muscles.count > 3 ? " +\(muscles.count - 3)" : "")
    }

    private func minutes(_ milliseconds: Double) -> String {
        "\(Swift.max(1, Int((milliseconds / 60_000).rounded(.up)))) min"
    }
}
