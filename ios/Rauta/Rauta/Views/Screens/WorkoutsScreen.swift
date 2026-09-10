import SwiftUI

struct WorkoutsScreen: View {
    @ObservedObject private var store = AppStore.shared
    @State private var tab = 0
    @State private var openRowId: String?
    @State private var pendingDelete: Workout?
    @State private var issue: String?
    @State private var upcomingLimit = 6
    @State private var pastLimit = 6

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
        ZStack {
            RautaScreen(title: "My workouts", right: {
                AppHeaderButton(systemImage: "gearshape", label: "Settings") { store.navigation.push(.settings) }
            }, content: {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(spacing: 0) {
                            StreakStrip(workouts: past.filter { $0.completion != nil })
                            SlidingTabs(tabs: [
                                TabDefinition(label: "Next", count: upcoming.count),
                                TabDefinition(label: "Past", count: past.count)
                            ], activeIndex: $tab).padding(.top, 20).padding(.bottom, 16)
                            let items = tab == 0 ? upcoming : past
                            let itemLimit = tab == 0 ? upcomingLimit : pastLimit
                            let remaining = Swift.max(0, items.count - itemLimit)
                            let showLess = itemLimit > 6
                            if items.isEmpty {
                                Text(tab == 0 ? "No upcoming workouts" : "No past workouts yet")
                                    .font(Theme.sans(13)).foregroundStyle(Theme.mutedForeground)
                            }
                            LazyVStack(spacing: 10) {
                                ForEach(items.prefix(itemLimit)) { workout in
                                    WorkoutRow(workout: workout, isPast: tab == 1,
                                               isRunning: store.activeWorkout.session?.workoutId == workout.id,
                                               isOpen: Binding(get: { openRowId == workout.id }, set: { openRowId = $0 ? workout.id : nil }),
                                               onOpen: { open(workout) }, onCopy: { copy(workout) },
                                               onDelete: { pendingDelete = workout })
                                }
                                sectionFooter(
                                    remaining: remaining,
                                    showLess: showLess,
                                    onMore: {
                                        if tab == 0 { upcomingLimit += 6 }
                                        else { pastLimit += 6 }
                                    },
                                    onLess: {
                                        if tab == 0 { upcomingLimit = 6 }
                                        else { pastLimit = 6 }
                                    }
                                )
                            }
                        }.padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 144)
                    }
                    RautaBottomDock(speech: companionLine, meta: "\(ProfileVocabulary.goalLabel(store.trainingProfile.profile.goal)) · \(Int(store.trainingProfile.profile.preferredSessionDurationMinutes)) min",
                                    mood: store.activeWorkout.session == nil ? .calm : .focused, actions: companionActions)
                }
            }, controls: {
                AppButton(store.activeWorkout.session == nil ? "New workout" : "Resume workout", size: .cta, expands: true) {
                    if let session = store.activeWorkout.session { store.navigation.push(.workoutDetail(workoutId: session.workoutId)) }
                    else { startExerciseFlow() }
                }
            })
            ConfirmModal(kind: pendingDelete == nil ? nil : .deleteWorkout, error: issue,
                         onCancel: { pendingDelete = nil; issue = nil }, onConfirm: deleteWorkout)
        }
        .task {
            // Restore any missing lightweight projection from its authoritative plan.
            for view in TrainingPlan.activePlannedSessions() where !TrainingPlan.isPlannedSessionRecorded(view.sessionId) {
                TrainingPlan.ensurePlannedWorkout(view)
            }
        }
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

    private var companionLine: String {
        if let issue { return issue }
        if store.activeWorkout.session != nil { return "Your workout is waiting. Want to continue?" }
        let ahead = TrainingPlan.activePlannedSessions().filter { $0.date >= CalendarDate.today && !TrainingPlan.isPlannedSessionRecorded($0.sessionId) }
        if let today = ahead.first(where: { $0.date == CalendarDate.today }) { return "\(today.title) is ready." }
        if ahead.count == 1 { return "One session left this week." }
        if ahead.count > 1 { return "\(ahead.count) sessions fit this week." }
        if store.trainingRecords.data.activeProgramId != nil { return "This week's plan is done. Ask me for the next one." }
        let name = store.trainingProfile.profile.name
        return name.isEmpty ? "Tell me what we're training today." : "Ready, \(name)? I can shape today's session."
    }
    private var companionActions: [CompanionAction] {
        var actions: [CompanionAction] = []
        if let source = TrainingPlan.activeProgramRecord(), store.activeWorkout.session == nil {
            let remaining = TrainingWorkflow.remainingTrainingSlots(source, ISOTime.now())
            if !remaining.sessions.isEmpty && store.trainingRecords.data.sessions.contains(where: { $0.plannedProgramId == source.id }) {
                actions.append(CompanionAction(title: "Adjust remaining week", primary: true) {
                    do {
                        let result = try TrainingWorkflow.generateAndSavePlan(source: source)
                        if let program = result.result.program { TrainingPlan.projectPlannedWorkouts(TrainingPlan.sessionViews(program)) }
                        Haptics.trigger(.success)
                    } catch { issue = error.localizedDescription }
                })
            } else if remaining.sessions.isEmpty {
                actions.append(CompanionAction(title: "Extend training plan", primary: true) {
                    store.navigation.push(.planWeek(sourceProgramId: source.id))
                })
            }
        }
        actions.append(CompanionAction(title: store.trainingRecords.data.activeProgramId == nil ? "Create training plan" : "New training plan", primary: actions.isEmpty) {
            store.navigation.push(.planWeek(sourceProgramId: nil))
        })
        actions.append(CompanionAction(title: "Choose exercises", action: startExerciseFlow))
        return actions
    }
    private func startExerciseFlow() {
        store.filters.reset(); store.filters.setEquipment(store.filters.gymEquipment)
        store.navigation.selectMode = false; store.navigation.selectedIds = []
        store.navigation.push(.muscles(preferredWorkoutId: nil))
    }
    private func open(_ workout: Workout) {
        if openRowId == workout.id { openRowId = nil; return }
        _ = EngineWorkout.ensureEngineWorkout(workout.id)
        store.navigation.push(.workoutDetail(workoutId: workout.id))
    }
    private func copy(_ workout: Workout) {
        do {
            _ = try EngineWorkout.duplicateWithEngine(workout.id, date: CalendarDate.today)
            openRowId = nil; Haptics.trigger(.success)
        } catch { issue = error.localizedDescription }
    }
    private func deleteWorkout() {
        guard let workout = pendingDelete else { return }
        do {
            try TrainingEdits.deleteScheduledWorkout(workout.id)
            pendingDelete = nil; issue = nil; openRowId = nil
        } catch { issue = error.localizedDescription }
    }
}

