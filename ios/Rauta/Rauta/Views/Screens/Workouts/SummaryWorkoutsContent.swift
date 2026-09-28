import SwiftUI

/// The Summary tab. It reads the stores itself rather than being handed its
/// figures, so the host redrawing for a tab change does not rebuild the
/// training history: with nothing passed in, SwiftUI has no reason to run this
/// body again until a store it reads changes.
struct SummaryWorkoutsContent: View {
    private let workouts = WorkoutsStore.shared
    private let trainingRecords = TrainingRecordsStore.shared
    private let activeWorkout = ActiveWorkoutStore.shared
    /// Off while Summary is away, on as it comes back: the cards arrive
    /// against it once per visit.
    @State private var arrived = false

    var body: some View {
        let completedWorkouts = WorkoutTimeline(
            workouts: workouts.workouts,
            records: trainingRecords.data,
            activeWorkoutId: activeWorkout.session?.workoutId
        ).past.filter { $0.completion != nil }
        let month = MonthlySummarySnapshot(
            workouts: completedWorkouts,
            history: trainingRecords.trainingHistory()
        )
        ScrollView {
            LazyVStack(spacing: 12) {
                ProfileIdentityCard()
                    .summaryArrival(0)

                SummaryCardLink(page: .summaryStreak, zoomID: "summary-streak", cornerRadius: Theme.Radius.xl3) {
                    StreakStrip(workouts: completedWorkouts)
                }
                .summaryArrival(1)

                MonthlySummaryDashboard(snapshot: month)

                ProfileRecordsSection()
                    .padding(.top, 12)
                    .summaryArrival(5)
            }
            .padding(.horizontal, 12)
            // Enough to scroll the last card clear of the tab bar, no more.
            .padding(.bottom, 120)
        }
        .pageScroll()
        .scrollIndicators(.hidden)
        .environment(\.summaryArrived, arrived)
        .onAppear {
            arrived = false
            Task { @MainActor in arrived = true }
        }
        .onDisappear { arrived = false }
    }
}

private struct StreakStrip: View {
    let workouts: [Workout]
    private var streak: Streak { StreakBuilder.build(workouts) }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT STREAK")
                        .font(Theme.sans(9, weight: .black))
                        .kerning(1.45)
                        .foregroundStyle(Theme.lime)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(streak.currentStreak)")
                            .font(Theme.readout(30))
                            .foregroundStyle(Theme.foreground)
                        Text(streak.currentStreak == 1 ? "day" : "days")
                            .font(Theme.sans(15, weight: .bold))
                            .foregroundStyle(Theme.foreground.opacity(0.78))
                    }
                }
                .padding(.leading, 10)

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    streakMetric(value: streak.weekWorkouts, label: "THIS WEEK", color: Theme.lime)

                    Rectangle()
                        .fill(Theme.foreground.opacity(0.10))
                        .frame(width: 1, height: 30)

                    streakMetric(value: streak.longestStreak, label: "BEST", color: Theme.gold)
                }
                .padding(.trailing, 4)
            }

            HStack(spacing: 4) {
                ForEach(Array(streak.week.enumerated()), id: \.element.id) { index, day in
                    VStack(spacing: 6) {
                        Flame(lit: day.workouts > 0, alive: day.isToday || day.workouts > 0, phase: Double(index) * 1.7)
                            .frame(width: day.isToday ? 38.4 : 30.4, height: day.isToday ? 48 : 38)
                            .frame(height: 48, alignment: .bottom).opacity(day.isFuture ? 0.6 : 1)
                        Text(CalendarDate.weekdayShort(day.date)).font(Theme.sans(10, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .foregroundStyle(day.isToday ? Theme.primaryForeground : Theme.mutedForeground)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(day.isToday ? Theme.primary : .clear, in: Capsule())
                    }.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background { GradientCard(radius: Theme.Radius.xl3, accent: Theme.primary) }
        // A week of fixed-width columns: text grows with Dynamic Type up to
        // the point where the columns can still hold it.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func streakMetric(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(Theme.readout(15))
                .foregroundStyle(color)
            Text(label)
                .font(Theme.sans(7, weight: .black))
                .kerning(0.9)
                .foregroundStyle(Theme.mutedForeground)
        }
        .frame(minWidth: 42)
    }
}
