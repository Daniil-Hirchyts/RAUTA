import SwiftUI

/// Behind the muscle map: a month's map drawn large, and every muscle trained,
/// with its sets a week set against what the plan aims for.
struct SummaryMusclesScreen: View {
    private let store = AppStore.shared
    @State private var month: String

    init(month: String) {
        _month = State(initialValue: month)
    }

    var body: some View {
        let history = store.trainingRecords.trainingHistory()
        let loads = SummaryAnalytics.muscles(month, history: history)
        let earliest = SummaryAnalytics.firstMonth(SummaryAnalytics.sessions())
        let maximum = loads.map(\.sets).max() ?? 0
        let weights = Dictionary(uniqueKeysWithValues: loads.map { load in
            (load.muscle, maximum > 0 ? 0.2 + 0.8 * sqrt(load.sets / maximum) : 0)
        })
        RautaScreen(
            title: "Muscles trained",
            backLabel: "Back to summary",
            onBack: store.navigation.pop
        ) {
            ScrollView {
                VStack(spacing: 16) {
                    MonthPager(month: $month, earliest: earliest)

                    BodyHeatmapPair(muscles: loads.map(\.muscle), weights: weights, height: 330)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background { GradientCard(radius: Theme.Radius.xl3, accent: Theme.destructive, strength: 0.8) }

                    if loads.isEmpty {
                        Text("No sets logged in \(SummaryAnalytics.monthTitle(month)).")
                            .font(Theme.sans(14, weight: .medium))
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(.vertical, 20)
                    } else {
                        SummarySectionLabel(text: "Sets a week")
                        VStack(spacing: 0) {
                            ForEach(Array(loads.enumerated()), id: \.element.id) { index, load in
                                if index > 0 {
                                    Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
                                }
                                row(load, maximum: loads.map { max($0.perWeek, $0.target?.upperBound ?? 0) }.max() ?? 1)
                            }
                        }
                        .padding(.horizontal, 16)
                        .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.ember, strength: 0.5) }

                        Text("Effective sets a week: a set for a muscle the exercise works directly, half for one it helps. The marked band is what your plan aims for.")
                            .font(Theme.sans(12, weight: .medium))
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, 32)
                .animation(Theme.Motion.settle, value: month)
            }
            .pageScroll()
        }
    }

    private func row(_ load: SummaryAnalytics.MuscleLoad, maximum: Double) -> some View {
        let scale = max(maximum, 1)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(load.muscle.label)
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                Spacer()
                Text(String(format: load.perWeek < 10 ? "%.1f" : "%.0f", load.perWeek))
                    .font(Theme.readout(15))
                    .foregroundStyle(Theme.foreground)
                if let target = load.target {
                    Text("/ \(Int(target.lowerBound))–\(Int(target.upperBound))")
                        .font(Theme.sans(12, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.foreground.opacity(0.07))
                    if let target = load.target {
                        Capsule()
                            .fill(Theme.foreground.opacity(0.14))
                            .frame(width: width * (target.upperBound - target.lowerBound) / scale)
                            .offset(x: width * target.lowerBound / scale)
                    }
                    Capsule()
                        .fill(Theme.ember)
                        .frame(width: max(4, width * min(1, load.perWeek / scale)))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(load.muscle.label), \(String(format: "%.1f", load.perWeek)) sets a week"
                + (load.target.map { ", aiming for \(Int($0.lowerBound)) to \(Int($0.upperBound))" } ?? "")
        )
    }
}
