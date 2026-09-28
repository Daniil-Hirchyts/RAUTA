import SwiftUI

extension EnvironmentValues {
    /// Whether Summary has finished arriving since it last came into view.
    /// Off while it is away, on as it appears: the cards arrive against it,
    /// once per visit rather than every time one scrolls back into view.
    @Entry var summaryArrived: Bool = true
}

/// A Summary card arriving: rising a little into place as it fades in, one
/// card after another.
struct SummaryArrival: ViewModifier {
    let order: Int
    @Environment(\.summaryArrived) private var arrived
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived || reduceMotion ? 0 : 14)
            .animation(
                arrived
                    ? .spring(response: 0.5, dampingFraction: 0.86).delay(Double(order) * 0.06)
                    : nil,
                value: arrived
            )
    }
}

extension View {
    func summaryArrival(_ order: Int) -> some View {
        modifier(SummaryArrival(order: order))
    }
}

/// A Summary card being pressed: it gives a little, like any card that opens.
struct SummaryCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A card on Summary that opens the page behind it, growing into it.
struct SummaryCardLink<Label: View>: View {
    let page: AppPage
    let zoomID: String
    var cornerRadius: CGFloat = 30
    var accessibilityHint = "Opens the details"
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            Haptics.trigger(.selection)
            AppStore.shared.navigation.push(page, from: zoomID)
        } label: {
            label()
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(SummaryCardButtonStyle())
        .appZoomSource(zoomID, cornerRadius: cornerRadius)
        .accessibilityHint(accessibilityHint)
    }
}
