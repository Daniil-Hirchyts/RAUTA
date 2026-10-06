import SwiftUI

/// Where exercises should go: into a new workout on a day of your choosing,
/// or into a workout already coming up.
///
/// It answers two questions the same way — where the exercises just picked go,
/// and where a workout being reused goes — so both read as one page: what is
/// being filed at the top, a new day, then the workouts ahead.
///
/// A page rather than a menu: the list of open workouts is as long as it is,
/// and a scrolling popover that closes on the wrong tap is a worse way to
/// answer a one-tap question.
struct WorkoutDestinationScreen: View {
    enum Mode: Hashable {
        /// Exercises picked from the library, with the workout the flow
        /// started from offered first.
        case exercises([String], preferredWorkoutId: String?)
        /// An existing workout, made again.
        case reuse(sourceWorkoutId: String)
    }

    private let store = AppStore.shared
    let mode: Mode

    @State private var choosingDate = false
    @State private var working = false
    @State private var issue: String?
    /// The workout being made, stopped if the page goes before it is saved.
    @State private var creating: Task<Void, Never>?

    private var source: Workout? {
        guard case .reuse(let id) = mode else { return nil }
        return store.workouts.workout(id)
    }

    /// The exercises being filed.
    private var exerciseIds: [String] {
        switch mode {
        case .exercises(let ids, _): return ids
        case .reuse: return source?.exerciseIds.filter(ExerciseCatalogue.has) ?? []
        }
    }

    private var currentId: String? {
        switch mode {
        case .exercises(_, let preferred): return preferred ?? store.activeWorkout.session?.workoutId
        case .reuse: return store.activeWorkout.session?.workoutId
        }
    }

    /// Every workout still open to more exercises, soonest first, with the one
    /// being worked on at the top.
    private var workouts: [Workout] {
        let open = WorkoutTimeline.destinations(
            workouts: store.workouts.workouts,
            records: store.trainingRecords.data,
            activeWorkoutId: store.activeWorkout.session?.workoutId,
            excluding: source?.id
        )
        guard let current = open.first(where: { $0.id == currentId }) else { return open }
        return [current] + open.filter { $0.id != current.id }
    }

    private var title: String {
        switch mode {
        case .exercises(let ids, _): return "Add \(Wording.countLabel(ids.count, "exercise"))"
        case .reuse: return "Reuse workout"
        }
    }

    private var intro: String {
        switch mode {
        case .exercises:
            return "Start a new workout, or add them to one that's coming up."
        case .reuse:
            return "Give it a new day, or add its exercises to a workout that's coming up."
        }
    }

