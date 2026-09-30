import SwiftUI

private enum WorkoutListFilter: Int, CaseIterable, Identifiable {
    case all
    case today
    case planned
    case past
    case fullBody
    case upper
    case lower
    case push
    case pull
    case legs

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .today: return "Today"
        case .planned: return "Planned"
        case .past: return "Past"
        case .fullBody: return "Full body"
        case .upper: return "Upper"
        case .lower: return "Lower"
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        }
    }

    var isWorkoutType: Bool {
        switch self {
        case .all, .today, .planned, .past: return false
        case .fullBody, .upper, .lower, .push, .pull, .legs: return true
        }
    }

    func matchesWorkoutType(_ workout: Workout) -> Bool {
        let name = workout.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch self {
        case .fullBody: return name.hasPrefix("full body")
        case .upper: return name.hasPrefix("upper")
        case .lower: return name.hasPrefix("lower")
        case .push: return name.hasPrefix("push")
        case .pull: return name.hasPrefix("pull")
        case .legs: return name.hasPrefix("legs") || name.hasPrefix("leg day")
        case .all, .today, .planned, .past: return false
        }
    }
}

struct WorkoutListContent: View {
    let upcoming: [Workout]
    let past: [Workout]
    let activeWorkoutId: String?
    @Binding var selection: Int
    let onOpen: (Workout) -> Void

    @State private var visibleLimit = 12

    private struct WorkoutSection: Identifiable {
        let id: String
        let title: String
        var workouts: [Workout]
    }

    private var filter: WorkoutListFilter {
        WorkoutListFilter(rawValue: selection) ?? .all
    }

    private var allWorkouts: [Workout] {
        var seen = Set<String>()
        return (upcoming + past)
            .filter { seen.insert($0.id).inserted }
            .soonestFirst()
    }

    private var filteredWorkouts: [Workout] {
        switch filter {
        case .all:
            return allWorkouts
        case .today:
            let today = CalendarDate.today
            return allWorkouts.filter { $0.date == today }
        case .planned:
            return upcoming.soonestFirst()
        case .past:
            return past.soonestFirst()
        case .fullBody, .upper, .lower, .push, .pull, .legs:
            return allWorkouts.filter(filter.matchesWorkoutType)
        }
    }

    private var availableFilters: [WorkoutListFilter] {
        let base: [WorkoutListFilter] = [.all, .today, .planned, .past]
        let workoutTypes = WorkoutListFilter.allCases.filter { candidate in
            candidate.isWorkoutType && allWorkouts.contains(where: candidate.matchesWorkoutType)
        }
        return base + workoutTypes
    }

    private var visibleWorkouts: [Workout] {
        Array(filteredWorkouts.prefix(visibleLimit))
    }

    private var pastIds: Set<String> {
        Set(past.map(\.id))
    }

    /// Today on its own, then a section per month for the days ahead and again
    /// for the days behind. A month on both sides of today names its earlier
    /// half "Earlier in …", so the two never read as one.
    private var sections: [WorkoutSection] {
        let today = CalendarDate.today
        let aheadMonths = Set(
            visibleWorkouts.filter { $0.date > today }.map { String($0.date.prefix(7)) }
        )
        var sections: [WorkoutSection] = []
        for workout in visibleWorkouts {
            let month = String(workout.date.prefix(7))
            let id: String
            let title: String
            if workout.date == today {
                id = "today"
                title = "Today"
            } else if workout.date > today {
                id = "ahead-\(month)"
                title = monthTitle(workout.date)
            } else {
                id = "behind-\(month)"
                title = aheadMonths.contains(month)
                    ? "Earlier in \(monthName(workout.date))"
                    : monthTitle(workout.date)
            }
            if let last = sections.indices.last, sections[last].id == id {
                sections[last].workouts.append(workout)
            } else {
                sections.append(WorkoutSection(id: id, title: title, workouts: [workout]))
            }
        }
        return sections
    }

    private var emptyTitle: String {
        switch filter {
        case .all: return "No workouts yet"
        case .today: return "Nothing planned for today"
        case .planned: return "No planned workouts"
        case .past: return "No past workouts yet"
        case .fullBody, .upper, .lower, .push, .pull, .legs:
            return "No \(filter.title.lowercased()) workouts"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all: return "Plan your week or choose exercises, and your workouts will show up here."
        case .today: return "A rest day. Pick exercises from the Library if you want to train anyway."
        case .planned: return "Create a training plan and its sessions will line up here."
        case .past: return "Finished workouts stay here with their sets and times."
        case .fullBody, .upper, .lower, .push, .pull, .legs:
            return "None of your workouts are \(filter.title.lowercased()) sessions yet."
        }
    }

