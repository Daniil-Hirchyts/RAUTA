import SwiftUI

/// My next week: RAUTA builds the week ahead from the plan you are on, what
/// you logged, your goal, days, equipment and time — and shows what changes
/// before anything is saved.
struct NextWeekScreen: View {
    private let store = AppStore.shared

    private enum Phase {
        case choosing
        case working
        case proposed(CoachingProposal)
        case applied(CoachingProposal, CoachingUndo)
        case failed(String)
    }

    @State private var choice: CoachingPlanner.WeekChoice = .nextWeek
    @State private var days: Set<Int> = []
    @State private var phase = Phase.choosing
    @State private var work: Task<Void, Never>?

    private var profile: TrainingProfile { store.trainingProfile.profile }
    private var dates: [String] { CoachingPlanner.nextWeekDates(choice, trainingDays: Array(days)) }
    private var restOfWeekAvailable: Bool {
        !CoachingPlanner.nextWeekDates(.restOfThisWeek, trainingDays: Array(days)).isEmpty
            && WeekProgress.current().remaining.isEmpty
    }

    var body: some View {
        RautaScreen(
            title: "My next week",
            backLabel: "Close",
            onBack: { work?.cancel(); store.navigation.pop() },
            right: { RautaHeaderBadge(mood: mood) }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch phase {
                    case .choosing, .failed:
                        chooser
                        if case .failed(let reason) = phase {
                            InlineNotice(message: reason, isError: true)
                        }
                    case .working:
                        working
                    case .proposed(let proposal):
                        CoachingProposalView(proposal: proposal)
                    case .applied(let proposal, _):
                        appliedNote(proposal)
                        CoachingProposalView(proposal: proposal, applied: true)
                    }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, 24)
            }
            .pageScroll()
        } controls: {
            controls
        }
        .onAppear {
            if days.isEmpty { days = Set(profile.effectiveTrainingDays) }
        }
        .onDisappear { work?.cancel() }
    }

    // MARK: Choosing

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("RAUTA carries on the exercises that are working, progresses loads from what you logged, and swaps anything your equipment or experience doesn't fit.")
                .font(Theme.sans(15, weight: .medium))
                .foregroundStyle(Theme.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)

            if restOfWeekAvailable {
                GlassSegmentedPicker(
                    title: "Which week",
                    options: [CoachingPlanner.WeekChoice.nextWeek, .restOfThisWeek],
                    selection: $choice,
                    label: { $0 == .nextWeek ? "Next week" : "Rest of this week" }
                )
            }

            PageSection(title: "Days") {
                WeekdayPicker(days: $days)
                    .padding(14)
                PageNote(text: datesNote)
            }

            PageSection(title: "Each session") {
                PageRow(
                    icon: "clock",
                    title: "About \(Int(profile.preferredSessionDurationMinutes)) min",
                    detail: "A target, warm-up and rest included — never more than 10 min over. Change it in Settings › Training.",
                    showsDivider: true
                ) { TermInfoButton(term: .sessionLength) }
                PageRow(
                    icon: "dumbbell",
                    title: equipmentTitle,
                    detail: "Plans only use what's on your equipment list.",
                    showsDivider: false
                )
            }
        }
    }

    private var datesNote: String {
        guard let first = dates.first else { return "Pick at least one day." }
        var note = "\(Wording.countLabel(dates.count, "session")): \(PlanStart.describe(dates))."
        let nextMonday = CalendarDate.shift(WeekProgress.mondayOf(CalendarDate.today), by: 7)
        if choice == .nextWeek, WeekProgress.mondayOf(first) > nextMonday {
            let covered = CalendarDate.shift(WeekProgress.mondayOf(first), by: -1)
            note += " Your plan already runs to \(CalendarDate.short(covered)), so this builds the week after."
        }
        return note
    }

    private var equipmentTitle: String {
        let equipment = store.filters.gymEquipment
        let fixtures = store.filters.effectiveFixtures
        if equipment.isEmpty && fixtures.isEmpty { return "Body weight only" }
        let names = (equipment.filter { $0 != "body weight" } + fixtures).map { TrainingEngineAdapter.fixtureLabel($0).lowercased() }
        return names.isEmpty ? "Body weight only" : Wording.list(Array(names.prefix(4))) + (names.count > 4 ? " and more" : "")
    }

    private var working: some View {
        let inputs = ThinkingInputs.plan(dates: dates)
        return RautaThinkingStage(thoughts: inputs.thoughts, chips: inputs.chips)
            .frame(height: 460)
            .padding(.horizontal, -Theme.Metrics.contentInset)
            .accessibilityLabel("RAUTA is building your week")
    }

    private func appliedNote(_ proposal: CoachingProposal) -> some View {
        Label("Saved. Your workouts list has the new week; Undo puts everything back as it was.", systemImage: "checkmark.circle.fill")
            .font(Theme.sans(14, weight: .semibold))
            .foregroundStyle(Theme.success)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        switch phase {
        case .choosing, .failed:
            AppButton("Prepare my week", size: .cta, isDisabled: dates.isEmpty, expands: true, action: prepare)
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
                onDone: finish
            )
        }
    }

    private var mood: RautaMood {
        switch phase {
        case .choosing: return .curious
        case .working: return .working
        case .proposed: return .happy
        case .applied: return .proud
        case .failed: return .confused
        }
    }

    // MARK: Work

    private func prepare() {
        let chosen = dates
        guard !chosen.isEmpty else { return }
        if Set(profile.effectiveTrainingDays) != days {
            // The days chosen here are the days the person trains now.
            store.trainingProfile.updateProfile(.init(trainingDays: days.sorted()))
        }
        phase = .working
        work = Task {
            do {
                let proposal = try await CoachingPlanner.previewNextWeek(dates: chosen)
                guard !Task.isCancelled else { return }
                phase = .proposed(proposal)
            } catch is CancellationError {
                phase = .choosing
            } catch {
                guard !Task.isCancelled else { return }
                Haptics.trigger(.warning)
                phase = .failed((error as? TrainingPersistenceError)?.message ?? "RAUTA couldn't build that week.")
            }
        }
    }

    private func keep(_ proposal: CoachingProposal) {
        do {
            let undo = try CoachingPlanner.apply(proposal)
            Haptics.trigger(.success)
            RautaSpeech.shared.say("Your next week is ready.", reaction: .celebrate)
            phase = .applied(proposal, undo)
        } catch {
            Haptics.trigger(.warning)
            phase = .failed((error as? TrainingPersistenceError)?.message ?? "That couldn't be saved.")
        }
    }

    private func revert(_ undo: CoachingUndo) {
        do {
            try CoachingPlanner.undo(undo)
            Haptics.trigger(.selection)
            RautaSpeech.shared.say("Put back as it was.")
            phase = .choosing
        } catch {
            phase = .failed((error as? TrainingPersistenceError)?.message ?? "That couldn't be undone.")
        }
    }

    private func finish() {
        store.navigation.pop()
    }
}

/// Monday to Sunday as seven toggles, in the person's own weekday names.
struct WeekdayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    Haptics.trigger(.selection)
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(Self.shortName(day))
                        .font(Theme.sans(13, weight: .bold))
                        .foregroundStyle(on ? Theme.primaryForeground : Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(on ? Theme.primary : Theme.muted.opacity(0.4))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.fullName(day))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// ISO weekday 1 = Monday.
    static func shortName(_ day: Int) -> String {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return symbols[day % 7]
    }

    static func fullName(_ day: Int) -> String {
        Calendar.current.standaloneWeekdaySymbols[day % 7]
    }
}
