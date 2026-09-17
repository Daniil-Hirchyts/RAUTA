import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum WorkoutDetailExternalAction: Hashable {
    case start
    case share
    case duplicate
    case addExercise
    case delete
}

struct WorkoutDetailActionState: Equatable {
    var workoutId: String?
    var canStart = false
    var isEmpty = false
    var canEdit = false
    var canDelete = false

    static let none = WorkoutDetailActionState(workoutId: nil)
}

struct WorkoutDetailScreen: View {
    private let store = AppStore.shared
    let workoutId: String
    var onOpenExercisePlayer: (() -> Void)? = nil
    var onBackToWorkouts: (() -> Void)? = nil
    var onReplaceWorkout: ((String) -> Void)? = nil
    var externalActionRequest: Binding<WorkoutDetailExternalAction?>? = nil
    var onActionStateChange: ((WorkoutDetailActionState) -> Void)? = nil

    @State private var tab = 0
    @State private var confirmation: ConfirmationKind?
    @State private var issue: String?
    @State private var showingDate = false
    @State private var countingDown = false
    @State private var sharePayload: WorkoutSharePayload?

    private var workout: Workout? { store.workouts.workout(workoutId) }
    private var session: ActiveWorkoutSession? {
        guard store.activeWorkout.session?.workoutId == workoutId else { return nil }
        return store.activeWorkout.session
    }
    private var planned: PlannedSessionView? {
        guard let reference = workout?.planned else { return nil }
        return TrainingPlan.plannedSessionView(reference.programId, reference.sessionId)
    }
    /// What each exercise is prescribed, by exercise. The plan's snapshot answers,
    /// except while this workout runs: then its draft does, because the draft
    /// also knows the exercises swapped in or added since it started.
    private var prescriptions: [String: PlannedExercisePrescription] {
        var byExercise: [String: PlannedExercisePrescription] = [:]
        for item in planned?.prescription ?? [] where byExercise[item.exerciseId] == nil {
            byExercise[item.exerciseId] = item
        }
        if session != nil {
            byExercise.merge(TrainingSessionBridge.activePrescriptions()) { _, active in active }
        }
        return byExercise
    }
    private var isPast: Bool { session == nil && workout?.completion != nil }
    private var hasAnotherActiveWorkout: Bool {
        guard let active = store.activeWorkout.session else { return false }
        return active.workoutId != workoutId
    }
    private var plannedUnavailable: Bool {
        guard let reference = workout?.planned else { return false }
        return planned == nil || !ProgramRecords.isStartablePlannedSession(
            store.trainingRecords.data,
            reference.programId,
            reference.sessionId
        )
    }
    /// The exercise rows to show. `reorderable()` needs one unconditional view
    /// per element, so ids missing from the catalogue are dropped here rather
    /// than inside the `ForEach` body — a conditional there traps the lift.
    private func resolvedExercises(_ workout: Workout) -> [ExerciseSummary] {
        workout.exerciseIds.compactMap { ExerciseCatalogue.byId[$0] }
    }