private struct StreakStrip: View {
    let workouts: [Workout]
    private var streak: Streak { StreakBuilder.build(workouts) }
    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(streak.currentStreak)").font(Theme.readout(32)).foregroundStyle(Theme.foreground)
                Text("day streak").font(Theme.sans(14, weight: .semibold)).foregroundStyle(Theme.mutedForeground)
            }
            HStack(spacing: 4) {
                ForEach(streak.week) { day in
                    VStack(spacing: 6) {
                        Flame(lit: day.workouts > 0)
                            .frame(width: day.isToday ? 44.8 : 35.2, height: day.isToday ? 56 : 44)
                            .frame(height: 56, alignment: .bottom).opacity(day.isFuture ? 0.6 : 1)
                        Text(CalendarDate.weekdayShort(day.date)).font(Theme.sans(10, weight: .semibold))
                            .foregroundStyle(day.isToday ? Theme.primaryForeground : Theme.mutedForeground)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(day.isToday ? Theme.primary : .clear, in: Capsule())
                    }.frame(maxWidth: .infinity)
                }
            }
        }.padding(16).frame(maxWidth: .infinity)
            .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Theme.border))
    }
}

private struct Flame: View {
    var lit: Bool
    var body: some View {
        Canvas { context, size in
            var ctx = context; ctx.scaleBy(x: size.width / 32, y: size.height / 40)
            if let path = SVGPath.parse("M16.6 1.6c.6 6.4 9.9 10.4 9.9 22.1a10.5 10.5 0 0 1-21 0c0-5.4 2.1-9 4.9-11.9.1 3.1 1.3 5.3 3.1 6.4 1.8-1.7 3-8.6 3.1-16.6Z") {
                ctx.fill(path, with: lit ? .linearGradient(Gradient(colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 40)) : .color(.white.opacity(0.09)))
            }
            if lit, let inner = SVGPath.parse("M16.2 15.8c0 4 6.1 6.1 6.1 11a6.2 6.2 0 0 1-12.4 0c0-4.9 6.3-7 6.3-11Z") { ctx.fill(inner, with: .color(.white.opacity(0.26))) }
        }
    }
}

