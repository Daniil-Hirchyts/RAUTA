import SwiftUI

struct MonthlySummarySnapshot {
    let monthTitle: String
    let workoutCount: Int
    let totalDurationSeconds: Double
    let averageDurationSeconds: Double
    let weeklyWorkoutCounts: [Double]
    let weeklyDurationSeconds: [Double]
    let trainedMuscles: [MuscleId]
    let muscleWeights: [MuscleId: Double]
    let leadingMuscles: [(muscle: MuscleId, value: Double)]

    @MainActor
    init(
        workouts: [Workout],
        history: TrainingHistory,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let key = SummaryAnalytics.monthKey(now, calendar: calendar)
        // The same sessions, counted the same way, as the page behind the card.
        let activity = SummaryAnalytics.activity(
            key,
            sessions: SummaryAnalytics.sessions(workouts: workouts),
            calendar: calendar
        )
        monthTitle = CalendarDate.string(from: now, template: "MMMM")
        workoutCount = activity.count
        totalDurationSeconds = activity.totalSeconds
        averageDurationSeconds = activity.averageSeconds
        weeklyWorkoutCounts = activity.weeklyCounts
        weeklyDurationSeconds = activity.weeklySeconds

        let loads = SummaryAnalytics.muscles(key, history: history, workouts: workouts, now: now)
        let maximum = loads.map(\.sets).max() ?? 0
        trainedMuscles = loads.map(\.muscle)
        leadingMuscles = Array(loads.prefix(4)).map { ($0.muscle, $0.sets) }
        muscleWeights = Dictionary(uniqueKeysWithValues: loads.map { load in
            let normalized = maximum > 0 ? load.sets / maximum : 0
            return (load.muscle, 0.20 + 0.80 * sqrt(normalized))
        })
    }
}

struct MonthlySummaryDashboard: View {
    let snapshot: MonthlySummarySnapshot
    private let month = SummaryAnalytics.monthKey()

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 10) {
                SummaryCardLink(page: .summaryActivity(month: month, metric: .workouts), zoomID: "summary-workouts") {
                    SummaryMetricCard(
                        title: "Workouts",
                        systemImage: "figure.strengthtraining.traditional",
                        accent: Theme.primary,
                        value: "\(snapshot.workoutCount)",
                        detail: snapshot.workoutCount == 1 ? "session this month" : "sessions this month",
                        bars: snapshot.weeklyWorkoutCounts
                    )
                }
                .pageArrival(4)

                SummaryCardLink(page: .summaryActivity(month: month, metric: .time), zoomID: "summary-time") {
                    SummaryMetricCard(
                        title: "Training time",
                        systemImage: "timer",
                        accent: Theme.gold,
                        value: SummaryAnalytics.duration(snapshot.totalDurationSeconds),
                        detail: snapshot.workoutCount == 0
                            ? "no time logged yet"
                            : "\(SummaryAnalytics.duration(snapshot.averageDurationSeconds)) average",
                        bars: snapshot.weeklyDurationSeconds
                    )
                }
                .pageArrival(5)
            }

            SummaryCardLink(page: .summaryMuscles(month: month), zoomID: "summary-muscles", cornerRadius: Theme.Radius.xl3) {
                MuscleHeatmapCard(snapshot: snapshot)
            }
            .pageArrival(6)
        }
        // Square cards and fixed chart columns: text grows with Dynamic Type
        // up to the point where they can still hold it.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

private struct SummaryMetricCard: View {
    let title: String
    let systemImage: String
    let accent: Color
    let value: String
    let detail: String
    let bars: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(Theme.sans(15, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    // Wraps rather than truncates at the larger text sizes.
                    .lineLimit(1...2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(0.14), in: Circle())
            }

            Text(value)
                .font(Theme.readout(value.count > 5 ? 27 : 34))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .padding(.top, 12)

            Text(detail)
                .font(Theme.sans(11, weight: .medium))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.top, 3)

            Spacer(minLength: 8)

            WeeklyBars(values: bars, accent: accent)
                .frame(height: 42)
        }
        .padding(14)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { GradientCard(radius: Theme.Radius.xl2, accent: accent) }
        .accessibilityElement(children: .combine)
    }
}

/// A month's five weeks as small bars. They grow into place as Summary
/// arrives, and this week's bar breathes, the one still being filled.
private struct WeeklyBars: View {
    let values: [Double]
    let accent: Color

