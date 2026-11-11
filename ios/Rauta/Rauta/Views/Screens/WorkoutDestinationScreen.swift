import SwiftUI

/// Where exercises should go: into a new workout on a day of your choosing,
/// or into a workout already coming up.
///
/// It answers two questions the same way — where the exercises just picked go,
/// and where a workout being reused goes — so both read as one page: what is
/// being filed at the top, the workouts ahead, and a new day at the bottom.
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

    var body: some View {
        ZStack {
            RautaScreen(
                title: title,
                backLabel: "Back",
                onBack: store.navigation.pop
            ) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        filing

                        if let issue {
                            InlineNotice(message: issue, isError: true)
                                .padding(.top, 12)
                        }

                        if !workouts.isEmpty {
                            sectionLabel("ADD TO")
                            VStack(spacing: 8) {
                                ForEach(workouts) { workout in
                                    WorkoutDestinationRow(
                                        row: .workout(workout),
                                        isRunning: workout.id == store.activeWorkout.session?.workoutId,
                                        isPreferred: workout.id == currentId,
                                        action: { add(to: workout.id) }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Metrics.contentInset)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                    .disabled(working)
                    .opacity(working ? 0.6 : 1)
                    .animation(.easeInOut(duration: 0.2), value: working)
                }
                .pageScroll()
            } controls: {
                AppButton(
                    source == nil ? "New workout" : "Pick a new day",
                    variant: workouts.isEmpty ? .primary : .secondary,
                    size: .cta,
                    expands: true
                ) {
                    Haptics.trigger(.selection)
                    choosingDate = true
                }
                .disabled(working)
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

    /// What is being filed: the workout being reused, or the exercises picked,
    /// as the cards they were picked from.
    @ViewBuilder private var filing: some View {
        if let source {
            VStack(alignment: .leading, spacing: 8) {
                Text("REUSING")
                    .font(Theme.sans(12, weight: .bold))
                    .kerning(1.55)
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, 4)
                WorkoutDestinationRow(row: .workout(source))
            }
        } else {
            let exercises = exerciseIds.compactMap { ExerciseCatalogue.byId[$0] }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(exercises, id: \.id) { exercise in
                        VStack(alignment: .leading, spacing: 8) {
                            ExerciseMediaView(exerciseId: exercise.id)
                                .frame(maxWidth: .infinity)
                                .frame(height: 104)
                                .accessibilityHidden(true)
                            Text(WorkoutAgenda.name(exercise))
                                .font(Theme.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.foreground)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                        }
                        .padding(10)
                        .frame(width: 136)
                        .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: 0.5) }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
            }
            .scrollClipDisabled()
            .padding(.horizontal, -Theme.Metrics.contentInset)
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
        guard !working else { return }
        do {
            try TrainingEdits.addExercises(exerciseIds, to: workoutId)
            store.navigation.selectedIds = []
            store.navigation.openWorkout(workoutId)
            Haptics.trigger(.success)
        } catch { capture(error) }
    }

    private func capture(_ error: Error) {
        issue = (error as? TrainingPersistenceError)?.message ?? error.localizedDescription
        Haptics.trigger(.warning)
    }
}

/// A workout as somewhere to put exercises: its day in the app's numerals,
/// its name and size, and "Add" when tapping it files them there.
private struct WorkoutDestinationRow: View {
    let row: AgentSessionRow
    var isRunning = false
    var isPreferred = false
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button {
                Haptics.trigger(.selection)
                action()
            } label: {
                card
            }
            .buttonStyle(EquipmentCardButtonStyle())
            .accessibilityHint("Adds the exercises to it")
        } else {
            card
        }
    }

    private var card: some View {
        HStack(spacing: 14) {
            VStack(spacing: 1) {
                Text(isRunning ? "NOW" : CalendarDate.weekdayShort(row.date).uppercased())
                    .font(Theme.sans(10, weight: .black))
                    .kerning(1.2)
                    .foregroundStyle(Theme.primary)
                Text(CalendarDate.format(row.date, "d"))
                    .font(Theme.readout(26))
                    .foregroundStyle(Theme.foreground)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(Theme.sans(17, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Text(meta)
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if action != nil {
                Text("Add")
                    .font(Theme.sans(15, weight: .bold))
                    .foregroundStyle(Theme.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: isPreferred ? 0.95 : 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        var parts = [Wording.countLabel(row.exerciseIds.count, "exercise")]
        if row.minutes > 0 { parts.append("\(row.minutes) min") }
        return parts.joined(separator: " · ")
    }
}
