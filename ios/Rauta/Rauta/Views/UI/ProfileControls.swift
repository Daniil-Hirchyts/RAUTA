import SwiftUI

struct ProfileNameControl: View {
    @ObservedObject private var store = AppStore.shared
    @State private var draft = ""
    @FocusState private var focused: Bool
    var onFocusChange: (Bool) -> Void = { _ in }

    var body: some View {
        TextField("", text: $draft, prompt: Text("Your name").foregroundColor(Theme.mutedForeground.opacity(0.3)))
            .font(Theme.sans(36, weight: .black)).tracking(-1.08)
            .multilineTextAlignment(.center).foregroundStyle(Theme.foreground)
            .textContentType(.givenName).submitLabel(.done).focused($focused)
            .tint(Theme.primary).padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.border).frame(height: 1)
                Rectangle().fill(Theme.primaryGradient).frame(height: 3)
                    .scaleEffect(x: focused || !draft.isEmpty ? 1 : 0)
                    .animation(.easeOut(duration: 0.5), value: focused || !draft.isEmpty)
            }
            .overlay(alignment: .trailing) {
                if !draft.isEmpty {
                    Button { draft = "" } label: {
                        Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(Theme.mutedForeground)
                    }
                    .buttonStyle(.glassControl(.clear, .circle(diameter: 32), legacyFill: Theme.card))
                    .accessibilityLabel("Clear name").padding(.bottom, 12)
                }
            }
            .onAppear { draft = store.trainingProfile.profile.name }
            .onChange(of: draft) { _, value in store.trainingProfile.updateProfile(.init(name: String(value.prefix(60)))) }
            .onChange(of: focused) { _, value in onFocusChange(value) }
            .onSubmit { focused = false }
            .accessibilityLabel("Your name")
    }
}

struct ProfileExperienceControl: View {
    @ObservedObject private var store = AppStore.shared
    private var healthLimited: Bool { store.trainingProfile.profile.health.status != .healthy }
    private var healthSummary: String {
        guard healthLimited else { return "Nothing to train around" }
        return Wording.countLabel(store.trainingProfile.profile.health.reasons?.count ?? 0, "limitation")
    }
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                ForEach(Array(ProfileVocabulary.experienceChoices.enumerated()), id: \.offset) { index, item in
                    let selected = store.trainingProfile.profile.trainingExperience == item.experience
                    Button { store.trainingProfile.updateProfile(.init(trainingExperience: item.experience)); Haptics.trigger(.selection) } label: {
                        HStack(spacing: 16) {
                            HStack(alignment: .bottom, spacing: 4) {
                                ForEach(0..<3) { bar in Capsule().fill(bar <= index ? Theme.primary : Theme.foreground.opacity(0.2)).frame(width: 6, height: CGFloat(9 + bar * 7)) }
                            }.padding(.horizontal, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.choice.title).font(Theme.sans(16, weight: .bold)).foregroundStyle(Theme.foreground)
                                Text(item.choice.description).font(Theme.sans(13)).foregroundStyle(Theme.mutedForeground).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            ProfileCheck(checked: selected)
                        }.padding(16)
                            .background(
                                selected ? Theme.primary.opacity(0.1) : Theme.card,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous)
                                    .strokeBorder(selected ? Theme.primary.opacity(0.6) : Theme.border)
                            )
                    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            // Native menu so it morphs out of the row on iOS 26+ instead of
            // floating in as an arrowed popover.
            Menu {
                Section("Anything to train around?") {
                    healthToggle(
                        "Nothing to train around",
                        isOn: store.trainingProfile.profile.health.status == .healthy,
                        action: store.trainingProfile.setHealthy
                    )

                    ForEach(ProfileVocabulary.healthLimitations, id: \.self) { limitation in
                        healthToggle(
                            ProfileVocabulary.label(for: limitation),
                            isOn: (store.trainingProfile.profile.health.reasons ?? []).contains(limitation)
                        ) {
                            store.trainingProfile.toggleHealthLimitation(limitation)
                        }
                        // Limitations stack, so keep the menu open while picking.
                        .menuActionDismissBehavior(.disabled)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text("Health").foregroundStyle(Theme.mutedForeground)
                    Rectangle().fill(Theme.border).frame(height: 1)
                    Text(healthSummary).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12))
                }
                .font(Theme.sans(14, weight: .semibold))
                .foregroundStyle(healthLimited ? Theme.primary : Theme.foreground)
                .padding(4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuOrder(.fixed)
            .tint(Theme.primary)
        }
    }

    private func healthToggle(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Toggle(title, isOn: Binding(
            get: { isOn },
            set: { _ in
                Haptics.trigger(.selection)
                action()
            }
        ))
    }
}

struct ProfileCheck: View {
    var checked: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(checked ? Theme.primary : .clear)
            RoundedRectangle(cornerRadius: 7).strokeBorder(checked ? Theme.primary : Theme.border, lineWidth: 1.5)
            if checked { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primaryForeground) }
        }.frame(width: 24, height: 24).accessibilityHidden(true)
    }
}