    @Environment(\.pageArrived) private var arrived
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maximum: Double { Swift.max(values.max() ?? 0, 1) }
    private var currentWeek: Int { SummaryAnalytics.weekBin(for: Date()) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(
                            value > 0
                                ? accent.opacity(0.42 + 0.58 * value / maximum)
                                : Theme.foreground.opacity(0.07)
                        )
                        .frame(width: 6, height: Swift.max(4, 28 * value / maximum * (arrived ? 1 : 0.1)))
                        .modifier(Breathing(active: index == currentWeek && value > 0 && !reduceMotion))
                        .animation(
                            arrived ? .spring(response: 0.6, dampingFraction: 0.72).delay(0.25 + Double(index) * 0.05) : nil,
                            value: arrived
                        )
                        .frame(maxHeight: 28, alignment: .bottom)

                    Text("W\(index + 1)")
                        .font(Theme.sans(7, weight: .bold))
                        .foregroundStyle(Theme.mutedForeground.opacity(0.72))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A slow rise and fall in brightness: something still in progress.
private struct Breathing: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                content.opacity(0.62 + 0.38 * (0.5 + 0.5 * sin(t * 2.2)))
            }
        } else {
            content
        }
    }
}

private struct MuscleHeatmapCard: View {
    let snapshot: MonthlySummarySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MUSCLES TRAINED")
                    .font(Theme.sans(10, weight: .black))
                    .kerning(1.35)
                    .foregroundStyle(Theme.ember)

                Text(snapshot.monthTitle)
                    .font(Theme.sans(20, weight: .bold))
                    .foregroundStyle(Theme.foreground)
            }

            HStack(alignment: .center, spacing: 12) {
                BodyHeatmapPair(
                    muscles: snapshot.trainedMuscles,
                    weights: snapshot.muscleWeights
                )
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 13) {
                    if snapshot.leadingMuscles.isEmpty {
                        Text("Finish a workout to light up your monthly map.")
                            .font(Theme.sans(12, weight: .medium))
                            .foregroundStyle(Theme.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("MOST TRAINED")
                            .font(Theme.sans(8, weight: .black))
                            .kerning(1.0)
                            .foregroundStyle(Theme.mutedForeground)

                        ForEach(snapshot.leadingMuscles, id: \.muscle) { entry in
                            muscleRow(entry)
                        }
                    }

                    Spacer(minLength: 0)

                    MuscleIntensityKey()
                }
                .frame(width: 116)
                .frame(minHeight: 224, alignment: .topLeading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { GradientCard(radius: Theme.Radius.xl3, accent: Theme.destructive, strength: 0.8) }
    }

    private func muscleRow(_ entry: (muscle: MuscleId, value: Double)) -> some View {
        let weight = snapshot.muscleWeights[entry.muscle] ?? 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.muscle.label)
                    .font(Theme.sans(11, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 2)

                Text(Self.setValue(entry.value))
                    .font(Theme.readout(9))
                    .foregroundStyle(Theme.ember)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(Theme.foreground.opacity(0.07))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.ember.opacity(0.34 + 0.66 * weight))
                            .frame(width: proxy.size.width * weight)
                    }
            }
            .frame(height: 4)
        }
    }

    private static func setValue(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

/// How the heat on a muscle map reads, from little work to a lot.
struct MuscleIntensityKey: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.ember.opacity(0.20 + 0.16 * Double(level)))
                        .frame(maxWidth: .infinity)
                        .frame(height: 7)
                }
            }
            HStack {
                Text("LOW")
                Spacer()
                Text("HIGH")
            }
            .font(Theme.sans(8, weight: .black))
            .kerning(0.65)
            .foregroundStyle(Theme.mutedForeground)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Muscle intensity from low to high")
    }
}

struct BodyHeatmapPair: View {
    let muscles: [MuscleId]
    let weights: [MuscleId: Double]
    var height: CGFloat = 238

    @Environment(\.pageArrived) private var arrived

    var body: some View {
        HStack(spacing: 2) {
            figure(.front)
            figure(.back)
        }
        .frame(height: height)
        // The map warms up as Summary arrives.
        .opacity(arrived ? 1 : 0.35)
        .scaleEffect(arrived ? 1 : 0.97)
        .animation(arrived ? .easeOut(duration: 0.7).delay(0.3) : nil, value: arrived)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            muscles.isEmpty
                ? "No muscles trained"
                : "Muscles trained: " + muscles.map(\.label).joined(separator: ", ")
        )
    }

    private func figure(_ side: BodySide) -> some View {
        BodyFigure(
            view: BodyPaths.view(side),
            selectedMuscles: muscles,
            muscleWeights: weights,
            selectedColor: Theme.ember,
            showsSelectionGlow: false,
            compact: true
        )
        .frame(maxWidth: .infinity)
    }
}
