import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct WorkoutDetailScreen: View {
    @ObservedObject private var store = AppStore.shared
    let workoutId: String

    @State private var tab = 0
    @State private var confirmation: ConfirmationKind?
    @State private var issue: String?
    @State private var showingDate = false
    @State private var countingDown = false
    @StateObject private var reorder = CardReorder()

    private var workout: Workout? { store.workouts.workout(workoutId) }
    private var session: ActiveWorkoutSession? {
        guard store.activeWorkout.session?.workoutId == workoutId else { return nil }
        return store.activeWorkout.session
    }
    private var planned: PlannedSessionView? {
        guard let reference = workout?.planned else { return nil }
        return TrainingPlan.plannedSessionView(reference.programId, reference.sessionId)
    }
    private var isPast: Bool { session == nil && workout?.completion != nil }
    private var plannedUnavailable: Bool {
        guard let reference = workout?.planned else { return false }
        return planned == nil || !ProgramRecords.isStartablePlannedSession(
            store.trainingRecords.data,
            reference.programId,
            reference.sessionId
        )
    }
    private var finishConfirmation: ConfirmationKind {
        TrainingSessionBridge.activePlannedCoverage()?.complete == false
            ? .finishWorkoutPartial
            : .finishWorkout
    }

    var body: some View {
        ZStack {
            if let workout {
                RautaScreen(
                    title: CalendarDate.long(workout.date),
                    subtitle: progressLabel,
                    subtitleProgress: headerProgress,
                    onTitleTap: session == nil && !isPast ? {
                        Haptics.trigger(.light)
                        showingDate = true
                    } : nil,
                    backLabel: "Back to workouts",
                    onBack: store.navigation.pop,
                    content: { content(workout) },
                    controls: { controls(workout) }
                )
            } else {
                Color.clear.onAppear(perform: store.navigation.pop)
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
        ZStack(alignment: .bottom) {
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

                        if plannedUnavailable || issue != nil {
                            InlineNotice(
                                message: issue ?? "This planned session is no longer available. Create a current plan from My workouts.",
                                isError: true
                            )
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
                                    restSeconds: planned?.prescription.first { $0.exerciseId == currentId }?.restSeconds ?? 90,
                                    onDetail: { store.navigation.push(.exerciseDetail(exerciseId: exercise.id)) }
                                )
                            } else {
                                Text("Every exercise in this workout is done.")
                                    .font(Theme.sans(14))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                        } else {
                            ForEach(Array(workout.exerciseIds.enumerated()), id: \.element) { index, id in
                                if let exercise = ExerciseCatalogue.byId[id] {
                                    WorkoutExerciseRow(
                                        exercise: exercise,
                                        index: index,
                                        prescription: planned?.prescription.first { $0.exerciseId == id },
                                        status: session.map { ActiveWorkout.status($0, id) },
                                        canFindAlternative: !isPast && !plannedUnavailable,
                                        canRemove: !isPast,
                                        canReorder: !isPast,
                                        exerciseIds: workout.exerciseIds,
                                        reorder: reorder,
                                        onOpen: { store.navigation.push(.exerciseDetail(exerciseId: id)) },
                                        onAlternative: { openAlternative(id) },
                                        onToggle: { store.activeWorkout.toggleComplete(id) },
                                        onReorder: { ids, moved in updateExercises(ids, moved: moved) },
                                        onRemove: { remove(id) }
                                    )
                                }
                            }
                        }
                }
                .padding(Theme.Metrics.contentInset)
                .padding(.top, session == nil ? 0 : 8)
                .padding(.bottom, session == nil ? 24 : 144)
            }
            .scrollDisabled(reorder.active != nil)
            .onDisappear { reorder.cancel() }

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

    @ViewBuilder private func controls(_ workout: Workout) -> some View {
        if let session {
            HStack(spacing: 8) {
                AppMenuButton(label: "Workout actions") {
                    shareAction(workout)
                    Button {
                        beginExerciseFlow(preferredWorkoutId: workout.id)
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                    Button {
                        Haptics.trigger(.medium)
                        confirmation = finishConfirmation
                    } label: {
                        Label("Finish workout", systemImage: "flag")
                    }
                    Button(role: .destructive) {
                        Haptics.trigger(.warning)
                        confirmation = .discardSession
                    } label: {
                        Label("Discard session", systemImage: "xmark")
                    }
                }
                if session.currentExerciseId != nil {
                    AppButton("Mark done", size: .cta, expands: true) {
                        Haptics.trigger(.success)
                        store.activeWorkout.completeCurrent()
                    }
                } else {
                    AppButton("Finish", size: .cta, expands: true) {
                        Haptics.trigger(.medium)
                        confirmation = finishConfirmation
                    }
                }
            }
        } else if isPast {
            HStack(spacing: 8) {
                AppMenuButton(label: "Workout actions") {
                    shareAction(workout)
                    Button(action: duplicate) {
                        Label("Copy to today", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        Haptics.trigger(.warning)
                        confirmation = .deleteWorkout
                    } label: {
                        Label("Delete workout", systemImage: "trash")
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 8) {
                AppMenuButton(label: "Workout actions") {
                    shareAction(workout)
                    Button(action: duplicate) {
                        Label("Copy to today", systemImage: "doc.on.doc")
                    }
                    if !workout.exerciseIds.isEmpty {
                        Button {
                            beginExerciseFlow(preferredWorkoutId: workout.id)
                        } label: {
                            Label("Add exercise", systemImage: "plus")
                        }
                    }
                    Button(role: .destructive) {
                        Haptics.trigger(.warning)
                        confirmation = .deleteWorkout
                    } label: {
                        Label("Delete workout", systemImage: "trash")
                    }
                }
                AppButton(
                    plannedUnavailable
                        ? "Plan unavailable"
                        : (workout.exerciseIds.isEmpty ? "Add exercise" : "Start workout"),
                    size: .cta,
                    isDisabled: plannedUnavailable,
                    expands: true
                ) {
                    if workout.exerciseIds.isEmpty {
                        beginExerciseFlow(preferredWorkoutId: workout.id)
                    } else {
                        Haptics.trigger(.heavy)
                        countingDown = true
                    }
                }
            }
        }
    }

    private func shareAction(_ workout: Workout) -> some View {
        ShareLink(
            item: WorkoutSharing.text(workout),
            subject: Text(WorkoutSharing.title(workout))
        ) {
            Label("Share workout", systemImage: "square.and.arrow.up")
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
        do {
            let id = try EngineWorkout.duplicateWithEngine(workoutId, date: CalendarDate.today)
            store.navigation.replace(.workoutDetail(workoutId: id))
            Haptics.trigger(.success)
        } catch { capture(error) }
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
        store.navigation.push(.exerciseAlternatives(exerciseId: exerciseId, workoutId: workoutId))
    }

    private func beginExerciseFlow(preferredWorkoutId: String) {
        store.filters.reset()
        store.filters.setEquipment(store.filters.gymEquipment)
        store.navigation.selectedIds = []
        store.navigation.selectMode = false
        store.navigation.push(.muscles(preferredWorkoutId: preferredWorkoutId))
    }

    private func move(_ id: String, from index: Int, by direction: Int) {
        guard let workout else { return }
        let target = index + direction
        guard target >= 0, target < workout.exerciseIds.count else { return }
        var ids = workout.exerciseIds
        ids.swapAt(index, target)
        updateExercises(ids, moved: id)
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
                store.navigation.reset([.workouts])
            case .discardSession:
                store.activeWorkout.cancel()
                confirmation = nil
            case .finishWorkout, .finishWorkoutPartial:
                store.activeWorkout.finish()
                TrainingEdits.refreshFutureWorkoutPrescriptions()
                confirmation = nil
            default:
                confirmation = nil
            }
        } catch { capture(error) }
    }

    private func capture(_ error: Error) {
        issue = (error as? TrainingPersistenceError)?.message ?? error.localizedDescription
        Haptics.trigger(.warning)
    }
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
                Haptics.trigger(.heavy)
                onComplete()
                return
            }
            Haptics.trigger(.light)
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            remaining -= 1
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Starting workout")
    }
}

private struct WorkoutOverview: View {
    let workout: Workout
    let past: Bool
    let planned: PlannedSessionView?

    private var signal: Color { past ? Theme.success : Theme.primary }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(past ? "COMPLETED" : "EXERCISES")
                        .font(Theme.sans(10, weight: .black))
                        .kerning(1.8)
                        .foregroundStyle(Theme.foreground.opacity(0.62))
                    Text(primaryValue)
                        .font(Theme.readout(72))
                        .tracking(1.8)
                        .foregroundStyle(Theme.foreground)
                        .shadow(color: signal.opacity(0.45), radius: 22)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 8)
                Image(systemName: past ? "checkmark.circle" : "checklist")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(signal)
                    .shadow(color: signal.opacity(0.45), radius: 8)
                .frame(width: 88, height: 88)
            }
            .frame(maxWidth: .infinity, minHeight: 152, alignment: .bottom)
            .padding(.horizontal, 20)
            .padding(.top, 20)
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
            .background {
                ZStack {
                    Theme.obsidian
                    LinearGradient(
                        colors: [signal.opacity(0.28), Theme.oxblood.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(signal.opacity(0.42), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background {
            ZStack {
                LinearGradient(
                    colors: [Theme.mix(Theme.card, .black, 0.14), Theme.obsidian],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [signal.opacity(0.18), .clear],
                    center: UnitPoint(x: 0.82, y: 0.10),
                    startRadius: 0,
                    endRadius: 170
                )
                DotPattern(spacing: 12, radius: 1, color: Theme.foreground, opacity: 0.10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Theme.mix(Theme.border, signal, 0.48), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 21, y: 9)
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

                        Text(exercise.name.capitalized)
                            .font(Theme.sans(18, weight: .heavy))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                            .shadow(color: .black.opacity(0.34), radius: 4, y: 1)
                            .frame(maxWidth: .infinity, alignment: .bottom)
                            .zIndex(2)
                    }
                    .frame(width: hero.size.width, height: hero.size.height)
                }
                .frame(height: min(380, UIScreen.main.bounds.width - Theme.Metrics.contentInset * 2))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous)
                        .strokeBorder(Theme.primary.opacity(0.30), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.20), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
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
    let canReorder: Bool
    let exerciseIds: [String]
    @ObservedObject var reorder: CardReorder
    let onOpen: () -> Void
    let onAlternative: () -> Void
    let onToggle: () -> Void
    let onReorder: ([String], String) -> Void
    let onRemove: () -> Void

    @State private var isOpen = false
    @State private var swipeDrag: CGFloat?

    private var revealWidth: CGFloat { canFindAlternative && canRemove ? 148 : 92 }
    private var settledX: CGFloat { isOpen ? -revealWidth : 0 }
    private var swipeOffset: CGFloat { swipeDrag ?? settledX }

    var body: some View {
        ZStack(alignment: .trailing) {
            if canFindAlternative || canRemove {
                swipeActions
                    .frame(width: revealWidth + Theme.Metrics.contentInset)
                    .opacity(swipeOffset < -8 ? 1 : 0)
            }

            card
                .offset(x: canFindAlternative || canRemove ? swipeOffset : 0)
        }
        .modifier(CardReorderPlacement(reorder: reorder, id: exercise.id, spacing: 20))
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
                .frame(width: 48)
                .frame(maxHeight: .infinity)
                .background(Theme.card)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Theme.border).frame(width: 1)
                }

                Button(action: onOpen) {
                    ExerciseMediaView(exerciseId: exercise.id, animated: true)
                        .frame(width: 144, height: 144)
                        .background(Theme.mix(Theme.card, .black, 0.12))
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)

                if canReorder {
                    CardReorderHandle(
                        reorder: reorder,
                        id: exercise.id,
                        order: exerciseIds,
                        name: exercise.name,
                        height: 144,
                        commit: onReorder
                    )
                }
            }
            .frame(height: 144)

            if let prescription {
                WorkoutPrescriptionStrip(prescription: prescription)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.mix(Theme.border, Theme.primary, 0.28)).frame(height: 1)
                    }
            }
        }
        .background(Theme.card.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    reorder.active == exercise.id
                        ? Theme.primary.opacity(0.70)
                        : Theme.mix(Theme.border, Theme.primary, 0.38),
                    lineWidth: 1
                )
        )
        .opacity(1)
        .shadow(
            color: .black.opacity(reorder.active == exercise.id ? 0.30 : 0.12),
            radius: reorder.active == exercise.id ? 20 : 13,
            y: reorder.active == exercise.id ? 10 : 6
        )
        .overlay {
            if reorder.active == exercise.id {
                AppGrain().clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
        .overlay {
            if canFindAlternative || canRemove {
                WorkoutCardSwipeObserver(
                    onChanged: { translation in
                        swipeDrag = Swift.min(
                            0,
                            Swift.max(-revealWidth, settledX + translation)
                        )
                    },
                    onEnded: { projectedTranslation in
                        let projectedX = settledX + projectedTranslation
                        withAnimation(Theme.Motion.smoothOut(0.24)) {
                            isOpen = projectedX <= -revealWidth / 2
                            swipeDrag = nil
                        }
                    }
                )
                .allowsHitTesting(false)

                if isOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(Theme.Motion.smoothOut(0.22)) { isOpen = false }
                        }
                }
            }
        }
    }

    private var swipeActions: some View {
        HStack(spacing: 10) {
            if canFindAlternative {
                AppControlButton(systemImage: "arrow.triangle.2.circlepath", label: "Find alternative") {
                    isOpen = false
                    onAlternative()
                }
            }
            if canRemove {
                AppControlButton(systemImage: "trash", label: "Remove exercise") {
                    isOpen = false
                    onRemove()
                }
            }
        }
    }
}

