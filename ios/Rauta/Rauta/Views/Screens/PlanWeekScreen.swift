import SwiftUI

struct PlanWeekScreen: View {
    @ObservedObject private var store = AppStore.shared
    let sourceProgramId: String?

    @State private var selectedDates: Set<String> = []
    @State private var working = false
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
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
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
        Task { @MainActor in
            await Task.yield()
            let outcome = TrainingPlan.createTrainingPlanForDates(
                dates: selectedDates.sorted(),
                sourceProgramId: sourceProgramId
            )
            working = false
            switch outcome {
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

struct PlanMonthCalendar: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDates: Set<String>
    var singleSelection = false
    var cellSize: CGFloat = 32
    var modalStyle = false
    var selectionHaptic: HapticInput = .selection
    var onSelectionChange: () -> Void
    var onSelectDate: ((String) -> Void)? = nil

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }

    static func monthStart(_ date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: visibleMonth)
    }

    private var weekdayLabels: [String] {
        let raw = calendar.veryShortStandaloneWeekdaySymbols
        guard raw.count == 7 else { return ["M", "T", "W", "T", "F", "S", "S"] }
        return Array(raw[1...]) + [raw[0]]
    }

    private var cells: [Date] {
        let first = Self.monthStart(visibleMonth)
        let weekday = calendar.component(.weekday, from: first)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: first)?.count ?? 31
        let cellCount = ((offset + days + 6) / 7) * 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: first) else { return [] }
        return (0..<cellCount).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var currentMonth: Int { calendar.component(.month, from: visibleMonth) }

    var body: some View {
        Group {
            if modalStyle {
                calendarContent
                    .padding(12)
                    .background(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            } else {
                calendarContent
                    .padding(12)
                    .background(Theme.background)
                    .padding(4)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
            }
        }
    }

    private var calendarContent: some View {
        VStack(spacing: 16) {
            HStack {
                navButton("chevron.left", delta: -1)
                Spacer()
                Text(monthTitle)
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                Spacer()
                navButton("chevron.right", delta: 1)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                }

                ForEach(cells, id: \.timeIntervalSinceReferenceDate) { date in
                    dayButton(date)
                }
            }
        }
    }

    private func navButton(_ icon: String, delta: Int) -> some View {
        Button {
            Haptics.trigger(.light)
            if let next = calendar.date(byAdding: .month, value: delta, to: visibleMonth) {
                withAnimation(Theme.Motion.smoothOut) { visibleMonth = Self.monthStart(next) }
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .frame(width: cellSize, height: cellSize)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func dayButton(_ date: Date) -> some View {
        let iso = CalendarDate.toISO(date)
        let selected = selectedDates.contains(iso)
        let disabled = iso < CalendarDate.today
        let outside = calendar.component(.month, from: date) != currentMonth
        let today = iso == CalendarDate.today

        return Button {
            guard !disabled else { return }
            if singleSelection {
                if selected {
                    selectedDates.remove(iso)
                    onSelectionChange()
                    return
                }
                selectedDates = [iso]
            } else if selected {
                selectedDates.remove(iso)
            } else {
                selectedDates.insert(iso)
            }
            Haptics.trigger(selectionHaptic)
            onSelectionChange()
            onSelectDate?(iso)
        } label: {
            Text(String(calendar.component(.day, from: date)))
                .font(Theme.sans(14))
                .foregroundStyle(selected ? Theme.primaryForeground : Theme.foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    selected
                        ? AnyShapeStyle(Theme.primaryGradient)
                        : AnyShapeStyle(today ? Theme.muted : Color.clear),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .opacity(disabled ? 0.45 : (outside ? 0.60 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(height: cellSize)
        .disabled(disabled)
        .accessibilityLabel(CalendarDate.long(iso))
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                border: Theme.Glassware.edge,
                legacyFill: Theme.card.opacity(0.78)
            )
            .onChange(of: selectedDate) { _, newValue in
                Haptics.trigger(.success)
                onClose()
                onSelect(CalendarDate.toISO(newValue))
            }
        }
    }
}
