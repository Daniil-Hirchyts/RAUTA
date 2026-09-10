import SwiftUI

struct ProfileNameControl: View {
    @ObservedObject private var store = AppStore.shared
    @State private var draft = ""
    @FocusState private var focused: Bool
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
                            .frame(width: 32, height: 32).background(Theme.card, in: Circle())
                            .overlay(Circle().stroke(Theme.border))
                    }.accessibilityLabel("Clear name").padding(.bottom, 12)
                }
            }
            .onAppear { draft = store.trainingProfile.profile.name }
            .onChange(of: draft) { _, value in store.trainingProfile.updateProfile(.init(name: String(value.prefix(60)))) }
            .onSubmit { focused = false }
            .accessibilityLabel("Your name")
    }
}

struct ProfileExperienceControl: View {
    @ObservedObject private var store = AppStore.shared
    @State private var healthOpen = false
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
                            .background(selected ? Theme.primary.opacity(0.1) : Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous).strokeBorder(selected ? Theme.primary.opacity(0.6) : Theme.border))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Button {
                Haptics.trigger(.light)
                healthOpen = true
            } label: {
                HStack(spacing: 12) {
                    Text("Health").foregroundStyle(Theme.mutedForeground)
                    Rectangle().fill(Theme.border).frame(height: 1)
                    Text(healthSummary).lineLimit(1)
                    Image(systemName: "chevron.right").font(.system(size: 12))
                }
                .font(Theme.sans(14, weight: .semibold))
                .foregroundStyle(healthLimited ? Theme.primary : Theme.foreground)
                .padding(4)
            }.buttonStyle(.plain)
        }
        .overlay {
            AppModal(isPresented: healthOpen, label: "Health", onClose: { healthOpen = false }) {
                VStack(spacing: 16) {
                    Text("Anything to train around?")
                        .font(Theme.sans(18, weight: .black))
                        .multilineTextAlignment(.center)
                    ProfileHealthControl()
                    AppButton("Done", expands: true) { healthOpen = false }
                }
            }
        }
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
                    colors: [Theme.primary.opacity(0.34), .clear],
                    center: UnitPoint(x: 0.68, y: 0.78),
                    startRadius: 0,
                    endRadius: 180
                )
                if let image = StillImage.load(MediaLibrary.goalURL(slide.id)) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                }
            }
        }
    }
}

struct ProfileTopPanel: View {
    @ObservedObject private var store = AppStore.shared
    var step: ProfileStep
    var hasRightControl: Bool
    private var speech: String {
        let p = store.trainingProfile.profile
        switch step {
        case .about: return p.name.isEmpty ? "Tell me your name, then turn the dial to your age." : "Good to meet you, \(p.name). Age \(Num.trimmed(p.age)) — adjust the dial if needed."
        case .experience: return p.health.status == .healthy ? "\(ProfileVocabulary.experienceLabel(p.trainingExperience)). I’ll use this as your starting point." : "Noted. I will leave the planning to you and stay out of the way."
        case .goal: return "\(ProfileVocabulary.goalLabel(p.goal)). That's our direction."
        case .duration: return "\(Num.trimmed(p.preferredSessionDurationMinutes)) minutes. I’ll plan around the time you have."
        case .gym: return "Pick the equipment you actually have."
        case .health: return "Your limits matter. You can always build your own workout."
        }
    }
    private var mood: RautaMood {
        let profile = store.trainingProfile.profile
        switch step {
        case .about: return profile.name.isEmpty ? .listening : .curious
        case .experience: return .focused
        case .goal: return .happy
        case .duration, .health: return .calm
        case .gym: return .curious
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 68 + DeviceScreen.safeAreaInsets.top)
            Text(speech).font(Theme.sans(15, weight: .semibold)).tracking(-0.3).lineSpacing(2)
                .foregroundStyle(Theme.foreground).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.horizontal, 52).padding(.top, 16).padding(.bottom, 16)
        }.background {
            ZStack {
                Theme.card.opacity(0.85)
                RadialGradient(colors: [Theme.primary.opacity(0.24), .clear], center: UnitPoint(x: 0.8, y: 1.25), startRadius: 0, endRadius: 230)
            }.clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.surfaceRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.surfaceRadius).strokeBorder(Theme.border))
        }.overlay(alignment: .topTrailing) {
            RautaCharacter(mood: mood, reactionKey: speech)
                .frame(width: 72, height: 72)
                // Centre the 72pt character on the same header row as the
                // 44pt back/skip buttons instead of pinning it to the surface
                // edge above the Dynamic Island.
                .offset(y: Swift.max(0, DeviceScreen.safeAreaInsets.top - 2))
                .padding(.trailing, hasRightControl ? 58 : 6)
        }
    }
}
