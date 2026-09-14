import SwiftUI

struct OnboardingScreen: View {
    var body: some View {
        ProfileStepFlow(
            steps: [.welcome, .about, .experience, .goal, .priorities, .duration, .gym, .ready],
            onboarding: true
        ) {
            Haptics.trigger(.success)
            AppStore.shared.trainingProfile.completeOnboarding()
            AppStore.shared.navigation.reset([.workouts])
        }
    }
}

enum ProfileStep: String {
    case welcome = "Meet RAUTA"
    case about = "About you", experience = "Experience", goal = "Goal"
    case priorities = "Priority muscles"
    case duration = "Session length", gym = "Your gym", health = "Health"
    case ready = "Ready to train"
}

/// Mirrors ProfileStepFlow in profile-pages.tsx; settings reuses these steps.
struct ProfileStepFlow: View {
    @Environment(\.appSafeAreaInsets) private var safeAreaInsets
    @ObservedObject private var store = AppStore.shared
    let steps: [ProfileStep]
    var onboarding = false
    let onFinish: () -> Void
    @State private var index = 0
    @State private var nameEntryFocused = false
    @State private var prioritySide: BodySide = .front
    private var step: ProfileStep { steps[index] }
    private var isStoryStep: Bool { step == .welcome || step == .ready }
    private var isEnteringName: Bool { step == .about && nameEntryFocused }
    private var actionTitle: String {
        if step == .welcome { return "Set up RAUTA" }
        if index == steps.count - 1 { return onboarding ? "Start training" : "Done" }
        return "Continue"
    }

    var body: some View {
        AppShell(commandsVisible: !isEnteringName) {
            GeometryReader { proxy in
                AppTitledPage {
                    header
                } content: {
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            if isStoryStep {
                                profileContent
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                    .padding(.horizontal, 12)
                                    .belowPageHeader()
                                    .padding(.bottom, 12)
                            } else if step == .about || step == .duration {
                                VStack(spacing: 0) {
                                    Spacer(minLength: 20)
                                    if step == .about {
                                        ProfileNameControl { nameEntryFocused = $0 }
                                            .padding(.horizontal, 12)
                                        Spacer(minLength: 20)
                                    }
                                    if step == .duration || !nameEntryFocused {
                                        ProfileDial(duration: step == .duration)
                                    }
                                }
                                .belowPageHeader()
                                // The app's safe area takes in an open keyboard, so
                                // the name centres in what the keyboard leaves.
                                .padding(.bottom, isEnteringName ? safeAreaInsets.bottom : 0)
                            } else if step == .priorities {
                                ProfilePrioritiesMap(side: $prioritySide, showsFlipButton: true)
                                    .padding(.horizontal, 12)
                                    .belowPageHeader()
                                    .padding(.bottom, 12)
                            } else {
                                ScrollView {
                                    profileContent
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: max(0, proxy.size.height - standardContentTop - bottomClearance))
                                        .padding(.bottom, bottomClearance)
                                        .padding(.horizontal, 12)
                                }
                                .pageScroll()
                            }
                        }
                        .id(step)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))

