import SwiftUI

struct OnboardingScreen: View {
    var body: some View {
        ProfileStepFlow(steps: [.about, .experience, .goal, .duration, .gym], onboarding: true) {
            Haptics.trigger(.success)
            AppStore.shared.trainingProfile.completeOnboarding()
            AppStore.shared.navigation.reset([.workouts])
        }
    }
}

enum ProfileStep: String {
    case about = "About you", experience = "Experience", goal = "Goal"
    case duration = "Session length", gym = "Your gym", health = "Health"
}

/// Mirrors ProfileStepFlow in profile-pages.tsx; settings reuses these steps.
struct ProfileStepFlow: View {
    @Environment(\.appSafeAreaInsets) private var safeAreaInsets
    @ObservedObject private var store = AppStore.shared
    let steps: [ProfileStep]
    var onboarding = false
    let onFinish: () -> Void
    @State private var index = 0
    private var step: ProfileStep { steps[index] }

    var body: some View {
        AppShell(commandsVisible: true) {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 68 + safeAreaInsets.top)
                        if step == .about || step == .duration {
                            Spacer(minLength: 20)
                            if step == .about {
                                ProfileNameControl().padding(.horizontal, 12)
                                Spacer(minLength: 20)
                            }
                            ProfileDial(duration: step == .duration)
                        } else {
                            ScrollView {
                                profileContent
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: max(0, proxy.size.height - 88 - (step == .gym ? 112 : 56)))
                                    .padding(.top, 20)
                                    .padding(.bottom, step == .gym ? 112 : 56)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }.id(step).transition(.opacity)
                    ProfileTopPanel(step: step, hasRightControl: onboarding)
                    header
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
        } controls: {
            AppButton(index == steps.count - 1 ? (onboarding ? "Start training" : "Done") : "Continue", size: .cta, expands: true) {
                if index == steps.count - 1 { onFinish() }
                else { withAnimation(.easeOut(duration: 0.2)) { index += 1 }; Haptics.trigger(.medium) }
            }.id(index)
        }
    }

    private var header: some View {
        ZStack {
            Text(step.rawValue)
                .font(Theme.sans(20, weight: .heavy))
                .tracking(-0.5)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) {
                    if steps.count > 1 { FlowProgress(stage: index + 1, steps: steps.count).offset(y: -7) }
                }
                .padding(.horizontal, 56)

            HStack(spacing: 0) {
                if index > 0 || !onboarding {
                    AppHeaderButton(systemImage: "chevron.left", label: index > 0 ? "Previous step" : "Back") {
                        if index > 0 { index -= 1 } else { onFinish() }
                    }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
                Spacer(minLength: 0)
                if onboarding {
                    AppHeaderButton(systemImage: "xmark", label: "Skip setup") {
                        Haptics.trigger(.light)
                        store.trainingProfile.completeOnboarding()
                        store.navigation.reset([.workouts])
                    }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
        }
        .frame(minHeight: 44)
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, 12)
        .padding(.top, 12 + safeAreaInsets.top)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var profileContent: some View {
        switch step {
        case .experience: ProfileExperienceControl()
        case .goal: ProfileGoalControl().padding(.horizontal, -12)
        case .gym: EquipmentGrid(selected: store.filters.gymEquipment, onToggle: store.filters.toggleGymEquipment)
        case .health: ProfileHealthControl()
        default: EmptyView()
        }
    }
}

struct ChoiceList<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }.background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.border))
    }
}
