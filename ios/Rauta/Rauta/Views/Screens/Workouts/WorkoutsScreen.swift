import SwiftUI

struct WorkoutsScreen: View {
    private let workouts = WorkoutsStore.shared
    private let trainingRecords = TrainingRecordsStore.shared
    private let activeWorkout = ActiveWorkoutStore.shared
    private let navigation = AppSessionStore.shared
    private let filters = FiltersStore.shared
    @State private var mainTab: MainTab = .summary
    @State private var rautaMenuPresented = false
    /// True for the one update in which the tab bar sits on RAUTA's slot. A tap
    /// on the glass around RAUTA selects that slot; turning this back off in
    /// the next update is what moves the tab bar back to the page it was on.
    @State private var rautaTabBounce = false
    @State private var chatPresented = false
    @State private var chatDictateOnOpen = false
    @State private var chatFocusOnOpen = false
    /// Navigation asked for from inside the chat, run once it has closed —
    /// a page cannot be presented over it.
    @State private var afterChat: (() -> Void)?
    @State private var rautaCompact = false
    @State private var exercisePlayerOpen = false
    /// The warm-up put away while it runs; the bar above the tabs brings it
    /// back.
    @State private var warmupHidden = false
    /// Navigation asked for from inside the exercise player, run once the
    /// player has finished closing — nothing can be presented while it is up.
    @State private var afterExercisePlayer: (() -> Void)?
    @State private var liveWorkoutPresented = false
    /// Why the last finish did not save. The session stays open when it is set.
    @State private var finishIssue: String?
    /// The workout just saved, while RAUTA celebrates it.
    @State private var celebration: WorkoutReceipt?
    /// RAUTA's arrival, once per launch. Reduce Motion skips it.
    @State private var introPlaying = !WorkoutsScreen.introPlayed
    /// The last moment of the intro: the tab bar's RAUTA is running, unseen,
    /// ready to take over from the one landing in its seat.
    @State private var introHandover = false
    /// Where the tab bar's RAUTA sits, for the arrival to land on.
    @State private var rautaSeat: CGRect = .zero
    private static var introPlayed = false
    @State private var workoutDetailActionState = WorkoutDetailActionState.none
    @State private var workoutDetailActionRequest: WorkoutDetailExternalAction?
    @State private var workoutListSelection = 0
    @State private var selectedWorkoutId: String?
    @Environment(\.rautaOnStage) private var onStage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// When the app last went to the background, so a return after a real
    /// absence is greeted and a glance at a notification is not.
    @State private var backgroundedAt: Date?
    /// Whether the tab bar and RAUTA are arranged for Profile. It follows
    /// `mainTab` a beat behind: the selection moves first, and only once it
    /// has settled does RAUTA leave its circle and the bar resize — each on
    /// frames of its own instead of all on the same one.
    /// The remaining week being re-planned, off the main actor.
    @State private var adjustingPlan = false

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
        activeWorkoutPlayerShell(nativeProminentTabView)
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
                            WorkoutAudio.play(.exerciseDone)
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
        // Full screen, like the player: the chat grows out of RAUTA's tab
        // button, and dragging it down throws it back in.
        .fullScreenCover(isPresented: $chatPresented, onDismiss: {
            chatDictateOnOpen = false
            chatFocusOnOpen = false
            let next = afterChat
            afterChat = nil
            next?()
        }) {
            RautaChatSheet(startDictation: chatDictateOnOpen, focusOnOpen: chatFocusOnOpen)
                .interactiveDismissDisabled(false)
                .presentationBackground(.clear)
                .appZoomTransition(from: RautaNativeTabControl.zoomSourceID)
        }
        // Every workout opens with its warm-up, however it was started: from
        // the page, from RAUTA, from Siri or a reminder.
        .overlay {
            if let session = activeWorkout.session, session.warmupUntil != nil, !warmupHidden, celebration == nil {
                WarmupScreen(
                    session: session,
                    onDone: exercisePlayerOpener,
                    onHide: { withAnimation(.easeInOut(duration: 0.3)) { warmupHidden = true } }
                )
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: activeWorkout.session?.warmupUntil != nil)
        // Put away, the warm-up still ends on time: its end is sounded as
        // ever, and the player is left closed — the person chose to be
        // elsewhere.
        .task(id: hiddenWarmupDeadline) {
            guard let deadline = hiddenWarmupDeadline else { return }
            let wait = Date(epochMillis: deadline).timeIntervalSinceNow + 0.9
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, hiddenWarmupDeadline == deadline else { return }
            activeWorkout.endWarmup()
        }
        .onChange(of: activeWorkout.session?.warmupUntil == nil) { _, over in
            if over { warmupHidden = false }
        }
        .overlay {
            if let celebration {
                WorkoutCelebration(receipt: celebration, onContinue: closeCelebration)
                    .transition(.opacity)
            }
        }
        .overlay {
            if introPlaying, !reduceMotion {
                RautaLaunchIntro(
                    seat: rautaSeat,
                    mood: activeWorkout.session == nil ? .calm : .focused,
                    onHandover: { introHandover = true },
                    onLanded: landIntro
                )
            }
        }
        .alert(
            "Workout not saved yet",
            isPresented: Binding(
                get: { finishIssue != nil },
                set: { if !$0 { finishIssue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(finishIssue ?? "")
        }
        .onChange(of: activeWorkout.session?.workoutId) { _, workoutId in
            if workoutId == nil {
                exercisePlayerOpen = false
                liveWorkoutPresented = false
                rautaCompact = false
            }
        }
        .onChange(of: chatPresented) { _, presented in
            if presented { RautaSpeech.shared.hush() }
            WorkoutAudio.touch(presented ? .open : .close)
        }
        .onChange(of: exercisePlayerOpen) { _, open in
            WorkoutAudio.touch(open ? .open : .close)
        }
        .onChange(of: mainTab) { _, tab in
            if tab != .workout {
                liveWorkoutPresented = false
            }
        }
        .onChange(of: navigation.requestedWorkoutId, initial: true) { _, workoutId in
            guard let workoutId else { return }
            openRequestedWorkout(workoutId)
        }
        .onChange(of: navigation.requestedStartWorkoutId, initial: true) { _, workoutId in
            guard let workoutId else { return }
            navigation.requestedStartWorkoutId = nil
            if let workout = WorkoutsStore.shared.workout(workoutId) {
                _ = startFromRauta(workout)
            }
        }
        .onChange(of: navigation.requestedAgentPrompt, initial: true) { _, prompt in
            guard let prompt else { return }
            navigation.requestedAgentPrompt = nil
            chatDictateOnOpen = false
            chatPresented = true
            if !prompt.isEmpty { RautaAgent.shared.send(prompt) }
        }
        .task {
            WorkoutsScreen.introPlayed = true
            guard !introPlaying || reduceMotion else { return }
            // Once the first frame has settled, so the line rises from a RAUTA
            // that is already there.
            introPlaying = false
            try? await Task.sleep(for: .seconds(0.9))
            greet()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { RautaAgent.shared.stop() }
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                AgentModelStore.shared.refresh()
                if let away = backgroundedAt, Date().timeIntervalSince(away) > 15 * 60 { greet() }
                backgroundedAt = nil
            default:
                break
            }
        }
        .task {
            RautaAgent.shared.setBridge(AgentUIBridge(
                startWorkout: { workout in
                    let result = startFromRauta(workout)
                    return result
                },
                finishWorkout: {
                    let before = activeWorkout.session?.workoutId
                    chatPresented = false
                    finishActiveWorkout()
                    return before != nil && activeWorkout.session == nil
                },
                openWorkout: { id in
                    chatPresented = false
                    openRequestedWorkout(id)
                },
                openExercise: { id in
                    afterChat = {
                        navigation.push(.exerciseDetail(exerciseId: id), from: RautaNativeTabControl.zoomSourceID)
                    }
                    chatPresented = false
                },
                dismissChat: { chatPresented = false }
            ))
            #if DEBUG
            let debugArguments = ProcessInfo.processInfo.arguments
            if debugArguments.contains("--rauta-menu") {
                try? await Task.sleep(for: .seconds(4.6))
                presentRautaMenu()
            }
            if debugArguments.contains("--agent-chat") || debugArguments.contains("--agent-demo") {
                // After the launch intro, the way a person would open it.
                try? await Task.sleep(for: .seconds(4.6))
                if let index = debugArguments.firstIndex(of: "--agent-demo") {
                    let page = debugArguments.indices.contains(index + 1) ? Int(debugArguments[index + 1]) ?? 0 : 0
                    RautaAgent.shared.showDemo(page: page)
                }
                chatPresented = true
            }
            if let promptIndex = debugArguments.firstIndex(of: "--agent-prompt"),
               debugArguments.indices.contains(promptIndex + 1) {
                chatPresented = true
                RautaAgent.shared.send(debugArguments[promptIndex + 1])
            }
            if debugArguments.contains("--demo-workout"), activeWorkout.session == nil {
                // A workout running, for the Lock Screen, the Island and the
                // watch to show: three exercises, today, started.
                try? await Task.sleep(for: .seconds(4.6))
                let ids = ["barbell bench press", "barbell squat", "pull up"]
                    .compactMap { ExerciseResolver.resolve($0).first?.exercise.id }
                if let id = try? await EngineWorkout.createWorkout(date: CalendarDate.today, name: "Demo", exerciseIds: ids),
                   let workout = WorkoutsStore.shared.workout(id) {
                    _ = activeWorkout.start(workout)
                }
            }
            #endif
            // Restore any missing lightweight projection from its authoritative
            // plan. Only days still ahead: a past day with no record is one the
            // person deleted or skipped, not one to bring back as unfinished.
            for view in TrainingPlan.activePlannedSessions()
            where view.date >= CalendarDate.today && !TrainingPlan.isPlannedSessionRecorded(view.sessionId) {
                TrainingPlan.ensurePlannedWorkout(view)
            }
        }
    }

    private func activeWorkoutPlayerShell<Content: View>(_ content: Content) -> some View {
        content
            // The wrapped layout exists only while an exercise player exists.
            // Scrolling down may wrap the native bar around that player; idle
            // navigation stays expanded.
            .tabBarMinimizeBehavior(activeWorkout.session == nil ? .never : .onScrollDown)
    }

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
            // iOS 27 has a real auxiliary/prominent tab role. Use it here
            // instead of abusing the search role: the system reserves a
            // separate trailing control without merging it into the three
            // navigation destinations.
            Tab(value: NativeTabSelection.rauta, role: .prominent) {
                // Never meant to be seen: the slot is RAUTA's button. If the
                // tab bar shows it for a frame, it is the app's own shell.
                Theme.shell.ignoresSafeArea()
            } label: {
                Image(uiImage: NativeTabIcons.transparentPlaceholder)
                    // The drawn RAUTA over this slot is hidden from
                    // VoiceOver; the tab itself is what it reaches.
                    .accessibilityLabel("Rauta actions")
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
        .onChange(of: rautaTabBounce) { _, bounced in
            guard bounced else { return }
            withTransaction(Transaction(animation: nil)) { rautaTabBounce = false }
        }
    }

    /// RAUTA's slot is a button, not a page. Selecting it opens RAUTA's menu,
    /// and the selection is really made and then undone: a getter that never
    /// reports the RAUTA slot leaves the tab bar on it, showing an empty page.
    private var nativeTabSelection: Binding<NativeTabSelection> {
        Binding(
            get: { rautaTabBounce ? .rauta : .page(mainTab) },
            set: { selection in
                switch selection {
                case .page(let tab):
                    rautaTabBounce = false
                    mainTab = tab
                case .rauta:
                    guard !rautaTabBounce else { return }
                    rautaTabBounce = true
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
                    // Hidden while the arriving RAUTA flies in to take its place.
                    .opacity(introPlaying && !reduceMotion ? 0 : 1)
                    // Covered by the player, the chat or the celebration, it
                    // neither performs nor speaks: the RAUTA in front does.
                    // Just before the arriving one lands it comes on stage,
                    // quietly, so it is already moving when it takes over.
                    .environment(
                        \.rautaOnStage,
                        onStage && !exercisePlayerOpen && !chatPresented && celebration == nil
                            && (activeWorkout.session?.warmupUntil == nil || warmupHidden)
                            && (!(introPlaying && !reduceMotion) || introHandover)
                    )
                    .environment(\.rautaQuiet, introPlaying && !reduceMotion)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .ignoresSafeArea(.keyboard)
    }

    private func rautaTabControl(bottomInset: CGFloat) -> some View {
        RautaNativeTabControl(
            mood: chatPresented ? .listening : (adjustingPlan ? .working : (activeWorkout.session == nil ? .calm : .focused)),
            activeTab: $mainTab,
            actionsForTab: companionActions(for:),
            workoutActive: activeWorkout.session != nil,
            wrapped: rautaCompact,
            isPresented: $rautaMenuPresented,
            onPresent: presentRautaMenu,
            onAsk: { dictate in
                chatDictateOnOpen = dictate
                chatFocusOnOpen = !dictate
                chatPresented = true
            },
            onSeat: { rautaSeat = $0 },
            lift: exerciseBarLift
        )
        // The exercise bar sits over the tabs during a workout; what RAUTA
        // says and offers rises above it rather than covering it.
        .rautaSpeaker(lift: exerciseBarLift)
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

    /// How far RAUTA's bubbles rise to clear the exercise bar, while it is
    /// laid out above the tabs.
    private var exerciseBarLift: CGFloat {
        shouldShowNativeExerciseAccessory && !rautaCompact ? 46 : 0
    }

    private func presentRautaMenu() {
        WorkoutAudio.play(.menuOpen)
        RautaSpeech.shared.hush()
        rautaMenuPresented = true
    }

    /// The line RAUTA opens with. Each offer in it is the first row of the menu
    /// a tap on RAUTA opens right now.
    private var greeting: String {
        let today = CalendarDate.today
        return RautaGreeting.line(RautaGreeting.Input(
            activeWorkout: activeWorkout.session?.workoutName,
            today: today,
            upcoming: startableUpcoming.map { RautaGreeting.Day(name: $0.name, date: $0.date) },
            trainedToday: timeline.past.contains { $0.date == today },
            hasPlan: TrainingPlan.activeProgramRecord() != nil
        ))
    }

    /// The opening line. `reaction` is the beat RAUTA says it with; the
    /// launch passes none, having just nodded hello on its way in.
    private func greet(reaction: RautaReaction? = .acknowledge) {
        guard !chatPresented else { return }
        RautaSpeech.shared.say(greeting, reaction: reaction)
    }

    /// What RAUTA can point to: anything on today, which it can always start —
    /// a session from a replaced plan runs as a one-off — and, further ahead,
    /// only what the current plan still holds.
    private var startableUpcoming: [Workout] {
        let today = CalendarDate.today
        return timeline.upcoming.filter { workout in
            workout.date == today || !ActiveWorkoutStore.planWasReplaced(workout)
        }
    }

    /// Today's workout, when there is one to start.
    private var todaysWorkout: Workout? {
        guard activeWorkout.session == nil else { return nil }
        let today = CalendarDate.today
        return startableUpcoming.first { $0.date == today && !$0.exerciseIds.isEmpty }
    }

    /// RAUTA starts the workout itself and takes you into it. A refusal is
    /// said in words, by RAUTA, rather than left to a buzz.
    @discardableResult
    private func startFromRauta(_ workout: Workout) -> WorkoutStartOutcome {
        _ = EngineWorkout.ensureEngineWorkout(workout.id)
        let result = activeWorkout.startAsOwnWorkout(workout)
        if let refusal = result.refusal {
            Haptics.trigger(.warning)
            RautaSpeech.shared.say(refusal)
            return result
        }
        WorkoutAudio.play(.workoutStart)
        withAnimation(Theme.Motion.smoothOut(0.28)) {
            selectedWorkoutId = nil
            liveWorkoutPresented = true
            selectMainTab(.workout)
        }
        return result
    }

    @ViewBuilder
    private var nativeExerciseAccessory: some View {
        if let session = activeWorkout.session {
            if session.warmupUntil != nil {
                NativeWarmupAccessory(
                    session: session,
                    onOpen: { withAnimation(.easeInOut(duration: 0.3)) { warmupHidden = false } },
                    onCompactChange: updateRautaCompactState
                )
            } else if let exercise = ActiveWorkout.currentExercise(session) {
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
        return session.warmupUntil != nil
            || ActiveWorkout.currentExercise(session) != nil
            || ActiveWorkout.progress(session).isComplete
    }

    /// The deadline of a warm-up running while put away, for the task that
    /// ends it on time.
    private var hiddenWarmupDeadline: Double? {
        warmupHidden ? activeWorkout.session?.warmupUntil : nil
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

    /// Summary and Library. The Workout tab is ``workoutTabContent``.
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
                            if pageTab == .summary {
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
        SummaryWorkoutsContent(past: timeline.past)
    }

    private func companionActions(for tab: MainTab) -> [CompanionAction] {
        switch tab {
        case .workout:
            return workoutCompanionActions
        case .library:
            return [
                CompanionAction(title: "Choose exercises", systemImage: "list.bullet.rectangle", primary: true, action: startExerciseFlow)
            ]
        case .summary:
            return summaryCompanionActions
        }
    }

    private var summaryCompanionActions: [CompanionAction] {
        var actions: [CompanionAction] = []
        if let today = todaysWorkout {
            actions.append(CompanionAction(title: "Start \(today.name)", systemImage: "play.fill", primary: true) {
                startFromRauta(today)
            })
        }
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
            if !adjustingPlan,
               !remaining.sessions.isEmpty && trainingRecords.data.sessions.contains(where: { $0.plannedProgramId == source.id }) {
                actions.append(CompanionAction(title: "Adjust remaining week", systemImage: "arrow.triangle.2.circlepath", primary: true) {
                    adjustingPlan = true
                    RautaSpeech.shared.say("Reshaping the rest of your week…", holds: true)
                    Task {
                        defer { adjustingPlan = false }
                        do {
                            // Saving the plan is what RAUTA answers with its
                            // result line; nothing more needs saying here.
                            let preview = try await TrainingWorkflow.previewAdjustedWeek(source: source)
                            try TrainingPlan.commit(preview)
                            WorkoutAudio.play(.planBuilt)
                        } catch {
                            Haptics.trigger(.warning)
                            let reason = (error as? TrainingPersistenceError)?.message ?? error.localizedDescription
                            RautaSpeech.shared.say("I couldn't adjust your week. \(reason)")
                        }
                    }
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
            if workoutDetailActionState.canRegenerate {
                actions.append(
                    CompanionAction(title: "Try another workout", systemImage: "arrow.clockwise") {
                        workoutDetailActionRequest = .regenerate
                    }
                )
            }
            if !workoutDetailActionState.isEmpty {
                actions.append(
                    CompanionAction(title: "Reuse workout", systemImage: "arrow.triangle.2.circlepath") {
                        workoutDetailActionRequest = .reuse
                    }
                )
            }

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
            finishActiveWorkout()
        })
        return actions
    }
    private func startExerciseFlow() {
        filters.reset(); filters.setEquipment(filters.gymEquipment)
        navigation.selectedIds = []
        navigation.push(.addExercises(preferredWorkoutId: nil), from: RautaNativeTabControl.zoomSourceID)
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
                withAnimation(Theme.Motion.settleSlow) {
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
        // The session only closes once its records are written; a refused
        // write leaves it open to try again rather than pretending it saved.
        switch activeWorkout.finish() {
        case .failed(let reason):
            Haptics.trigger(.warning)
            finishIssue = reason
        case .saved(let receipt):
            WorkoutAudio.play(.workoutFinish)
            closeExercisePlayer()
            selectMainTab(.summary)
            // Drawn under the player as it closes, so the player shrinks away
            // to reveal RAUTA celebrating.
            withAnimation(.easeOut(duration: 0.25)) { celebration = receipt }
        }
    }

    /// RAUTA is in its seat: the tab bar's one takes over in the same frame —
    /// no crossfade, which showed two characters at once — and the greeting
    /// rises as it settles.
    private func landIntro() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            introPlaying = false
            introHandover = false
        }
        Task {
            try? await Task.sleep(for: .seconds(0.12))
            greet(reaction: nil)
        }
    }

    private func closeCelebration() {
        withAnimation(.easeInOut(duration: 0.3)) { celebration = nil }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            greet()
        }
    }

    private func updateRautaCompactState(_ compact: Bool) {
        guard compact != rautaCompact else { return }
        withAnimation(Theme.Motion.settle) {
            rautaCompact = compact
        }
    }

    private func restSeconds(for exerciseId: String) -> Double {
        TrainingSessionBridge.activePrescriptions()[exerciseId]?.restSeconds ?? PlannedExercisePrescription.fallbackRestSeconds
    }
}
