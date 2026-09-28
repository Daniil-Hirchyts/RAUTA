import Charts
import SwiftUI

/// Behind the Workouts and Training time cards: a month of training, week by
/// week, and every session in it. The two cards open the same page on their
/// own measure; the switch at the top moves between them.
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
        RautaScreen(
            title: metric == .workouts ? "Workouts" : "Training time",
            backLabel: "Back to summary",
            onBack: store.navigation.pop
        ) {
            ScrollView {
                VStack(spacing: 16) {
                    MonthPager(month: $month, earliest: SummaryAnalytics.firstMonth(sessions))

                    GlassSegmentedPicker(
                        title: "Measure",
                        options: SummaryMetric.allCases,
                        selection: $metric,
                        label: \.label
                    )

                    hero(activity)
                    chart(activity)

                    if activity.sessions.isEmpty {
                        Text("Nothing trained in \(SummaryAnalytics.monthTitle(month)).")
                            .font(Theme.sans(14, weight: .medium))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        SummarySectionLabel(text: "Sessions")
                            .padding(.top, 4)
                        WorkoutAgenda(
                            rows: activity.sessions.map(row),
                            onOpen: { id in
                                guard store.workouts.workout(id) != nil else { return }
                                Haptics.trigger(.selection)
                                store.navigation.openWorkout(id)
                            }
                        )
                        .background { GradientCard(radius: Theme.Radius.xl2, accent: accent, strength: 0.5) }
                    }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, 32)
                .animation(Theme.Motion.settle, value: month)
                .animation(Theme.Motion.settle, value: metric)
            }
            .pageScroll()
        }
    }

    // MARK: Pieces

    private func hero(_ activity: SummaryAnalytics.MonthActivity) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric == .workouts ? "\(activity.count)" : SummaryAnalytics.duration(activity.totalSeconds))
                    .font(Theme.readout(52))
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                Text(metric == .workouts
                     ? (activity.count == 1 ? "session in \(SummaryAnalytics.monthTitle(month))" : "sessions in \(SummaryAnalytics.monthTitle(month))")
                     : "trained in \(SummaryAnalytics.monthTitle(month))")
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
            }
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

    private struct WeekBar: Identifiable {
        var id: String { label }
        var label: String
        var value: Double
    }

    private func chart(_ activity: SummaryAnalytics.MonthActivity) -> some View {
        let values = metric == .workouts ? activity.weeklyCounts : activity.weeklySeconds.map { $0 / 60 }
        let bars = zip(activity.weekRanges, values)
            .filter { !$0.0.isEmpty }
            .map { WeekBar(label: $0.0, value: $0.1) }
        let selected = bars.first { $0.label == selectedWeek }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BY WEEK")
                    .font(Theme.sans(10, weight: .black))
                    .kerning(1.3)
                    .foregroundStyle(Theme.mutedForeground)
                Spacer()
                if let selected {
                    Text("\(selected.label): \(format(selected.value))")
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .transition(.opacity)
                }
            }
            Chart(bars) { bar in
                BarMark(
                    x: .value("Days", bar.label),
                    y: .value(metric == .workouts ? "Sessions" : "Minutes", bar.value),
                    width: .ratio(0.42)
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
                            Text(metric == .workouts ? "\(Int(number))" : "\(Int(number))m")
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
            .frame(height: 170)
            .accessibilityLabel("Weekly \(metric == .workouts ? "sessions" : "training time")")
        }
        .padding(16)
        .background { GradientCard(radius: Theme.Radius.xl2, accent: accent, strength: 0.5) }
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
