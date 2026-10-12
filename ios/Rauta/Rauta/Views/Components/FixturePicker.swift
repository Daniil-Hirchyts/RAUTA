import SwiftUI

/// The second equipment question: not what you lift, but what has to be there
/// to lift it — a bar to hang from, a bench to lie on. Body-weight exercises
/// need these too, so a plan only uses them when you say you have them.
struct FixturePicker: View {
    private let store = AppStore.shared

    private static let symbols: [String: String] = [
        "pull-up bar": "figure.play",
        "dip station": "figure.strengthtraining.functional",
        "bench": "bed.double",
        "rack": "square.split.bottomrightquarter",
        "low bar": "arrow.down.to.line",
        "suspension trainer": "point.topleft.down.to.point.bottomright.curvepath",
    ]

    private static let details: [String: String] = [
        "pull-up bar": "Pull-ups, hanging raises, band-assisted chin-ups",
        "dip station": "Dips and knee raises",
        "bench": "Presses, step-ups, supported rows",
        "rack": "Squats and presses from a barbell rack",
        "low bar": "Inverted rows — a smith bar, a rack bar or a sturdy railing",
        "suspension trainer": "TRX-style straps anchored overhead",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Also available")
                    .font(Theme.sans(18, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .accessibilityAddTraits(.isHeader)
                Text("Things to hang from or lie on. Plans only include exercises that need them when they're ticked.")
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(TrainingEngineAdapter.selectableFixtures, id: \.self) { fixture in
                    let on = store.filters.effectiveFixtures.contains(fixture)
                    Button {
                        Haptics.trigger(.selection)
                        store.filters.toggleGymFixture(fixture)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: Self.symbols[fixture] ?? "square")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                                .frame(width: 32, height: 32)
                                .background(Theme.primary.opacity(0.14), in: Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(TrainingEngineAdapter.fixtureLabel(fixture))
                                    .font(Theme.sans(15, weight: .semibold))
                                    .foregroundStyle(Theme.foreground)
                                Text(Self.details[fixture] ?? "")
                                    .font(Theme.sans(12, weight: .medium))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            AnimatedCheck(checked: on)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) {
                            if fixture != TrainingEngineAdapter.selectableFixtures.last {
                                Rectangle().fill(Theme.border).frame(height: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                }
            }
            .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: 0.55) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous))
        }
    }
}
