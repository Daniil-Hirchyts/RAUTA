import SwiftUI

/// The second equipment question: not what you lift, but what has to be there
/// to lift it — a bar to hang from, a bench to lie on. Body-weight exercises
/// need these too, so a plan only uses them when you say you have them.
/// Drawn like the equipment above it; renders live beside the equipment's.
struct FixturePicker: View {
    private let store = AppStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ALSO AVAILABLE")
                .font(Theme.sans(12, weight: .bold))
                .kerning(1.9)
                .foregroundStyle(Theme.mutedForeground)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)

            EquipmentGrid(
                options: TrainingEngineAdapter.selectableFixtures,
                selected: store.filters.effectiveFixtures,
                onToggle: store.filters.toggleGymFixture,
                label: TrainingEngineAdapter.fixtureLabel
            )
        }
    }
}
