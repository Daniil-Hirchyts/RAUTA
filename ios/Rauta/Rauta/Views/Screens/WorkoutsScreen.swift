import SwiftUI
import UIKit

enum MainTab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case workout = "Workout"
    case library = "Library"
    case profile = "Profile"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .summary: return "chart.bar"
        case .workout: return "figure.strengthtraining.traditional"
        case .library: return "books.vertical"
        case .profile: return "person.crop.circle"
        }
    }
}

/// RAUTA's auxiliary slot is a control, never a destination. Keeping it out of
/// `MainTab` prevents it from becoming restorable navigation state.
private enum NativeTabSelection: Hashable {
    case page(MainTab)
    case rauta
}

private enum WorkoutListFilter: Int, CaseIterable, Identifiable {
    case all
    case today
    case planned
    case past
    case fullBody
    case upper
    case lower
    case push
    case pull
    case legs

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .today: return "Today"
        case .planned: return "Planned"
        case .past: return "Past"
        case .fullBody: return "Full body"
        case .upper: return "Upper"
        case .lower: return "Lower"
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        }
    }

    var isWorkoutType: Bool {
        switch self {
        case .all, .today, .planned, .past: return false
        case .fullBody, .upper, .lower, .push, .pull, .legs: return true
        }
    }

    func matchesWorkoutType(_ workout: Workout) -> Bool {
        let name = workout.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch self {
        case .fullBody: return name.hasPrefix("full body")
        case .upper: return name.hasPrefix("upper")
        case .lower: return name.hasPrefix("lower")
        case .push: return name.hasPrefix("push")
        case .pull: return name.hasPrefix("pull")
        case .legs: return name.hasPrefix("legs") || name.hasPrefix("leg day")
        case .all, .today, .planned, .past: return false
        }
    }
}

enum NativeTabIcons {
    static let summary = make(MainTab.summary.systemImage)
    static let workout = make(MainTab.workout.systemImage)
    static let library = make(MainTab.library.systemImage)
    static let profile = make(MainTab.profile.systemImage)
    static let transparentPlaceholder = UIGraphicsImageRenderer(
        size: CGSize(width: 28, height: 28)
    ).image { _ in }