    var body: some View {
        ZStack {
            RautaScreen(
                title: title,
                backLabel: "Back",
                onBack: store.navigation.pop
            ) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(intro)
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.mutedForeground)

                        filing
                            .padding(.top, 16)

                        NewWorkoutDestinationRow(
                            subtitle: source == nil ? "Pick a day for it" : "Same exercises, a new day"
                        ) {
                            Haptics.trigger(.selection)
                            choosingDate = true
                        }
                        .padding(.top, 12)

                        if let issue {
                            InlineNotice(message: issue, isError: true)
                                .padding(.top, 12)
                        }

                        sectionLabel("COMING UP")
                        if workouts.isEmpty {
                            Text("No upcoming workouts yet.")
                                .font(Theme.sans(14))
                                .foregroundStyle(Theme.mutedForeground)
                                .padding(.horizontal, 4)
                        } else {
                            WorkoutAgenda(
                                rows: workouts.map(AgentSessionRow.workout),
                                onOpen: add(to:),
                                highlightedId: currentId,
                                accessory: .add
                            )
                            .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: 0.6) }
                        }
                    }
                    .padding(.horizontal, Theme.Metrics.contentInset)
                    .padding(.bottom, 24)
                    .disabled(working)
                    .opacity(working ? 0.6 : 1)
                    .animation(.easeInOut(duration: 0.2), value: working)
                }
                .pageScroll()
            }

            WorkoutDateCalendarModal(
                isPresented: choosingDate,
                date: CalendarDate.today,
                confirmTitle: source == nil ? "Create workout" : "Reuse on this day",
                onClose: { choosingDate = false },
                onSelect: create(on:)
            )
            .zIndex(9)
        }
        .onDisappear { creating?.cancel() }
    }

    /// What is being filed: the workout being reused, or the exercises picked.
    @ViewBuilder private var filing: some View {
        if let source {
            VStack(alignment: .leading, spacing: 0) {
                Text("REUSING")
                    .font(Theme.sans(10, weight: .black))
                    .kerning(1.4)
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                WorkoutAgenda(rows: [AgentSessionRow.workout(source)])
            }
            .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: 0.45) }
        } else {
            let exercises = exerciseIds.compactMap { ExerciseCatalogue.byId[$0] }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(exercises.prefix(5), id: \.id) { exercise in
                        ExerciseMediaView(exerciseId: exercise.id)
                            .padding(3)
                            .frame(width: 46, height: 46)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.muted.opacity(0.7)))
                    }
                    if exercises.count > 5 {
                        Text("+\(exercises.count - 5)")
                            .font(Theme.sans(13, weight: .bold))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(width: 46, height: 46)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.muted.opacity(0.7)))
                    }
                }
                .accessibilityHidden(true)
                Text(exercises.prefix(3).map { WorkoutAgenda.name($0) }.joined(separator: " · ")
                     + (exercises.count > 3 ? " …" : ""))
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: 0.45) }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.sans(12, weight: .bold))
            .kerning(1.55)
            .foregroundStyle(Theme.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    private func create(on date: String) {
        guard !working, !exerciseIds.isEmpty else { return }
        working = true
        issue = nil
        creating = Task {
            defer {
                working = false
                creating = nil
            }
            do {
                let id: String
                if let source {
                    id = try await EngineWorkout.reuse(source.id, date: date)
                } else {
                    id = try await EngineWorkout.createWorkout(date: date, exerciseIds: exerciseIds)
                }
                store.navigation.selectedIds = []
                store.navigation.openWorkout(id)
                Haptics.trigger(.success)
                RautaSpeech.shared.say(
                    date == CalendarDate.today
                        ? "It's on today. Start it whenever you're ready."
                        : "It's on \(CalendarDate.format(date, "EEEEdMMMM")).",
                    reaction: .wink
                )
            } catch is CancellationError {
                // Left before it was ready: nothing was saved.
            } catch { capture(error) }
        }
    }

    private func add(to workoutId: String) {
        guard !working, let workout = store.workouts.workout(workoutId) else { return }
        var seen = Set<String>()
        let ids = (workout.exerciseIds + exerciseIds).filter { seen.insert($0).inserted }
        do {
            if store.activeWorkout.session?.workoutId == workout.id {
                store.workouts.updateWorkout(workout.id, .init(exerciseIds: ids))
                store.activeWorkout.syncExercises(ids)
            } else {
                try TrainingEdits.updateScheduledWorkoutExercises(workout.id, ids)
            }
            store.navigation.selectedIds = []
            store.navigation.openWorkout(workout.id)
            Haptics.trigger(.success)
        } catch { capture(error) }
    }

    private func capture(_ error: Error) {
        issue = (error as? TrainingPersistenceError)?.message ?? error.localizedDescription
        Haptics.trigger(.warning)
    }
}

private struct NewWorkoutDestinationRow: View {
    var subtitle = "Pick a day for it"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.primaryForeground)
                    .frame(width: 44, height: 44)
                    .glassSurface(
                        .tinted(Theme.primary),
                        in: Circle(),
                        border: Theme.Glassware.brightEdge
                    )
                    .overlay {
                        Circle()
                            .fill(Theme.primaryGradient)
                            .opacity(Theme.Glassware.primaryWash)
                            .allowsHitTesting(false)
                    }
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("New workout")
                        .font(Theme.sans(16, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                    Text(subtitle)
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(16)
            .background(
                Theme.mix(Theme.card, Theme.primary, 0.10),
                in: RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
                    .strokeBorder(Theme.primary.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
