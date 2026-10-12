import SwiftUI

/// Planning a week with RAUTA: it asks when you can train, builds the week while
/// you watch, and hands over what it built. One question, one button, and the
/// result stays on screen until you move on.
struct PlanWeekScreen: View {
    private let store = AppStore.shared
    let sourceProgramId: String?

    private enum Phase: Equatable {
        case choosing
        case working
        case built([PlannedSessionView])
        case blocked(reason: String, page: PlanBlockPage?)
    }

    @State private var selectedDates: Set<String> = []
    @State private var phase = Phase.choosing
    @State private var work: Task<Void, Never>?
    /// The scroll view's height between the title bar and the button, so the
    /// calendar can sit at the foot of it with RAUTA centred above.
    @State private var visibleHeight: CGFloat = 0
    /// As large as the room above the calendar allows: RAUTA grows on a tall
    /// phone and gives way on a short one, so the calendar ends just above the
    /// button. Settled from the page's measured height.
    @State private var rautaSize: CGFloat = 130

    private static let spacing: CGFloat = 10
    private static let rautaRange: ClosedRange<CGFloat> = 96...180

    private var continuing: Bool { sourceProgramId != nil }
    private var minutes: Int { Int(store.trainingProfile.profile.preferredSessionDurationMinutes) }

    var body: some View {
        RautaScreen(
            title: continuing ? "Extend training plan" : "Create training plan",
            backLabel: "Back to workouts",
            onBack: store.navigation.pop
        ) {
            ScrollView {
                VStack(spacing: Self.spacing) {
                    if phase == .working {
                        // RAUTA at work over the request itself: the days,
                        // the goal and the kit orbit it while it plans.
                        let inputs = ThinkingInputs.plan(dates: Array(selectedDates))
                        RautaThinkingStage(thoughts: inputs.thoughts, chips: inputs.chips)
                            .frame(height: max(520, visibleHeight - 24))
                            .padding(.horizontal, -Theme.Metrics.contentInset)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        // RAUTA is the subject here: centred, its line under
                        // it and kept there, not spoken and folded away.
                        RautaSays(
                            text: line,
                            mood: mood,
                            reaction: reaction,
                            reactionKey: phaseKey,
                            size: rautaSize,
                            layout: .stacked,
                            trims: true,
                            plain: true
                        )
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                    }

                    switch phase {
                    case .built(let sessions):
                        sessionList(sessions)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    case .blocked(_, let page):
                        picker
                        if let page {
                            AppButton(variant: .secondary, expands: true, action: { open(page) }) {
                                Text(fixLabel(page))
                            }
                        }
                    case .choosing:
                        startChooser
                        picker
                        planningNotes
                    case .working:
                        EmptyView()
                    }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.top, 4)
                .padding(.bottom, 12)
                // The scroller asks for the content's own height: whatever it
                // falls short of the room, or runs past it, RAUTA takes up or
                // gives back.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    fitRauta(contentHeight: height)
                }
                .frame(minHeight: visibleHeight, alignment: .bottom)
                .animation(Theme.Motion.settle, value: phase)
            }
            // The container is already the room between the title bar and
            // the button; the insets are the bars themselves, outside it.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height
            } action: { _, height in
                visibleHeight = max(0, height)
            }
            .pageScroll()
        } controls: {
            AppButton(
                variant: .primary,
                size: .cta,
                isDisabled: ctaDisabled,
                expands: true,
                accessibilityLabel: ctaTitle,
                action: ctaAction
            ) {
                Text(ctaTitle)
            }
        }
        .task { selectDefaultDates() }
        // Leaving the page abandons a plan still being built; nothing is saved.
        .onDisappear { work?.cancel() }
    }

    private var picker: some View {
        PlanDatePicker(
            selectedDates: $selectedDates,
            onSelectionChange: {
                if case .blocked = phase { phase = .choosing }
            }
        )
        .disabled(phase == .working)
        .opacity(phase == .working ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.25), value: phase == .working)
    }

    // MARK: RAUTA's part

    private func fitRauta(contentHeight: CGFloat) {
        guard visibleHeight > 0, phase == .choosing || isBlocked else { return }
        // Damped: the block grows a little faster than the character does,
        // so a full step would overshoot and swing.
        let next = min(Self.rautaRange.upperBound, max(Self.rautaRange.lowerBound, rautaSize + (visibleHeight - contentHeight) * 0.6))
        guard abs(next - rautaSize) > 1 else { return }
        rautaSize = next
    }

    private var isBlocked: Bool {
        if case .blocked = phase { return true }
        return false
    }

    private var line: String {
        switch phase {
        case .choosing:
            return PlanTalk.asking(selected: Array(selectedDates), minutes: minutes, continuing: continuing)
        case .working:
            return PlanTalk.working(selected: Array(selectedDates))
        case .built(let sessions):
            return PlanTalk.built(dates: sessions.map(\.date))
        case .blocked(let reason, _):
            return reason
        }
    }

    private var mood: RautaMood {
        switch phase {
        case .choosing: return .curious
        case .working: return .working
        case .built: return .happy
        case .blocked: return .confused
        }
    }

    private var reaction: RautaReaction? {
        switch phase {
        case .choosing: return nil
        case .working: return .gearUp
        case .built: return .celebrate
        case .blocked: return .surprise
        }
    }

    /// Each new phase is one beat from RAUTA; picking days is not.
    private var phaseKey: String {
        switch phase {
        case .choosing: return "choosing"
        case .working: return "working"
        case .built: return "built"
        case .blocked(let reason, _): return "blocked-\(reason)"
        }
    }

    // MARK: The one button

    private var ctaTitle: String {
        switch phase {
        case .choosing: return continuing ? "Extend my plan" : "Build my week"
        case .working: return "Building…"
        case .built: return "Let's go"
        case .blocked: return "Try again"
        }
    }

    private var ctaDisabled: Bool {
        switch phase {
        case .choosing, .blocked: return selectedDates.isEmpty
        case .working: return true
        case .built: return false
        }
    }

    private func ctaAction() {
        switch phase {
        case .choosing, .blocked: create()
        case .working: break
        case .built(let sessions): finish(sessions)
        }
    }

    // MARK: The result

    /// The week RAUTA built, each day's workout pictured and named. It is
    /// already saved, so each one opens.
    private func sessionList(_ sessions: [PlannedSessionView]) -> some View {
        let ordered = sessions.sorted { $0.date < $1.date }
        let rows = ordered.map { session in
            AgentSessionRow.planned(session, id: plannedWorkoutId(session) ?? session.sessionId)
        }
        return WorkoutAgenda(rows: rows, onOpen: { id in
            guard store.workouts.workout(id) != nil else { return }
            Haptics.trigger(.selection)
            store.navigation.push(.plannedWorkout(workoutId: id))
        })
        .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: 0.7) }
        .modifier(Arrival())
    }

    private func plannedWorkoutId(_ session: PlannedSessionView) -> String? {
        store.workouts.workouts.first { $0.planned?.sessionId == session.sessionId }?.id
    }

    // MARK: Work

    /// The first session today, then the person's usual days: nobody waits
    /// a week for their first workout. "Start next week" is one tap away.
    private func selectDefaultDates() {
        guard selectedDates.isEmpty else { return }
        selectedDates = Set(dates(for: continuing ? .nextWeek : .today))
    }

    private func dates(for start: PlanStart) -> [String] {
        start.dates(trainingDays: store.trainingProfile.profile.effectiveTrainingDays)
    }

    // MARK: Starting

    private var startChooser: some View {
        HStack(spacing: 8) {
            ForEach(PlanStart.allCases) { start in
                let options = dates(for: start)
                let selected = Set(options) == selectedDates
                Button {
                    Haptics.trigger(.selection)
                    selectedDates = Set(options)
                } label: {
                    VStack(spacing: 2) {
                        Text(start.title(options))
                            .font(Theme.sans(15, weight: .bold))
                        Text(options.first.map { start == .today ? "today, " + CalendarDate.format($0, "EEEd") : "from " + CalendarDate.format($0, "EEEdMMM") } ?? "")
                            .font(Theme.sans(12, weight: .medium))
                            .opacity(0.85)
                    }
                    .foregroundStyle(selected ? Theme.primaryForeground : Theme.foreground)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(selected ? Theme.primary : Theme.muted.opacity(0.4))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(start.title(options)): \(PlanStart.describe(options))")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// What the chosen dates mean for what is already scheduled, and what a
    /// session's length means — before anything is built.
    @ViewBuilder private var planningNotes: some View {
        let notes = planningNoteLines
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(notes, id: \.self) { note in
                    Label {
                        Text(note).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(Theme.primary)
                    }
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.secondaryForeground)
                }
                HStack(spacing: 4) {
                    Text("What does the session length mean?")
                        .font(Theme.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                    TermInfoButton(term: .sessionLength)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: 0.5) }
        }
    }

    private var planningNoteLines: [String] {
        var lines: [String] = []
        let chosen = selectedDates.sorted()
        guard let first = chosen.first else { return lines }
        if let active = TrainingPlan.activeProgramRecord() {
            let replaced = PlanRevision.pendingSessions(active).filter { String($0.scheduledAt.prefix(10)) >= first }
            if !replaced.isEmpty {
                lines.append("This plan takes over from \(CalendarDate.short(first)): it replaces \(Wording.countLabel(replaced.count, "upcoming session")) from your current plan. Anything you've already trained stays.")
            }
        }
        let own = store.workouts.workouts.filter { workout in
            workout.planned == nil && workout.completion == nil && chosen.contains(workout.date)
        }
        if !own.isEmpty {
            let names = own.map { "\($0.name) on \(CalendarDate.short($0.date))" }
            lines.append("You already have \(Wording.list(names)). \(own.count == 1 ? "It stays" : "They stay") on your list next to the plan.")
        }
        return lines
    }

    private func create() {
        guard phase != .working, !selectedDates.isEmpty else { return }
        phase = .working
        work = Task {
            let outcome = await TrainingPlan.createTrainingPlanForDates(
                dates: selectedDates.sorted(),
                sourceProgramId: sourceProgramId
            )
            switch outcome {
            case nil:
                phase = .choosing
            case .created(_, let sessions, _):
                WorkoutAudio.play(.planBuilt)
                phase = .built(sessions)
            case .blocked(let block):
                Haptics.trigger(.warning)
                phase = .blocked(reason: block.message, page: block.page)
            }
        }
    }

    /// Out to the Workout tab, on the first session RAUTA built.
    private func finish(_ sessions: [PlannedSessionView]) {
        let first = sessions.min { $0.date < $1.date }
        let workout = first.flatMap { session in
            store.workouts.workouts.first { $0.planned?.sessionId == session.sessionId }
        }
        if let workout {
            store.navigation.openWorkout(workout.id)
        } else {
            store.navigation.reset([.workouts])
        }
    }

    private func fixLabel(_ page: PlanBlockPage) -> String {
        switch page {
        case .profileBasics: return "Open my details"
        case .profileTraining: return "Open training preferences"
        case .profileHealth: return "Open health"
        case .profileEquipment: return "Open my equipment"
        case .profilePriorities: return "Open muscle priorities"
        }
    }

    private func open(_ page: PlanBlockPage) {
        switch page {
        case .profileBasics: store.navigation.push(.profileBasics)
        case .profileTraining: store.navigation.push(.profileTraining)
        case .profileHealth: store.navigation.push(.profileHealth)
        case .profileEquipment: store.navigation.push(.profileEquipment)
        case .profilePriorities: store.navigation.push(.profilePriorities)
        }
    }
}

/// The built week arriving from below, the way RAUTA hands it over.
private struct Arrival: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8).delay(0.2)) { shown = true }
            }
    }
}

private struct PlanDatePicker: View {
    @Binding var selectedDates: Set<String>
    var onSelectionChange: () -> Void

    var body: some View {
        RautaCalendar(
            selection: .multiple($selectedDates),
            label: "Training dates",
            onChange: onSelectionChange
        )
    }
}