    static func image(for tab: MainTab) -> UIImage {
        switch tab {
        case .summary: return summary
        case .workout: return workout
        case .library: return library
        case .profile: return profile
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
    @ObservedObject private var workouts = WorkoutsStore.shared
    @ObservedObject private var trainingRecords = TrainingRecordsStore.shared
    @ObservedObject private var activeWorkout = ActiveWorkoutStore.shared
    private let navigation = AppSessionStore.shared
    private let filters = FiltersStore.shared
    @State private var mainTab: MainTab = .summary
    @State private var rautaMenuPresented = false
    @State private var rautaCompact = false
    @State private var exercisePlayerOpen = false
    /// Navigation asked for from inside the exercise player, run once the
    /// player has finished closing — nothing can be presented while it is up.
    @State private var afterExercisePlayer: (() -> Void)?
    @State private var liveWorkoutPresented = false
    @State private var workoutDetailActionState = WorkoutDetailActionState.none
    @State private var workoutDetailActionRequest: WorkoutDetailExternalAction?
    @State private var workoutListSelection = 0
    @State private var selectedWorkoutId: String?
    @State private var tabHostIdentity = UUID()
    @Environment(\.rautaOnStage) private var onStage
    /// Whether the tab bar and RAUTA are arranged for Profile. It follows
    /// `mainTab` a beat behind: the selection moves first, and only once it
    /// has settled does RAUTA leave its circle and the bar resize — each on
    /// frames of its own instead of all on the same one.
    @State private var profileChrome = false

    @State private var timelineMemo = Memo<TimelineInputs, WorkoutTimeline>()

    private struct TimelineInputs: Equatable {
        var workouts: [Workout]
        var records: PersistedTrainingState
        var activeWorkoutId: String?
    }

    /// This screen's body runs on every tab change, so the split is kept until
    /// the workouts, the records or the running workout actually change.
    /// Unchanged arrays compare by storage, so asking costs next to nothing.
    private var timeline: WorkoutTimeline {
        let inputs = TimelineInputs(
            workouts: workouts.workouts,
            records: trainingRecords.data,
            activeWorkoutId: activeWorkout.session?.workoutId
        )
        return timelineMemo(inputs) {
            WorkoutTimeline(
                workouts: inputs.workouts,
                records: inputs.records,
                activeWorkoutId: inputs.activeWorkoutId
            )
        }
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
        .fullScreenCover(isPresented: $exercisePlayerOpen, onDismiss: {
            let next = afterExercisePlayer
            afterExercisePlayer = nil
            next?()
        }) {
            if let session = activeWorkout.session {
                if let exercise = ActiveWorkout.currentExercise(session) {
                    ActiveExerciseDrawer(
                        exercise: exercise,
                        session: session,
                        restSeconds: restSeconds(for: exercise.id),
                        onDetail: {
                            afterExercisePlayer = {
                                navigation.push(
                                    .exerciseDetail(exerciseId: exercise.id),
                                    from: ExercisePlayerZoom.sourceID
                                )
                            }
                            closeExercisePlayer()
                        },
                        hasNextExercise: session.exerciseIds.contains { id in
                            id != session.currentExerciseId && !session.completedIds.contains(id)
                        },
                        onFinishExercise: {
                            Haptics.trigger(.success)
                            activeWorkout.completeCurrent()
                        },
                        onFinish: finishActiveWorkout,
                        onDismiss: closeExercisePlayer
                    )
                    .interactiveDismissDisabled(false)
                    .presentationBackground(.clear)
                    .appZoomTransition(from: ExercisePlayerZoom.sourceID)
                } else if ActiveWorkout.progress(session).isComplete {
                    CompletedWorkoutDrawer(
                        session: session,
                        onFinish: finishActiveWorkout,
                        onDismiss: closeExercisePlayer
                    )
                    .interactiveDismissDisabled(false)
                    .presentationBackground(.clear)
                    .appZoomTransition(from: ExercisePlayerZoom.sourceID)
                } else {
                    Color.clear
                        .onAppear { exercisePlayerOpen = false }
                }
            } else {
                Color.clear
                    .onAppear { exercisePlayerOpen = false }
            }
        }
        .onChange(of: activeWorkout.session?.workoutId) { _, workoutId in
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
            if tab == .profile {
                rautaMenuPresented = false
            }
        }
        .task(id: mainTab == .profile) {
            let target = mainTab == .profile
            guard profileChrome != target else { return }
            // Let the tab selection finish moving before anything else does. The
            // first short wait only resumes once the new page has been built —
            // the first visit to a page can hold the main thread for a moment —
            // so the second is always a full beat of settled selection.
            try? await Task.sleep(for: .milliseconds(30))
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                profileChrome = target
            }
        }
        .onReceive(navigation.$requestedWorkoutId) { workoutId in
            guard let workoutId else { return }
            openRequestedWorkout(workoutId)
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
            // The wrapped layout exists only while an exercise player exists.
            // Scrolling down may wrap the native bar around that player; idle
            // navigation stays expanded.
            .tabBarMinimizeBehavior(activeWorkout.session == nil ? .never : .onScrollDown)
            // UIKit can retain the previous bottom-accessory chrome after the
            // accessory disappears. Rebuild the native tab host at the workout
            // lifecycle boundary so an ended workout cannot leave an empty pill.
            .id(
                "\(tabHostIdentity.uuidString)-\(activeWorkout.session?.workoutId ?? "idle-native-tabs")"
            )
    }

    @available(iOS 27.0, *)
    private var nativeProminentTabView: some View {
        TabView(selection: nativeTabSelection) {
            Tab(value: NativeTabSelection.page(.summary)) {
                page(for: .summary)
            } label: {
                tabLabel(.summary)
            }
            Tab(value: NativeTabSelection.page(.workout)) {
                workoutTabContent
            } label: {
                tabLabel(.workout)
            }
            Tab(value: NativeTabSelection.page(.library)) {
                page(for: .library)
            } label: {
                tabLabel(.library)
            }
            Tab(value: NativeTabSelection.page(.profile)) {
                page(for: .profile)
            } label: {
                tabLabel(.profile)
            }
            if !profileChrome {
                // iOS 27 has a real auxiliary/prominent tab role. Use it here
                // instead of abusing the search role: the system reserves a
                // separate trailing control without merging it into the four
                // navigation destinations.
                Tab(value: NativeTabSelection.rauta, role: .prominent) {
                    Color.clear
                } label: {
                    Image(uiImage: NativeTabIcons.transparentPlaceholder)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.primary)
        .modifier(
            ConditionalNativeBottomAccessory(isVisible: shouldShowNativeExerciseAccessory) {
                nativeExerciseAccessory
            }
        )
        .overlay { nativeRautaControl }
    }

    @available(iOS 26.0, *)
    private var nativeAccessoryTabView: some View {
        TabView(selection: nativeTabSelection) {
            Tab(value: NativeTabSelection.page(.summary)) {
                page(for: .summary)
            } label: {
                tabLabel(.summary)
            }
            Tab(value: NativeTabSelection.page(.workout)) {
                workoutTabContent
            } label: {
                tabLabel(.workout)
            }
            Tab(value: NativeTabSelection.page(.library)) {
                page(for: .library)
            } label: {
                tabLabel(.library)
            }
            Tab(value: NativeTabSelection.page(.profile)) {
                page(for: .profile)
            } label: {
                tabLabel(.profile)
            }
            if !profileChrome {
                Tab(value: NativeTabSelection.rauta, role: .search) {
                    Color.clear
                } label: {
                    Image(uiImage: NativeTabIcons.transparentPlaceholder)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.primary)
        .modifier(
            ConditionalNativeBottomAccessory(isVisible: shouldShowNativeExerciseAccessory) {
                nativeExerciseAccessory
            }
        )
        .overlay { nativeRautaControl }
    }

    @available(iOS 18.4, *)
    private var nativeTabView: some View {
        TabView(selection: nativeTabSelection) {
            Tab(value: NativeTabSelection.page(.summary)) {
                page(for: .summary)
            } label: {
                tabLabel(.summary)
            }
            Tab(value: NativeTabSelection.page(.workout)) {
                workoutTabContent
            } label: {
                tabLabel(.workout)
            }
            Tab(value: NativeTabSelection.page(.library)) {
                page(for: .library)
            } label: {
                tabLabel(.library)
            }
            Tab(value: NativeTabSelection.page(.profile)) {
                page(for: .profile)
            } label: {
                tabLabel(.profile)
            }
            if !profileChrome {
                Tab(value: NativeTabSelection.rauta, role: .search) {
                    Color.clear
                } label: {
                    Image(uiImage: NativeTabIcons.transparentPlaceholder)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.primary)
        .overlay { nativeRautaControl }
    }

    private var legacyTabView: some View {
        TabView(selection: $mainTab) {
            page(for: .summary)
                .tabItem { Label("Summary", systemImage: MainTab.summary.systemImage) }
                .tag(MainTab.summary)
            workoutTabContent
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

    private var nativeTabSelection: Binding<NativeTabSelection> {
        Binding(
            get: { .page(mainTab) },
            set: { selection in
                switch selection {
                case .page(let tab):
                    mainTab = tab
                case .rauta:
                    presentRautaMenu()
                }
            }
        )
    }

    private func tabLabel(_ tab: MainTab) -> some View {
        Label {
            Text(tab.rawValue)
        } icon: {
            Image(uiImage: NativeTabIcons.image(for: tab))
                .renderingMode(.template)
        }
    }

    /// RAUTA sits in the tab bar. A keyboard opens over the tab bar without
    /// moving it, so RAUTA is laid out as if the keyboard were not there either.
    private var nativeRautaControl: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                // Always mounted: building a RAUTA costs about 100 ms of frames,
                // and switching to Profile and back used to build one each way.
                // Off to one side it only hides and stops rendering.
                rautaTabControl(bottomInset: proxy.safeAreaInsets.bottom)
                    .scaleEffect(profileChrome ? 0.78 : 1, anchor: .bottomTrailing)
                    .opacity(profileChrome ? 0 : 1)
                    .allowsHitTesting(!profileChrome)
                    .accessibilityHidden(profileChrome)
                    .environment(\.rautaOnStage, onStage && !profileChrome)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .ignoresSafeArea(.keyboard)
    }

    private func rautaTabControl(bottomInset: CGFloat) -> some View {
        RautaNativeTabControl(
            mood: activeWorkout.session == nil ? .calm : .focused,
            activeTab: $mainTab,
            actionsForTab: companionActions(for:),
            workoutActive: activeWorkout.session != nil,
            wrapped: rautaCompact,
            isPresented: $rautaMenuPresented,
            onPresent: presentRautaMenu
        )
        .padding(.trailing, 6)
        .padding(.bottom, Swift.max(7, bottomInset))
        .offset(
            // Keep the center fixed while the RAUTA overlay shrinks from
            // 68pt to 48pt. With a bottom-trailing anchor the smaller frame
            // otherwise drifts 10pt right; the native prominent circle does
            // not move horizontally when it morphs.
            x: rautaCompact ? -23 : -13,
            y: rautaCompact ? 42 : 52
        )
        .zIndex(1_000)
    }

    private func presentRautaMenu() {
        Haptics.trigger(.selection)
        rautaMenuPresented = true
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private var nativeExerciseAccessory: some View {
        if let session = activeWorkout.session {
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
        guard let session = activeWorkout.session else { return false }
        return ActiveWorkout.currentExercise(session) != nil
            || ActiveWorkout.progress(session).isComplete
    }

    @ViewBuilder
    private var workoutTabContent: some View {
        let timeline = timeline
        WorkoutTabHost(
            upcoming: timeline.upcoming,
            past: timeline.past,
            activeWorkoutId: activeWorkout.session?.workoutId,
            liveWorkoutPresented: $liveWorkoutPresented,
            detailActionState: $workoutDetailActionState,
            detailActionRequest: $workoutDetailActionRequest,
            listSelection: $workoutListSelection,
            selectedWorkoutId: $selectedWorkoutId,
            onOpenExercisePlayer: exercisePlayerOpener
        )
    }

    /// Summary, Library and Profile. The Workout tab is ``workoutTabContent``.
    private func page(for pageTab: MainTab) -> some View {
        AppShell(commandsVisible: false) {
            if pageTab == .library {
                LibraryScreen()
            } else {
                // Summary opens straight onto its first card, a little closer
                // to the bar than a page that starts with a title of its own.
                AppTitledPage(contentGap: pageTab == .summary ? 12 : Theme.Metrics.headerContentGap) {
                    AppShellHeader(
                        title: pageTab.rawValue,
                        left: { Color.clear.frame(width: 44, height: 44) },
                        right: {
                            if pageTab == .profile {
                                AppHeaderButton(systemImage: "gearshape", label: "Settings") {
                                    navigation.push(.settings, from: "profile-settings")
                                }
                                .appZoomSource("profile-settings", cornerRadius: 22)
                            } else {
                                Color.clear.frame(width: 44, height: 44)
                            }
                        },
                        above: { EmptyView() },
                        below: { EmptyView() }
                    )
                } content: {
                    if pageTab == .summary {
                        summaryContent
                    } else if pageTab == .profile {
                        ProfileDashboard(isActive: profileChrome)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            }
        } controls: {
            EmptyView()
        }
    }

    private var summaryContent: some View {
        SummaryWorkoutsContent()
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
                    navigation.push(.settings, from: RautaNativeTabControl.zoomSourceID)
                }
            ]
        case .summary:
            return summaryCompanionActions
        }
    }

    private var summaryCompanionActions: [CompanionAction] {
        var actions: [CompanionAction] = []
        if activeWorkout.session != nil {
            actions.append(CompanionAction(title: "Continue workout", systemImage: "figure.strengthtraining.traditional", primary: true) {
                withAnimation(Theme.Motion.smoothOut(0.28)) {
                    liveWorkoutPresented = true
                    selectMainTab(.workout)
                }
            })
        }
        if let source = TrainingPlan.activeProgramRecord(), activeWorkout.session == nil {
            let remaining = TrainingWorkflow.remainingTrainingSlots(source, ISOTime.now())
            if !remaining.sessions.isEmpty && trainingRecords.data.sessions.contains(where: { $0.plannedProgramId == source.id }) {
                actions.append(CompanionAction(title: "Adjust remaining week", systemImage: "arrow.triangle.2.circlepath", primary: true) {
                    do {
                        let result = try TrainingWorkflow.generateAndSavePlan(source: source)
                        if let program = result.result.program { TrainingPlan.projectPlannedWorkouts(TrainingPlan.sessionViews(program)) }
                        Haptics.trigger(.success)
                    } catch { Haptics.trigger(.warning) }
                })
            } else if remaining.sessions.isEmpty {
                actions.append(CompanionAction(title: "Extend training plan", systemImage: "calendar.badge.plus", primary: true) {
                    navigation.push(.planWeek(sourceProgramId: source.id), from: RautaNativeTabControl.zoomSourceID)
                })
            }
        }
        actions.append(CompanionAction(title: trainingRecords.data.activeProgramId == nil ? "Create training plan" : "New training plan", systemImage: "calendar.badge.plus", primary: actions.isEmpty) {
            navigation.push(.planWeek(sourceProgramId: nil), from: RautaNativeTabControl.zoomSourceID)
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

        guard let session = activeWorkout.session else {
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
                    activeWorkout.resume()
                } else {
                    activeWorkout.pause()
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
            activeWorkout.finish()
            selectMainTab(.summary)
        })
        return actions
    }
    private func startExerciseFlow() {
        filters.reset(); filters.setEquipment(filters.gymEquipment)
        navigation.selectMode = false; navigation.selectedIds = []
        navigation.push(.muscles(preferredWorkoutId: nil), from: RautaNativeTabControl.zoomSourceID)
    }
    private func selectMainTab(_ tab: MainTab) {
        mainTab = tab
    }

    /// A flow over the tabs — adding exercises, building a workout — finished
    /// with a workout and asked for it to be shown.
    private func openRequestedWorkout(_ workoutId: String) {
        _ = EngineWorkout.ensureEngineWorkout(workoutId)
        workoutDetailActionState = .none
        workoutDetailActionRequest = nil
        if activeWorkout.session?.workoutId == workoutId {
            selectedWorkoutId = nil
            liveWorkoutPresented = true
        } else {
            liveWorkoutPresented = false
            selectedWorkoutId = workoutId
        }
        mainTab = .workout
        DispatchQueue.main.async {
            if navigation.requestedWorkoutId == workoutId {
                navigation.requestedWorkoutId = nil
            }
        }
    }

    private var exercisePlayerOpener: () -> Void {
        let activeWorkout = activeWorkout
        return {
            DispatchQueue.main.async {
                guard let session = activeWorkout.session else { return }
                if session.currentExerciseId == nil,
                   let exercise = ActiveWorkout.currentExercise(session) {
                    activeWorkout.setCurrentExercise(exercise.id)
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
        activeWorkout.finish()
        selectMainTab(.summary)
    }

    private func updateRautaCompactState(_ compact: Bool) {
        guard compact != rautaCompact else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            rautaCompact = compact
        }
    }

    private func restSeconds(for exerciseId: String) -> Double {
        TrainingSessionBridge.activePrescriptions()[exerciseId]?.restSeconds ?? 90
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

/// The exercise player grows out of the accessory above the tab bar, the way a
/// mini player opens into Now Playing, and drags back down into it.
enum ExercisePlayerZoom {
    static let sourceID = "exercise-player"
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
        .appZoomSource(ExercisePlayerZoom.sourceID, cornerRadius: compact ? 25 : 31)
        .padding(.horizontal, compact ? 4 : Theme.Metrics.contentInset)
        .task(id: compact) {
            // The native tab/accessory morph can briefly keep both placement
            // hosts alive. Yield once so a disappearing host is cancelled and
            // only the currently mounted placement drives RAUTA's compactness.
            await Task.yield()
            guard !Task.isCancelled else { return }
            onCompactChange(compact)
        }
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
        .appZoomSource(ExercisePlayerZoom.sourceID, cornerRadius: compact ? 25 : 31)
        .padding(.horizontal, compact ? 4 : Theme.Metrics.contentInset)
        .accessibilityLabel("Workout complete, open workout summary")
        .task(id: compact) {
            // See `NativeExerciseBottomAccessory`: only the surviving native
            // placement host may update the shared RAUTA compact state.
            await Task.yield()
            guard !Task.isCancelled else { return }
            onCompactChange(compact)
        }
    }
}

private struct WorkoutTabHost: View {
    @ObservedObject private var activeWorkout = ActiveWorkoutStore.shared
    let upcoming: [Workout]
    let past: [Workout]
    let activeWorkoutId: String?
    @Binding var liveWorkoutPresented: Bool
    @Binding var detailActionState: WorkoutDetailActionState
    @Binding var detailActionRequest: WorkoutDetailExternalAction?
    @Binding var listSelection: Int
    @Binding var selectedWorkoutId: String?
    let onOpenExercisePlayer: () -> Void

    private var hasWorkouts: Bool {
        !upcoming.isEmpty || !past.isEmpty
    }

    /// A workout opened from the list, or the one running.
    private enum Route: Hashable {
        case workout(String)
        case live(String)

        var workoutId: String {
            switch self {
            case .workout(let id), .live(let id): return id
            }
        }
    }

    /// The tab's stack, read from the selection this host is given: opening a
    /// workout pushes it, and swiping back or dragging it down closes it.
    private var path: Binding<[Route]> {
        Binding(
            get: {
                if let selectedWorkoutId { return [.workout(selectedWorkoutId)] }
                if liveWorkoutPresented, let session = activeWorkout.session {
                    return [.live(session.workoutId)]
                }
                return []
            },
            set: { routes in
                guard routes.isEmpty else { return }
                detailActionState = .none
                detailActionRequest = nil
                selectedWorkoutId = nil
                liveWorkoutPresented = false
            }
        )
    }

    var body: some View {
        NavigationStack(path: path) {
            workoutListPage
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    detail(route)
                        .toolbar(.hidden, for: .navigationBar)
                        .swipeBackEnabled()
                        .background(Theme.shell.ignoresSafeArea())
                        // The workout grows out of its row, and a drag down
                        // throws it back there.
                        .appZoomTransition(from: WorkoutRow.zoomSourceID(route.workoutId))
                }
        }
    }

    @ViewBuilder
    private func detail(_ route: Route) -> some View {
        switch route {
        case .workout(let id):
            WorkoutDetailScreen(
                workoutId: id,
                onOpenExercisePlayer: onOpenExercisePlayer,
                onBackToWorkouts: closeWorkout,
                onReplaceWorkout: { self.selectedWorkoutId = $0 },
                externalActionRequest: $detailActionRequest,
                onActionStateChange: { detailActionState = $0 }
            )
        case .live(let id):
            WorkoutDetailScreen(
                workoutId: id,
                onOpenExercisePlayer: onOpenExercisePlayer,
                onBackToWorkouts: closeWorkout
            )
        }
    }

    private var workoutListPage: some View {
        AppShell(commandsVisible: false) {
            AppTitledPage {
                AppShellHeader(
                    title: "Workout",
                    left: { Color.clear.frame(width: 44, height: 44) },
                    right: { Color.clear.frame(width: 44, height: 44) },
                    above: { EmptyView() },
                    below: {
                        if hasWorkouts {
                            WorkoutsModeSwitcher(
                                selection: $listSelection,
                                workouts: upcoming + past
                            )
                        }
                    }
                )
            } content: {
                WorkoutListContent(
                    upcoming: upcoming,
                    past: past,
                    activeWorkoutId: activeWorkoutId,
                    selection: $listSelection,
                    onOpen: openWorkout
                )
            }
        } controls: {
            EmptyView()
        }
    }

    private func openWorkout(_ workout: Workout) {
        _ = EngineWorkout.ensureEngineWorkout(workout.id)
        Haptics.trigger(.selection)
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

    private func closeWorkout() {
        detailActionState = .none
        detailActionRequest = nil
        selectedWorkoutId = nil
        liveWorkoutPresented = false
    }
}

struct RautaNativeTabControl: View {
    var mood: RautaMood
    @Binding var activeTab: MainTab
    var actionsForTab: (MainTab) -> [CompanionAction]
    var workoutActive = false
    var wrapped = false
    @Binding var isPresented: Bool
    var onPresent: () -> Void
    @State private var reactionKey = ""
    /// The action picked from the menu, run once the menu has finished
    /// closing: a page cannot be presented while the menu still is.
    @State private var pendingAction: (() -> Void)?

    static let zoomSourceID = "rauta-menu"

    private var controlSize: CGFloat {
        if wrapped { return 48 }
        return workoutActive ? 68 : 64
    }

    // IMPORTANT: the scroll-wrapped / inline exercise-player RAUTA MUST stay
    // smaller than the expanded version and centered in the SAME native
    // prominent circle. iOS 27 morphs that circle with the tab bar; do not hide
    // it or draw a replacement circle here.
    private var characterSize: CGFloat {
        if wrapped { return 40 }
        return workoutActive ? 56 : 62
    }

    var body: some View {
        let actions = actionsForTab(activeTab)

        Button(action: onPresent) {
            rautaFace
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rauta actions")
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            AppMenuSurface(dismiss: { isPresented = false }) {
                ForEach(actions) { action in
                    Button {
                        pendingAction = action.action
                        isPresented = false
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.clear)
            .onDisappear {
                let action = pendingAction
                pendingAction = nil
                action?()
            }
        }
        .onChange(of: isPresented) { _, presented in
            if presented, !actions.isEmpty {
                reactionKey = UUID().uuidString
            }
        }
        .accessibilityHidden(true)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: workoutActive)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: wrapped)
    }

    private var rautaFace: some View {
        ZStack {
            RautaCharacter(
                mood: mood,
                reactionKey: reactionKey
            )
            .frame(width: characterSize, height: characterSize)
            .offset(y: -3)
            .allowsHitTesting(false)
        }
        .frame(width: controlSize, height: controlSize)
        .contentShape(Circle())
        .appZoomSource(Self.zoomSourceID, cornerRadius: controlSize / 2)
    }
}

/// Every visible workout, split once into what is still ahead and what is done.
/// A workout is upcoming while it is the one in progress, or not yet completed
/// and not already recorded against its planned session. A planned session a
/// later plan has replaced is not shown at all.
struct WorkoutTimeline {
    var upcoming: [Workout]
    var past: [Workout]

    init(workouts: [Workout], records: PersistedTrainingState, activeWorkoutId: String?) {
        let recordedSessions = Set(records.sessions.compactMap(\.plannedSessionId))
        var upcoming: [Workout] = []
        var past: [Workout] = []
        for workout in workouts {
            if let planned = workout.planned, workout.completion == nil, workout.id != activeWorkoutId,
               ProgramRecords.isSupersededPlannedSession(records, planned.programId, planned.sessionId) {
                continue
            }
            let recorded = workout.planned.map { recordedSessions.contains($0.sessionId) } ?? false
            if workout.id == activeWorkoutId || (workout.completion == nil && !recorded) {
                upcoming.append(workout)
            } else {
                past.append(workout)
            }
        }
        self.upcoming = upcoming.sorted { $0.date < $1.date }
        self.past = past.sorted { $0.date > $1.date }
    }
}

/// The Summary tab. It reads the stores itself rather than being handed its
/// figures, so the host redrawing for a tab change does not rebuild the
/// training history: with nothing passed in, SwiftUI has no reason to run this
/// body again until a store it reads changes.
private struct SummaryWorkoutsContent: View {
    @ObservedObject private var workouts = WorkoutsStore.shared
    @ObservedObject private var trainingRecords = TrainingRecordsStore.shared
    @ObservedObject private var activeWorkout = ActiveWorkoutStore.shared

    var body: some View {
        let completedWorkouts = WorkoutTimeline(
            workouts: workouts.workouts,
            records: trainingRecords.data,
            activeWorkoutId: activeWorkout.session?.workoutId
        ).past.filter { $0.completion != nil }
        let month = MonthlySummarySnapshot(
            workouts: completedWorkouts,
            history: trainingRecords.trainingHistory()
        )
        ScrollView {
            LazyVStack(spacing: 12) {
                StreakStrip(workouts: completedWorkouts)
                    .allowsHitTesting(false)

                MonthlySummaryDashboard(snapshot: month)
            }
            .padding(.horizontal, 12)
            // The same run-out as Profile: enough to scroll the last card clear
            // of the tab bar, no more.
            .padding(.bottom, 120)
        }
        .pageScroll()
        .scrollIndicators(.hidden)
    }
}

private struct WorkoutListContent: View {
    let upcoming: [Workout]
    let past: [Workout]
    let activeWorkoutId: String?
    @Binding var selection: Int
    let onOpen: (Workout) -> Void

    @State private var visibleLimit = 12

    private struct WorkoutSection: Identifiable {
        let id: String
        let title: String
        var workouts: [Workout]
    }

    private var filter: WorkoutListFilter {
        WorkoutListFilter(rawValue: selection) ?? .all
    }

    private var allWorkouts: [Workout] {
        var seen = Set<String>()
        return (upcoming + past)
            .filter { seen.insert($0.id).inserted }
            .soonestFirst()
    }

    private var filteredWorkouts: [Workout] {
        switch filter {
        case .all:
            return allWorkouts
        case .today:
            let today = CalendarDate.today
            return allWorkouts.filter { $0.date == today }
        case .planned:
            return upcoming.soonestFirst()
        case .past:
            return past.soonestFirst()
        case .fullBody, .upper, .lower, .push, .pull, .legs:
            return allWorkouts.filter(filter.matchesWorkoutType)
        }
    }

    private var availableFilters: [WorkoutListFilter] {
        let base: [WorkoutListFilter] = [.all, .today, .planned, .past]
        let workoutTypes = WorkoutListFilter.allCases.filter { candidate in
            candidate.isWorkoutType && allWorkouts.contains(where: candidate.matchesWorkoutType)
        }
        return base + workoutTypes
    }

    private var visibleWorkouts: [Workout] {
        Array(filteredWorkouts.prefix(visibleLimit))
    }

    private var pastIds: Set<String> {
        Set(past.map(\.id))
    }

    /// Today on its own, then a section per month for the days ahead and again
    /// for the days behind. A month on both sides of today names its earlier
    /// half "Earlier in …", so the two never read as one.
    private var sections: [WorkoutSection] {
        let today = CalendarDate.today
        let aheadMonths = Set(
            visibleWorkouts.filter { $0.date > today }.map { String($0.date.prefix(7)) }
        )
        var sections: [WorkoutSection] = []
        for workout in visibleWorkouts {
            let month = String(workout.date.prefix(7))
            let id: String
            let title: String
            if workout.date == today {
                id = "today"
                title = "Today"
            } else if workout.date > today {
                id = "ahead-\(month)"
                title = monthTitle(workout.date)
            } else {
                id = "behind-\(month)"
                title = aheadMonths.contains(month)
                    ? "Earlier in \(monthName(workout.date))"
                    : monthTitle(workout.date)
            }
            if let last = sections.indices.last, sections[last].id == id {
                sections[last].workouts.append(workout)
            } else {
                sections.append(WorkoutSection(id: id, title: title, workouts: [workout]))
            }
        }
        return sections
    }

    private var emptySymbol: String {
        switch filter {
        case .all: return "figure.strengthtraining.traditional"
        case .today: return "calendar"
        case .planned: return "calendar.badge.plus"
        case .past: return "clock.arrow.circlepath"
        case .fullBody, .upper, .lower, .push, .pull, .legs: return "line.3.horizontal.decrease"
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .all: return "No workouts yet"
        case .today: return "Nothing planned for today"
        case .planned: return "No planned workouts"
        case .past: return "No past workouts yet"
        case .fullBody, .upper, .lower, .push, .pull, .legs:
            return "No \(filter.title.lowercased()) workouts"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all: return "Plan your week or choose exercises, and your workouts will show up here."
        case .today: return "A rest day. Pick exercises from the Library if you want to train anyway."
        case .planned: return "Create a training plan and its sessions will line up here."
        case .past: return "Finished workouts stay here with their sets and times."
        case .fullBody, .upper, .lower, .push, .pull, .legs:
            return "None of your workouts are \(filter.title.lowercased()) sessions yet."
        }
    }

    var body: some View {
        Group {
            if filteredWorkouts.isEmpty {
                EmptyStatePlaceholder(
                    systemImage: emptySymbol,
                    title: emptyTitle,
                    message: emptyMessage,
                    actionTitle: filter == .all ? nil : "Show all workouts",
                    action: {
                        Haptics.trigger(.selection)
                        selection = WorkoutListFilter.all.rawValue
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .belowPageHeader()
                .padding(32)
                .offset(y: -30)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(sections) { section in
                            Text(section.title)
                                .font(Theme.sans(17, weight: .heavy))
                                .foregroundStyle(Theme.foreground)
                                .padding(.horizontal, 4)
                                .padding(.top, 8)

                            ForEach(section.workouts) { workout in
                                WorkoutRow(
                                    workout: workout,
                                    isPast: pastIds.contains(workout.id),
                                    isRunning: activeWorkoutId == workout.id,
                                    onOpen: { onOpen(workout) }
                                )
                            }
                        }

                        sectionFooter(
                            remaining: Swift.max(0, filteredWorkouts.count - visibleLimit),
                            showLess: visibleLimit > 12,
                            onMore: { visibleLimit += 12 },
                            onLess: { visibleLimit = 12 }
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 92)
                }
                .pageScroll()
                .scrollIndicators(.hidden)
            }
        }
        .animation(Theme.Motion.smoothOut(0.24), value: selection)
        .onChange(of: selection) { _, _ in
            visibleLimit = 12
        }
        .onChange(of: availableFilters.map(\.rawValue)) { _, filters in
            guard filters.contains(selection) else {
                selection = WorkoutListFilter.all.rawValue
                return
            }
        }
    }

    private func monthTitle(_ isoDate: String) -> String {
        formatted(isoDate, template: "MMMM yyyy")
    }

    private func monthName(_ isoDate: String) -> String {
        formatted(isoDate, template: "MMMM")
    }

    private func formatted(_ isoDate: String, template: String) -> String {
        CalendarDate.format(isoDate, template)
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
    let workouts: [Workout]

    private var availableFilters: [WorkoutListFilter] {
        let base: [WorkoutListFilter] = [.all, .today, .planned, .past]
        let workoutTypes = WorkoutListFilter.allCases.filter { candidate in
            candidate.isWorkoutType && workouts.contains(where: candidate.matchesWorkoutType)
        }
        return base + workoutTypes
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(availableFilters) { filter in
                    WorkoutFilterChip(
                        title: filter.title,
                        selected: selection == filter.rawValue
                    ) {
                        guard selection != filter.rawValue else { return }
                        Haptics.trigger(.selection)
                        withAnimation(Theme.Motion.smoothOut(0.24)) {
                            selection = filter.rawValue
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .leading)
    }
}

private struct WorkoutFilterChip: View {
    let title: String
    let selected: Bool
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

    static func zoomSourceID(_ workoutId: String) -> String { "workout:\(workoutId)" }

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
        .appZoomSource(Self.zoomSourceID(workout.id), cornerRadius: 30)
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