    var body: some View {
        Group {
            if filteredWorkouts.isEmpty {
                EmptyStatePlaceholder(
                    mood: filter == .all ? .calm : .curious,
                    title: emptyTitle,
                    message: emptyMessage,
                    actionTitle: filter == .all ? nil : "Show all workouts",
                    action: {
                        Haptics.trigger(.selection)
                        selection = WorkoutListFilter.all.rawValue
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .belowPageHeader()
                .padding(32)
                .offset(y: -30)
                .pageArrival(0)
            } else {
                // Where each workout stands on the page, so the rows arrive
                // one after another down it.
                let order = Dictionary(uniqueKeysWithValues: visibleWorkouts.enumerated().map { ($1.id, $0) })
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(sections) { section in
                            Text(section.title)
                                .font(Theme.sans(17, weight: .heavy))
                                .foregroundStyle(Theme.foreground)
                                .padding(.horizontal, 4)
                                .padding(.top, 8)
                                .pageArrival(Self.arrivalOrder(section.workouts.first.flatMap { order[$0.id] }))

                            ForEach(section.workouts) { workout in
                                WorkoutRow(
                                    workout: workout,
                                    isPast: pastIds.contains(workout.id),
                                    isRunning: activeWorkoutId == workout.id,
                                    onOpen: { onOpen(workout) }
                                )
                                .pageArrival(Self.arrivalOrder(order[workout.id]))
                            }
                        }

                        sectionFooter(
                            remaining: Swift.max(0, filteredWorkouts.count - visibleLimit),
                            showLess: visibleLimit > 12,
                            onMore: { visibleLimit += 12 },
                            onLess: { visibleLimit = 12 }
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 92)
                }
                .pageScroll()
                .scrollIndicators(.hidden)
            }
        }
        .animation(Theme.Motion.smoothOut(0.24), value: selection)
        .onChange(of: selection) { _, _ in
            visibleLimit = 12
        }
        .onChange(of: availableFilters.map(\.rawValue)) { _, filters in
            guard filters.contains(selection) else {
                selection = WorkoutListFilter.all.rawValue
                return
            }
        }
    }

    /// Rows past the first screenful arrive with the last one on it: nothing
    /// below the fold is worth waiting for.
    private static func arrivalOrder(_ index: Int?) -> Int {
        min(index ?? 0, 6)
    }

    private func monthTitle(_ isoDate: String) -> String {
        formatted(isoDate, template: "MMMM yyyy")
    }

    private func monthName(_ isoDate: String) -> String {
        formatted(isoDate, template: "MMMM")
    }

    private func formatted(_ isoDate: String, template: String) -> String {
        CalendarDate.format(isoDate, template)
    }

    @ViewBuilder
    private func sectionFooter(
        remaining: Int,
        showLess: Bool,
        onMore: @escaping () -> Void,
        onLess: @escaping () -> Void
    ) -> some View {
        if remaining > 0 || showLess {
            HStack(spacing: 8) {
                if remaining > 0 {
                    AppButton(
                        variant: .ghost,
                        expands: true,
                        accessibilityLabel: "Load more (\(remaining))",
                        action: onMore
                    ) {
                        HStack(spacing: 6) {
                            Text("Load more")
                            Text("(\(remaining))")
                                .foregroundStyle(Theme.mutedForeground)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
                if showLess {
                    AppButton(
                        variant: .ghost,
                        expands: remaining == 0,
                        accessibilityLabel: "Show less",
                        action: onLess
                    ) {
                        HStack(spacing: 6) {
                            Text("Show less")
                            Image(systemName: "chevron.up")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
            }
        }
    }
}

struct WorkoutsModeSwitcher: View {
    @Binding var selection: Int
    let workouts: [Workout]

    private var availableFilters: [WorkoutListFilter] {
        let base: [WorkoutListFilter] = [.all, .today, .planned, .past]
        let workoutTypes = WorkoutListFilter.allCases.filter { candidate in
            candidate.isWorkoutType && workouts.contains(where: candidate.matchesWorkoutType)
        }
        return base + workoutTypes
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(availableFilters) { filter in
                    WorkoutFilterChip(
                        title: filter.title,
                        selected: selection == filter.rawValue
                    ) {
                        guard selection != filter.rawValue else { return }
                        Haptics.trigger(.selection)
                        withAnimation(Theme.Motion.smoothOut(0.24)) {
                            selection = filter.rawValue
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .leading)
    }
}

private struct WorkoutFilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(selected ? Theme.primaryForeground : Theme.secondaryForeground)
                .padding(.horizontal, 16)
        }
        .buttonStyle(
            .glassControl(
                selected ? .tinted(Theme.primary) : .clear,
                .capsule(height: 40)
            )
        )
        .frame(minHeight: 44)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct WorkoutRow: View {
    let workout: Workout
    let isPast: Bool
    let isRunning: Bool
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var muscles: [MuscleId] { ExerciseCatalogue.musclesForExerciseIds(workout.exerciseIds) }

    static func zoomSourceID(_ workoutId: String) -> String { "workout:\(workoutId)" }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                dateStamp
                VStack(alignment: .leading, spacing: 5) {
                    title
                    detail
                    progressBars
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                BodyPreview(selectedMuscles: muscles, width: 70, height: 60)
                    .opacity(isPast ? 0.9 : 1)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 100)
            // Today's and upcoming workouts carry the warm light; finished
            // ones sit back.
            .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: isPast ? 0.35 : 0.75) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appZoomSource(Self.zoomSourceID(workout.id), cornerRadius: Theme.Radius.xl2)
        .frame(maxWidth: .infinity)
    }

    private var dateStamp: some View {
        VStack(spacing: 2) {
            Text(CalendarDate.weekdayShort(workout.date).uppercased())
                .font(Theme.sans(8, weight: .black))
                .tracking(1.15)
            Text(CalendarDate.dayOfMonth(workout.date))
                .font(Theme.readout(20))
            if isPast {
                Text(CalendarDate.monthShort(workout.date).uppercased())
                    .font(Theme.sans(8, weight: .black))
                    .tracking(0.8)
                    .opacity(0.66)
            }
        }
        .foregroundStyle(isRunning ? Theme.primary : isPast ? Theme.mutedForeground : Theme.foreground)
        .frame(width: 52)
        .frame(minHeight: 58)
    }

    private var title: some View {
        Text("\(workout.name) · \(Wording.countLabel(workout.exerciseIds.count, "exercise"))")
            .font(Theme.sans(16, weight: .heavy))
            .tracking(-0.2)
            .foregroundStyle(Theme.foreground)
            // Large text wraps instead of cutting the name short.
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    @ViewBuilder private var detail: some View {
        if isRunning, let session = ActiveWorkoutStore.shared.session {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                HStack(spacing: 6) {
                    Circle().fill(Theme.primary).frame(width: 6, height: 6)
                    Text("\(session.runningSince == nil ? "Paused" : "In progress") · \(minutes(ActiveWorkout.elapsedMs(session)))")
                }
                .font(Theme.sans(11, weight: .black))
                .tracking(0.35)
                .foregroundStyle(Theme.primary)
                .textCase(.uppercase)
            }
        } else if let completion = workout.completion {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
                Text("Completed")
                Text(minutes(completion.durationMs))
                if completion.activeCalories > 0 {
                    Text("\(Int(completion.activeCalories)) kcal")
                        .foregroundStyle(Theme.gold)
                }
            }
            .font(Theme.sans(12, weight: .semibold))
            .foregroundStyle(Theme.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        } else if isPast {
            Text("Not completed")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
        } else {
            Text(muscleSummary)
                .font(Theme.sans(11, weight: .medium))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
        }
    }

    private var progressBars: some View {
        let completed = completedExerciseIds
        let current = isRunning ? ActiveWorkoutStore.shared.session?.currentExerciseId : nil

        return HStack(spacing: 4) {
            ForEach(workout.exerciseIds, id: \.self) { id in
                Capsule()
                    .fill(progressFill(id: id, completed: completed, current: current))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 3)
    }

    private var completedExerciseIds: Set<String> {
        if isRunning, let session = ActiveWorkoutStore.shared.session {
            return Set(session.completedIds)
        }
        return Set(workout.completion?.completedExerciseIds ?? [])
    }

    private func progressFill(id: String, completed: Set<String>, current: String?) -> AnyShapeStyle {
        if completed.contains(id) {
            if isPast { return AnyShapeStyle(Theme.success) }
            return AnyShapeStyle(Theme.primaryGradient)
        }
        if id == current { return AnyShapeStyle(Theme.primary.opacity(0.48)) }
        return AnyShapeStyle(Theme.foreground.opacity(0.10))
    }

    private var muscleSummary: String {
        muscles.prefix(3).map(\.label).joined(separator: " · ")
            + (muscles.count > 3 ? " +\(muscles.count - 3)" : "")
    }

    private func minutes(_ milliseconds: Double) -> String {
        "\(Swift.max(1, Int((milliseconds / 60_000).rounded(.up)))) min"
    }
}
