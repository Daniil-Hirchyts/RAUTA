import SwiftUI
import UIKit

enum WorkoutDetailExternalAction: Hashable {
    case start
    case share
    case reuse
    case regenerate
    case addExercise
    case delete
}

struct WorkoutDetailActionState: Equatable {
    var workoutId: String?
    var canStart = false
    var isEmpty = false
    var canEdit = false
    var canDelete = false
    /// RAUTA built it and nobody has started it: RAUTA can build it again.
    var canRegenerate = false

    static let none = WorkoutDetailActionState(workoutId: nil)
}

struct WorkoutDetailScreen: View {
    private let store = AppStore.shared
    let workoutId: String
    var onOpenExercisePlayer: (() -> Void)? = nil
    var onBackToWorkouts: (() -> Void)? = nil
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
    /// A workout from a replaced plan can still be trained or cleared away;
    /// only editing it as part of that plan is closed. A trained one can be
    /// cleared away too, taking its logged sets with it.
    private var canDeleteWorkout: Bool {
        guard store.activeWorkout.session?.workoutId != workoutId else { return false }
        return canEditWorkout || (plannedUnavailable && session == nil) || isPast
    }
    private var canStartWorkout: Bool {
        !isPast && store.activeWorkout.session == nil
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
        .task(id: workoutId) { await explainReplacedPlan() }
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
                        onToggle: { toggleComplete(id) },
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
                                    restSeconds: prescriptions[currentId]?.restSeconds ?? PlannedExercisePrescription.fallbackRestSeconds,
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
                                        onToggle: { toggleComplete(id) },
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

    /// Checks an exercise off, or back on; checking one off is a moment.
    private func toggleComplete(_ id: String) {
        if store.activeWorkout.session?.completedIds.contains(id) == false {
            WorkoutAudio.play(.exerciseDone)
        } else {
            Haptics.trigger(.selection, sound: .off)
        }
        store.activeWorkout.toggleComplete(id)
    }

    private func nextExercise(_ session: ActiveWorkoutSession) -> String? {
        guard let current = session.currentExerciseId else { return nil }
        return ActiveWorkout.nextPendingExerciseId(session, from: current)
    }

    private func start() {
        guard let workout else { return }
        let outcome = plannedUnavailable
            ? store.activeWorkout.startAsOwnWorkout(workout)
            : store.activeWorkout.start(workout)
        if let refusal = outcome.refusal {
            issue = refusal
        } else {
            // The countdown's last sound already marked the start.
            tab = 0
        }
    }

    /// Workouts RAUTA has already explained this launch, so opening one again
    /// is not a lecture.
    private static var explained: Set<String> = []

    /// Why this workout reads differently, once: its plan was replaced, and
    /// RAUTA will still run it.
    private func explainReplacedPlan() async {
        guard plannedUnavailable, !isPast, session == nil, !Self.explained.contains(workoutId) else { return }
        try? await Task.sleep(for: .seconds(0.6))
        guard !Task.isCancelled else { return }
        Self.explained.insert(workoutId)
        RautaSpeech.shared.say(
            "This one's from a plan you replaced. I can still run it as a one-off — tap me.",
            reaction: .peek
        )
    }

    /// RAUTA builds the workout again around the same muscles, in place.
    private func regenerate() {
        RautaSpeech.shared.working("Trying another combination…")
        Task {
            do {
                try await EngineWorkout.regenerate(workoutId)
                Haptics.trigger(.medium)
                RautaSpeech.shared.say("How about this one?", reaction: .wink)
            } catch {
                RautaSpeech.shared.hush()
                capture(error)
            }
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
            case .deleteWorkout, .deleteCompletedWorkout:
                try TrainingEdits.deleteWorkout(workoutId)
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
            EngineWorkout.canRegenerate(workout) ? "rebuildable" : "fixed",
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
                canDelete: canDeleteWorkout,
                canRegenerate: EngineWorkout.canRegenerate(workout)
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
        case .reuse:
            guard !workout.exerciseIds.isEmpty else { return }
            store.navigation.push(.reuseWorkout(sourceWorkoutId: workout.id), from: RautaNativeTabControl.zoomSourceID)
        case .regenerate:
            guard EngineWorkout.canRegenerate(workout) else { return }
            regenerate()
        case .addExercise:
            beginExerciseFlow(preferredWorkoutId: workout.id)
        case .delete:
            guard canDeleteWorkout else { return }
            Haptics.trigger(.warning)
            confirmation = TrainingEdits.isHistory(workout) ? .deleteCompletedWorkout : .deleteWorkout
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
                WorkoutAudio.play(.workoutStart)
                onComplete()
                return
            }
            WorkoutAudio.tick(secondsLeft: remaining)
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            remaining -= 1
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Starting workout")
    }
}