private struct WorkoutRow: View {
    let workout: Workout
    let isPast: Bool
    let isRunning: Bool
    @Binding var isOpen: Bool
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var runningPulse = false
    private var muscles: [MuscleId] { ExerciseCatalogue.musclesForExerciseIds(workout.exerciseIds) }
    var body: some View {
        SwipeableRow(isOpen: $isOpen, actionInset: 20, revealWidth: 148, action: {
            HStack(spacing: 8) {
                action("doc.on.doc", label: "Copy workout to today", onCopy)
                action("trash", label: "Delete workout", onDelete)
            }
        }, content: {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    dateStamp
                    VStack(alignment: .leading, spacing: 4) {
                        if isRunning, let session = ActiveWorkoutStore.shared.session {
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Theme.primary)
                                        .frame(width: 6, height: 6)
                                        .opacity(runningPulse ? 0.35 : 1)
                                    Text("\(session.runningSince == nil ? "Paused" : "In progress") · \(ActiveWorkout.formatDuration(ActiveWorkout.elapsedMs(session))) · \(session.completedIds.count)/\(workout.exerciseIds.count)")
                                        .font(Theme.sans(13, weight: .bold))
                                }
                                .foregroundStyle(Theme.primary)
                                .onAppear {
                                    guard !runningPulse else { return }
                                    withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                                        runningPulse = true
                                    }
                                }
                            }
                            progress(session.completedIds.count).padding(.top, 6)
                        } else if let completion = workout.completion {
                            HStack(spacing: 8) {
                                stat(ActiveWorkout.formatDuration(completion.durationMs), "Duration", Theme.foreground)
                                stat("\(Int(completion.activeCalories)) kcal", "Energy", Theme.gold)
                                stat("\(completion.completedExerciseIds.count)/\(workout.exerciseIds.count)", "Completed", Theme.success)
                            }
                            progress(completion.completedExerciseIds.count).padding(.top, 6)
                        } else if isPast {
                            Text("Not completed · \(Wording.countLabel(workout.exerciseIds.count, "exercise"))")
                                .font(Theme.sans(13, weight: .semibold))
                                .foregroundStyle(Theme.mutedForeground)
                        } else {
                            Text((workout.planned == nil ? "" : "\(workout.name) · ") + Wording.countLabel(workout.exerciseIds.count, "exercise"))
                                .font(Theme.sans(15, weight: .bold)).foregroundStyle(Theme.foreground)
                            Text(muscles.prefix(3).map(\.label).joined(separator: " · ") + (muscles.count > 3 ? " +\(muscles.count - 3)" : ""))
                                .font(Theme.sans(11, weight: .medium)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    BodyPreview(selectedMuscles: muscles, width: 80, height: 56)
                        .opacity(isPast ? 0.9 : 1)
                }.padding(12)
                    .background(LinearGradient(colors: [Theme.mix(Theme.card, Theme.foreground, 0.05), Theme.card, Theme.mix(Theme.card, .black, 0.14)], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(isRunning ? Theme.primary.opacity(0.6) : Theme.border))
            }.buttonStyle(.plain)
        })
    }
    private var dateStamp: some View {
        VStack(spacing: 2) {
            Text(CalendarDate.weekdayShort(workout.date).uppercased()).font(Theme.sans(9, weight: .bold)).tracking(1.26).opacity(0.75)
            Text(CalendarDate.dayOfMonth(workout.date)).font(Theme.readout(21))
            if isPast { Text(CalendarDate.monthShort(workout.date).uppercased()).font(Theme.sans(9, weight: .bold)).opacity(0.6) }
        }.foregroundStyle(isRunning ? Theme.primaryForeground : isPast ? Theme.mutedForeground : Theme.foreground)
            .padding(.vertical, 8).frame(width: 52)
            .background(
                isRunning
                    ? AnyShapeStyle(Theme.primaryGradient)
                    : AnyShapeStyle(Theme.muted.opacity(isPast ? 0.35 : 0.45)),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                if !isPast {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(isRunning ? Theme.primary.opacity(0.7) : Theme.border)
                }
            }
    }
    private func stat(_ value: String, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.readout(15)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption.uppercased()).font(Theme.sans(9, weight: .bold)).tracking(0.9).foregroundStyle(Theme.mutedForeground)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func progress(_ done: Int) -> some View {
        GeometryReader { p in
            Capsule().fill(Theme.muted)
            Capsule().fill(Theme.primaryGradient).frame(width: p.size.width * min(1, Double(done) / Double(max(1, workout.exerciseIds.count))))
        }.frame(height: 4)
    }
    private func action(_ icon: String, label: String, _ handler: @escaping () -> Void) -> some View {
        Button(action: handler) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.primary)
                .frame(width: 56, height: 56).background(Theme.card, in: Circle())
                .overlay(Circle().strokeBorder(icon == "trash" ? Theme.primary : Theme.border))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}
