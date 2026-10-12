import SwiftUI

/// My weekly review: the week as planned and as done, what changed in
/// exercises that can be compared like for like, and one thing to do next.
struct WeeklyReviewScreen: View {
    private let store = AppStore.shared

    private enum Which: Hashable { case thisWeek, lastWeek }
    @State private var which: Which = .thisWeek

    private var day: String {
        which == .thisWeek ? CalendarDate.today : CalendarDate.shift(CalendarDate.today, by: -7)
    }

    var body: some View {
        // Read on every redraw: a session finished elsewhere shows at once.
        let review = WeeklyReview.current(weekOf: day)
        RautaScreen(
            title: "Weekly review",
            subtitle: review.week.label,
            backLabel: "Close",
            onBack: store.navigation.pop,
            right: { RautaHeaderBadge(mood: review.isEmpty ? .curious : .proud) }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GlassSegmentedPicker(
                        title: "Week",
                        options: [Which.thisWeek, .lastWeek],
                        selection: $which,
                        label: { $0 == .thisWeek ? "This week" : "Last week" }
                    )

                    VStack(alignment: .leading, spacing: 14) {
                        Text(review.headline)
                            .font(Theme.sans(22, weight: .heavy))
                            .foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        WeekStrip(week: review.week)
                        ForEach(review.consistency, id: \.self) { line in
                            Text(line)
                                .font(Theme.sans(14, weight: .medium))
                                .foregroundStyle(Theme.secondaryForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { GradientCard(radius: Theme.Radius.xl3, accent: Theme.primary, strength: 0.9) }

                    if !review.changes.isEmpty {
                        PageSection(title: "Compared with last time") {
                            ForEach(review.changes) { change in
                                PageRow(
                                    icon: icon(change.direction),
                                    tint: tint(change.direction),
                                    title: change.name,
                                    detail: [change.text, change.estimate].compactMap { $0 }.joined(separator: "\n"),
                                    showsDivider: change.id != review.changes.last?.id
                                )
                                .accessibilityValue(direction(change.direction))
                            }
                            PageNote(text: "Each exercise is set against the last session it was done in, on the same equipment. Top set means the heaviest set, then the most reps at it.")
                        }
                    }

                    if !review.dataNotes.isEmpty {
                        PageSection(title: "What RAUTA can't tell yet") {
                            ForEach(Array(review.dataNotes.enumerated()), id: \.offset) { index, note in
                                PageRow(icon: "questionmark.circle", tint: Theme.gold, title: note,
                                        showsDivider: index < review.dataNotes.count - 1)
                            }
                        }
                    }

                    PageSection(title: "Next") {
                        PageRow(icon: "arrow.right.circle.fill", title: review.next.title, detail: review.next.detail, showsDivider: false)
                        if let label = actionLabel(review.next.kind) {
                            AppButton(label, size: .cta, expands: true) { perform(review.next.kind) }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 14)
                        }
                    }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, 24)
            }
            .pageScroll()
        }
    }

    private func icon(_ direction: WeeklyReview.ExerciseChange.Direction) -> String {
        switch direction {
        case .up: return "arrow.up.right.circle.fill"
        case .same: return "equal.circle"
        case .down: return "arrow.down.right.circle"
        }
    }

    private func tint(_ direction: WeeklyReview.ExerciseChange.Direction) -> Color {
        switch direction {
        case .up: return Theme.success
        case .same: return Theme.mutedForeground
        case .down: return Theme.gold
        }
    }

    private func direction(_ direction: WeeklyReview.ExerciseChange.Direction) -> String {
        switch direction {
        case .up: return "Up"
        case .same: return "Same"
        case .down: return "Down"
        }
    }

    private func actionLabel(_ kind: WeeklyReview.NextAction.Kind) -> String? {
        switch kind {
        case .start: return "Start workout"
        case .adjust: return "Help me adjust"
        case .nextWeek: return "Plan my next week"
        case .buildPlan: return "Build a plan"
        case .recordEffort, .none: return nil
        }
    }

    private func perform(_ kind: WeeklyReview.NextAction.Kind) {
        switch kind {
        case .start(let workoutId):
            store.navigation.requestedStartWorkoutId = workoutId
            store.navigation.reset([.workouts])
        case .adjust:
            store.navigation.replace(.coachAdjust)
        case .nextWeek:
            store.navigation.replace(.coachNextWeek)
        case .buildPlan:
            store.navigation.replace(.planWeek(sourceProgramId: nil))
        case .recordEffort, .none:
            break
        }
    }
}

/// The seven days of a week, each marked by what happened — a tick for done,
/// a ring for still planned, a cross for missed, "Rest" for a planned rest
/// day — so the state reads without relying on colour.
struct WeekStrip: View {
    let week: WeekProgress

    var body: some View {
        HStack(spacing: 4) {
            ForEach(week.days) { day in
                VStack(spacing: 6) {
                    symbol(day.status)
                        .frame(height: 22)
                    Text(CalendarDate.weekdayShort(day.date))
                        .font(Theme.sans(11, weight: day.isToday ? .black : .semibold))
                        .foregroundStyle(day.isToday ? Theme.primary : Theme.mutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(CalendarDate.format(day.date, "EEEE")): \(label(day.status))")
            }
        }
    }

    @ViewBuilder private func symbol(_ status: WeekProgress.DayStatus) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.success)
        case .planned:
            Image(systemName: "circle").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.primary)
        case .missed:
            Image(systemName: "xmark.circle").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.mutedForeground)
        case .rest:
            Text("Rest")
                .font(Theme.sans(10, weight: .bold))
                .foregroundStyle(Theme.mutedForeground)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(Theme.muted.opacity(0.5), in: Capsule())
        case .open:
            Circle().fill(Theme.foreground.opacity(0.08)).frame(width: 8, height: 8)
        }
    }

    private func label(_ status: WeekProgress.DayStatus) -> String {
        switch status {
        case .done: return "trained"
        case .planned: return "planned"
        case .missed: return "missed"
        case .rest: return "planned rest day"
        case .open: return "nothing planned"
        }
    }
}
