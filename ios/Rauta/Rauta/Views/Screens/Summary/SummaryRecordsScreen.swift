import SwiftUI

/// Behind the all-time figures: the best each exercise has seen — its heaviest
/// set, and the one-rep max that suggests.
///
/// The card that opens the page already shows the four totals large, so the
/// bests come first and the totals follow as one row. All time has nothing to
/// step through, so the page has no band at its foot.
struct SummaryRecordsScreen: View {
    private let store = AppStore.shared

    var body: some View {
        let bests = SummaryAnalytics.records(store.trainingRecords.data.sessions)
        let totals = ProfileRecordsSection.Records(
            workouts: store.workouts.workouts,
            history: store.trainingRecords.trainingHistory()
        )
        SummaryDetailPage(title: "Records", period: "All time") {
            if bests.isEmpty {
                EmptyStatePlaceholder(
                    symbol: "trophy",
                    title: "No personal bests yet",
                    message: "Log a set with a weight, and the best each exercise has seen shows up here."
                )
                .padding(.vertical, 24)
            } else {
                SummarySectionLabel(text: "Personal bests")
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

            SummarySectionLabel(text: "Totals")
                .padding(.top, 8)
            HStack(spacing: 12) {
                SummaryStat(value: "\(totals.workouts)", label: "Workouts", accent: Theme.primary)
                SummaryStat(value: SummaryAnalytics.duration(totals.trainingSeconds), label: "Time", accent: Theme.gold)
                SummaryStat(value: "\(totals.bestStreak)", label: "Best streak", accent: Theme.lime)
                SummaryStat(value: "\(totals.exercisesLogged)", label: "Exercises", accent: Theme.ember)
            }
            .padding(16)
            .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: 0.35) }
        }
    }

    private func row(_ record: SummaryAnalytics.ExerciseRecord) -> some View {
        let exercise = ExerciseCatalogue.byId[record.exerciseId]
        let each = record.basis == .perImplement ? " each" : ""
        return Button {
            Haptics.trigger(.selection)
            // Inside this page's stack, so Back comes back here.
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
                    Text("Best \(Resistance.formatKg(record.heaviestKg)) kg\(each) × \(Num.trimmed(record.heaviestReps)) · \(Wording.countLabel(record.sets, "set"))")
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.mutedForeground.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the exercise")
    }
}
