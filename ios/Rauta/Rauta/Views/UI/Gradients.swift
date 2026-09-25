import SwiftUI

// The app's lighting, in two pieces: the page behind everything, and the cards
// on it. Both take the warm light the workout player and the celebration use —
// accent and oxblood falling in from a corner — so a page and the player feel
// like one place.

/// A page's backdrop: warm light falling in from the top right, a low ember in
/// the opposite corner, and the grain over both.
struct AppPageBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            LinearGradient(
                stops: [
                    .init(color: Theme.primary.opacity(0.22), location: 0),
                    .init(color: Theme.oxblood.opacity(0.24), location: 0.32),
                    .init(color: .clear, location: 0.7),
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            RadialGradient(
                colors: [Theme.ember.opacity(0.14), .clear],
                center: UnitPoint(x: -0.05, y: 1.02),
                startRadius: 0,
                endRadius: 420
            )
        }
    }
}

/// A card's fill: the card colour lit from its top-leading corner in the
/// card's own accent, a touch of oxblood settling in the far corner, and a
/// hairline that catches the light along the lit edges.
struct GradientCard: View {
    var radius: CGFloat
    var accent: Color = Theme.primary
    /// How much of the accent the card takes. Records and headline cards carry
    /// more; rows in a long list, less.
    var strength: Double = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(Theme.card)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [accent.opacity(0.18 * strength), accent.opacity(0.04 * strength), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                shape.fill(
                    RadialGradient(
                        colors: [Theme.oxblood.opacity(0.16 * strength), .clear],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [accent.opacity(0.34 * strength), Theme.border.opacity(0.25), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
    }
}
