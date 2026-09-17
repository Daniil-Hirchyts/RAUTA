import SwiftUI
import UniformTypeIdentifiers

/// Where the exercises just picked should go.
///
/// A page rather than a menu: the list of open workouts is as long as it is,
/// and a scrolling popover that closes on the wrong tap is a worse way to
/// answer a one-tap question.
struct WorkoutDestinationScreen: View {
    private let store = AppStore.shared
    /// The exercises being filed, carried by the page rather than read from the
    /// selection — one exercise opened from the Library is the same question.
    let exerciseIds: [String]
    /// The workout the flow started from, offered first.
    let preferredWorkoutId: String?

    /// Every workout still open to more exercises, soonest first, with the one
    /// being worked on at the top: the workout this flow started from, or else
    /// the one in progress.
    private var workouts: [Workout] {
        let currentId = preferredWorkoutId ?? store.activeWorkout.session?.workoutId
        let open = store.workouts.workouts
            .filter { $0.completion == nil }
            .soonestFirst()
        guard let current = open.first(where: { $0.id == currentId }) else { return open }
        return [current] + open.filter { $0.id != current.id }
    }

    private var currentId: String? {
        preferredWorkoutId ?? store.activeWorkout.session?.workoutId
    }

    var body: some View {
        RautaScreen(
            title: "Add \(Wording.countLabel(exerciseIds.count, "exercise"))",
            backLabel: "Back to exercises",
            onBack: store.navigation.pop
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Start fresh or add them to a workout you already use.")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.mutedForeground)

                    NewWorkoutDestinationRow {
                        Haptics.trigger(.selection)
                        store.navigation.push(.workoutForm(
                            exerciseIds: exerciseIds,
                            workoutId: nil,
                            engineFocusMuscles: nil
                        ))
                    }
                    .padding(.top, 20)

                    if workouts.isEmpty {
                        Text("No planned workouts yet.")
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(.top, 20)
                    } else {
                        Text("PLANNED WORKOUTS")
                            .font(Theme.sans(12, weight: .bold))
                            .kerning(1.55)
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.top, 20)
                            .padding(.bottom, 8)

                        ForEach(workouts) { workout in
                            ExistingWorkoutDestinationRow(
                                workout: workout,
                                current: workout.id == currentId,
                                action: { add(to: workout) }
                            )
                            .padding(.bottom, 8)
                        }
                    }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, 24)
            }
            .pageScroll()
        }
    }

    private func add(to workout: Workout) {
        var seen = Set<String>()
        let ids = (workout.exerciseIds + exerciseIds)
            .filter { seen.insert($0).inserted }
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
        } catch {
            Haptics.trigger(.warning)
        }
    }
}

struct WorkoutFormScreen: View {
    private let store = AppStore.shared
    let initialExerciseIds: [String]
    let workoutId: String?
    let focusMuscles: [MuscleId]?

    @State private var date = Date()
    @State private var exerciseIds: [String] = []
    @State private var issue: String?
    @State private var saving = false
    @State private var regenerating = false
    @State private var showingDate = false
    /// Proposing or saving: the session is composed off the main actor.
    @State private var work: Task<Void, Never>?

    private var workout: Workout? { workoutId.flatMap(store.workouts.workout) }

    /// The rows to show. `reorderable()` needs one unconditional view per
    /// element, so ids missing from the catalogue are dropped here rather than
    /// inside the `ForEach` body — a conditional there traps the reorder lift.
    private var resolvedExercises: [ExerciseSummary] {
        exerciseIds.compactMap { ExerciseCatalogue.byId[$0] }
    }

    var body: some View {
        ZStack {
            RautaScreen(
                title: workout == nil ? (focusMuscles == nil ? "New workout" : "Proposed workout") : "Edit workout",
                onBack: store.navigation.pop
            ) {
                ScrollView {
                    VStack(spacing: 12) {
                        WorkoutFormDatePicker(selection: $date) { showingDate = true }

                            ForEach(resolvedExercises) { exercise in
                                EditableExerciseRow(
                                    exercise: exercise,
                                    index: resolvedExercises.firstIndex(of: exercise) ?? 0,
                                    remove: { exerciseIds.removeAll { $0 == exercise.id } },
                                    move: { move(exercise.id, by: $0) }
                                )
                            }
                            .reorderable()
                            if let issue { InlineNotice(message: issue, isError: true) }
                        }
                        .reorderContainer(for: ExerciseSummary.self) { difference in
                            exerciseIds = exerciseIds.applyingReorder(difference)
                        }
                        .padding(.horizontal, Theme.Metrics.contentInset)
                        .padding(.bottom, 24)
                }
                .pageScroll()
                .swipeActionsContainer()
            } controls: {
                HStack(spacing: 10) {
                    if focusMuscles != nil {
                        AppControlButton(
                            systemImage: "arrow.clockwise",
                            label: "Regenerate workout",
                            isDisabled: regenerating || saving,
                            action: regenerate
                        )
                    }
                    AppButton(
                        saveButtonTitle,
                        size: .cta,
                        isDisabled: exerciseIds.isEmpty || saving || regenerating,
                        expands: true,
                        action: save
                    )
                }
            }

            WorkoutDateCalendarModal(
                isPresented: showingDate,
                date: CalendarDate.toISO(date),
                onClose: { showingDate = false },
                onSelect: { iso in
                    if let selected = CalendarDate.parse(iso) { date = selected }
                }
            )
            .zIndex(9)
        }
        .onAppear(perform: load)
        .onDisappear { work?.cancel() }
    }

