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
        let interval = calendar.dateInterval(of: .month, for: now)
            ?? DateInterval(start: now, duration: 1)
        let monthWorkouts = workouts.filter { workout in
            guard let completedAt = workout.completion?.completedAt,
                  let millis = ISOTime.parse(completedAt)
            else { return false }
            return interval.contains(Date(epochMillis: millis))
        }
        let monthSessions = history.sessions.filter { session in
            guard let millis = ISOTime.parse(session.completedAt) else { return false }
            return interval.contains(Date(epochMillis: millis))
        }

        monthTitle = CalendarDate.string(from: now, template: "MMMM")

        workoutCount = Swift.max(monthWorkouts.count, monthSessions.count)
        let workoutDuration = monthWorkouts.compactMap(\.completion).reduce(0) {
            $0 + $1.durationMs / 1_000
        }
        let sessionDuration = monthSessions.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
        totalDurationSeconds = monthWorkouts.isEmpty ? sessionDuration : workoutDuration
        averageDurationSeconds = workoutCount > 0
            ? totalDurationSeconds / Double(workoutCount)
            : 0

        var workoutBins = Array(repeating: 0.0, count: 5)
        var durationBins = Array(repeating: 0.0, count: 5)
        for workout in monthWorkouts {
            guard let completion = workout.completion,
                  let millis = ISOTime.parse(completion.completedAt)
            else { continue }
            let date = Date(epochMillis: millis)
            let bin = Self.weekBin(for: date, calendar: calendar)
            workoutBins[bin] += 1
            durationBins[bin] += completion.durationMs / 1_000
        }
        if monthWorkouts.isEmpty {
            for session in monthSessions {
                guard let millis = ISOTime.parse(session.completedAt) else { continue }
                let date = Date(epochMillis: millis)
                let bin = Self.weekBin(for: date, calendar: calendar)
                workoutBins[bin] += 1
                durationBins[bin] += session.durationSeconds ?? 0
            }
        }
        weeklyWorkoutCounts = workoutBins
        weeklyDurationSeconds = durationBins

        let monthHistory = TrainingHistory(
            sessions: monthSessions,
            coverage: history.coverage,
            coverageStart: history.coverageStart
        )
        let preciseVolume = Volume.historyVolume(
            monthHistory,
            TrainingWorkflow.trainingIndex(),
            DEFAULT_POLICY,
            from: interval.start.timeIntervalSince1970 * 1_000,
            to: now.timeIntervalSince1970 * 1_000,
            inclusiveStart: true
        ).mapValues(\.effective)
        let preciseTotal = preciseVolume.values.reduce(0, +)
        let volume = preciseTotal > 0
            ? preciseVolume
            : Self.exerciseFallbackVolume(monthWorkouts)
        let maximum = volume.values.max() ?? 0

        let ordered = volume
            .filter { $0.value > 0 }
            .sorted {
                $0.value == $1.value
                    ? $0.key.label < $1.key.label
                    : $0.value > $1.value
            }
        trainedMuscles = ordered.map(\.key)
        leadingMuscles = Array(ordered.prefix(4)).map { ($0.key, $0.value) }
        muscleWeights = Dictionary(uniqueKeysWithValues: ordered.map { entry in
            let normalized = maximum > 0 ? entry.value / maximum : 0
            return (entry.key, 0.20 + 0.80 * sqrt(normalized))
        })
    }

    private static func weekBin(for date: Date, calendar: Calendar) -> Int {
        SummaryAnalytics.weekBin(for: date, calendar: calendar)
    }

    private static func exerciseFallbackVolume(_ workouts: [Workout]) -> [MuscleId: Double] {
        var volume: [MuscleId: Double] = [:]
        for workout in workouts {
            guard let completion = workout.completion else { continue }
            let exerciseIds = completion.completedExerciseIds.isEmpty
                ? workout.exerciseIds
                : completion.completedExerciseIds
            for exerciseId in exerciseIds {
                guard let exercise = ExerciseCatalogue.byId[exerciseId] else { continue }
                for (index, muscle) in exercise.muscles.enumerated() {
                    let involvement = exercise.muscleWeights.indices.contains(index)
                        ? exercise.muscleWeights[index]
                        : 1
                    volume[muscle, default: 0] += involvement
                }
            }
        }
        return volume
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
                .summaryArrival(2)

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
                .summaryArrival(3)
            }

            SummaryCardLink(page: .summaryMuscles(month: month), zoomID: "summary-muscles", cornerRadius: Theme.Radius.xl3) {
                MuscleHeatmapCard(snapshot: snapshot)
            }
            .summaryArrival(4)
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

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
    }

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

    @Environment(\.summaryArrived) private var arrived
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

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous)
    }

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

                    intensityKey
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

    private var intensityKey: some View {
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
            .font(Theme.sans(7, weight: .black))
            .kerning(0.65)
            .foregroundStyle(Theme.mutedForeground)
        }
        .accessibilityLabel("Muscle intensity from low to high")
    }

    private static func setValue(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

struct BodyHeatmapPair: View {
    let muscles: [MuscleId]
    let weights: [MuscleId: Double]
    var height: CGFloat = 238

    @Environment(\.summaryArrived) private var arrived

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
                ? "No muscles trained this month"
                : "Muscles trained this month: " + muscles.map(\.label).joined(separator: ", ")
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
