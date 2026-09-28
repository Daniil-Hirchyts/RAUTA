import SwiftUI

/// Behind the all-time figures: the same four at the top, then the best each
/// exercise has seen — its heaviest set, and the one-rep max that suggests.
struct SummaryRecordsScreen: View {
    private let store = AppStore.shared

    var body: some View {
        let totals = ProfileRecordsSection.Records(
            workouts: store.workouts.workouts,
            history: store.trainingRecords.trainingHistory()
        )
        let bests = SummaryAnalytics.records(store.trainingRecords.data.sessions)
        RautaScreen(
            title: "Records",
            backLabel: "Back to summary",
            onBack: store.navigation.pop
        ) {
            ScrollView {
                VStack(spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ProfileRecordCard(systemImage: "figure.strengthtraining.traditional", value: "\(totals.workouts)", label: "Workouts", accent: Theme.primary)
                        ProfileRecordCard(systemImage: "timer", value: SummaryAnalytics.duration(totals.trainingSeconds), label: "Training time", accent: Theme.gold)
                        ProfileRecordCard(systemImage: "flame.fill", value: "\(totals.bestStreak)", label: "Best streak", accent: Theme.lime)
                        ProfileRecordCard(systemImage: "checkmark.circle", value: "\(totals.exercisesLogged)", label: "Exercises logged", accent: Theme.ember)
                    }

                    SummarySectionLabel(text: "Personal bests")
                        .padding(.top, 4)
                    if bests.isEmpty {
                        Text("Log a set with a weight and its best shows up here.")
                            .font(Theme.sans(14, weight: .medium))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(bests.enumerated()), id: \.element.id) { index, record in
                                if index > 0 {
                                    Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1).padding(.leading, 72)
                                }
                                row(record)
                            }
                        }
                        .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: 0.5) }
                    }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, 32)
            }
            .pageScroll()
        }
    }

    private func row(_ record: SummaryAnalytics.ExerciseRecord) -> some View {
        let exercise = ExerciseCatalogue.byId[record.exerciseId]
        let each = record.basis == .perImplement ? " each" : ""
        return Button {
            Haptics.trigger(.selection)
            store.navigation.push(.exerciseDetail(exerciseId: record.exerciseId))
        } label: {
            HStack(spacing: 12) {
                ExerciseMediaView(exerciseId: record.exerciseId)
                    .padding(3)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.muted.opacity(0.7)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.map { WorkoutAgenda.name($0) } ?? "Exercise")
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(2)
                    Text("\(Resistance.formatKg(record.heaviestKg)) kg\(each) × \(Num.trimmed(record.heaviestReps)) · \(Wording.countLabel(record.sets, "set"))")
                        .font(Theme.sans(12, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Resistance.formatKg(record.estimatedMaxKg.rounded()))
                        .font(Theme.readout(20))
                        .foregroundStyle(Theme.primary)
                    Text("EST. 1RM")
                        .font(Theme.sans(8, weight: .black))
                        .kerning(0.9)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the exercise")
    }
}
