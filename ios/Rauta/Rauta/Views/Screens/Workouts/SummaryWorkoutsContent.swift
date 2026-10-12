import SwiftUI

/// The Summary tab. It reads the stores itself rather than being handed its
/// figures, so the host redrawing for a tab change does not rebuild the
/// training history: with nothing passed in, SwiftUI has no reason to run this
/// body again until a store it reads changes.
struct SummaryWorkoutsContent: View {
    /// The timeline's past, from the screen that already keeps it split.
    let past: [Workout]
    var onStart: (Workout) -> Void = { _ in }
    var onResume: () -> Void = {}
    var onOpenWorkout: (String) -> Void = { _ in }
    private let trainingRecords = TrainingRecordsStore.shared
    private let workouts = WorkoutsStore.shared
    private let activeWorkout = ActiveWorkoutStore.shared

    var body: some View {
        let completedWorkouts = past.filter { $0.completion != nil }
        let month = MonthlySummarySnapshot(
            workouts: completedWorkouts,
            history: trainingRecords.trainingHistory()
        )
        let next = NextWorkout.resolve(
            workouts: workouts.workouts,
            records: trainingRecords.data,
            activeWorkoutId: activeWorkout.session?.workoutId,
            today: CalendarDate.today
        )
        ScrollView {
            LazyVStack(spacing: 12) {
                // What to train next comes first; history follows.
                TodayCard(next: next, onStart: onStart, onResume: onResume, onOpen: onOpenWorkout)
                    .appZoomSource("summary-today", cornerRadius: Theme.Radius.xl3)
                    .pageArrival(0)

                CoachingTiles(hasPlan: trainingRecords.data.activeProgramId != nil)
                    .pageArrival(1)

                ProfileIdentityCard()
                    .pageArrival(2)

                SummaryCardLink(page: .summaryStreak, zoomID: "summary-streak", cornerRadius: Theme.Radius.xl3) {
                    StreakStrip(workouts: completedWorkouts, week: next.week)
                }
                .pageArrival(3)

                MonthlySummaryDashboard(snapshot: month)

                ProfileRecordsSection()
                    .padding(.top, 12)
                    .pageArrival(7)
            }
            .padding(.horizontal, 12)
            // Enough to scroll the last card clear of the tab bar, no more.
            .padding(.bottom, 120)
        }
        .pageScroll()
        .scrollIndicators(.hidden)
        .arrivesAsPage()
    }
}

private struct StreakStrip: View {
    let workouts: [Workout]
    /// This week against its plan, so a planned rest day reads as rest and
    /// the week's progress is counted in planned sessions, not just days.
    let week: WeekProgress

    var body: some View {
        // Built once per render; it walks every completed workout.
        let streak = StreakBuilder.build(workouts)
        let planned = week.planned > 0
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    // With a plan, the week is measured against it: rest days
                    // are part of it, so a gap in the streak is not a miss.
                    Text(planned ? "THIS WEEK" : "CURRENT STREAK")
                        .font(Theme.sans(9, weight: .black))
                        .kerning(1.45)
                        .foregroundStyle(Theme.lime)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(planned ? "\(week.completedPlanned)/\(week.planned)" : "\(streak.currentStreak)")
                            .font(Theme.readout(30))
                            .foregroundStyle(Theme.foreground)
                        Text(planned ? "planned" : (streak.currentStreak == 1 ? "day" : "days"))
                            .font(Theme.sans(15, weight: .bold))
                            .foregroundStyle(Theme.foreground.opacity(0.78))
                    }
                }
                .padding(.leading, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(planned
                    ? "This week: \(week.completedPlanned) of \(week.planned) planned sessions done"
                    : "Current streak: \(streak.currentStreak) \(streak.currentStreak == 1 ? "day" : "days")")

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    if planned {
                        streakMetric(value: streak.currentStreak, label: "STREAK", color: Theme.lime)
                    } else {
                        streakMetric(value: streak.weekWorkouts, label: "THIS WEEK", color: Theme.lime)
                    }

                    Rectangle()
                        .fill(Theme.foreground.opacity(0.10))
                        .frame(width: 1, height: 30)
                        .accessibilityHidden(true)

                    streakMetric(value: streak.longestStreak, label: "BEST", color: Theme.gold)
                }
                .padding(.trailing, 4)
            }

            HStack(spacing: 4) {
                ForEach(Array(streak.week.enumerated()), id: \.element.id) { index, day in
                    let status = week.days.first { $0.date == day.date }?.status
                    VStack(spacing: 6) {
                        Group {
                            if status == .rest && day.workouts == 0 {
                                // A planned rest day: rest, not an unlit flame.
                                Image(systemName: "moon.zzz")
                                    .font(.system(size: day.isToday ? 20 : 16, weight: .semibold))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .frame(width: day.isToday ? 38.4 : 30.4, height: day.isToday ? 48 : 38)
                            } else {
                                Flame(lit: day.workouts > 0, alive: day.isToday || day.workouts > 0, phase: Double(index) * 1.7)
                                    .frame(width: day.isToday ? 38.4 : 30.4, height: day.isToday ? 48 : 38)
                            }
                        }
                        .frame(height: 48, alignment: .bottom).opacity(day.isFuture ? 0.6 : 1)
                        Text(CalendarDate.weekdayShort(day.date)).font(Theme.sans(10, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .foregroundStyle(day.isToday ? Theme.primaryForeground : Theme.mutedForeground)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(day.isToday ? Theme.primary : .clear, in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(CalendarDate.format(day.date, "EEEE")): \(dayLabel(day, status))")
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

    private func dayLabel(_ day: StreakDay, _ status: WeekProgress.DayStatus?) -> String {
        if day.workouts > 0 { return "trained" }
        switch status {
        case .rest?: return "planned rest day"
        case .planned?: return "workout planned"
        case .missed?: return "planned workout missed"
        default: return day.isFuture ? "still to come" : "no workout"
        }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.capitalized): \(value)")
    }
}