                        if step == .gym {
                            VStack {
                                Spacer()
                                EquipmentPresets(value: store.filters.gymEquipment, onChange: store.filters.setGymEquipment)
                                    .padding(.bottom, 12)
                                    .padding(.top, 28)
                            }
                        }
                    }
                }
            }
        } controls: {
            AppButton(actionTitle, size: .cta, expands: true) {
                if index == steps.count - 1 { onFinish() }
                else {
                    withAnimation(Theme.Motion.pageEnter) { index += 1 }
                    Haptics.trigger(.medium)
                }
            }.id(index)
        }
        .onChange(of: index) { _, _ in nameEntryFocused = false }
    }

    /// Where a scrolling step's content starts under a plain title bar.
    private var standardContentTop: CGFloat {
        safeAreaInsets.top + Theme.Metrics.headerHeight + Theme.Metrics.headerContentGap
    }

    private var bottomClearance: CGFloat { step == .gym ? 112 : 56 }

    private var header: some View {
        AppShellHeader(
            title: step.rawValue,
            left: {
                if index > 0 || !onboarding {
                    AppHeaderButton(
                        systemImage: "chevron.left",
                        label: index > 0 ? "Previous step" : "Back"
                    ) {
                        if index > 0 {
                            withAnimation(Theme.Motion.pageExit) { index -= 1 }
                            Haptics.trigger(.selection)
                        } else {
                            onFinish()
                        }
                    }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            },
            right: {
                if isStoryStep {
                    Color.clear.frame(width: 44, height: 44)
                } else {
                    ProfileTopPanel(step: step)
                        .headerBadge
                }
            },
            above: {
                if steps.count > 1 {
                    FlowProgress(stage: index + 1, steps: steps.count)
                }
            },
            below: {
                if !isStoryStep {
                    ProfileTopPanel(step: step)
                }
            }
        )
    }

    @ViewBuilder private var profileContent: some View {
        switch step {
        case .welcome: OnboardingIntroView()
        case .experience: ProfileExperienceControl()
        case .goal: ProfileGoalControl().padding(.horizontal, -12)
        case .gym: EquipmentGrid(selected: store.filters.gymEquipment, onToggle: store.filters.toggleGymEquipment)
        case .health: ProfileHealthControl()
        case .ready: OnboardingReadyView()
        default: EmptyView()
        }
    }
}

private struct OnboardingIntroView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 4)

            ZStack {
                Circle()
                    .fill(Theme.primary.opacity(0.10))
                    .frame(width: 156, height: 156)
                    .blur(radius: 24)

                RautaCharacter(
                    mood: .excited,
                    reactionKey: "onboarding-welcome",
                    reaction: .gearUp
                )
                .frame(width: 172, height: 172)
            }

            VStack(spacing: 8) {
                Text("Training that fits your week")
                    .font(Theme.sans(26, weight: .black))
                    .tracking(-0.8)
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)

                Text("A few quick choices. A plan that fits.")
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                OnboardingPill(systemImage: "clock", title: "Your time")
                OnboardingPill(systemImage: "target", title: "Your goal")
                OnboardingPill(systemImage: "dumbbell", title: "Your gym")
            }

            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OnboardingPill: View {
    let systemImage: String
    let title: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.primary)
            Text(title)
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .padding(.horizontal, 8)
        .background(
            Theme.card.opacity(0.82),
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.border)
        )
    }
}

private struct OnboardingReadyView: View {
    @ObservedObject private var store = AppStore.shared

    private var equipmentSummary: String {
        let count = store.filters.gymEquipment.count
        return count == 0 ? "No equipment selected" : "\(count) equipment types"
    }

    var body: some View {
        let profile = store.trainingProfile.profile

        VStack(spacing: 22) {
            Spacer(minLength: 4)

            RautaCharacter(
                mood: .proud,
                reactionKey: "onboarding-ready",
                reaction: .celebrate
            )
            .frame(width: 190, height: 190)

            VStack(spacing: 8) {
                Text("Your plan starts here")
                    .font(Theme.sans(26, weight: .black))
                    .tracking(-0.8)
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)

                Text("You can change any answer in Settings.")
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 0) {
                OnboardingSummaryRow(
                    systemImage: "target",
                    label: "Goal",
                    value: ProfileVocabulary.goalLabel(profile.goal)
                )
                Divider().overlay(Theme.border)
                OnboardingSummaryRow(
                    systemImage: "figure.strengthtraining.traditional",
                    label: "Experience",
                    value: ProfileVocabulary.experienceLabel(profile.trainingExperience)
                )
                Divider().overlay(Theme.border)
                OnboardingSummaryRow(
                    systemImage: "clock",
                    label: "Session",
                    value: "\(Num.trimmed(profile.preferredSessionDurationMinutes)) min"
                )
                Divider().overlay(Theme.border)
                OnboardingSummaryRow(
                    systemImage: "dumbbell",
                    label: "Equipment",
                    value: equipmentSummary
                )
            }
            .background(
                Theme.card.opacity(0.88),
                in: RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
                    .strokeBorder(Theme.border)
            )

            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OnboardingSummaryRow: View {
    let systemImage: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 28)

            Text(label)
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)

            Spacer(minLength: 12)

            Text(value)
                .font(Theme.sans(14, weight: .bold))
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