struct ProfileHealthControl: View {
    @ObservedObject private var store = AppStore.shared
    var body: some View {
        VStack(spacing: 12) {
            Text("Plans are only built for you while none of these apply. Browsing and building your own workouts always works.")
                .font(Theme.sans(14)).foregroundStyle(Theme.mutedForeground).lineSpacing(4)
            VStack(spacing: 0) {
                healthRow("Nothing to train around", checked: store.trainingProfile.profile.health.status == .healthy, action: store.trainingProfile.setHealthy)
                ForEach(ProfileVocabulary.healthLimitations, id: \.self) { limitation in
                    Rectangle().fill(Theme.border).frame(height: 1)
                    healthRow(ProfileVocabulary.label(for: limitation), checked: (store.trainingProfile.profile.health.reasons ?? []).contains(limitation)) {
                        store.trainingProfile.toggleHealthLimitation(limitation)
                    }
                }
            }.background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.xl2))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl2).strokeBorder(Theme.border))
        }
    }
    private func healthRow(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.trigger(.selection)
            action()
        } label: {
            HStack(spacing: 12) {
                Text(title).font(Theme.sans(15, weight: checked ? .bold : .regular)).foregroundStyle(checked ? Theme.foreground : Theme.mutedForeground)
                Spacer(); ProfileCheck(checked: checked)
            }.padding(.horizontal, 14).padding(.vertical, 12)
        }.buttonStyle(.plain)
    }
}

struct ProfileGoalControl: View {
    @ObservedObject private var store = AppStore.shared
    private var choices: [(goal: TrainingGoal, choice: ProfileChoice)] { ProfileVocabulary.goalChoices }

    var body: some View {
        CoverflowCarousel(
            label: "Training goal",
            slides: choices.map {
                CoverflowSlide(
                    id: $0.goal,
                    title: $0.choice.title,
                    description: $0.choice.description
                )
            },
            value: store.trainingProfile.profile.goal,
            onChange: { goal in
                store.trainingProfile.updateProfile(.init(goal: goal))
            }
        ) { slide in
            ZStack {
                Theme.muted
                RadialGradient(
                    colors: [Theme.primary.opacity(0.28), Theme.oxblood.opacity(0.12), .clear],
                    center: UnitPoint(x: 0.68, y: 0.74),
                    startRadius: 0,
                    endRadius: 220
                )
                GoalImageView(goal: slide.id)
            }
        }
    }
}

/// RAUTA's line for a profile step, carried under the step's title, and the
/// badge it speaks from.
struct ProfileTopPanel: View {
    @ObservedObject private var store = AppStore.shared
    var step: ProfileStep
    private var speech: String {
        let p = store.trainingProfile.profile
        switch step {
        case .welcome: return "I’ll learn the constraints that matter, then help you train around them."
        case .about: return p.name.isEmpty ? "Tell me your name, then turn the dial to your age." : "Good to meet you, \(p.name). Age \(Num.trimmed(p.age)) — adjust the dial if needed."
        case .experience: return p.health.status == .healthy ? "\(ProfileVocabulary.experienceLabel(p.trainingExperience)). I’ll use this as your starting point." : "Noted. I will leave the planning to you and stay out of the way."
        case .goal: return "\(ProfileVocabulary.goalLabel(p.goal)). That's our direction."
        case .priorities:
            return p.priorityMuscles.isEmpty
                ? "Tap the muscles you want to grow first. Skip it and I’ll keep things balanced."
                : "\(Wording.countLabel(p.priorityMuscles.count, "muscle")) in focus. They’ll get more of the work."
        case .duration: return "\(Num.trimmed(p.preferredSessionDurationMinutes)) minutes. I’ll plan around the time you have."
        case .gym: return "Pick the equipment you actually have."
        case .health: return "Your limits matter. You can always build your own workout."
        case .ready: return "That’s enough context. I can make the rest practical from here."
        }
    }
    private var mood: RautaMood {
        let profile = store.trainingProfile.profile
        switch step {
        case .welcome: return .excited
        case .about: return profile.name.isEmpty ? .listening : .curious
        case .experience: return .focused
        case .goal: return .happy
        case .priorities: return profile.priorityMuscles.isEmpty ? .curious : .focused
        case .duration, .health: return .calm
        case .gym: return .curious
        case .ready: return .proud
        }
    }
    private var reaction: RautaReaction {
        switch step {
        case .welcome: return .gearUp
        case .about: return .peek
        case .experience: return .acknowledge
        case .goal: return .spinRight
        case .priorities: return .blinkDouble
        case .duration: return .turnaround
        case .gym: return .wink
        case .health: return .relieved
        case .ready: return .celebrate
        }
    }
    var body: some View {
        Text(speech).font(Theme.sans(15, weight: .semibold)).tracking(-0.3).lineSpacing(2)
            .foregroundStyle(Theme.foreground).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.horizontal, 40).padding(.top, 6)
    }

    var headerBadge: some View {
        RautaHeaderBadge(
            mood: mood,
            reactionKey: step.rawValue,
            reaction: reaction
        )
    }
}
