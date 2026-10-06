import Charts
import SwiftUI

/// Behind the Workouts and Training time cards: a month of training, week by
/// week, and every session in it.
///
/// The month and the measure are switched from the band at the foot of the
/// page, so they stay in reach and in view however far down the sessions the
/// page is scrolled; the month the page covers sits under its title.
struct SummaryActivityScreen: View {
    private let store = AppStore.shared
    @State private var month: String
    @State private var metric: SummaryMetric
    @State private var selectedWeek: String?

    init(month: String, metric: SummaryMetric) {
        _month = State(initialValue: month)
        _metric = State(initialValue: metric)
    }

    private var accent: Color { metric == .workouts ? Theme.primary : Theme.gold }

    var body: some View {
        let sessions = SummaryAnalytics.sessions()
        let activity = SummaryAnalytics.activity(month, sessions: sessions)
        let earliest = SummaryAnalytics.firstMonth(sessions)
        SummaryDetailPage(
            title: metric == .workouts ? "Workouts" : "Training time",
            period: SummaryAnalytics.monthTitle(month)
        ) {
            overview(activity)

            if activity.sessions.isEmpty {
                EmptyStatePlaceholder(
                    symbol: "calendar",
                    title: "Nothing trained in \(SummaryAnalytics.monthTitle(month))",
                    message: month == SummaryAnalytics.monthKey()
                        ? "Workouts you finish this month show up here."
                        : "Step to another month at the bottom of the page."
                )
                .padding(.vertical, 24)
            } else {
                SummarySectionLabel(text: "Sessions")
                    .padding(.top, 8)
                WorkoutAgenda(
                    rows: activity.sessions.map(row),
                    onOpen: { id in
                        Haptics.trigger(.selection)
                        // Inside this page's stack, so Back comes back here.
                        store.navigation.push(.plannedWorkout(workoutId: id))
                    },
                    canOpen: { store.workouts.workout($0) != nil }
                )
                .background { GradientCard(radius: Theme.Radius.xl2, accent: accent, strength: 0.5) }
            }
        } controls: {
            SummaryPeriodBar(month: $month, earliest: earliest) {
                GlassSegmentedPicker(
                    title: "Measure",
                    options: SummaryMetric.allCases,
                    selection: $metric,
                    label: { $0 == .workouts ? "Workouts" : "Time" },
                    tint: accent
                )
            }
        }
        .animation(Theme.Motion.settle, value: month)
        .animation(Theme.Motion.settle, value: metric)
        .onChange(of: month) { _, _ in selectedWeek = nil }
    }

    // MARK: Pieces

    /// The month in one card: the figure, what it is made of, and how it fell
    /// week by week. A week touched on the chart takes over the figure.
    private func overview(_ activity: SummaryAnalytics.MonthActivity) -> some View {
        let bars = weekBars(activity)
        let selected = bars.first { $0.label == selectedWeek }
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.map { format($0.value) } ?? headline(activity))
                    .font(Theme.readout(44))
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(selected.map { "in the week of \($0.label)" } ?? caption(activity))
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
            }

            chart(bars)

            HStack(spacing: 12) {
                SummaryStat(value: SummaryAnalytics.duration(activity.averageSeconds), label: "Average")
                SummaryStat(value: activity.longest.map { SummaryAnalytics.duration($0.durationSeconds) } ?? "—", label: "Longest")
                SummaryStat(value: "\(activity.totalSets)", label: "Working sets")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { GradientCard(radius: Theme.Radius.xl2, accent: accent) }
    }

    private func headline(_ activity: SummaryAnalytics.MonthActivity) -> String {
        metric == .workouts ? "\(activity.count)" : SummaryAnalytics.duration(activity.totalSeconds)
    }

    private func caption(_ activity: SummaryAnalytics.MonthActivity) -> String {
        let when = month == SummaryAnalytics.monthKey() ? "this month" : "in \(SummaryAnalytics.monthTitle(month))"
        switch metric {
        case .workouts: return (activity.count == 1 ? "session " : "sessions ") + when
        case .time: return "trained " + when
        }
    }

    private struct WeekBar: Identifiable {
        var id: String { label }
        var label: String
        var value: Double
    }

    private func weekBars(_ activity: SummaryAnalytics.MonthActivity) -> [WeekBar] {
        let values = metric == .workouts ? activity.weeklyCounts : activity.weeklySeconds.map { $0 / 60 }
        return zip(activity.weekRanges, values)
            .filter { !$0.0.isEmpty }
            .map { WeekBar(label: $0.0, value: $0.1) }
    }

    private func chart(_ bars: [WeekBar]) -> some View {
        // Minutes read as hours once a week passes two hours.
        let hours = metric == .time && (bars.map(\.value).max() ?? 0) > 120
        return Chart(bars) { bar in
            BarMark(
                x: .value("Week", bar.label),
                y: .value(metric == .workouts ? "Sessions" : "Minutes", hours ? bar.value / 60 : bar.value),
                width: .ratio(0.46)
            )
            .foregroundStyle(accent.opacity(selectedWeek == nil || selectedWeek == bar.label ? 1 : 0.35))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
        }
        .chartXSelection(value: $selectedWeek)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.foreground.opacity(0.08))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(axisLabel(number, hours: hours))
                            .font(Theme.sans(10, weight: .medium))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(Theme.sans(10, weight: .semibold))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
        }
        .frame(height: 150)
        .accessibilityLabel("Weekly \(metric == .workouts ? "sessions" : "training time")")
    }

    private func axisLabel(_ number: Double, hours: Bool) -> String {
        switch metric {
        case .workouts:
            return number == number.rounded() ? "\(Int(number))" : ""
        case .time:
            return hours ? "\(Num.trimmed(number))h" : "\(Int(number))m"
        }
    }

    private func format(_ value: Double) -> String {
        metric == .workouts
            ? Wording.countLabel(Int(value), "session")
            : SummaryAnalytics.duration(value * 60)
    }

    private func row(_ session: SummaryAnalytics.SessionRow) -> AgentSessionRow {
        AgentSessionRow(
            id: session.workoutId ?? session.id,
            date: CalendarDate.toISO(session.completedAt),
            title: session.partial ? "\(session.title) · partial" : session.title,
            minutes: Int((session.durationSeconds / 60).rounded()),
            exerciseIds: session.exerciseIds,
            sets: session.sets
        )
    }
}