    private var canEditWorkout: Bool {
        guard let workout, !isPast, !plannedUnavailable else { return false }
        return workout.planned == nil || !hasAnotherActiveWorkout
    }
    private var canDeleteWorkout: Bool { canEditWorkout }
    private var canStartWorkout: Bool {
        !isPast && !plannedUnavailable && store.activeWorkout.session == nil
    }
    var body: some View {
        ZStack {
            if let workout {
                if let session {
                    activeWorkoutPage(workout, session: session)
                } else if isPast {
                    RautaScreen(
                        title: CalendarDate.long(workout.date),
                        backLabel: "Back to workouts",
                        onBack: backToWorkouts,
                        content: { content(workout) }
                    )
                } else {
                    standardWorkoutScreen(workout)
                }
            } else {
                Color.clear.onAppear(perform: backToWorkouts)
            }

            ConfirmModal(
                kind: confirmation,
                error: issue,
                onCancel: { confirmation = nil; issue = nil },
                onConfirm: confirmAction
            )

            if countingDown {
                WorkoutStartCountdown(
                    onCancel: { countingDown = false },
                    onComplete: {
                        countingDown = false
                        start()
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }

            if let workout, session == nil, !isPast {
                WorkoutDateCalendarModal(
                    isPresented: showingDate,
                    date: workout.date,
                    onClose: { showingDate = false },
                    onSelect: reschedule
                )
                .zIndex(9)
            }
        }
        .sheet(item: $sharePayload) { payload in
            WorkoutActivityShareView(text: payload.text)
        }
        .onAppear(perform: publishCompanionActions)
        .onChange(of: companionActionSignature) { _, _ in
            publishCompanionActions()
        }
        .onChange(of: externalActionRequest?.wrappedValue) { _, action in
            guard let action else { return }
            handleExternalAction(action)
            externalActionRequest?.wrappedValue = nil
        }
    }

    private func standardWorkoutScreen(_ workout: Workout) -> some View {
        RautaScreen(
            title: CalendarDate.long(workout.date),
            subtitle: progressLabel,
            subtitleProgress: headerProgress,
            onTitleTap: canEditWorkout ? {
                Haptics.trigger(.light)
                showingDate = true
            } : nil,
            backLabel: "Back to workouts",
            onBack: backToWorkouts,
            content: { content(workout) }
        )
    }

    private func backToWorkouts() {
        onBackToWorkouts?()
    }

    private func activeWorkoutPage(_ workout: Workout, session: ActiveWorkoutSession) -> some View {
        RautaScreen(
            title: CalendarDate.long(workout.date),
            subtitle: progressLabel,
            subtitleProgress: headerProgress,
            backLabel: onBackToWorkouts == nil ? nil : "Back to workouts",
            onBack: onBackToWorkouts
        ) {
            activeWorkoutContent(workout, session: session)
        }
    }

    private func activeWorkoutContent(_ workout: Workout, session: ActiveWorkoutSession) -> some View {
        let prescriptions = prescriptions
        let rows = resolvedExercises(workout)
        return ScrollView {
            LazyVStack(spacing: 18) {
                RunningWorkoutOverview(
                    session: session,
                    sets: workout.exerciseIds.compactMap { prescriptions[$0]?.sets }.reduce(0, +)
                )

                ForEach(rows) { exercise in
                    let id = exercise.id
                    WorkoutExerciseRow(
                        exercise: exercise,
                        index: rows.firstIndex(of: exercise) ?? 0,
                        prescription: prescriptions[id],
                        status: ActiveWorkout.status(session, id),
                        canFindAlternative: canEditWorkout,
                        canRemove: canEditWorkout,
                        onOpen: {
                            if session.currentExerciseId != id {
                                store.activeWorkout.setCurrentExercise(id)
                            }
                            onOpenExercisePlayer?()
                        },
                        onAlternative: { openAlternative(id) },
                        onToggle: { store.activeWorkout.toggleComplete(id) },
                        onRemove: { remove(id) },
                        onMove: canEditWorkout ? { move(id, by: $0, among: rows) } : nil
                    )
                }
                .reorderable()
            }
            .reorderContainer(for: ExerciseSummary.self, isEnabled: canEditWorkout) { difference in
                updateExercises(
                    workout.exerciseIds.applyingReorder(difference),
                    moved: difference.sources.first
                )
            }
            .padding(.bottom, 188)
        }
        .pageScroll()
        .swipeActionsContainer()
    }

    private var progressLabel: String? {
        guard let session else { return nil }
        let progress = ActiveWorkout.progress(session)
        return "\(progress.completed) of \(progress.total) done"
    }

    private var headerProgress: [HeaderProgressState]? {
        guard let session else { return nil }
        return session.exerciseIds.map { id in
            if session.completedIds.contains(id) { return .completed }
            if session.currentExerciseId == id { return .current }
            return .pending
        }
    }

    private func content(_ workout: Workout) -> some View {
        let prescriptions = prescriptions
        let rows = resolvedExercises(workout)
        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    // In React the tabs are the first item inside the same
                    // scroll region as the workout body. Keeping them here
                    // makes the shell's top content margin place them below
                    // the floating header instead of behind the Dynamic Island.
                    if session != nil {
                        SlidingTabs(
                            tabs: [
                                TabDefinition(label: "Exercise", count: nil),
                                TabDefinition(label: "Workout", count: nil),
                            ],
                            activeIndex: $tab
                        )
                    }

                        if (session == nil || tab == 1) && (isPast || planned != nil) {
                            WorkoutOverview(workout: workout, past: isPast, planned: planned)
                        }

                        if workout.exerciseIds.isEmpty {
                            Text("This workout is empty. Add an exercise to start building it.")
                                .font(Theme.sans(16))
                                .foregroundStyle(Theme.mutedForeground)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 280)
                                .frame(maxWidth: .infinity, minHeight: 288)
                                .padding(.horizontal, 24)
                        } else if let session, tab == 0 {
                            if let currentId = session.currentExerciseId,
                               let exercise = ExerciseCatalogue.byId[currentId] {
                                LiveExerciseCard(
                                    exercise: exercise,
                                    restSeconds: prescriptions[currentId]?.restSeconds ?? 90,
                                    onDetail: {
                                        store.navigation.push(
                                            .exerciseDetail(exerciseId: exercise.id),
                                            from: "live-exercise:\(exercise.id)"
                                        )
                                    }
                                )
                            } else {
                                Text("Every exercise in this workout is done.")
                                    .font(Theme.sans(14))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                        } else {
                            LazyVStack(spacing: 20) {
                                ForEach(rows) { exercise in
                                    let id = exercise.id
                                    WorkoutExerciseRow(
                                        exercise: exercise,
                                        index: rows.firstIndex(of: exercise) ?? 0,
                                        prescription: prescriptions[id],
                                        status: session.map { ActiveWorkout.status($0, id) },
                                        canFindAlternative: canEditWorkout,
                                        canRemove: canEditWorkout,
                                        onOpen: {
                                            store.navigation.push(
                                                .exerciseDetail(exerciseId: id),
                                                from: "workout-exercise:\(id)"
                                            )
                                        },
                                        onAlternative: { openAlternative(id) },
                                        onToggle: { store.activeWorkout.toggleComplete(id) },
                                        onRemove: { remove(id) },
                                        onMove: canEditWorkout ? { move(id, by: $0, among: rows) } : nil
                                    )
                                }
                                .reorderable()
                            }
                            .reorderContainer(
                                for: ExerciseSummary.self,
                                isEnabled: canEditWorkout
                            ) { difference in
                                updateExercises(
                                    workout.exerciseIds.applyingReorder(difference),
                                    moved: difference.sources.first
                                )
                            }
                        }
                }
                .padding(.bottom, 188)
            }
            .pageScroll()
            .swipeActionsContainer()

            if let session {
                WorkoutSessionDock(
                    session: session,
                    exercise: ActiveWorkout.currentExercise(session),
                    onNext: nextExercise(session).map { id in
                        { store.activeWorkout.setCurrentExercise(id) }
                    },
                    onPause: store.activeWorkout.pause,
                    onResume: store.activeWorkout.resume
                )
            }
        }
    }

    private func nextExercise(_ session: ActiveWorkoutSession) -> String? {
        guard let current = session.currentExerciseId else { return nil }
        return ActiveWorkout.nextPendingExerciseId(session, from: current)
    }

    private func start() {
        guard let workout else { return }
        if !store.activeWorkout.start(workout) {
            issue = "This workout could not be started. Finish the current session or refresh its plan."
        } else {
            tab = 0
            Haptics.trigger(.success)
        }
    }

    private func duplicate() {
        Task {
            do {
                let id = try await EngineWorkout.duplicateWithEngine(workoutId, date: CalendarDate.today)
                onReplaceWorkout?(id)
                Haptics.trigger(.success)
            } catch { capture(error) }
        }
    }

    private func reschedule(_ date: String) {
        do {
            try TrainingEdits.rescheduleWorkout(workoutId, date: date)
            showingDate = false
        } catch { capture(error) }
    }

    private func openAlternative(_ exerciseId: String) {
        if workout?.planned != nil,
           session != nil,
           let draftExercise = store.trainingRecords.data.activeWorkout?.exercises.first(where: {
               $0.exerciseId == exerciseId
           }),
           draftExercise.sets.contains(where: { $0.observation != nil }) {
            issue = "This exercise already has recorded sets, so it can’t be replaced in this session."
            Haptics.trigger(.warning)
            return
        }
        issue = nil
        store.navigation.push(
            .exerciseAlternatives(exerciseId: exerciseId, workoutId: workoutId),
            from: "workout-exercise:\(exerciseId)"
        )
    }

    private func beginExerciseFlow(preferredWorkoutId: String) {
        store.filters.reset()
        store.filters.setEquipment(store.filters.gymEquipment)
        store.navigation.selectedIds = []
        // Asked for from RAUTA's menu, so the flow grows out of RAUTA.
        store.navigation.push(.addExercises(preferredWorkoutId: preferredWorkoutId), from: RautaNativeTabControl.zoomSourceID)
    }

    /// One place up or down: the accessible form of dragging a row.
    private func move(_ id: String, by offset: Int, among rows: [ExerciseSummary]) {
        guard let workout else { return }
        let ids = workout.exerciseIds.movingElement(id, by: offset, visible: Set(rows.map(\.id)))
        guard ids != workout.exerciseIds else { return }
        updateExercises(ids, moved: id)
        let position = ids.filter { id in rows.contains { $0.id == id } }.firstIndex(of: id).map { $0 + 1 } ?? 0
        AccessibilityNotification.Announcement("Moved to position \(position) of \(rows.count)").post()
    }

    private func remove(_ id: String) {
        guard let workout else { return }
        updateExercises(workout.exerciseIds.filter { $0 != id })
    }

    private func updateExercises(_ ids: [String], moved: String? = nil) {
        do {
            if session != nil {
                store.workouts.updateWorkout(workoutId, .init(exerciseIds: ids))
                store.activeWorkout.syncExercises(ids, movedExerciseId: moved)
            } else {
                try TrainingEdits.updateScheduledWorkoutExercises(workoutId, ids)
            }
        } catch { capture(error) }
    }

    private func confirmAction() {
        do {
            switch confirmation {
            case .deleteWorkout:
                try TrainingEdits.deleteScheduledWorkout(workoutId)
                confirmation = nil
                backToWorkouts()
            default:
                confirmation = nil
            }
        } catch { capture(error) }
    }

    private func capture(_ error: Error) {
        issue = (error as? TrainingPersistenceError)?.message ?? error.localizedDescription
        Haptics.trigger(.warning)
    }

    private var companionActionSignature: String {
        guard let workout else { return "missing" }
        return [
            workout.id,
            session == nil ? "idle" : "active",
            isPast ? "past" : "future",
            canEditWorkout ? "editable" : "locked",
            canStartWorkout ? "startable" : "blocked",
            String(workout.exerciseIds.count),
        ].joined(separator: "|")
    }

    private func publishCompanionActions() {
        guard let workout,
              session == nil
        else {
            onActionStateChange?(.none)
            return
        }
        onActionStateChange?(
            WorkoutDetailActionState(
                workoutId: workout.id,
                canStart: canStartWorkout,
                isEmpty: workout.exerciseIds.isEmpty,
                canEdit: canEditWorkout,
                canDelete: canDeleteWorkout
            )
        )
    }

    private func handleExternalAction(_ action: WorkoutDetailExternalAction) {
        guard let workout else { return }
        switch action {
        case .start:
            guard canStartWorkout, !workout.exerciseIds.isEmpty else { return }
            Haptics.trigger(.heavy)
            countingDown = true
        case .share:
            sharePayload = WorkoutSharePayload(text: WorkoutSharing.text(workout))
        case .duplicate:
            duplicate()
        case .addExercise:
            beginExerciseFlow(preferredWorkoutId: workout.id)
        case .delete:
            guard canDeleteWorkout else { return }
            Haptics.trigger(.warning)
            confirmation = .deleteWorkout
        }
    }
}

