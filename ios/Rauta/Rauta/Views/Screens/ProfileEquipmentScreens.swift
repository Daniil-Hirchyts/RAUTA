import SwiftUI

struct ProfileEquipmentScreen: View {
    @ObservedObject private var store = AppStore.shared
    @State private var presetEditorOpen = false

    private var subtitle: String? {
        let count = store.filters.gymEquipment.count
        return count > 0 ? Wording.countLabel(count, "item") : nil
    }

    private var loadEquipment: [String] {
        Resistance.loadConfigurableEquipment(store.filters.gymEquipment)
    }

    var body: some View {
        RautaScreen(
            title: "Available equipment",
            subtitle: subtitle,
            onBack: store.navigation.pop,
            right: { equipmentRautaMenu }
        ) {
            ZStack(alignment: .bottom) {
                ScrollView {
                    EquipmentGrid(
                        selected: store.filters.gymEquipment,
                        onToggle: store.filters.toggleGymEquipment
                    )
                    .padding(.horizontal, Theme.Metrics.contentInset)
                    .padding(.top, 20)
                    .padding(.bottom, 112)
                }

                EquipmentPresets(
                    value: store.filters.gymEquipment,
                    onChange: store.filters.setGymEquipment
                )
                .padding(.bottom, 10)
                .padding(.top, 28)
            }
        } controls: {
            if presetEditorOpen {
                HStack(spacing: 10) {
                    EquipmentPresetEditor(equipment: store.filters.gymEquipment) {
                        presetEditorOpen = false
                    }
                    AppControlButton(systemImage: "xmark", label: "Close preset editor") {
                        presetEditorOpen = false
                    }
                }
            } else {
                AppButton("Done", size: .cta, expands: true, action: store.navigation.pop)
            }
        }
    }

    private var equipmentRautaMenu: some View {
        AppMenuButton(label: "Equipment actions", arrowEdge: .top, compact: true) {
            if presetEditorOpen {
                Button {
                    presetEditorOpen = false
                } label: {
                    Label("Close preset editor", systemImage: "xmark")
                }
            } else {
                if !store.filters.gymEquipment.isEmpty {
                    Button {
                        Haptics.trigger(.selection)
                        store.filters.setGymEquipment([])
                    } label: {
                        Label("Clear selection", systemImage: "xmark")
                    }
                }

                Button {
                    store.navigation.push(.profileLoadSteps)
                } label: {
                    Label("Set load steps", systemImage: "scalemass")
                }
                .disabled(loadEquipment.isEmpty)

                Button {
                    presetEditorOpen = true
                } label: {
                    Label("Create equipment preset", systemImage: "plus")
                }
                .disabled(store.filters.gymEquipment.isEmpty)
            }
        }
    }
}

struct EquipmentLoadScreen: View {
    @Environment(\.appSafeAreaInsets) private var safeAreaInsets
    @ObservedObject private var store = AppStore.shared
    @State private var selectedEquipment = ""

    private var equipment: [String] {
        Resistance.loadConfigurableEquipment(store.filters.gymEquipment)
    }

    private var selected: String {
        equipment.contains(selectedEquipment) ? selectedEquipment : (equipment.first ?? "")
    }