/// Installs a horizontal-only recognizer on the enclosing `ScrollView`.
/// Vertical drags fail this recognizer before it begins, leaving the native
/// scroll pan untouched; horizontal drags update only the card under the touch.
private struct WorkoutCardSwipeObserver: UIViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.hostView = view
        DispatchQueue.main.async { context.coordinator.installIfNeeded() }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.hostView = uiView
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        DispatchQueue.main.async { context.coordinator.installIfNeeded() }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject {
        weak var hostView: UIView?
        weak var scrollView: UIScrollView?
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat) -> Void
        private var panRecognizer: UIPanGestureRecognizer?

        init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping (CGFloat) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func installIfNeeded() {
            guard let hostView else { return }
            let enclosingScrollView = sequence(first: hostView.superview, next: { $0?.superview })
                .compactMap { $0 as? UIScrollView }
                .first
            guard enclosingScrollView !== scrollView else { return }
            uninstall()
            scrollView = enclosingScrollView
            guard let enclosingScrollView else { return }
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            enclosingScrollView.addGestureRecognizer(recognizer)
            panRecognizer = recognizer
        }

        func uninstall() {
            if let panRecognizer {
                scrollView?.removeGestureRecognizer(panRecognizer)
            }
            panRecognizer = nil
            scrollView = nil
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let scrollView else { return }

            switch recognizer.state {
            case .began, .changed:
                onChanged(recognizer.translation(in: scrollView).x)
            case .ended:
                let translation = recognizer.translation(in: scrollView).x
                let velocity = recognizer.velocity(in: scrollView).x
                onEnded(translation + velocity * 0.16)
            case .cancelled, .failed:
                onEnded(0)
            default:
                break
            }
        }
    }
}

