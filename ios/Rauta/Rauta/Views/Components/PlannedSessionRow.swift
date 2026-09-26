import SwiftUI

/// One session RAUTA built: when, what, and how long. They arrive one after
/// another, the way RAUTA hands them over.
struct PlannedSessionRow: View {
    let session: PlannedSessionView
    let index: Int
    /// Rows already on screen before appear as they are; only new ones arrive.
    var animated = true
    /// A chevron for a row that opens its workout.
    var opens = false
    @State private var shown = false

    private var detail: String {
        let exercises = Wording.countLabel(session.exerciseIds.count, "exercise")
        return session.minutes > 0 ? "\(session.minutes) min · \(exercises)" : exercises
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(CalendarDate.weekdayShort(session.date).uppercased())
                    .font(Theme.sans(10, weight: .black))
                    .kerning(1.2)
                    .foregroundStyle(Theme.primary)
                Text(CalendarDate.dayOfMonth(session.date))
                    .font(Theme.sans(22, weight: .black))
                    .foregroundStyle(Theme.foreground)
            }
            .frame(width: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(Theme.sans(17, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Text(detail)
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if opens {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .padding(14)
        .background { GradientCard(radius: Theme.Radius.xl, accent: Theme.primary, strength: 0.8) }
        .opacity(shown || !animated ? 1 : 0)
        .offset(y: shown || !animated ? 0 : 14)
        .onAppear {
            guard animated else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8).delay(0.25 + Double(index) * 0.08)) {
                shown = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}
