import SwiftUI

/// Workouts as a calendar's list view draws them: each day once, down the
/// side, with its workouts beside it — what each is, how long it takes, what
/// it works, and the exercises in it, pictured and named.
///
/// The chat, the plan RAUTA just built and the "where should this go" page all
/// list workouts this way, so a workout reads the same wherever it turns up.
struct WorkoutAgenda: View {
    enum Accessory {
        /// The row opens the workout.
        case chevron
        /// The row files something into the workout.
        case add
    }

    let rows: [AgentSessionRow]
    var onOpen: ((String) -> Void)?
    /// The workout being worked on, marked as the current one.
    var highlightedId: String? = nil
    var accessory: Accessory = .chevron

    private static let dayColumn: CGFloat = 44

    private var days: [(date: String, rows: [AgentSessionRow])] {
        var order: [String] = []
        var byDay: [String: [AgentSessionRow]] = [:]
        for row in rows {
            if byDay[row.date] == nil { order.append(row.date) }
            byDay[row.date, default: []].append(row)
        }
        return order.map { ($0, byDay[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                if index > 0 { AgentCardDivider(inset: 14) }
                HStack(alignment: .top, spacing: 12) {
                    dayLabel(day.date)
                        .frame(width: Self.dayColumn)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(day.rows.enumerated()), id: \.element.id) { position, row in
                            if position > 0 { AgentCardDivider().padding(.vertical, 12) }
                            workout(row)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
    }

    private func dayLabel(_ date: String) -> some View {
        let today = date == CalendarDate.today
        return VStack(spacing: 0) {
            Text(today ? "TODAY" : CalendarDate.weekdayShort(date).uppercased())
                .font(Theme.sans(10, weight: .black))
                .kerning(today ? 0.4 : 1.2)
                .foregroundStyle(Theme.primary)
            Text(CalendarDate.dayOfMonth(date))
                .font(Theme.sans(24, weight: .black))
                .foregroundStyle(Theme.foreground)
            if !today, date.prefix(7) != CalendarDate.today.prefix(7) {
                Text(CalendarDate.format(date, "MMM").uppercased())
                    .font(Theme.sans(9, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CalendarDate.format(date, "EEEEdMMMM"))
    }

    @ViewBuilder private func workout(_ row: AgentSessionRow) -> some View {
        if let onOpen {
            Button {
                WorkoutAudio.touch(.tap)
                onOpen(row.id)
            } label: { workoutBody(row, opens: true) }
                .buttonStyle(.plain)
                .accessibilityHint(accessory == .add ? "Adds to this workout" : "Opens this workout")
        } else {
            workoutBody(row, opens: false)
        }
    }

    private func workoutBody(_ row: AgentSessionRow, opens: Bool) -> some View {
        let exercises = row.exerciseIds.compactMap { ExerciseCatalogue.byId[$0] }
        let current = row.id == highlightedId
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.title)
                    .font(Theme.sans(17, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                if current {
                    Text("CURRENT")
                        .font(Theme.sans(9, weight: .black))
                        .kerning(0.9)
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.primary.opacity(0.14), in: Capsule())
                }
                Spacer(minLength: 4)
                Text(detail(row))
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
                if opens {
                    switch accessory {
                    case .chevron:
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.mutedForeground)
                    case .add:
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    }
                }
            }
            if let focus = row.focus, !focus.isEmpty {
                Text(focus.prefix(4).map(\.label).joined(separator: " · "))
                    .font(Theme.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.primary.opacity(0.85))
                    .lineLimit(1)
            }
            if !exercises.isEmpty {
                HStack(spacing: 6) {
                    ForEach(exercises.prefix(4), id: \.id) { exercise in
                        ExerciseMediaView(exerciseId: exercise.id)
                            .padding(3)
                            .frame(width: 42, height: 42)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.muted.opacity(0.7)))
                    }
                    if exercises.count > 4 {
                        Text("+\(exercises.count - 4)")
                            .font(Theme.sans(13, weight: .bold))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(width: 42, height: 42)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.muted.opacity(0.7)))
                    }
                }
                .accessibilityHidden(true)
                Text(exercises.prefix(3).map { Self.name($0) }.joined(separator: " · ")
                     + (exercises.count > 3 ? " …" : ""))
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No exercises yet")
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func detail(_ row: AgentSessionRow) -> String {
        var parts: [String] = []
        if row.minutes > 0 { parts.append("\(row.minutes) min") }
        if let sets = row.sets, sets > 0 { parts.append("\(sets) sets") }
        if parts.isEmpty { parts.append(Wording.countLabel(row.exerciseIds.count, "exercise")) }
        return parts.joined(separator: " · ")
    }

    static func name(_ exercise: ExerciseSummary) -> String {
        exercise.name.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

extension AgentSessionRow {
    /// A saved workout as an agenda row, with what its plan prescribes.
    @MainActor
    static func workout(_ workout: Workout) -> AgentSessionRow {
        let planned = workout.planned.flatMap {
            TrainingPlan.plannedSessionView($0.programId, $0.sessionId)
        }
        return AgentSessionRow(
            id: workout.id,
            date: workout.date,
            title: workout.name,
            minutes: planned?.minutes ?? 0,
            exerciseIds: workout.exerciseIds,
            sets: planned?.workingSets,
            focus: planned?.focus
        )
    }

    /// A session RAUTA planned, as an agenda row.
    static func planned(_ view: PlannedSessionView, id: String? = nil) -> AgentSessionRow {
        AgentSessionRow(
            id: id ?? view.sessionId,
            date: view.date,
            title: view.title,
            minutes: view.minutes,
            exerciseIds: view.exerciseIds,
            sets: view.workingSets,
            focus: view.focus
        )
    }
}