extension WorkoutCardSwipeObserver.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              let hostView,
              let scrollView else { return false }
        let velocity = pan.velocity(in: scrollView)
        let rowFrame = hostView.convert(hostView.bounds, to: scrollView)
        let touch = pan.location(in: scrollView)
        return rowFrame.contains(touch) && abs(velocity.x) > abs(velocity.y) * 1.08
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
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
            HStack(spacing: 22) {
                metric("Sets", String(prescription.sets), accent: true)
                metric("Reps", reps)
                metric("RIR", Num.trimmed(prescription.rir))
                if let loadKg = prescription.loadKg {
                    let each = prescription.loadBasis == .perImplement ? " each" : ""
                    metric("Load", "\(Resistance.formatKg(loadKg)) kg\(each)")
                }
                metric("Rest", "\(Int(prescription.restSeconds.rounded()))s")
            }
            .padding(.horizontal, 16)
            .padding(.top, 11)
            .padding(.bottom, 13)
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

            GlassGroup(spacing: 8) {
                HStack(spacing: 6) {
                    Button {
                        Haptics.trigger(.medium)
                        session.runningSince == nil ? onResume() : onPause()
                    } label: {
                        Image(systemName: session.runningSince == nil ? "play.fill" : "pause.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                            .frame(width: 38, height: 38)
                            .glassSurface(.clear, in: Circle(), interactive: true, border: Theme.Glassware.edge, legacyFill: .clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.runningSince == nil ? "Resume workout" : "Pause workout")

                    Button {
                        Haptics.trigger(.light)
                        onNext?()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(onNext == nil ? Theme.mutedForeground : Theme.foreground)
                            .frame(width: 38, height: 38)
                            .glassSurface(
                                onNext == nil ? .inert : .clear,
                                in: Circle(),
                                interactive: onNext != nil,
                                border: Theme.Glassware.edge,
                                legacyFill: .clear
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(onNext == nil)
                    .accessibilityLabel(exercise.map { "Skip \($0.name)" } ?? "Next exercise")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 88)
        .glassSurface(.regular, in: shape, legacyFill: .clear)
        .padding(.horizontal, Theme.Metrics.contentInset)
        .padding(.bottom, Theme.Metrics.contentInset)
    }
}
