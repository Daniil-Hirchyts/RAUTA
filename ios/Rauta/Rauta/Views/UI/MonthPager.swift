import SwiftUI

/// A month, with a step back and a step on: from the first month anything was
/// trained up to this one, never into the future.
struct MonthPager: View {
    @Binding var month: String
    /// The earliest month there is anything to show for.
    var earliest: String

    private var current: String { SummaryAnalytics.monthKey() }
    private var canGoBack: Bool { month > earliest }
    private var canGoOn: Bool { month < current }

    var body: some View {
        HStack(spacing: 12) {
            step("chevron.left", label: "Previous month", enabled: canGoBack, by: -1)
            Text(SummaryAnalytics.monthTitle(month))
                .font(Theme.sans(18, weight: .bold))
                .foregroundStyle(Theme.foreground)
                .contentTransition(.opacity)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: month)
            step("chevron.right", label: "Next month", enabled: canGoOn, by: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func step(_ symbol: String, label: String, enabled: Bool, by months: Int) -> some View {
        Button {
            Haptics.trigger(.selection)
            month = SummaryAnalytics.shiftMonth(month, by: months)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? Theme.primary : Theme.mutedForeground.opacity(0.4))
                .frame(width: 44, height: 44)
                .glassSurface(.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// A figure and what it counts, as the Summary pages head their sections.
struct SummaryStat: View {
    let value: String
    let label: String
    var accent: Color = Theme.foreground

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(Theme.readout(22))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(Theme.sans(9, weight: .black))
                .kerning(1.1)
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A small caps heading over a Summary page section.
struct SummarySectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.sans(11, weight: .black))
            .kerning(1.5)
            .foregroundStyle(Theme.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
