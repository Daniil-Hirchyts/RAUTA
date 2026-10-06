import SwiftUI

/// Behind the muscle map: the month's map drawn large with how its heat reads,
/// then every muscle the month worked, its sets a week against what the plan
/// aims for.
///
/// The card that opens the page already names the leaders, so the page goes
/// straight to the whole list. The month is stepped from the band at the foot
/// of the page, or by swiping the map.
struct SummaryMusclesScreen: View {
    private let store = AppStore.shared
    @State private var month: String

    init(month: String) {
        _month = State(initialValue: month)
    }

    var body: some View {
        let loads = SummaryAnalytics.muscles(month, history: store.trainingRecords.trainingHistory())
        let earliest = SummaryAnalytics.firstMonth(SummaryAnalytics.sessions())
        let estimated = loads.contains(where: \.estimated)
        SummaryDetailPage(title: "Muscles trained", period: SummaryAnalytics.monthTitle(month)) {
            map(loads)
                .monthSwipe($month, earliest: earliest)

            if loads.isEmpty {
                EmptyStatePlaceholder(
                    symbol: "figure.strengthtraining.traditional",
                    title: "Nothing trained in \(SummaryAnalytics.monthTitle(month))",
                    message: month == SummaryAnalytics.monthKey()
                        ? "Finish a workout and the muscles it worked light up here."
                        : "Step to another month at the bottom of the page."
                )
                .padding(.vertical, 24)
            } else {
                SummarySectionLabel(text: estimated ? "Sets a week · estimated" : "Sets a week")
                    .padding(.top, 8)
                list(loads)
                Text(footnote(loads, estimated: estimated))
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        } controls: {
            SummaryPeriodBar(month: $month, earliest: earliest)
        }
        .animation(Theme.Motion.settle, value: month)
    }

    // MARK: Pieces

    /// The month's map, front and back, warmest where the most sets went.
    private func map(_ loads: [SummaryAnalytics.MuscleLoad]) -> some View {
        let maximum = loads.map(\.sets).max() ?? 0
        let weights = Dictionary(uniqueKeysWithValues: loads.map { load in
            (load.muscle, maximum > 0 ? 0.2 + 0.8 * sqrt(load.sets / maximum) : 0)
        })
        return VStack(spacing: 16) {
            BodyHeatmapPair(muscles: loads.map(\.muscle), weights: weights, height: 300)
            MuscleIntensityKey()
                .frame(maxWidth: 200)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.ember, strength: 0.6) }
    }

    private func list(_ loads: [SummaryAnalytics.MuscleLoad]) -> some View {
        // One scale for every bar, so the bars compare across rows.
        let scale = max(1, loads.map { max($0.perWeek, $0.target?.upperBound ?? 0) }.max() ?? 1)
        return VStack(spacing: 0) {
            ForEach(Array(loads.enumerated()), id: \.element.id) { index, load in
                if index > 0 {
                    Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
                }
                row(load, scale: scale)
            }
        }
        .padding(.horizontal, 16)
        .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.ember, strength: 0.4) }
    }

    private func row(_ load: SummaryAnalytics.MuscleLoad, scale: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(load.muscle.label)
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                Spacer(minLength: 8)
                Text(Self.sets(load.perWeek))
                    .font(Theme.readout(17))
                    .foregroundStyle(Theme.ember)
                if let target = load.target {
                    Text("aim \(Int(target.lowerBound))–\(Int(target.upperBound))")
                        .font(Theme.sans(12, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.foreground.opacity(0.07))
                    if let target = load.target {
                        // What the plan aims for, as a band the bar fills into.
                        Capsule()
                            .fill(Theme.foreground.opacity(0.12))
                            .frame(width: max(6, width * (target.upperBound - target.lowerBound) / scale))
                            .offset(x: width * target.lowerBound / scale)
                    }
                    Capsule()
                        .fill(Theme.ember)
                        .frame(width: max(6, width * min(1, load.perWeek / scale)))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(load.muscle.label), \(Self.sets(load.perWeek)) sets a week"
                + (load.target.map { ", aiming for \(Int($0.lowerBound)) to \(Int($0.upperBound))" } ?? "")
        )
    }

    private func footnote(_ loads: [SummaryAnalytics.MuscleLoad], estimated: Bool) -> String {
        if estimated {
            let when = month == SummaryAnalytics.monthKey() ? "this month" : "in \(SummaryAnalytics.monthTitle(month))"
            return "Worked out from the exercises checked off, as no sets were logged \(when). Log sets to see the real count."
        }
        let band = loads.contains { $0.target != nil } ? " The marked band is what your plan aims for." : ""
        return "Effective sets: a set counts in full for a muscle the exercise works directly, and half for one it helps.\(band)"
    }

    private static func sets(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }
}