private struct WorkoutSharePayload: Identifiable {
    let id = UUID()
    let text: String
}

private struct WorkoutActivityShareView: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct WorkoutStartCountdown: View {
    @State private var remaining = 3
    let onCancel: () -> Void
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .background(Theme.shell.opacity(0.72))
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Text("GET READY")
                    .font(Theme.sans(12, weight: .black))
                    .kerning(2)
                    .foregroundStyle(Theme.primary)

                Button { remaining = 0 } label: {
                    ZStack {
                        Circle()
                            .stroke(Theme.border, lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: CGFloat(remaining) / 3)
                            .stroke(Theme.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.25), value: remaining)
                        Text("\(max(remaining, 1))")
                            .font(Theme.readout(88))
                            .foregroundStyle(Theme.foreground)
                            .contentTransition(.numericText())
                    }
                    .frame(width: 184, height: 184)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start now")

                AppButton("Cancel", variant: .secondary, size: .cta, action: onCancel)
                    .frame(maxWidth: 288)
            }
        }
        .task(id: remaining) {
            if remaining <= 0 {
                WorkoutAudio.go()
                Haptics.trigger(.heavy)
                onComplete()
                return
            }
            WorkoutAudio.tick()
            Haptics.trigger(.light)
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            remaining -= 1
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Starting workout")
    }
}

