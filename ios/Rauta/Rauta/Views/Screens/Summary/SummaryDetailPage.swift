import SwiftUI

/// The frame every page behind a Summary card shares: its title, the period
/// it covers under it, the content scrolling beneath, and its controls
/// floating in a glass band at the foot — in reach of a thumb, and in view
/// however far down the page has been scrolled.
struct SummaryDetailPage<Content: View, Controls: View>: View {
    var title: String
    /// "October", "September 2025", "All time".
    var period: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        RautaScreen(
            title: title,
            subtitle: period,
            backLabel: "Back to summary",
            onBack: AppStore.shared.navigation.pop
        ) {
            ScrollView {
                VStack(spacing: 12) {
                    content()
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, 24)
            }
            .pageScroll()
        } controls: {
            controls()
        }
    }
}

extension SummaryDetailPage where Controls == EmptyView {
    init(title: String, period: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, period: period, content: content, controls: { EmptyView() })
    }
}

/// The month, stepped from the foot of the page: back as far as anything was
/// trained, on as far as this month. What sits between the steps is the
/// page's own — the measure on Activity, the way back to this month elsewhere.
struct SummaryPeriodBar<Middle: View>: View {
    @Binding var month: String
    /// The earliest month there is anything to show for.
    var earliest: String
    @ViewBuilder var middle: () -> Middle

    private var current: String { SummaryAnalytics.monthKey() }

    var body: some View {
        HStack(spacing: 10) {
            AppControlButton(
                systemImage: "chevron.left",
                label: "Previous month",
                isDisabled: month <= earliest
            ) { step(-1) }

            middle()
                .frame(maxWidth: .infinity)

            AppControlButton(
                systemImage: "chevron.right",
                label: "Next month",
                isDisabled: month >= current
            ) { step(1) }
        }
    }

    private func step(_ months: Int) {
        Haptics.trigger(.selection)
        withAnimation(Theme.Motion.settle) { month = SummaryAnalytics.shiftMonth(month, by: months) }
    }
}

extension SummaryPeriodBar where Middle == SummaryThisMonthButton {
    /// The month stepped, with a way straight back to this month between the
    /// steps.
    init(month: Binding<String>, earliest: String) {
        self.init(month: month, earliest: earliest) { SummaryThisMonthButton(month: month) }
    }
}

/// Back to this month in one tap, from however far back the steps went.
struct SummaryThisMonthButton: View {
    @Binding var month: String

    var body: some View {
        let current = SummaryAnalytics.monthKey()
        AppButton(
            month == current ? "This month" : "Back to this month",
            variant: .secondary,
            size: .cta,
            isDisabled: month == current,
            expands: true
        ) {
            Haptics.trigger(.selection)
            withAnimation(Theme.Motion.settle) { month = current }
        }
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
                .minimumScaleFactor(0.8)
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

/// A month the person can swipe through, as well as step with the bar.
struct MonthSwipe: ViewModifier {
    @Binding var month: String
    var earliest: String

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > 2 * abs(value.translation.height),
                          abs(value.translation.width) > 60
                    else { return }
                    let next = SummaryAnalytics.shiftMonth(month, by: value.translation.width < 0 ? 1 : -1)
                    guard next >= earliest, next <= SummaryAnalytics.monthKey() else { return }
                    Haptics.trigger(.selection)
                    withAnimation(Theme.Motion.settle) { month = next }
                }
        )
    }
}

extension View {
    func monthSwipe(_ month: Binding<String>, earliest: String) -> some View {
        modifier(MonthSwipe(month: month, earliest: earliest))
    }
}
