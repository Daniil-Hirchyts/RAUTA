import SwiftUI

/// One session RAUTA built: when, what, and how long. They arrive one after
/// another, the way RAUTA hands them over.
struct PlannedSessionRow: View {
    let session: PlannedSessionView
    let index: Int
    @State private var shown = false

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
                Text("\(session.minutes) min · \(Wording.countLabel(session.exerciseIds.count, "exercise"))")
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background { GradientCard(radius: Theme.Radius.xl, accent: Theme.primary, strength: 0.8) }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 14)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8).delay(0.25 + Double(index) * 0.08)) {
                shown = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}