struct CurrentExerciseAccessory: View {
    private let store = AppStore.shared
    let exercise: ExerciseSummary
    let onOpen: () -> Void
    let compact: Bool

    private var draft: PersistedActiveExerciseDraft? {
        TrainingSessionBridge.draftExercise(store.trainingRecords.data.activeWorkout, exercise.id)
    }

    private var repsText: String {
        if let set = draft?.sets.first(where: { $0.observation?.completed != true }) {
            if let reps = set.observation?.reps {
                return "\(Num.trimmed(reps)) reps"
            }
            if let target = set.target?.reps {
                return repRangeText(target)
            }
        }
        if let reps = draft?.sets.reversed().compactMap({ $0.observation?.reps }).first {
            return "\(Num.trimmed(reps)) reps"
        }
        if let target = draft?.sets.compactMap({ $0.target?.reps }).first {
            return repRangeText(target)
        }
        return "— reps"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: compact ? 8 : 10) {
                // Always on screen with the tab bar: a still, not a loop.
                ExerciseMediaView(exerciseId: exercise.id)
                    .frame(width: compact ? 30 : 42, height: compact ? 30 : 42)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 10, style: .continuous))

                VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                    Text(exercise.name.capitalized)
                        .font(Theme.sans(compact ? 13 : 16, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    Text(repsText)
                        .font(Theme.sans(compact ? 10 : 11, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                }
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)

                setTimer
            }
            .padding(.horizontal, compact ? 10 : 12)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .frame(height: compact ? 50 : 62)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(exercise.name.capitalized), Current exercise")
        .accessibilityHint("Opens the current exercise")
        // A fixed-height bar accessory: text grows while it still fits.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: compact)
    }

    private var setTimer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let session = store.activeWorkout.session
            let restUntil = session?.restUntil.map { Date(timeIntervalSince1970: $0 / 1_000) }
            let remaining = restUntil.map { $0.timeIntervalSince(context.date) } ?? -1
            let isResting = remaining > 0
            let anchor = session.map {
                Date(timeIntervalSince1970: ($0.setPhaseStartedAt ?? $0.startedAt) / 1_000)
            } ?? context.date
            let seconds = isResting
                ? Int(remaining.rounded(.up))
                : Swift.max(0, Int(context.date.timeIntervalSince(anchor).rounded(.down)))

            VStack(alignment: .trailing, spacing: compact ? 0 : 1) {
                Text(isResting ? "REST" : "SET")
                    .font(Theme.sans(compact ? 7 : 8, weight: .black))
                    .kerning(0.8)
                    .foregroundStyle(isResting ? Theme.primary : Theme.mutedForeground)
                Text(clock(seconds))
                    .font(Theme.sans(compact ? 11 : 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.foreground)
            }
            .frame(width: compact ? 42 : 52, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isResting ? "Rest timer, \(clock(seconds))" : "Set timer, \(clock(seconds))")
        }
    }

    private func repRangeText(_ range: RepRange) -> String {
        if range.min == range.max {
            return "\(Num.trimmed(range.max)) reps"
        }
        return "\(Num.trimmed(range.min))–\(Num.trimmed(range.max)) reps"
    }

    private func clock(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

struct ActiveExerciseDrawer: View {
    private let store = AppStore.shared
    private let activeWorkout = ActiveWorkoutStore.shared
    let exercise: ExerciseSummary
    let session: ActiveWorkoutSession
    let restSeconds: Double
    let onDetail: () -> Void
    let hasNextExercise: Bool
    let onFinishExercise: () -> Void
    let onFinish: () -> Void
    let onDismiss: () -> Void
    @State private var revealDetails = false

    var body: some View {
        Group {
            if let liveSession = activeWorkout.session,
               ActiveWorkout.progress(liveSession).isComplete {
                CompletedWorkoutDrawer(
                    session: liveSession,
                    onFinish: onFinish,
                    onDismiss: onDismiss
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                // Dragging the player down is the zoom transition's own
                // dismissal: the system follows the finger and throws the
                // player back into the accessory it grew from.
                GeometryReader { proxy in
                    playerSurface(proxy)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.24), value: store.activeWorkout.session.map { ActiveWorkout.progress($0).isComplete } ?? false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.22).delay(0.12)) {
                revealDetails = true
            }
        }
        .accessibilityAddTraits(.isModal)
        // The zoom dismissal is a drag; VoiceOver's scrub closes it too.
        .accessibilityAction(.escape, onDismiss)
    }

    private func playerSurface(_ proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            GeometryReader { mediaProxy in
                let mediaSize = max(
                    0,
                    min(336, min(proxy.size.width - 32, mediaProxy.size.height))
                )

                // A tap rather than a button: a button holds on to a touch that
                // starts on it, and this is the biggest thing a drag down to
                // close the player starts on.
                ExerciseMediaView(exerciseId: exercise.id, animated: true)
                    .frame(width: mediaSize, height: mediaSize)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDetail)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Open \(exercise.name) details")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .padding(.top, Swift.max(proxy.safeAreaInsets.top, 18) + 24)
            .frame(maxWidth: .infinity)
            .layoutPriority(-1)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name.capitalized)
                        .font(Theme.sans(24, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(trainedMusclesText)
                        .font(Theme.sans(13, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LikeButton(
                    liked: store.favorites.isFavorite(exercise.id),
                    label: store.favorites.isFavorite(exercise.id)
                        ? "Remove \(exercise.name) from favorites"
                        : "Add \(exercise.name) to favorites",
                    size: 36,
                    iconSize: 18,
                    chromeless: true
                ) {
                    store.favorites.toggleFavorite(exercise.id)
                }

                Menu {
                    Button {
                        Haptics.trigger(.selection)
                        if store.activeWorkout.session?.runningSince == nil {
                            store.activeWorkout.resume()
                        } else {
                            store.activeWorkout.pause()
                        }
                    } label: {
                        Label(
                            store.activeWorkout.session?.runningSince == nil ? "Resume workout" : "Pause workout",
                            systemImage: store.activeWorkout.session?.runningSince == nil ? "play.fill" : "pause.fill"
                        )
                    }
                    Button {
                        onFinishExercise()
                    } label: {
                        Label("Finish exercise", systemImage: "flag.checkered")
                    }
                    Button {
                        onFinish()
                    } label: {
                        Label("Finish workout", systemImage: "flag.checkered")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Workout actions")
            }
            .padding(.horizontal, Theme.Metrics.contentInset)
            .padding(.top, 18)

            ActiveSetLog(
                exerciseId: exercise.id,
                restSeconds: restSeconds,
                hasNextExercise: hasNextExercise,
                onFinishExercise: onFinishExercise
            )
                .fixedSize(horizontal: false, vertical: true)
                .opacity(revealDetails ? 1 : 0)
                .offset(y: revealDetails ? 0 : 18)
                .padding(.top, 12)
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, Swift.max(proxy.safeAreaInsets.bottom, 14))
        }
        .background {
            ZStack {
                Theme.background
                LinearGradient(
                    colors: [Theme.primary.opacity(0.34), Theme.oxblood.opacity(0.38), .clear],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                AppGrain()
            }
            .ignoresSafeArea()
        }
    }

    private var trainedMusclesText: String {
        let labels = exercise.muscles.map(\.label)
        return labels.isEmpty ? "Full body" : labels.joined(separator: " · ")
    }
}

struct CompletedWorkoutDrawer: View {
    private let store = AppStore.shared
    let session: ActiveWorkoutSession
    let onFinish: () -> Void
    let onDismiss: () -> Void

    private var liveSession: ActiveWorkoutSession {
        store.activeWorkout.session ?? session
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: Swift.max(proxy.safeAreaInsets.top, 18) + 48)

                RautaCharacter(mood: .focused)
                    .frame(width: 118, height: 118)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text(liveSession.workoutName)
                        .font(Theme.sans(30, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text("All exercises complete")
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)

                    AppButton("Finish workout", size: .cta, expands: true, action: onFinish)
                        .frame(maxWidth: 280)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 28)

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(ActiveWorkout.formatDuration(ActiveWorkout.elapsedMs(liveSession)))
                        .font(Theme.readout(72))
                        .monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)
                }
                .padding(.top, 34)

                HStack(spacing: 28) {
                    workoutMetric(
                        value: "\(ActiveWorkout.progress(liveSession).completed)",
                        label: "Exercises"
                    )
                    workoutMetric(
                        value: liveSession.runningSince == nil ? "Paused" : "Running",
                        label: "Workout"
                    )
                }
                .padding(.top, 16)
                .padding(.horizontal, 28)

                Spacer(minLength: Swift.max(proxy.safeAreaInsets.bottom, 24))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background {
                ZStack {
                    Theme.background
                    LinearGradient(
                        colors: [Theme.primary.opacity(0.34), Theme.oxblood.opacity(0.38), .clear],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                    AppGrain()
                }
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        // The zoom dismissal is a drag; VoiceOver's scrub closes it too.
        .accessibilityAction(.escape, onDismiss)
    }

    private func workoutMetric(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.sans(20, weight: .bold))
                .foregroundStyle(Theme.foreground)
            Text(label.uppercased())
                .font(Theme.sans(9, weight: .black))
                .kerning(1.5)
                .foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RunningWorkoutOverview: View {
    let session: ActiveWorkoutSession
    /// Working sets across the workout as it now stands.
    let sets: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.runningSince == nil ? "PAUSED" : "IN PROGRESS")
                        .font(Theme.sans(11, weight: .black))
                        .kerning(1.8)
                        .foregroundStyle(Theme.primary)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(ActiveWorkout.formatDuration(ActiveWorkout.elapsedMs(session)))
                            .font(Theme.readout(58))
                            .foregroundStyle(Theme.foreground)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "checklist")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 58, height: 58)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 18)

            HStack(spacing: 0) {
                metric("square.stack.3d.up", value: String(sets), label: "Sets")
                Rectangle().fill(Theme.foreground.opacity(0.16)).frame(width: 1).padding(.vertical, 4)
                metric("clock", value: elapsedMinutes, label: "Minutes")
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Theme.primary.opacity(0.24), Theme.oxblood.opacity(0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, Theme.Metrics.contentInset)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var elapsedMinutes: String {
        String(max(0, Int(ActiveWorkout.elapsedMs(session) / 60_000)))
    }

    private func metric(_ icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.primary)
            Text(value).font(Theme.readout(22)).foregroundStyle(Theme.foreground)
            Text(label.uppercased())
                .font(Theme.sans(9, weight: .black))
                .kerning(1.6)
                .foregroundStyle(Theme.foreground.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

private struct WorkoutOverview: View {
    let workout: Workout
    let past: Bool
    let planned: PlannedSessionView?

    private var signal: Color { past ? Theme.success : Theme.primary }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(past ? "COMPLETED" : "EXERCISES")
                        .font(Theme.sans(11, weight: .black))
                        .kerning(1.8)
                        .foregroundStyle(signal)
                    Text(primaryValue)
                        .font(Theme.readout(58))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
                Spacer(minLength: 4)
                Image(systemName: past ? "checkmark.circle" : "checklist")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(signal)
                    .frame(width: 58, height: 58)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 18)

            HStack(spacing: 0) {
                metric(
                    icon: past ? "clock" : "square.stack.3d.up",
                    value: secondaryValue,
                    label: past ? "Duration" : "Sets"
                )
                Rectangle()
                    .fill(Theme.foreground.opacity(0.16))
                    .frame(width: 1)
                    .padding(.vertical, 2)
                metric(
                    icon: past ? "waveform.path.ecg" : "clock",
                    value: tertiaryValue,
                    label: past ? "kcal" : "Minutes"
                )
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [signal.opacity(0.24), Theme.oxblood.opacity(0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, Theme.Metrics.contentInset)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var primaryValue: String {
        if past {
            let completed = workout.completion?.completedExerciseIds.count ?? 0
            return "\(completed)/\(workout.exerciseIds.count)"
        }
        return String(format: "%02d", planned?.prescription.count ?? workout.exerciseIds.count)
    }

    private var secondaryValue: String {
        if past {
            guard let completion = workout.completion else { return "—" }
            return ActiveWorkout.formatDuration(completion.durationMs)
        }
        return planned.map { String($0.workingSets) } ?? "—"
    }

    private var tertiaryValue: String {
        if past {
            return workout.completion.map { String(Int($0.activeCalories)) } ?? "—"
        }
        return planned.map { String($0.minutes) } ?? "—"
    }

    private func metric(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(signal)
            Text(value)
                .font(Theme.readout(22))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label.uppercased())
                .font(Theme.sans(9, weight: .black))
                .kerning(1.6)
                .foregroundStyle(Theme.foreground.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

private struct LiveExerciseCard: View {
    let exercise: ExerciseSummary
    let restSeconds: Double
    let onDetail: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onDetail) {
                GeometryReader { hero in
                    ZStack(alignment: .bottom) {
                        ExerciseMediaView(exerciseId: exercise.id, animated: true)
                            .frame(width: hero.size.width, height: hero.size.height)
                            .background(Theme.card)

                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .frame(width: hero.size.width, height: 118)
                            .mask(
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.72), .white],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        .zIndex(1)
                        .allowsHitTesting(false)

                        // The caption sits on frosted glass, which is light in Light
                        // Mode: ink on it there, and a halo of the shell behind it.
                        Text(exercise.name.capitalized)
                            .font(Theme.sans(18, weight: .heavy))
                            .foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                            .shadow(color: Theme.shell.opacity(0.34), radius: 4, y: 1)
                            .frame(maxWidth: .infinity, alignment: .bottom)
                            .zIndex(2)
                    }
                    .frame(width: hero.size.width, height: hero.size.height)
                }
                .frame(height: min(380, DeviceScreen.width - Theme.Metrics.contentInset * 2))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous)
                        .strokeBorder(Theme.primary.opacity(0.30), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.20), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .appZoomSource("live-exercise:\(exercise.id)", cornerRadius: Theme.Radius.xl3)
            .accessibilityLabel("Open \(exercise.name) demonstration")

            ActiveSetLog(exerciseId: exercise.id, restSeconds: restSeconds)
        }
    }
}

private struct WorkoutExerciseRow: View {
    let exercise: ExerciseSummary
    let index: Int
    let prescription: PlannedExercisePrescription?
    let status: ExerciseStatus?
    let canFindAlternative: Bool
    let canRemove: Bool
    let onOpen: () -> Void
    let onAlternative: () -> Void
    let onToggle: () -> Void
    let onRemove: () -> Void
    /// Moves the row one place (-1 up, +1 down); nil where it cannot move.
    var onMove: ((Int) -> Void)? = nil

    var body: some View {
        card
            .appZoomSource("workout-exercise:\(exercise.id)", cornerRadius: Theme.Radius.xl2)
            // Attached to the card rather than the padded row so the actions
            // stay inside the content inset, where the hand-rolled ones sat.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if canRemove {
                    Button(role: .destructive) {
                        Haptics.trigger(.selection)
                        onRemove()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .accessibilityLabel("Remove \(exercise.name)")
                }
                if canFindAlternative {
                    Button {
                        Haptics.trigger(.selection)
                        onAlternative()
                    } label: {
                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .tint(Theme.primary)
                    .accessibilityLabel("Replace \(exercise.name)")
                }
            }
            .padding(.horizontal, Theme.Metrics.contentInset)
            // Dragging to reorder has no VoiceOver form of its own.
            .accessibilityActions {
                if let onMove {
                    Button("Move up") { onMove(-1) }
                    Button("Move down") { onMove(1) }
                }
            }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                    if let status {
                        Button(action: onToggle) {
                            AnimatedCheck(checked: status == .completed)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            status == .completed
                                ? "Mark \(exercise.name) as not done"
                                : "Mark \(exercise.name) as done"
                        )
                    } else {
                        Text(String(format: "%02d", index + 1))
                            .font(Theme.sans(16, weight: .bold))
                            .kerning(0.65)
                            .foregroundStyle(Theme.primary)
                    }
                }
                .frame(width: 50)
                .frame(maxHeight: .infinity)

                Button(action: onOpen) {
                    // A list row shows the poster; the demonstration plays
                    // when the exercise is opened.
                    ExerciseMediaView(exerciseId: exercise.id)
                        .frame(width: 136, height: 136)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(exercise.name) demonstration")

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name.capitalized)
                        .font(Theme.sans(17, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(3)
                    Text(Wording.titleCase(exercise.equipment))
                        .font(Theme.sans(14, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
                .padding(.leading, 14)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .frame(height: 148)

            if let prescription {
                WorkoutPrescriptionStrip(prescription: prescription)
            }
        }
        .contentShape(Rectangle())
        .background(Theme.card)
        .clipShape(
            RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
        )
    }
}

private struct WorkoutPrescriptionStrip: View {
    let prescription: PlannedExercisePrescription

    private var reps: String {
        prescription.reps.min == prescription.reps.max
            ? Num.trimmed(prescription.reps.max)
            : "\(Num.trimmed(prescription.reps.min))–\(Num.trimmed(prescription.reps.max))"
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                metric("Sets", String(prescription.sets), accent: true)
                metric("Reps", reps)
                metric("RIR", Num.trimmed(prescription.rir))
                if let loadKg = prescription.loadKg {
                    let each = prescription.loadBasis == .perImplement ? " each" : ""
                    metric("Load", "\(Resistance.formatKg(loadKg)) kg\(each)")
                }
                metric("Rest", "\(Int(prescription.restSeconds.rounded()))s")
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 15)
        }
        .background {
            LinearGradient(
                colors: [Theme.primary.opacity(0.09), .clear],
                startPoint: .leading,
                endPoint: UnitPoint(x: 0.78, y: 0.5)
            )
        }
    }

    private func metric(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(Theme.sans(10, weight: .black))
                .kerning(1.8)
                .foregroundStyle(Theme.foreground.opacity(0.62))
            Text(value)
                .font(Theme.readout(15))
                .foregroundStyle(accent ? Theme.primarySofter : Theme.foreground)
                .lineLimit(1)
        }
    }
}

private struct WorkoutSessionDock: View {
    let session: ActiveWorkoutSession
    let exercise: ExerciseSummary?
    let onNext: (() -> Void)?
    let onPause: () -> Void
    let onResume: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.runningSince == nil ? "PAUSED" : "IN PROGRESS")
                    .font(Theme.sans(10, weight: .bold))
                    .kerning(1.4)
                    .foregroundStyle(Theme.primary)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(ActiveWorkout.formatDuration(ActiveWorkout.elapsedMs(session)))
                        .font(Theme.readout(32))
                        .foregroundStyle(Theme.foreground)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)

            HStack(spacing: 6) {
                Button {
                    Haptics.trigger(.medium)
                    session.runningSince == nil ? onResume() : onPause()
                } label: {
                    Image(systemName: session.runningSince == nil ? "play.fill" : "pause.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                }
                .buttonStyle(.glassControl(.clear, .circle(diameter: 38)))
                .accessibilityLabel(session.runningSince == nil ? "Resume workout" : "Pause workout")

                Button {
                    Haptics.trigger(.light)
                    onNext?()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(onNext == nil ? Theme.mutedForeground : Theme.foreground)
                }
                .buttonStyle(
                    .glassControl(
                        onNext == nil ? .inert : .clear,
                        .circle(diameter: 38)
                    )
                )
                .disabled(onNext == nil)
                .accessibilityLabel(exercise.map { "Skip \($0.name)" } ?? "Next exercise")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 88)
        .glassSurface(.regular, in: shape)
        .padding(.horizontal, Theme.Metrics.contentInset)
        .padding(.bottom, Theme.Metrics.contentInset)
    }
}
