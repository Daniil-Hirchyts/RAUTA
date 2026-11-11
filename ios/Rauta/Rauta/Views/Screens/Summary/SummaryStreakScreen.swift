import SwiftUI

/// Behind the streak card: every trained day of a month on a calendar, runs of
/// days joined into one mark.
///
/// The calendar comes first — it is what the month steps through — with how
/// the month went inside its card. The streak itself, which the card already
/// shows large, is a slim row underneath rather than a second hero.
struct SummaryStreakScreen: View {
    private let store = AppStore.shared
    @State private var month = SummaryAnalytics.monthKey()

    private var completed: [Workout] { store.workouts.workouts.filter { $0.completion != nil } }

    var body: some View {
        let workouts = completed
        let streak = StreakBuilder.build(workouts)
        let days = SummaryAnalytics.trainedDays(workouts)
        let earliest = days.min().map { String($0.prefix(7)) } ?? SummaryAnalytics.monthKey()
        SummaryDetailPage(title: "Streak", period: SummaryAnalytics.monthTitle(month)) {
            if days.isEmpty {
                EmptyStatePlaceholder(
                    symbol: "flame",
                    title: "No streak yet",
                    message: "Finish a workout to start one."
                )
                .padding(.vertical, 24)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(summaryLine(days))
                        .font(Theme.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                    MonthCalendarGrid(month: month, trained: days)
                }
                .padding(16)
                .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.lime, strength: 0.5) }
                .monthSwipe($month, earliest: earliest)
                .id(month)
                .transition(.opacity)

                HStack(spacing: 12) {
                    SummaryStat(value: "\(streak.currentStreak)", label: "Current streak", accent: Theme.lime)
                    SummaryStat(value: "\(streak.longestStreak)", label: "Best streak", accent: Theme.gold)
                    SummaryStat(value: "\(streak.weekWorkouts)", label: "This week")
                }
                .padding(16)
                .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.lime, strength: 0.35) }
            }
        } controls: {
            if !days.isEmpty {
                SummaryPeriodBar(month: $month, earliest: earliest)
            }
        }
        .animation(Theme.Motion.settle, value: month)
    }

    private func summaryLine(_ days: Set<String>) -> String {
        let interval = SummaryAnalytics.monthInterval(month)
        let first = CalendarDate.toISO(interval.start)
        let last = CalendarDate.toISO(interval.end.addingTimeInterval(-1))
        let trained = days.filter { $0 >= first && $0 <= last }.count
        let isCurrent = month == SummaryAnalytics.monthKey()
        let total = isCurrent
            ? Calendar.current.component(.day, from: Date())
            : Calendar.current.range(of: .day, in: .month, for: interval.start)?.count ?? 30
        return "Trained on \(trained) of \(total) days"
    }
}

/// A month as a calendar, weeks starting on the phone's own first day, trained
/// days lit. Consecutive trained days in a week are drawn as one joined mark,
/// so a run reads as a run.
struct MonthCalendarGrid: View {
    let month: String
    let trained: Set<String>

    private var calendar: Calendar { Calendar.current }

    /// The weekday letters, in the order the calendar's weeks run.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month's days, padded to whole weeks with nil.
    private var weeks: [[String?]] {
        let interval = SummaryAnalytics.monthInterval(month, calendar: calendar)
        let weekday = calendar.component(.weekday, from: interval.start)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [String?] = Array(repeating: nil, count: lead)
        var day = interval.start
        while day < interval.end {
            cells.append(CalendarDate.toISO(day))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? interval.end
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(Theme.sans(10, weight: .black))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(weeks.indices, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        cell(weeks[row][column], left: column > 0 ? weeks[row][column - 1] : nil,
                             right: column < 6 ? weeks[row][column + 1] : nil)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(SummaryAnalytics.monthTitle(month)): trained on \(trainedInMonth) days")
    }

    private var trainedInMonth: Int {
        weeks.joined().compactMap { $0 }.filter { trained.contains($0) }.count
    }

    private func cell(_ day: String?, left: String?, right: String?) -> some View {
        let lit = day.map { trained.contains($0) } ?? false
        let joinsLeft = lit && (left.map { trained.contains($0) } ?? false)
        let joinsRight = lit && (right.map { trained.contains($0) } ?? false)
        let today = day == CalendarDate.today
        let future = day.map { $0 > CalendarDate.today } ?? false
        return ZStack {
            if lit {
                // A run: the mark reaches across to the trained day beside it.
                HStack(spacing: 0) {
                    Rectangle().fill(joinsLeft ? Theme.lime.opacity(0.16) : .clear)
                    Rectangle().fill(joinsRight ? Theme.lime.opacity(0.16) : .clear)
                }
                .frame(height: 30)
                Circle()
                    .fill(Theme.lime.opacity(0.2))
                    .overlay(Circle().strokeBorder(Theme.lime.opacity(0.75), lineWidth: 1.2))
                    .frame(width: 32, height: 32)
            } else if today {
                Circle().strokeBorder(Theme.primary, lineWidth: 1.5).frame(width: 32, height: 32)
            }
            if let day {
                Text(CalendarDate.dayOfMonth(day))
                    .font(Theme.sans(13, weight: lit ? .black : .semibold))
                    .foregroundStyle(lit ? Theme.lime : (future ? Theme.mutedForeground.opacity(0.5) : Theme.foreground))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
    }
}
