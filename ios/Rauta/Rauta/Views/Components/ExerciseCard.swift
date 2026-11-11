import SwiftUI

private let longPressSeconds: Double = 0.5

struct ExerciseCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// One exercise in the results grid.
///
/// While selecting, a long press still opens the detail page: choosing what to
/// add and looking something up are different intents, and the tap is already
/// spoken for.
struct ExerciseCard: View {
    var exercise: ExerciseSummary
    var index: Int = 0
    var selectMode: Bool = false
    var selected: Bool = false
    /// How many are chosen so far: each one picked sounds a step higher.
    var selectionCount: Int = 0
    /// The id its detail page grows out of; unique to the grid it sits in.
    var zoomSourceID: String?
    var onOpenDetail: (ExerciseSummary) -> Void
    var onToggleSelect: (String) -> Void

    var body: some View {
        Group {
            if selectMode {
                cardButton
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: longPressSeconds)
                            .onEnded { _ in
                                Haptics.trigger(.light)
                                onOpenDetail(exercise)
                            }
                    )
            } else {
                cardButton
            }
        }
        .modifier(OptionalZoomSource(id: zoomSourceID, cornerRadius: Theme.Metrics.cardRadius))
        .overlay(alignment: .topTrailing) {
            AnimatedCheck(checked: selected)
                .opacity(selectMode ? 1 : 0)
                .scaleEffect(selectMode ? 1 : 0.75)
                .animation(Theme.Motion.smoothOut, value: selectMode)
                .padding(20)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(
            selectMode ? "Select \(exercise.name)" : "View \(exercise.name) details"
        )
        .accessibilityAddTraits(selectMode && selected ? [.isSelected] : [])
        // The long press that opens details while selecting has no
        // VoiceOver equivalent of its own.
        .accessibilityActions {
            if selectMode {
                Button("View details") { onOpenDetail(exercise) }
            }
        }
    }

    private var cardButton: some View {
        Button {
            if selectMode {
                Haptics.trigger(.selection, sound: selected ? .drop(selectionCount - 1) : .pick(selectionCount + 1))
                onToggleSelect(exercise.id)
            } else {
                Haptics.trigger(.light)
                onOpenDetail(exercise)
            }
        } label: {
            VStack(spacing: 0) {
                // Let a neutral square own layout instead of the animated
                // UIImageView's intrinsic dimensions. React's `aspect-square`
                // media block is always exactly the card width; allowing the
                // UIKit image view to participate in sizing can make a grid
                // row much taller than that contract.
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ExerciseMediaView(exerciseId: exercise.id, animated: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                // Fixed height, not content-driven, so every card is identical
                // regardless of grid row or one- versus two-line names.
                Text(exercise.name.capitalized)
                    .font(Theme.sans(16, weight: .semibold))
                    .kerning(-0.16)
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 72)
                    .padding(.horizontal, 14)
            }
            .frame(maxWidth: .infinity)
            .background { GradientCard(radius: Theme.Metrics.cardRadius, accent: Theme.primary, strength: 0.55) }
            .clipShape(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(
                        selectMode && selected ? Theme.primary.opacity(0.75) : .clear,
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
            .contentShape(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
            )
        }
        .buttonStyle(ExerciseCardButtonStyle())
    }
}

struct EquipmentCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The app's one equipment picker. It answers two different questions — which
/// equipment to filter this browse by, and which equipment you actually have —
/// from the same list, the same pictures and the same tap.
struct EquipmentGrid: View {
    var options: [String] = ExerciseCatalogue.equipmentOptions
    var selected: [String]
    var onToggle: (String) -> Void
    var label: (String) -> String = { Wording.titleCase($0) }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(options, id: \.self) { equipment in
                let checked = selected.contains(equipment)
                Button {
                    Haptics.trigger(.selection, sound: checked ? .drop(selected.count - 1) : .pick(selected.count + 1))
                    onToggle(equipment)
                } label: {
                    // Built like an exercise card: the artwork and its name
                    // sit on one card, with nothing laid between them.
                    VStack(spacing: 0) {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                EquipmentImageView(equipment: equipment)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }

                        Text(label(equipment))
                            .font(Theme.sans(16, weight: .semibold))
                            .kerning(-0.16)
                            .foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(height: 72)
                            .padding(.horizontal, 14)
                    }
                    .frame(maxWidth: .infinity)
                    .background { GradientCard(radius: Theme.Metrics.cardRadius, accent: Theme.primary, strength: checked ? 1 : 0.55) }
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                            .strokeBorder(
                                checked ? Theme.primary.opacity(0.75) : .clear, lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
                    .overlay(alignment: .topTrailing) {
                        AnimatedCheck(checked: checked)
                            .padding(20)
                            .allowsHitTesting(false)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
                }
                .buttonStyle(EquipmentCardButtonStyle())
                .accessibilityLabel(label(equipment))
                .accessibilityAddTraits(checked ? [.isSelected] : [])
            }
        }
    }
}
