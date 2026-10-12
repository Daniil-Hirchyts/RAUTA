import SwiftUI

/// The top of Summary: what to train next, and the one button that does it —
/// resume, start, plan the next week, or build a first plan. A week missed in
/// part is offered a way back in, never a scolding.
struct TodayCard: View {
    let next: NextWorkout
    var onStart: (Workout) -> Void
    var onResume: () -> Void
    var onOpen: (String) -> Void

    private let navigation = AppSessionStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(kicker)
                    .font(Theme.sans(11, weight: .black))
                    .kerning(1.5)
                    .foregroundStyle(kickerTint)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if next.week.planned > 0 {
                    WeekDots(week: next.week)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(Theme.sans(23, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(Theme.sans(14, weight: .medium))
                        .foregroundStyle(Theme.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let workout = shownWorkout, !workout.exerciseIds.isEmpty {
                ExerciseStrip(exerciseIds: workout.exerciseIds)
            }

            primaryButton

            if !next.missed.isEmpty, !isRunning {
                missedRow
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { GradientCard(radius: Theme.Radius.xl3, accent: Theme.primary, strength: 1) }
    }

    // MARK: State

    private var isRunning: Bool {
        if case .running = next.state { return true }
        return false
    }

    private var shownWorkout: Workout? {
        switch next.state {
        case .running(let workout), .today(let workout), .upcoming(let workout): return workout
        case .restDay(let workout), .doneToday(let workout): return workout
        case .planFinished, .noPlan: return nil
        }
    }

    private var kicker: String {
        let today = CalendarDate.format(CalendarDate.today, "EEEdMMM").uppercased()
        switch next.state {
        case .running: return "IN PROGRESS"
        case .today: return "TODAY · \(today)"
        case .doneToday: return "DONE TODAY"
        case .restDay: return "REST DAY · \(today)"
        case .upcoming: return "NEXT WORKOUT"
        case .planFinished: return "PLAN COMPLETE"
        case .noPlan: return "GET STARTED"
        }
    }

    private var kickerTint: Color {
        switch next.state {
        case .doneToday, .planFinished: return Theme.success
        default: return Theme.primary
        }
    }

    private var title: String {
        switch next.state {
        case .running(let workout): return workout.name
        case .today(let workout): return workout.name
        case .doneToday: return "Today's training is logged"
        case .restDay: return "Rest and recover"
        case .upcoming(let workout): return workout.name
        case .planFinished: return "Your plan is done"
        case .noPlan: return "Let RAUTA build your first week"
        }
    }

    private var detail: String? {
        switch next.state {
        case .running:
            return "Pick up where you left off — your sets are saved as you go."
        case .today(let workout):
            return summary(workout)
        case .doneToday(let workout):
            return workout.map { "Next: \($0.name), \(day($0.date)). \(summary($0))" } ?? "Nothing else is scheduled yet."
        case .restDay(let workout):
            return workout.map { "Rest is part of the plan. Next: \($0.name), \(day($0.date))." }
        case .upcoming(let workout):
            return "\(day(workout.date)). \(summary(workout))"
        case .planFinished:
            return "Plan the next week and RAUTA carries on the exercises that are working, with loads from what you logged."
        case .noPlan:
            return "Pick the days you can train. RAUTA plans around your goal, your equipment and your time."
        }
    }

    private func summary(_ workout: Workout) -> String {
        var parts = [Wording.countLabel(workout.exerciseIds.count, "exercise")]
        if let planned = workout.planned.flatMap({ TrainingPlan.plannedSessionView($0.programId, $0.sessionId) }) {
            parts.append("about \(planned.minutes) min")
        }
        return parts.joined(separator: " · ")
    }

    private func day(_ date: String) -> String {
        if date == CalendarDate.today { return "today" }
        if date == CalendarDate.shift(CalendarDate.today, by: 1) { return "tomorrow" }
        return CalendarDate.format(date, "EEEEdMMM")
    }

    // MARK: Actions

    @ViewBuilder private var primaryButton: some View {
        switch next.state {
        case .running:
            AppButton("Resume workout", size: .cta, expands: true, action: onResume)
        case .today(let workout):
            VStack(spacing: 8) {
                AppButton("Start workout", size: .cta, expands: true) { onStart(workout) }
                Button {
                    Haptics.trigger(.selection)
                    onOpen(workout.id)
                } label: {
                    Text(workout.planned == nil ? "See exercises" : "See exercises and why")
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.plain)
            }
        case .doneToday:
            AppButton("See your week", variant: .secondary, size: .cta, expands: true) {
                navigation.push(.coachReview, from: "summary-today")
            }
        case .restDay(let workout?), .upcoming(let workout):
            AppButton("Open \(CalendarDate.weekdayShort(workout.date))'s workout", variant: .secondary, size: .cta, expands: true) {
                onOpen(workout.id)
            }
        case .restDay(nil):
            AppButton("Plan my next week", size: .cta, expands: true) {
                navigation.push(.coachNextWeek, from: "summary-today")
            }
        case .planFinished:
            AppButton("Plan my next week", size: .cta, expands: true) {
                navigation.push(.coachNextWeek, from: "summary-today")
            }
        case .noPlan:
            AppButton("Build a starter plan", size: .cta, expands: true) {
                navigation.push(.planWeek(sourceProgramId: nil), from: "summary-today")
            }
        }
    }

    private var missedRow: some View {
        Button {
            Haptics.trigger(.selection)
            navigation.push(.coachAdjust, from: "summary-today")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.gold)
                    .accessibilityHidden(true)
                Text(missedText)
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Adjust")
                    .font(Theme.sans(13, weight: .bold))
                    .foregroundStyle(Theme.primary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Theme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Help me adjust")
    }

    private var missedText: String {
        guard let first = next.missed.first else { return "" }
        if next.missed.count == 1 {
            return "\(first.name) on \(CalendarDate.format(first.date, "EEEE")) didn't happen. Move it or fit it into the week?"
        }
        return "\(next.missed.count) planned sessions didn't happen this week. Want to rebalance?"
    }
}

/// This week's planned sessions as dots: filled when done, ringed when still
/// to come, crossed when missed. Shape as well as colour carries the state.
struct WeekDots: View {
    let week: WeekProgress

    var body: some View {
        HStack(spacing: 6) {
            Text(week.summary)
                .font(Theme.sans(12, weight: .bold))
                .foregroundStyle(Theme.secondaryForeground)
                .monospacedDigit()
            HStack(spacing: 3) {
                ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                    dot(state)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(week.completedPlanned) of \(week.planned) planned sessions done"
            + (week.missed.isEmpty ? "" : ", \(week.missed.count) missed"))
    }

    private enum DotState { case done, missed, pending }

    private var states: [DotState] {
        let missed = week.missed.count
        let done = week.completedPlanned
        let pending = Swift.max(0, week.planned - done - missed)
        return Array(repeating: .done, count: done) + Array(repeating: .missed, count: missed)
            + Array(repeating: .pending, count: pending)
    }

    @ViewBuilder private func dot(_ state: DotState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.success)
        case .missed:
            Image(systemName: "xmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.primary)
        }
    }
}

/// The first exercises of a workout, pictured, with how many more follow.
struct ExerciseStrip: View {
    let exerciseIds: [String]

    var body: some View {
        let exercises = exerciseIds.compactMap { ExerciseCatalogue.byId[$0] }
        HStack(spacing: 6) {
            ForEach(exercises.prefix(5), id: \.id) { exercise in
                ExerciseMediaView(exerciseId: exercise.id)
                    .padding(3)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.muted.opacity(0.7)))
            }
            if exercises.count > 5 {
                Text("+\(exercises.count - 5)")
                    .font(Theme.sans(13, weight: .bold))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.muted.opacity(0.7)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exercises: " + exercises.prefix(5).map { $0.name.capitalized }.joined(separator: ", ")
            + (exercises.count > 5 ? ", and \(exercises.count - 5) more" : ""))
    }
}

/// The three coaching features, always in the same place under the Today
/// card: plan the week ahead, adjust this one, look back on it.
struct CoachingTiles: View {
    var hasPlan: Bool
    private let navigation = AppSessionStore.shared

    var body: some View {
        HStack(spacing: 10) {
            tile(
                title: hasPlan ? "My next week" : "Plan my week",
                detail: hasPlan ? "Build what's next" : "A first plan",
                icon: "calendar.badge.plus",
                zoomID: "coach-next"
            ) {
                navigation.push(hasPlan ? .coachNextWeek : .planWeek(sourceProgramId: nil), from: "coach-next")
            }
            tile(title: "Help me adjust", detail: "Missed, short or no kit", icon: "arrow.triangle.2.circlepath", zoomID: "coach-adjust") {
                navigation.push(.coachAdjust, from: "coach-adjust")
            }
            tile(title: "Weekly review", detail: "What changed", icon: "chart.line.uptrend.xyaxis", zoomID: "coach-review") {
                navigation.push(.coachReview, from: "coach-review")
            }
        }
    }

    private func tile(title: String, detail: String, icon: String, zoomID: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.trigger(.selection)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 30, height: 30)
                    .background(Theme.primary.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.sans(14, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(Theme.sans(11, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: 0.6) }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous))
        }
        .buttonStyle(EquipmentCardButtonStyle())
        .appZoomSource(zoomID, cornerRadius: Theme.Radius.xl2)
        .accessibilityElement(children: .combine)
        .accessibilityHint(detail)
    }
}
