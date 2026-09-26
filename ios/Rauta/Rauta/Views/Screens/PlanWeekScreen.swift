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

    private var continuing: Bool { sourceProgramId != nil }
    private var minutes: Int { Int(store.trainingProfile.profile.preferredSessionDurationMinutes) }

    var body: some View {
        RautaScreen(
            title: continuing ? "Extend training plan" : "Create training plan",
            backLabel: "Back to workouts",
            onBack: store.navigation.pop
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if phase == .working {
                        // RAUTA at work over the request itself: the days,
                        // the goal and the kit orbit it while it plans.
                        let inputs = ThinkingInputs.plan(dates: Array(selectedDates))
                        RautaThinkingStage(thoughts: inputs.thoughts, chips: inputs.chips)
                            .frame(height: 520)
                            .padding(.horizontal, -Theme.Metrics.contentInset)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        RautaSays(
                            text: line,
                            mood: mood,
                            reaction: reaction,
                            reactionKey: phaseKey,
                            size: 96,
                            layout: .beside,
                            transient: true
                        )
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
                        picker
                    case .working:
                        EmptyView()
                    }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: phase)
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

    private func sessionList(_ sessions: [PlannedSessionView]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(sessions.sorted { $0.date < $1.date }.enumerated()), id: \.element.id) { index, session in
                PlannedSessionRow(session: session, index: index)
            }
        }
    }

    // MARK: Work

    private func selectDefaultDates() {
        guard selectedDates.isEmpty else { return }
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let weekday = calendar.component(.weekday, from: Date())
        let daysUntilMonday = (9 - weekday) % 7
        let mondayOffset = daysUntilMonday == 0 ? 7 : daysUntilMonday
        selectedDates = Set([0, 2, 4].map {
            CalendarDate.shift(CalendarDate.today, by: mondayOffset + $0)
        })
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
                Haptics.trigger(.success)
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

private struct PlanDatePicker: View {
    @Binding var selectedDates: Set<String>
    var onSelectionChange: () -> Void

    private var calendar: Calendar { Calendar.current }
    private var earliestDate: Date { calendar.startOfDay(for: Date()) }

    private var selection: Binding<Set<DateComponents>> {
        Binding(
            get: {
                Set(selectedDates.compactMap { iso in
                    guard let date = CalendarDate.parse(iso) else { return nil }
                    return calendar.dateComponents([.year, .month, .day], from: date)
                })
            },
            set: { values in
                selectedDates = Set(values.compactMap { components in
                    guard let date = calendar.date(from: components) else { return nil }
                    let iso = CalendarDate.toISO(date)
                    return iso >= CalendarDate.today ? iso : nil
                })
                Haptics.trigger(.selection)
                onSelectionChange()
            }
        )
    }

    var body: some View {
        MultiDatePicker(
            "Training dates",
            selection: selection,
            in: earliestDate...
        )
        .labelsHidden()
        .tint(Theme.primary)
        .padding(12)
        .frame(maxWidth: .infinity)
        .background { GradientCard(radius: Theme.Radius.xl3, accent: Theme.primary, strength: 0.7) }
    }
}

struct WorkoutDateCalendarModal: View {
    var isPresented: Bool
    @State private var selectedDate: Date
    let onClose: () -> Void
    let onSelect: (String) -> Void

    init(isPresented: Bool, date: String, onClose: @escaping () -> Void, onSelect: @escaping (String) -> Void) {
        let parsed = CalendarDate.parse(date) ?? Date()
        self.isPresented = isPresented
        _selectedDate = State(initialValue: parsed)
        self.onClose = onClose
        self.onSelect = onSelect
    }

    var body: some View {
        AppModal(
            isPresented: isPresented,
            label: "Choose workout date",
            onClose: onClose,
            panelPadding: 6
        ) {
            DatePicker(
                "Workout date",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(Theme.primary)
            .padding(12)
            .glassSurface(
                .clear,
                in: RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous),
                border: Theme.Glassware.edge
            )
            .onChange(of: selectedDate) { _, newValue in
                Haptics.trigger(.success)
                onClose()
                onSelect(CalendarDate.toISO(newValue))
            }
        }
    }
}
