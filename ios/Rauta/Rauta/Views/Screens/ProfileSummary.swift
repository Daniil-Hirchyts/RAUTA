import SwiftUI

/// Who the training is for, at the top of Summary: a compact card rather than
/// a page of its own. Tapping it opens the details it summarises.
struct ProfileIdentityCard: View {
    private let store = AppStore.shared

    private var profile: TrainingProfile { store.trainingProfile.profile }

    private var displayName: String {
        let value = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "You" : value
    }

    private var profileLine: String {
        "\(Int(profile.age)) years · \(ProfileVocabulary.experienceLabel(profile.trainingExperience))"
    }

    private var trainingLine: String {
        var parts = [
            ProfileVocabulary.goalLabel(profile.goal),
            "\(Int(profile.preferredSessionDurationMinutes)) min",
        ]
        let equipmentCount = store.filters.gymEquipment.count
        parts.append(equipmentCount == 0 ? "No equipment" : Wording.countLabel(equipmentCount, "item"))
        if !profile.priorityMuscles.isEmpty {
            let count = profile.priorityMuscles.count
            parts.append(count == 1 ? "1 priority" : "\(count) priorities")
        }
        if profile.health.status != .healthy { parts.append("Manual planning") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button {
            Haptics.trigger(.selection)
            store.navigation.push(.profileBasics, from: "summary-identity")
        } label: {
            HStack(spacing: 14) {
                DotMatrixEmblem(seed: profile.name, size: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(Theme.sans(20, weight: .black))
                        .kerning(-0.4)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    Text(profileLine)
                        .font(Theme.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.secondaryForeground)
                        .lineLimit(1)
                    Text(trainingLine)
                        .font(Theme.sans(12, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(16)
            .background { GradientCard(radius: 28, accent: Theme.primary) }
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .appZoomSource("summary-identity", cornerRadius: 28)
        .accessibilityLabel("\(displayName), \(profileLine), \(trainingLine)")
        .accessibilityHint("Opens your details")
    }
}

/// All-time records, at the foot of Summary.
struct ProfileRecordsSection: View {
    private let store = AppStore.shared

    private let recordColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    /// The four record figures, from one pass over the history. Building the
    /// training history converts every logged session, so it is done once per
    /// render rather than once per figure.
    struct Records {
        var workouts: Int
        var trainingSeconds: Double
        var bestStreak: Int
        var exercisesLogged: Int

        init(workouts allWorkouts: [Workout], history: TrainingHistory) {
            let completed = allWorkouts.filter { $0.completion != nil }
            workouts = Swift.max(completed.count, history.sessions.count)

            let structuredSeconds = history.sessions.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
            trainingSeconds = structuredSeconds > 0
                ? structuredSeconds
                : completed.reduce(0) { $0 + ($1.completion?.durationMs ?? 0) / 1_000 }

            bestStreak = StreakBuilder.build(completed).longestStreak

            let structuredExercises = history.sessions.reduce(0) { $0 + $1.exercises.count }
            exercisesLogged = structuredExercises > 0
                ? structuredExercises
                : completed.reduce(0) { $0 + ($1.completion?.completedExerciseIds.count ?? 0) }
        }
    }

    var body: some View {
        let records = Records(
            workouts: store.workouts.workouts,
            history: store.trainingRecords.trainingHistory()
        )
        VStack(alignment: .leading, spacing: 10) {
            Text("ALL TIME")
                .font(Theme.sans(10, weight: .black))
                .kerning(1.55)
                .foregroundStyle(Theme.mutedForeground)
                .padding(.horizontal, 4)

            SummaryCardLink(page: .summaryRecords, zoomID: "summary-records", cornerRadius: 28) {
                recordGrid(records)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordGrid(_ records: Records) -> some View {
        LazyVGrid(columns: recordColumns, spacing: 10) {
            ProfileRecordCard(
                systemImage: "figure.strengthtraining.traditional",
                value: "\(records.workouts)",
                label: "Workouts",
                accent: Theme.primary
            )
            ProfileRecordCard(
                systemImage: "timer",
                value: SummaryAnalytics.duration(records.trainingSeconds),
                label: "Training time",
                accent: Theme.gold
            )
            ProfileRecordCard(
                systemImage: "flame.fill",
                value: "\(records.bestStreak)",
                label: "Best streak",
                accent: Theme.lime
            )
            ProfileRecordCard(
                systemImage: "checkmark.circle",
                value: "\(records.exercisesLogged)",
                label: "Exercises logged",
                accent: Theme.ember
            )
        }
    }
}

struct ProfileRecordCard: View {
    let systemImage: String
    let value: String
    let label: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(accent)

            Text(value)
                .font(Theme.readout(value.count > 5 ? 25 : 31))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .background { GradientCard(radius: 28, accent: accent) }
        .accessibilityElement(children: .combine)
    }
}