    /// One place up or down: the accessible form of dragging a row.
    private func move(_ id: String, by offset: Int) {
        let rows = resolvedExercises
        let next = exerciseIds.movingElement(id, by: offset, visible: Set(rows.map(\.id)))
        guard next != exerciseIds else { return }
        exerciseIds = next
        let position = next.filter { id in rows.contains { $0.id == id } }.firstIndex(of: id).map { $0 + 1 } ?? 0
        AccessibilityNotification.Announcement("Moved to position \(position) of \(rows.count)").post()
    }

    private func load() {
        guard exerciseIds.isEmpty else { return }
        if let workout {
            date = CalendarDate.parse(workout.date) ?? Date()
            exerciseIds = workout.exerciseIds
        } else {
            exerciseIds = initialExerciseIds
        }
    }

    private var saveButtonTitle: String {
        if workout != nil { return "Save workout" }
        if focusMuscles != nil { return "Use workout" }
        return "Create workout"
    }

    private func regenerate() {
        guard let focusMuscles, !regenerating, !saving else { return }
        regenerating = true
        work = Task {
            defer { regenerating = false }
            do {
                let proposal = try await EngineWorkout.propose(
                    date: CalendarDate.toISO(date),
                    focusMuscles: focusMuscles,
                    previousExerciseIds: exerciseIds,
                    availableEquipment: store.filters.selectedEquipment
                )
                exerciseIds = proposal
                issue = nil
                Haptics.trigger(.medium)
            } catch is CancellationError {
            } catch { capture(error) }
        }
    }

    private func save() {
        guard !exerciseIds.isEmpty, !saving, !regenerating else { return }
        saving = true
        work = Task {
            defer { saving = false }
            do {
                let id: String
                if let workout {
                    if workout.date != CalendarDate.toISO(date) {
                        try TrainingEdits.rescheduleWorkout(workout.id, date: CalendarDate.toISO(date))
                    }
                    try TrainingEdits.updateScheduledWorkoutExercises(workout.id, exerciseIds)
                    id = workout.id
                } else {
                    id = try await EngineWorkout.createWorkout(
                        date: CalendarDate.toISO(date),
                        exerciseIds: exerciseIds,
                        focusMuscles: focusMuscles
                    )
                }
                store.navigation.selectedIds = []
                store.navigation.openWorkout(id)
                Haptics.trigger(.success)
            } catch is CancellationError {
            } catch { capture(error) }
        }
    }

    private func capture(_ error: Error) {
        issue = (error as? TrainingPersistenceError)?.message ?? error.localizedDescription
        Haptics.trigger(.warning)
    }
}

private struct NewWorkoutDestinationRow: View {
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
                    Text("Pick a date and review the order")
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

private struct ExistingWorkoutDestinationRow: View {
    let workout: Workout
    let current: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(width: 40, height: 40)
                    .background(
                        Theme.muted,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(CalendarDate.short(workout.date))
                        .font(Theme.sans(16, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                    Text(
                        Wording.countLabel(workout.exerciseIds.count, "exercise")
                            + (current ? " · Current" : "")
                    )
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(14)
            .background(
                Theme.card,
                in: RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
                    .strokeBorder(current ? Theme.primary.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WorkoutFormDatePicker: View {
    @Binding var selection: Date
    let onOpen: () -> Void

    var body: some View {
        Button {
            Haptics.trigger(.light)
            onOpen()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                Text(CalendarDate.long(CalendarDate.toISO(selection)))
                    .font(Theme.sans(18, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                Theme.input,
                in: RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workout date, \(CalendarDate.long(CalendarDate.toISO(selection)))")
    }
}

private struct EditableExerciseRow: View {
    let exercise: ExerciseSummary
    let index: Int
    let remove: () -> Void
    /// Moves the row one place (-1 up, +1 down).
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(String(format: "%02d", index + 1))
                .font(Theme.sans(16, weight: .bold))
                .kerning(0.65)
                .foregroundStyle(Theme.primary)
                .frame(width: 50)
                .frame(maxHeight: .infinity)

            ExerciseMediaView(exerciseId: exercise.id)
                .frame(width: 128, height: 128)

            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name.capitalized)
                    .font(Theme.sans(17, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(Wording.titleCase(exercise.equipment))
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 136)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Haptics.trigger(.warning)
                remove()
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .accessibilityLabel("Remove \(exercise.name)")
        }
        // Dragging to reorder has no VoiceOver form of its own.
        .accessibilityActions {
            Button("Move up") { move(-1) }
            Button("Move down") { move(1) }
        }
    }
}
