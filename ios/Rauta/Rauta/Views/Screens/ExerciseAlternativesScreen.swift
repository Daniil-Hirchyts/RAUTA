import SwiftUI

struct ExerciseAlternativesScreen: View {
    private let store = AppStore.shared
    let exerciseId: String
    let workoutId: String

    @State private var equipment: String?
    @State private var issue: String?
    /// Searched for once as the page opens, away from the main actor; nil
    /// until then. The search walks the whole catalogue, and running it per
    /// render made the page slow to open.
    @State private var alternatives: [ExerciseSummary]?
    /// The planned search's answer, handed to the swap so it isn't run twice.
    @State private var checkedIds: [String]?

    private var source: ExerciseSummary? { ExerciseCatalogue.byId[exerciseId] }
    private var workout: Workout? { store.workouts.workout(workoutId) }
    private var allAlternatives: [ExerciseSummary] { alternatives ?? [] }

    private func loadAlternatives() async {
        guard let source else { return }
        guard workout?.planned != nil else {
            alternatives = ExerciseCatalogue.findAlternatives(to: source, excluding: workout?.exerciseIds ?? [])
            return
        }
        let ids = await TrainingWorkflow.searchReplacements(
            TrainingWorkflow.replacementQuery(exerciseId, workoutId: workoutId)
        )
        guard !Task.isCancelled else { return }
        checkedIds = ids
        alternatives = ids.compactMap { ExerciseCatalogue.byId[$0] }
    }
    private var visibleAlternatives: [ExerciseSummary] {
        allAlternatives.filter { equipment == nil || $0.equipment == equipment }
    }
    private var equipmentOptions: [String] {
        var seen = Set<String>()
        return allAlternatives.map(\.equipment).filter { seen.insert($0).inserted }
    }

    /// When the exercise being replaced needs kit the profile doesn't have:
    /// why it's worth replacing.
    private var headerNote: String? {
        guard workout?.planned != nil else { return nil }
        let filters = store.filters
        let missing = TrainingEngineAdapter.missingRequirements(
            exerciseId, equipment: filters.gymEquipment, fixtures: filters.effectiveFixtures
        ).map { TrainingEngineAdapter.fixtureLabel($0).lowercased() }
        guard !missing.isEmpty else { return nil }
        return "Needs \(Wording.list(missing))"
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
                                if let headerNote {
                                    Text(headerNote)
                                        .font(Theme.sans(13, weight: .semibold))
                                        .foregroundStyle(Theme.primary)
                                }
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

                        if alternatives == nil {
                            MatrixLoader(variant: .scan, label: "Finding alternatives", dot: 3, gap: 3)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 48)
                        } else if visibleAlternatives.isEmpty {
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
            .task(id: exerciseId) { await loadAlternatives() }
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
                        workout.id, exerciseId, replacement.id, checked: checkedIds
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
                    workout.id, exerciseId, replacement.id, checked: checkedIds
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
