import SwiftUI

struct ProfileDashboard: View {
    @Environment(\.appSafeAreaInsets) private var safeAreaInsets
    @ObservedObject private var store = AppStore.shared

    private let recordColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var profile: TrainingProfile { store.trainingProfile.profile }

    private var completedWorkouts: [Workout] {
        store.workouts.workouts.filter { $0.completion != nil }
    }

    private var history: TrainingHistory {
        store.trainingRecords.trainingHistory()
    }

    private var streak: Streak {
        StreakBuilder.build(completedWorkouts)
    }

    private var displayName: String {
        let value = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Your profile" : value
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

    private var totalWorkoutCount: Int {
        Swift.max(completedWorkouts.count, history.sessions.count)
    }

    private var totalTrainingSeconds: Double {
        let structured = history.sessions.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
        if structured > 0 { return structured }
        return completedWorkouts.reduce(0) {
            $0 + ($1.completion?.durationMs ?? 0) / 1_000
        }
    }

    private var completedExerciseCount: Int {
        let structured = history.sessions.reduce(0) { $0 + $1.exercises.count }
        if structured > 0 { return structured }
        return completedWorkouts.reduce(0) {
            $0 + ($1.completion?.completedExerciseIds.count ?? 0)
        }
    }

    private var achievements: [ProfileAchievement] {
        [
            ProfileAchievement(
                title: "First session",
                detail: "Complete one workout",
                systemImage: "flag.checkered",
                unlocked: totalWorkoutCount >= 1
            ),
            ProfileAchievement(
                title: "Ten strong",
                detail: "Complete 10 workouts",
                systemImage: "10.circle.fill",
                unlocked: totalWorkoutCount >= 10
            ),
            ProfileAchievement(
                title: "On a roll",
                detail: "Reach a 3-day streak",
                systemImage: "flame.fill",
                unlocked: streak.longestStreak >= 3
            ),
            ProfileAchievement(
                title: "Ten hours",
                detail: "Log 10 hours of training",
                systemImage: "timer",
                unlocked: totalTrainingSeconds >= 36_000
            ),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                identity

                section(title: "Records") {
                    LazyVGrid(columns: recordColumns, spacing: 10) {
                        ProfileRecordCard(
                            systemImage: "figure.strengthtraining.traditional",
                            value: "\(totalWorkoutCount)",
                            label: "Workouts",
                            accent: Theme.primary
                        )
                        ProfileRecordCard(
                            systemImage: "timer",
                            value: durationLabel(totalTrainingSeconds),
                            label: "Training time",
                            accent: Theme.gold
                        )
                        ProfileRecordCard(
                            systemImage: "flame.fill",
                            value: "\(streak.longestStreak)",
                            label: "Best streak",
                            accent: Theme.lime
                        )
                        ProfileRecordCard(
                            systemImage: "checkmark.circle",
                            value: "\(completedExerciseCount)",
                            label: "Exercises logged",
                            accent: Theme.ember
                        )
                    }
                }

                section(title: "Achievements") {
                    VStack(spacing: 10) {
                        ForEach(achievements) { achievement in
                            ProfileAchievementRow(achievement: achievement)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 200)
        }
        .contentMargins(
            .top,
            Theme.Metrics.headerHeight + safeAreaInsets.top + 18,
            for: .scrollContent
        )
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
            }
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

private struct ProfileAchievement: Identifiable {
    let title: String
    let detail: String
    let systemImage: String
    let unlocked: Bool

    var id: String { title }
}

private struct ProfileAchievementRow: View {
    let achievement: ProfileAchievement

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: achievement.unlocked ? achievement.systemImage : "lock.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(achievement.unlocked ? Theme.primary : Theme.mutedForeground)
                .frame(width: 44, height: 44)
                .background(
                    (achievement.unlocked ? Theme.primary : Theme.mutedForeground).opacity(0.10),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title)
                    .font(Theme.sans(15, weight: .bold))
                    .foregroundStyle(Theme.foreground)

                Text(achievement.unlocked ? "Unlocked" : achievement.detail)
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
            }

            Spacer(minLength: 8)

            if achievement.unlocked {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.primary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 68)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
