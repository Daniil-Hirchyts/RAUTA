import SwiftUI

struct PlanWeekScreen: View {
    private let store = AppStore.shared
    let sourceProgramId: String?

    @State private var selectedDates: Set<String> = []
    @State private var working = false
    @State private var work: Task<Void, Never>?
    @State private var block: PlanBlock?

    private var continuing: Bool { sourceProgramId != nil }

    var body: some View {
        RautaScreen(
            title: continuing ? "Extend training plan" : "Create training plan",
            backLabel: "Back to workouts",
            onBack: store.navigation.pop,
            right: {
                RautaHeaderBadge(
                    mood: .focused,
                    reactionKey: continuing
                        ? "Pick the next dates. I'll adapt from your logged work."
                        : "Pick your dates. I'll build the plan from your preferences."
                )
            }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    planIntro

                    PlanDatePicker(
                        selectedDates: $selectedDates,
                        onSelectionChange: { block = nil }
                    )
                    .padding(.top, 18)

                    if let block {
                        blockNotice(block)
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, 24)
            }
            .pageScroll()
        } controls: {
            AppButton(
                variant: .primary,
                size: .cta,
                isDisabled: selectedDates.isEmpty || working,
                expands: true,
                accessibilityLabel: continuing ? "Extend plan" : "Create plan",
                action: create
            ) {
                if working {
                    MatrixLoader(
                        variant: .orbit,
                        label: continuing ? "Extending your plan" : "Building your plan",
                        dot: 3,
                        gap: 2
                    )
                } else {
                    Text(continuing ? "Extend plan" : "Create plan")
                }
            }
        }
        .task { selectDefaultDates() }
        // Leaving the page abandons a plan still being built; nothing is saved.
        .onDisappear { work?.cancel() }
    }

    private var planIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(continuing ? "PLAN MORE TRAINING" : "BUILD YOUR SCHEDULE")
                .font(Theme.sans(10, weight: .black))
                .kerning(1.8)
                .foregroundStyle(Theme.primary)

            Text(continuing ? "When do you want to train next?" : "When do you want to train?")
                .font(Theme.sans(24, weight: .black))
                .foregroundStyle(Theme.foreground)
                .tracking(-0.7)
                .lineLimit(2)

            Text(profileLine)
                .font(Theme.sans(12, weight: .medium))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var profileLine: String {
        let profile = store.trainingProfile.profile
        return "\(ProfileVocabulary.goalLabel(profile.goal)) · \(Int(profile.preferredSessionDurationMinutes)) min · \(ProfileVocabulary.experienceLabel(profile.trainingExperience))"
    }

    private func blockNotice(_ block: PlanBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NO PLAN YET")
                .font(Theme.sans(12, weight: .black))
                .tracking(1.9)
                .foregroundStyle(Theme.primary)

            Text(block.message)
                .font(Theme.sans(15, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .lineSpacing(2)
                .padding(.top, 8)

            if let page = block.page {
                AppButton(
                    variant: .secondary,
                    size: .standard,
                    expands: true,
                    action: { open(page) }
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                        Text(fixLabel(page))
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.mix(Theme.card, Theme.primary, 0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous)
                .strokeBorder(Theme.primary.opacity(0.45), lineWidth: 1)
        )
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
        guard !working else { return }
        working = true
        block = nil
        work = Task {
            let outcome = await TrainingPlan.createTrainingPlanForDates(
                dates: selectedDates.sorted(),
                sourceProgramId: sourceProgramId
            )
            working = false
            switch outcome {
            case nil:
                break
            case .created:
                Haptics.trigger(.success)
                store.navigation.reset([.workouts])
            case .blocked(let next):
                block = next
                Haptics.trigger(.warning)
            }
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
        .background(
            Theme.card,
            in: RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous)
        )
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
