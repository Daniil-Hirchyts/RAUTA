import SwiftUI

struct ExerciseAlternativesScreen: View {
    @ObservedObject private var store = AppStore.shared
    let exerciseId: String
    let workoutId: String

    @State private var equipment: String?
    @State private var issue: String?

    private var source: ExerciseSummary? { ExerciseCatalogue.byId[exerciseId] }
    private var workout: Workout? { store.workouts.workout(workoutId) }
    private var allAlternatives: [ExerciseSummary] {
        guard let source else { return [] }
        if workout?.planned != nil {
            return TrainingWorkflow.replacementIds(exerciseId, workoutId: workoutId)
                .compactMap { ExerciseCatalogue.byId[$0] }
        }
        return ExerciseCatalogue.findAlternatives(
            to: source,
            excluding: workout?.exerciseIds ?? []
        )
    }
    private var visibleAlternatives: [ExerciseSummary] {
        allAlternatives.filter { equipment == nil || $0.equipment == equipment }
    }
    private var equipmentOptions: [String] {
        var seen = Set<String>()
        return allAlternatives.map(\.equipment).filter { seen.insert($0).inserted }
    }

    var body: some View {
        if let source {
            RautaScreen(
                title: "Find alternative",
                backLabel: "Back to workout",
                onBack: store.navigation.pop
            ) {
                ScrollView {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            ExerciseMediaView(exerciseId: source.id, animated: true)
                                .frame(width: 88, height: 88)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.name.capitalized)
                                    .font(Theme.sans(17, weight: .semibold))
                                    .foregroundStyle(Theme.foreground)
                                    .lineLimit(2)
                                Text(
                                    workout?.planned == nil
                                        ? "Same muscles, different equipment."
                                        : "Fits this workout and your current equipment."
                                )
                                    .font(Theme.sans(13))
                                    .foregroundStyle(Theme.mutedForeground)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(
                            Theme.card.opacity(0.88),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
                        )

                        if let issue {
                            InlineNotice(message: issue, isError: true)
                                .padding(.top, 16)
                        }

                        if equipmentOptions.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 7) {
                                    SelectionChip(title: "All", selected: equipment == nil) {
                                        equipment = nil
                                    }
                                    ForEach(equipmentOptions, id: \.self) { item in
                                        SelectionChip(
                                            title: Wording.titleCase(item),
                                            selected: equipment == item
                                        ) { equipment = item }
                                    }
                                }
                                .padding(.horizontal, Theme.Metrics.contentInset)
                            }
                            .padding(.horizontal, -Theme.Metrics.contentInset)
                            .padding(.top, 16)
                            .padding(.bottom, 1)
                        }

                        if visibleAlternatives.isEmpty {
                            Text(
                                workout?.planned == nil
                                    ? "Nothing else works the same muscles on the equipment you have. Pick a different filter above, or keep the exercise you are on."
                                    : "No other exercise fits this planned slot with your current equipment. Keep the current exercise."
                            )
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.mutedForeground)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 28)
                            .frame(maxWidth: .infinity)
                            .background(
                                Theme.card,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
                            )
                            .padding(.top, 16)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(visibleAlternatives) { alternative in
                                    Button { swap(to: alternative) } label: {
                                        HStack(spacing: 16) {
                                            ExerciseMediaView(exerciseId: alternative.id, animated: true)
                                                .frame(width: 128, height: 128)
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(alternative.name.capitalized)
                                                    .font(Theme.sans(17, weight: .semibold))
                                                    .foregroundStyle(Theme.foreground)
                                                    .lineLimit(3)
                                                Text("Use \(Wording.titleCase(alternative.equipment))")
                                                    .font(Theme.sans(14, weight: .medium))
                                                    .foregroundStyle(Theme.primary)
                                                    .lineLimit(1)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.vertical, 4)
                                        .padding(.leading, 8)
                                        .padding(.trailing, 16)
                                        .frame(minHeight: 136)
                                        .background(
                                            Theme.card,
                                            in: RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
                                        )
                                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Swap to \(alternative.name)")
                                }
                            }
                            .padding(.top, 16)
                        }
                    }
                    .padding(.horizontal, Theme.Metrics.contentInset)
                    .padding(.bottom, 24)
                }
                .pageScroll()
            }
        } else {
            Color.clear.onAppear(perform: store.navigation.pop)
        }
    }

    private func swap(to replacement: ExerciseSummary) {
        guard let workout else { return }
        do {
            if store.activeWorkout.session?.workoutId == workout.id {
                if workout.planned != nil {
                    try PlannedSubstitution.substituteRunningPlannedExercise(
                        workout.id, exerciseId, replacement.id
                    )
                } else {
                    let entryId = try activeExerciseEntryId()
                    try store.trainingRecords.substituteExercise(
                        exerciseEntryId: entryId,
                        exerciseId: replacement.id
                    )
                    let ids = workout.exerciseIds.map { $0 == exerciseId ? replacement.id : $0 }
                    store.workouts.updateWorkout(workout.id, .init(exerciseIds: ids))
                    store.activeWorkout.syncExercises(ids)
                }
            } else if workout.planned != nil {
                try TrainingEdits.substituteScheduledPlannedExercise(
                    workout.id, exerciseId, replacement.id
                )
            } else {
                let ids = workout.exerciseIds.map { $0 == exerciseId ? replacement.id : $0 }
                store.workouts.updateWorkout(workout.id, .init(exerciseIds: ids))
            }
            issue = nil
            Haptics.trigger(.success)
            store.navigation.pop()
        } catch {
            issue = (error as? TrainingPersistenceError)?.message ?? error.localizedDescription
            Haptics.trigger(.warning)
        }
    }

    private func activeExerciseEntryId() throws -> String {
        guard let id = store.trainingRecords.data.activeWorkout?.exercises
            .first(where: { $0.exerciseId == exerciseId })?.id
        else { throw TrainingPersistenceError("Active exercise not found.") }
        return id
    }
}
