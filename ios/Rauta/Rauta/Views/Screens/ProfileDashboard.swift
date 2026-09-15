import SwiftUI

struct ProfileDashboard: View {
    @ObservedObject private var store = AppStore.shared
    @Environment(\.rautaOnStage) private var onStage
    /// Whether Profile is the tab on screen. The avatar is built once and
    /// kept; switching tabs only brings it in or sends it away.
    let isActive: Bool

    private let recordColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var profile: TrainingProfile { store.trainingProfile.profile }

    /// The four record figures, from one pass over the history. Building the
    /// training history converts every logged session, so it is done once per
    /// render rather than once per figure.
    private struct Records {
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

    private var displayName: String {
        let value = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Rauta" : value
    }

    private var profileLine: String {
        "\(Int(profile.age)) years · \(ProfileVocabulary.experienceLabel(profile.trainingExperience))"
    }

    private var trainingLine: String {
        "\(ProfileVocabulary.goalLabel(profile.goal)) · \(Int(profile.preferredSessionDurationMinutes)) min sessions"
    }

    private var setupLine: String {
        var parts: [String] = []
        let equipmentCount = store.filters.gymEquipment.count
        parts.append(
            equipmentCount == 0
                ? "No equipment saved"
                : Wording.countLabel(equipmentCount, "equipment item")
        )

        let priorityCount = profile.priorityMuscles.count
        if priorityCount > 0 {
            parts.append(Wording.countLabel(priorityCount, "priority muscle"))
        }
        if profile.health.status != .healthy {
            parts.append("Manual planning")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let records = Records(
            workouts: store.workouts.workouts,
            history: store.trainingRecords.trainingHistory()
        )
        ScrollView {
            VStack(spacing: 24) {
                identity

                section(title: "Records") {
                    LazyVGrid(columns: recordColumns, spacing: 10) {
                        ProfileRecordCard(
                            systemImage: "figure.strengthtraining.traditional",
                            value: "\(records.workouts)",
                            label: "Workouts",
                            accent: Theme.primary
                        )
                        ProfileRecordCard(
                            systemImage: "timer",
                            value: durationLabel(records.trainingSeconds),
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
            .padding(.horizontal, 12)
            .padding(.bottom, 120)
        }
        .pageScroll()
        .scrollIndicators(.hidden)
    }

    private var identity: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.primary.opacity(0.07))
                    .frame(width: 144, height: 144)
                    .blur(radius: 18)

                Color.clear
                    .frame(width: 132, height: 132)
                    .glassSurface(
                        .regular,
                        in: Circle(),
                        border: Theme.Glassware.edge,
                        legacyFill: Theme.card.opacity(0.78)
                    )
                    .allowsHitTesting(false)

                RautaCharacter(mood: .happy)
                    .frame(width: 126, height: 126)
                    .environment(\.rautaOnStage, onStage && isActive)
            }
            // RAUTA arrives from the tab bar as the page changes: the one there
            // shrinks away while this one grows in.
            .scaleEffect(isActive ? 1 : 0.82)
            .opacity(isActive ? 1 : 0)
            .frame(width: 148, height: 148)
            .frame(height: 148)
            .accessibilityLabel("RAUTA profile avatar")

            VStack(spacing: 5) {
                Text(displayName)
                    .font(Theme.sans(28, weight: .black))
                    .kerning(-0.7)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(profileLine)
                    .font(Theme.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.secondaryForeground)

                Text(trainingLine)
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)

                Text(setupLine)
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground.opacity(0.86))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 2)
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(Theme.sans(10, weight: .black))
                .kerning(1.55)
                .foregroundStyle(Theme.mutedForeground)
                .padding(.horizontal, 4)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func durationLabel(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}

private struct ProfileRecordCard: View {
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
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
