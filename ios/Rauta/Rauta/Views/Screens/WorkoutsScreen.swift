import SwiftUI

struct WorkoutsScreen: View {
    @ObservedObject private var store = AppStore.shared
    @State private var tab = 0
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
        RautaScreen(title: "My workouts", right: {
            AppHeaderButton(systemImage: "gearshape", label: "Settings") {
                store.navigation.push(.settings)
            }
        }, content: {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        StreakStrip(workouts: past.filter { $0.completion != nil })

                        WorkoutsModeSwitcher(selection: $tab)
                            .padding(.top, 10)
                            .padding(.bottom, 10)

                        let items = tab == 0 ? upcoming : past
                        let itemLimit = tab == 0 ? upcomingLimit : pastLimit
                        let remaining = Swift.max(0, items.count - itemLimit)
                        let showLess = itemLimit > 6

                        if items.isEmpty {
                            Text(tab == 0 ? "No upcoming workouts" : "No past workouts yet")
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.mutedForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                        }

                        LazyVStack(spacing: 14) {
                            ForEach(items.prefix(itemLimit)) { workout in
                                WorkoutRow(
                                    workout: workout,
                                    isPast: tab == 1,
                                    isRunning: store.activeWorkout.session?.workoutId == workout.id,
                                    onOpen: { open(workout) }
                                )
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
                        .id(tab)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 20)
                    .padding(.bottom, 144)
                }

                RautaBottomDock(
                    speech: companionLine,
                    meta: "\(ProfileVocabulary.goalLabel(store.trainingProfile.profile.goal)) · \(Int(store.trainingProfile.profile.preferredSessionDurationMinutes)) min",
                    mood: store.activeWorkout.session == nil ? .calm : .focused,
                    actions: companionActions,
                    characterSize: 100,
                    floating: true,
                    showsText: true,
                    glassContainer: true
                )
            }
        })
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
                actions.append(CompanionAction(title: "Adjust remaining week", systemImage: "arrow.triangle.2.circlepath", primary: true) {
                    do {
                        let result = try TrainingWorkflow.generateAndSavePlan(source: source)
                        if let program = result.result.program { TrainingPlan.projectPlannedWorkouts(TrainingPlan.sessionViews(program)) }
                        Haptics.trigger(.success)
                    } catch { issue = error.localizedDescription }
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
    private func startExerciseFlow() {
        store.filters.reset(); store.filters.setEquipment(store.filters.gymEquipment)
        store.navigation.selectMode = false; store.navigation.selectedIds = []
        store.navigation.push(.muscles(preferredWorkoutId: nil))
    }
    private func open(_ workout: Workout) {
        _ = EngineWorkout.ensureEngineWorkout(workout.id)
        store.navigation.push(.workoutDetail(workoutId: workout.id))
    }
}

private struct WorkoutsModeSwitcher: View {
    @Binding var selection: Int
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            option(title: "Next", index: 0)
            option(title: "Past", index: 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }

    private func option(title: String, index: Int) -> some View {
        let selected = selection == index

        return VStack(spacing: 5) {
            Text(title)
                .font(Theme.sans(13, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.foreground : Theme.mutedForeground)

            ZStack {
                Capsule()
                    .fill(.clear)
                    .frame(width: 34, height: 2)

                if selected {
                    Capsule()
                        .fill(Theme.primaryGradient)
                        .frame(width: 34, height: 2)
                        .matchedGeometryEffect(id: "workout-mode", in: indicator)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            guard selection != index else { return }
            Haptics.trigger(.selection)
            withAnimation(Theme.Motion.spring) { selection = index }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
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
                        .foregroundStyle(Theme.primary)

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
                    streakMetric(value: streak.weekWorkouts, label: "THIS WEEK")

                    Rectangle()
                        .fill(Theme.foreground.opacity(0.10))
                        .frame(width: 1, height: 30)

                    streakMetric(value: streak.longestStreak, label: "BEST")
                }
                .padding(.trailing, 4)
            }

            GlassGroup(spacing: 6) {
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
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Color.clear
                    .glassSurface(
                        .regular,
                        in: shape,
                        border: Theme.Glassware.edge,
                        legacyFill: Theme.card.opacity(0.64)
                    )
                RadialGradient(
                    colors: [Theme.primary.opacity(0.14), .clear],
                    center: UnitPoint(x: 0.52, y: 0.72),
                    startRadius: 0,
                    endRadius: 150
                )
                .clipShape(shape)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(.white.opacity(0.08))
                .frame(width: 74, height: 1)
                .padding(.top, 1)
        }
    }

    private func streakMetric(value: Int, label: String) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(Theme.readout(15))
                .foregroundStyle(Theme.foreground)
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
            Color.clear
                .glassSurface(
                    lit ? .tinted(Theme.primary.opacity(0.68)) : .regular,
                    in: FlameShape(),
                    border: lit ? Theme.primary.opacity(0.42) : .white.opacity(0.07),
                    legacyFill: lit ? Theme.primary.opacity(0.68) : .white.opacity(0.055)
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 100)
            .background(
                LinearGradient(
                    colors: [
                        Theme.mix(Theme.card, Theme.foreground, 0.05),
                        Theme.card,
                        Theme.mix(Theme.card, .black, 0.14)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 36, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .strokeBorder(isRunning ? Theme.primary.opacity(0.6) : Theme.border)
            )
        }
        .buttonStyle(.plain)
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
