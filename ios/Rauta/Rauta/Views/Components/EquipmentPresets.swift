import SwiftUI

private struct StarterPreset: Identifiable {
    var id: String
    var name: String
    var equipment: [String]
}

private let starterPresets: [StarterPreset] = [
    StarterPreset(
        id: "starter-home",
        name: "Home kit",
        equipment: ["body weight", "band", "resistance band", "dumbbell", "kettlebell"]
    ),
    StarterPreset(
        id: "starter-gym",
        name: "Full gym",
        equipment: ExerciseCatalogue.equipmentOptions
    ),
]

private func sameSelection(_ left: [String], _ right: [String]) -> Bool {
    left.count == right.count && left.allSatisfy(right.contains)
}

/// The saved presets, applied to whichever equipment selection asked for them:
/// the browse filter by default, or the profile's own equipment when it passes
/// `value` and `onChange`. One preset list, two places to spend it.
struct EquipmentPresets: View {
    var value: [String]?
    var onChange: (([String]) -> Void)?

    @ObservedObject private var store = AppStore.shared

    private var selectedEquipment: [String] { value ?? store.filters.selectedEquipment }

    private func apply(_ equipment: [String]) {
        Haptics.trigger(.selection)
        let next = sameSelection(selectedEquipment, equipment) ? [] : equipment
        if let onChange { onChange(next) } else { store.filters.setEquipment(next) }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(starterPresets) { preset in
                        PresetChip(
                            name: preset.name,
                            selected: sameSelection(selectedEquipment, preset.equipment)
                        ) { apply(preset.equipment) }
                    }
                    ForEach(store.filters.equipmentPresets) { preset in
                        PresetChip(
                            name: preset.name,
                            selected: sameSelection(selectedEquipment, preset.equipment),
                            onDelete: {
                                Haptics.trigger(.warning)
                                store.filters.deleteEquipmentPreset(preset.id)
                            }
                        ) { apply(preset.equipment) }
                    }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.vertical, 4)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .center)
            }
            // RautaScreen gives the page's primary vertical scroller a top
            // content margin so rows can pass behind the floating header.
            // Content margins propagate to descendant ScrollViews, including
            // this horizontal dock, which otherwise pushes its chips below
            // the surface. The dock owns its vertical placement, so explicitly
            // clear the inherited margin here.
            .contentMargins(.top, 0, for: .scrollContent)
        }
        .frame(height: 44)
    }
}

private struct PresetChip: View {
    var name: String
    var selected: Bool
    var onDelete: (() -> Void)?
    var action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: action) {
                Text(name)
                    .font(Theme.sans(13, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 13)
                    .foregroundStyle(selected ? Theme.primaryForeground : Theme.secondaryForeground)
            }
            .buttonStyle(
                .glassControl(
                    selected ? .tinted(Theme.primary) : .clear,
                    .capsule(height: 34)
                )
            )
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.primary)
                }
                .buttonStyle(
                    .glassControl(.clear, .circle(diameter: 34))
                )
                .accessibilityLabel("Delete \(name) preset")
            }
        }
    }
}

/// The field the "+" tool opens into, so the round button stretches into the box
/// rather than being swapped for one.
struct EquipmentPresetEditor: View {
    /// What the preset should hold; the browse filter when nothing is passed.
    var equipment: [String]?
    var onSaved: () -> Void

    @ObservedObject private var store = AppStore.shared
    @State private var name = ""
    @FocusState private var focused: Bool

    private var selection: [String] { equipment ?? store.filters.selectedEquipment }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selection.isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField("Preset name", text: $name)
                .focused($focused)
                .font(Theme.sans(16))
                .foregroundStyle(Theme.foreground)
                .tint(Theme.primary)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .glassSurface(
                    .regular,
                    in: Capsule(),
                    border: focused ? Theme.ring : Theme.Glassware.edge
                )
                .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
                .accessibilityLabel("Preset name")

            AppControlButton(
                systemImage: "checkmark",
                label: "Save preset",
                isDisabled: !canSave,
                action: save
            )
        }
        .onAppear { focused = true }
    }

    private func save() {
        guard canSave else { return }
        store.filters.saveEquipmentPreset(name, equipment: selection)
        Haptics.trigger(.success)
        onSaved()
    }
}

/// The bottom tool opens this inline field and moves focus into it. The field
/// claims the same command role as the magnifier that opened it.
struct ExerciseSearchField: View {
    @Binding var value: String
    var onClose: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.leading, 16)
                    .padding(.trailing, 10)

                TextField("Search exercises", text: $value)
                    .focused($focused)
                    .font(Theme.sans(16))
                    .foregroundStyle(Theme.foreground)
                    .tint(Theme.primary)
                    .submitLabel(.search)
                    .onSubmit { focused = false }
                    .accessibilityLabel("Search exercises")

                if !value.isEmpty {
                    Button {
                        Haptics.trigger(.selection)
                        value = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .accessibilityLabel("Clear search")
                }
            }
            .frame(height: 42)
            .glassSurface(
                .regular,
                in: Capsule(),
                border: focused ? Theme.ring : Theme.Glassware.edge
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 8)

            AppControlButton(systemImage: "xmark", label: "Close search", action: onClose)
        }
        .onAppear { focused = true }
    }
}
