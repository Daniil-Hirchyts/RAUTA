import SwiftUI

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
