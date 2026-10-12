import SwiftUI

/// Help me adjust: when a session was missed, time is short, or some equipment
/// isn't there this week. RAUTA prepares the change, shows every workout it
/// touches and why, and saves nothing until you keep it.
struct AdjustWeekScreen: View {
    private let store = AppStore.shared

    private enum Scenario: Hashable { case missed, time, equipment }

    private enum Phase {
        case choosing
        case working
        case proposed(CoachingProposal)
        case applied(CoachingProposal, CoachingUndo)
    }

    @State private var scenario: Scenario?
    @State private var missedId: String?
    @State private var minutes = 30
    @State private var unavailable: Set<String> = []
    @State private var phase = Phase.choosing
    @State private var issue: String?
    @State private var work: Task<Void, Never>?

    private var week: WeekProgress { WeekProgress.current() }
    private var missed: [Workout] { week.missed }
    private var hasPlan: Bool { TrainingPlan.activeProgramRecord() != nil }

    var body: some View {
        RautaScreen(
            title: "Help me adjust",
            backLabel: "Close",
            onBack: { work?.cancel(); store.navigation.pop() },
            right: { RautaHeaderBadge(mood: mood) }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch phase {
                    case .choosing:
                        chooser
                    case .working:
                        RautaThinkingStage(
                            thoughts: ["Looking at what's left this week…", "Keeping your completed sessions as they are…", "Checking every session still fits…"],
                            chips: []
                        )
                        .frame(height: 420)
                        .padding(.horizontal, -Theme.Metrics.contentInset)
                    case .proposed(let proposal):
                        CoachingProposalView(proposal: proposal)
                    case .applied(let proposal, _):
                        Label("Saved. Undo puts your week back exactly as it was.", systemImage: "checkmark.circle.fill")
                            .font(Theme.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.success)
                            .fixedSize(horizontal: false, vertical: true)
                        CoachingProposalView(proposal: proposal, applied: true)
                    }
                    if let issue { InlineNotice(message: issue, isError: true) }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, 24)
            }
            .pageScroll()
        } controls: {
            controls
        }
        .onAppear {
            if scenario == nil { scenario = missed.isEmpty ? nil : .missed }
            if missedId == nil { missedId = missed.first?.id }
            let usual = Int(store.trainingProfile.profile.preferredSessionDurationMinutes)
            minutes = Swift.max(20, Swift.min(usual - 15, 30))
        }
        .onDisappear { work?.cancel() }
    }

    // MARK: Choosing

    @ViewBuilder private var chooser: some View {
        Text("What changed this week?")
            .font(Theme.sans(20, weight: .heavy))
            .foregroundStyle(Theme.foreground)
            .accessibilityAddTraits(.isHeader)

        VStack(spacing: 10) {
            scenarioCard(
                .missed, icon: "calendar.badge.exclamationmark",
                title: "I missed a session",
                detail: missed.isEmpty ? "Nothing planned this week was missed." : "Move it to another day, or fit its work into the week."
            )
            scenarioCard(.time, icon: "clock.badge.exclamationmark", title: "I have less time", detail: "Shorter sessions for the rest of this week.")
            scenarioCard(.equipment, icon: "dumbbell", title: "Some equipment isn't available", detail: "Swap exercises that need it, this week only.")
        }

        switch scenario {
        case .missed?: missedOptions
        case .time?: timeOptions
        case .equipment?: equipmentOptions
        case nil: EmptyView()
        }

        if !hasPlan {
            InlineNotice(message: "These adjustments reshape a plan. Build one first from Summary › Plan my week.")
        }
    }

    private func scenarioCard(_ value: Scenario, icon: String, title: String, detail: String) -> some View {
        let selected = scenario == value
        let disabled = value == .missed && missed.isEmpty
        return Button {
            guard !disabled else { return }
            Haptics.trigger(.selection)
            scenario = value
            issue = nil
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(disabled ? Theme.mutedForeground : Theme.primary)
                    .frame(width: 34, height: 34)
                    .background(Theme.primary.opacity(disabled ? 0.05 : 0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.sans(16, weight: .bold))
                        .foregroundStyle(disabled ? Theme.mutedForeground : Theme.foreground)
                    Text(detail)
                        .font(Theme.sans(13, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? Theme.primary : Theme.mutedForeground.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: selected ? 1 : 0.5) }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
                    .strokeBorder(selected ? Theme.primary.opacity(0.7) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(disabled ? "Unavailable" : "")
    }

    @ViewBuilder private var missedOptions: some View {
        if missed.count > 1 {
            PageSection(title: "Which session") {
                ForEach(missed) { workout in
                    Button {
                        Haptics.trigger(.selection)
                        missedId = workout.id
                    } label: {
                        PageRow(
                            icon: missedId == workout.id ? "checkmark.circle.fill" : "circle",
                            title: workout.name,
                            detail: CalendarDate.long(workout.date),
                            showsDivider: workout.id != missed.last?.id
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(missedId == workout.id ? .isSelected : [])
                }
            }
        }
        if let workout = missed.first(where: { $0.id == missedId }) ?? missed.first {
            PageSection(title: "Move it") {
                let targets = CoachingPlanner.moveTargets(for: workout)
                if targets.isEmpty {
                    PageNote(text: "Every day left this week already has a workout. Fitting it into the week works instead.")
                } else {
                    ForEach(targets, id: \.self) { date in
                        PageActionRow(
                            icon: "calendar",
                            title: date == CalendarDate.today ? "Today" : CalendarDate.long(date),
                            detail: "Same exercises and targets; nothing else changes.",
                            showsDivider: date != targets.last
                        ) {
                            phase = .proposed(CoachingPlanner.previewMove(workout, to: date))
                        }
                    }
                }
            }
            PageSection(title: "Or fit it into the week") {
                PageActionRow(
                    icon: "square.stack.3d.up",
                    title: "Spread its work over the sessions left",
                    detail: "Only where muscles are short of this week's target, and only while each session stays inside your time.",
                    showsDivider: false
                ) {
                    prepare { try await CoachingPlanner.previewFoldMissed(workout) }
                }
            }
        }
    }

    @ViewBuilder private var timeOptions: some View {
        PageSection(title: "Time per session") {
            GlassSegmentedPicker(
                title: "Minutes",
                options: [20, 30, 40, 45],
                selection: $minutes,
                label: { "\($0) min" }
            )
            .padding(14)
            PageNote(text: "For the rest of this week. Your usual \(Int(store.trainingProfile.profile.preferredSessionDurationMinutes)) minutes stay for later weeks. Rest between sets isn't cut — sets and exercises are.")
        }
    }

    @ViewBuilder private var equipmentOptions: some View {
        let items = store.filters.gymEquipment.filter { $0 != "body weight" } + store.filters.effectiveFixtures
        PageSection(title: "Not available this week") {
            if items.isEmpty {
                PageNote(text: "Your equipment list is body weight only, so there's nothing to take away.")
            } else {
                ForEach(items, id: \.self) { item in
                    let off = unavailable.contains(item)
                    Button {
                        Haptics.trigger(.selection)
                        if off { unavailable.remove(item) } else { unavailable.insert(item) }
                    } label: {
                        PageRow(
                            icon: off ? "xmark.circle.fill" : "checkmark.circle",
                            tint: off ? Theme.destructive : Theme.success,
                            title: TrainingEngineAdapter.fixtureLabel(item),
                            detail: off ? "Not this week" : "Available",
                            showsDivider: item != items.last
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(off ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        switch phase {
        case .choosing:
            switch scenario {
            case .time?:
                AppButton("Prepare shorter sessions", size: .cta, isDisabled: !hasPlan, expands: true) {
                    let value = minutes
                    prepare { try await CoachingPlanner.previewShorter(minutes: value) }
                }
            case .equipment?:
                AppButton("Prepare the swaps", size: .cta, isDisabled: unavailable.isEmpty || !hasPlan, expands: true) {
                    let equipment = store.filters.gymEquipment.filter { unavailable.contains($0) }
                    let fixtures = store.filters.effectiveFixtures.filter { unavailable.contains($0) }
                    prepare { try await CoachingPlanner.previewWithout(equipment: equipment, fixtures: fixtures) }
                }
            default:
                EmptyView()
            }
        case .working:
            AppButton("Stop", variant: .secondary, size: .cta, expands: true) {
                work?.cancel()
                phase = .choosing
            }
        case .proposed(let proposal):
            CoachingProposalControls(
                proposal: proposal, applied: nil, working: false,
                onKeep: { keep(proposal) },
                onDiscard: { phase = .choosing },
                onUndo: {}, onDone: {}
            )
        case .applied(let proposal, let undo):
            CoachingProposalControls(
                proposal: proposal, applied: undo, working: false,
                onKeep: {}, onDiscard: {},
                onUndo: { revert(undo) },
                onDone: { store.navigation.pop() }
            )
        }
    }

    private var mood: RautaMood {
        switch phase {
        case .choosing: return .curious
        case .working: return .working
        case .proposed: return .happy
        case .applied: return .proud
        }
    }

    // MARK: Work

    private func prepare(_ build: @escaping () async throws -> CoachingProposal) {
        issue = nil
        phase = .working
        work = Task {
            do {
                let proposal = try await build()
                guard !Task.isCancelled else { return }
                phase = .proposed(proposal)
            } catch is CancellationError {
                phase = .choosing
            } catch {
                guard !Task.isCancelled else { return }
                Haptics.trigger(.warning)
                issue = (error as? TrainingPersistenceError)?.message ?? "RAUTA couldn't prepare that change."
                phase = .choosing
            }
        }
    }

    private func keep(_ proposal: CoachingProposal) {
        do {
            let undo = try CoachingPlanner.apply(proposal)
            Haptics.trigger(.success)
            RautaSpeech.shared.say("Done. Your week's adjusted.", reaction: .celebrate)
            phase = .applied(proposal, undo)
            issue = nil
        } catch {
            Haptics.trigger(.warning)
            issue = (error as? TrainingPersistenceError)?.message ?? "That couldn't be saved."
            phase = .choosing
        }
    }

    private func revert(_ undo: CoachingUndo) {
        do {
            try CoachingPlanner.undo(undo)
            Haptics.trigger(.selection)
            RautaSpeech.shared.say("Put back as it was.")
            phase = .choosing
            issue = nil
        } catch {
            issue = (error as? TrainingPersistenceError)?.message ?? "That couldn't be undone."
        }
    }
}
