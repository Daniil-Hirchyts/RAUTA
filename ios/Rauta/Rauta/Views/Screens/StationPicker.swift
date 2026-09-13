import SwiftUI

struct StationPicker: View {
    @ObservedObject private var store = AppStore.shared
    let exercise: ExerciseSummary
    let mode: ResistanceMode
    @Binding var context: StationContext?

    @State private var editor: StationEditorModel?
    @State private var issue: String?

    private var increment: Double? { store.filters.equipmentLoadIncrements[exercise.equipment] }
    private var choices: [StationChoice] {
        Resistance.stationChoices(
            for: exercise,
            mode: mode,
            settings: store.trainingRecords.data.settings,
            equipmentIncrementKg: increment
        )
    }
    private var active: StationChoice {
        choices.first { choice in
            guard let context else { return false }
            return Resistance.sameLoadContext(
                choice.context.stationId, choice.context.basis,
                context.stationId, context.basis
            )
        } ?? choices[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("WHERE")
                    .font(Theme.sans(9, weight: .black))
                    .foregroundStyle(Theme.mutedForeground)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                            SelectionChip(
                                title: choice.label,
                                selected: choice.id == active.id
                                    && choice.context.stationId == active.context.stationId
                            ) { choose(choice) }
                        }
                    }
                }
                HStack(spacing: 6) {
                    Button { edit(active) } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Theme.primary)
                            .frame(width: 34, height: 34)
                            .glassSurface(.clear, in: Circle(), interactive: true, border: Theme.Glassware.edge, legacyFill: Theme.card)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit station")
                    Button(action: add) {
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.primary)
                            .frame(width: 34, height: 34)
                            .glassSurface(.clear, in: Circle(), interactive: true, border: Theme.Glassware.edge, legacyFill: Theme.card)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add station")
                }
            }
            if let issue {
                Text(issue).font(Theme.sans(11)).foregroundStyle(Theme.destructive)
            }
        }
        .sheet(item: $editor) { model in
            StationEditorSheet(
                model: model,
                onSave: save,
                onDelete: model.configurationId == nil ? nil : { delete(model) }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func choose(_ choice: StationChoice) {
        do {
            try store.trainingRecords.selectLoadConfiguration(exercise.id, choice.id)
            context = choice.context
            issue = nil
            Haptics.trigger(.selection)
        } catch { capture(error) }
    }

    private func add() {
        let seed = choices[0].context
        let new = StationEditorModel(
            configurationId: nil,
            exerciseId: exercise.id,
            stationId: Resistance.newStationId(seed.stationId),
            title: "New station",
            mode: mode,
            basis: seed.basis,
            grid: seed.grid
        )
        editor = new
    }

    private func edit(_ choice: StationChoice) {
        editor = StationEditorModel(
            configurationId: choice.id,
            exerciseId: exercise.id,
            stationId: choice.context.stationId,
            title: choice.label,
            mode: mode,
            basis: choice.context.basis,
            grid: choice.context.grid
        )
    }

    private func save(_ model: StationEditorModel, _ grid: LoadGrid) {
        do {
            let id = try store.trainingRecords.saveLoadConfiguration(
                id: model.configurationId,
                exerciseId: model.exerciseId,
                stationId: model.stationId,
                mode: model.mode == .assistance ? .assistance : .externalLoad,
                basis: model.basis,
                grid: grid
            )
            try store.trainingRecords.selectLoadConfiguration(exercise.id, id)
            context = StationContext(stationId: model.stationId, basis: model.basis, grid: grid)
            editor = nil
            issue = nil
            Haptics.trigger(.success)
        } catch { capture(error) }
    }

    private func delete(_ model: StationEditorModel) {
        guard let id = model.configurationId else { return }
        do {
            try store.trainingRecords.removeLoadConfiguration(id)
            context = choices.first?.context
            editor = nil
            issue = nil
        } catch { capture(error) }
    }

    private func capture(_ error: Error) {
        issue = (error as? TrainingPersistenceError)?.message ?? error.localizedDescription
        Haptics.trigger(.warning)
    }
}

struct StationEditorModel: Identifiable {
    var configurationId: String?
    var exerciseId: String
    var stationId: String
    var title: String
    var mode: ResistanceMode
    var basis: LoadBasis
    var grid: LoadGrid
    var id: String { configurationId ?? stationId }
}

private struct StationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: StationEditorModel
    let onSave: (StationEditorModel, LoadGrid) -> Void
    let onDelete: (() -> Void)?

    @State private var facet = 0
    @State private var increment: Double
    @State private var minimum: Double
    @State private var loads: [Double]
    @State private var nextLoad: Double

    init(
        model: StationEditorModel,
        onSave: @escaping (StationEditorModel, LoadGrid) -> Void,
        onDelete: (() -> Void)?
    ) {
        self.model = model
        self.onSave = onSave
        self.onDelete = onDelete
        let existing = model.grid.availableLoadsKg ?? []
        _facet = State(initialValue: existing.isEmpty ? 0 : 1)
        _increment = State(initialValue: model.grid.incrementKg ?? 2.5)
        _minimum = State(initialValue: model.grid.minimumKg ?? 0)
        _loads = State(initialValue: existing)
        _nextLoad = State(initialValue: existing.last.map { $0 + 2.5 } ?? 20)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Grid type", selection: $facet) {
                        Text("Even steps").tag(0)
                        Text("Fixed loads").tag(1)
                    }
                    .pickerStyle(.segmented)
                    if facet == 0 {
                        AppStepper(
                            label: "Load step",
                            display: Resistance.formatKg(increment),
                            unit: "kg",
                            canDecrement: increment > 0.25
                        ) { increment = min(20, max(0.25, increment + Double($0) * 0.25)) }
                        AppStepper(
                            label: "Lightest load",
                            display: Resistance.formatKg(minimum),
                            unit: "kg",
                            canDecrement: minimum > 0
                        ) { minimum = min(300, max(0, minimum + Double($0) * 0.5)) }
                    } else {
                        HStack(spacing: 8) {
                            AppStepper(
                                label: "Next load",
                                display: Resistance.formatKg(nextLoad),
                                unit: "kg",
                                canDecrement: nextLoad > 0
                            ) { nextLoad = min(300, max(0, nextLoad + Double($0) * 0.5)) }
                            AppButton("Add", variant: .secondary) {
                                if !loads.contains(nextLoad), loads.count < 60 {
                                    loads.append(nextLoad)
                                    loads.sort()
                                }
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 7)], spacing: 7) {
                            ForEach(loads, id: \.self) { load in
                                Button {
                                    loads.removeAll { $0 == load }
                                } label: {
                                    Text("\(Resistance.formatKg(load)) kg  ×")
                                        .font(Theme.sans(12, weight: .semibold))
                                        .foregroundStyle(Theme.foreground)
                                        .padding(8)
                                        .glassSurface(.clear, in: Capsule(), interactive: true, border: Theme.Glassware.edge, legacyFill: Theme.card)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(Resistance.formatKg(load)) kilograms")
                            }
                        }
                    }
                    if let onDelete {
                        AppButton("Delete station", variant: .destructive, expands: true) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(model.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(facet == 1 && loads.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        let grid = facet == 0
            ? LoadGrid(incrementKg: increment, minimumKg: minimum)
            : LoadGrid(availableLoadsKg: loads.sorted())
        onSave(model, grid)
        dismiss()
    }
}