    var body: some View {
        RautaScreen(
            title: "Load steps",
            subtitle: "The next weight your equipment actually offers",
            onBack: store.navigation.pop
        ) {
            Group {
                if selected.isEmpty {
                    Text("Nothing here to describe yet. Pick equipment that carries a weight and its steps show up here.")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.mutedForeground)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 256)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(Theme.Metrics.contentInset)
                } else {
                    VStack(spacing: 0) {
                        loadDeck
                            .padding(.top, 88 + safeAreaInsets.top)

                        Spacer(minLength: 12)

                        defaultControl
                            .frame(minHeight: 32)
                            .padding(.top, 8)

                        loadDial
                            .padding(.top, 4)
                            .padding(.bottom, 4)
                    }
                }
            }
            .onAppear { normalizeSelection() }
            .onChange(of: equipment) { _, _ in normalizeSelection() }
        } controls: {
            AppButton("Done", size: .cta, expands: true, action: store.navigation.pop)
        }
    }

    private var loadDeck: some View {
        CoverflowCarousel(
            label: "Equipment",
            slides: equipment.map {
                CoverflowSlide(
                    id: $0,
                    title: Wording.titleCase($0),
                    description: basisLabel($0)
                )
            },
            value: selected,
            minimumCardWidth: 170,
            maximumCardWidth: 220,
            widthFraction: 0.48,
            onChange: { item in
                selectedEquipment = item
            }
        ) { slide in
            ZStack {
                Theme.muted.opacity(0.4)
                EquipmentImageView(equipment: slide.id)
                    .padding(10)
            }
        }
    }

    private var defaultControl: some View {
        let item = selected
        let spec = Resistance.equipmentLoadSpec(item)
        let saved = store.filters.equipmentLoadIncrements[item]
        let label = Wording.titleCase(item).lowercased()

        return Group {
            if let spec, saved != nil {
                Button {
                    Haptics.trigger(.selection)
                    store.filters.clearEquipmentLoadIncrement(item)
                } label: {
                    Text("Use \(Resistance.formatKg(spec.incrementKg)) kg default")
                        .font(Theme.sans(12, weight: .bold))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text("Default for \(label)")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var loadDial: some View {
        let item = selected
        let fallback = Resistance.equipmentLoadSpec(item)?.incrementKg ?? 2.5
        let value = store.filters.equipmentLoadIncrements[item] ?? fallback

        return RotaryDial(
            value: value,
            range: NumericRange(min: 0.25, max: 20, step: 0.25),
            scale: (min: 0.25, max: 20),
            label: "\(Wording.titleCase(item)) load increment",
            unit: "kg step"
        ) { incrementKg in
            store.filters.setEquipmentLoadIncrement(item, incrementKg)
        }
        .padding(.horizontal, Theme.Metrics.contentInset)
    }

    private func basisLabel(_ item: String) -> String {
        Resistance.equipmentLoadSpec(item)?.basis == .perImplement
            ? "Logged per implement · the value is for each hand"
            : "Logged as total load"
    }

    private func normalizeSelection() {
        if !equipment.contains(selectedEquipment) {
            selectedEquipment = equipment.first ?? ""
        }
    }
}

struct MusclePrioritiesScreen: View {
    @ObservedObject private var store = AppStore.shared
    @State private var side: BodySide = .front

    private var priorities: [MusclePriority] {
        store.trainingProfile.profile.priorityMuscles
    }

    private var selected: [MuscleId] {
        priorities.map(\.muscleId)
    }

    private var weights: [MuscleId: Double] {
        Dictionary(uniqueKeysWithValues: priorities.map {
            ($0.muscleId, ProfileVocabulary.priorityPaintWeights[$0.level] ?? 1)
        })
    }

    private var subtitle: String {
        priorities.isEmpty
            ? "Tap a muscle to prioritise it"
            : "\(Wording.countLabel(priorities.count, "muscle")) · tap to change"
    }

    var body: some View {
        RautaScreen(
            title: "Priority muscles",
            subtitle: subtitle,
            onBack: store.navigation.pop
        ) {
            VStack(spacing: 0) {
                ZStack {
                    DotPattern(
                        color: Theme.mix(
                            Theme.mutedForeground,
                            Theme.primary,
                            min(Double(priorities.count) / 6, 1) * 0.75
                        ),
                        opacity: 0.36 + min(Double(priorities.count) / 6, 1) * 0.28
                    )
                    BodyMap(
                        selectedMuscles: selected,
                        muscleWeights: weights,
                        onToggle: store.trainingProfile.cycleMusclePriority,
                        onSideChange: { side = $0 },
                        showCornerCount: false,
                        showFlipButton: false,
                        side: side,
                        figureOffsetY: 48
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                PriorityScaleLegend()
                    .padding(.horizontal, 48)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, Theme.Metrics.contentInset)
            .padding(.top, 12)
            .padding(.bottom, 12)
        } controls: {
            HStack(spacing: 10) {
                if !priorities.isEmpty {
                    AppControlButton(systemImage: "xmark", label: "Clear priority muscles") {
                        Haptics.trigger(.selection)
                        store.trainingProfile.clearMusclePriorities()
                    }
                }

                AppControlButton(
                    systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    label: "Show \(side == .front ? "back" : "front")"
                ) {
                    Haptics.trigger(.selection)
                    side = side == .front ? .back : .front
                }

                AppButton("Done", size: .cta, expands: true, action: store.navigation.pop)
            }
        }
    }
}

private struct PriorityScaleLegend: View {
    private let resting = Color(hex: 0x3D322B)

    private var stops: [(label: String, weight: Double)] {
        [("Normal", 0)] + ProfileVocabulary.selectablePriorityLevels.reversed().map {
            (ProfileVocabulary.label(for: $0), ProfileVocabulary.priorityPaintWeights[$0] ?? 1)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            LinearGradient(
                colors: stops.map { Theme.mix(resting, Theme.primary, $0.weight) },
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 10)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1))

            HStack {
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    Text(stop.label.uppercased())
                        .font(Theme.sans(10, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.mutedForeground)
                    if index < stops.count - 1 { Spacer(minLength: 0) }
                }
            }
        }
        .frame(maxWidth: 256)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}
