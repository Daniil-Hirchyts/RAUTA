import SwiftUI

struct ExerciseDetailScreen: View {
    @ObservedObject private var store = AppStore.shared
    let exerciseId: String

    var body: some View {
        if let exercise = ExerciseCatalogue.byId[exerciseId] {
            RautaScreen(
                title: exercise.name.capitalized,
                backLabel: "Back",
                onBack: store.navigation.pop,
                titleMultiline: true,
                right: {
                    LikeButton(
                        liked: store.favorites.isFavorite(exercise.id),
                        label: store.favorites.isFavorite(exercise.id)
                            ? "Remove \(exercise.name) from favorites"
                            : "Add \(exercise.name) to favorites",
                        size: 40,
                        iconSize: 17
                    ) { store.favorites.toggleFavorite(exercise.id) }
                    .frame(width: 44, height: 44)
                }
            ) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ExerciseMediaView(exerciseId: exercise.id, animated: true)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
                        if !exercise.instructions.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, instruction in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(index + 1)")
                                            .font(Theme.sans(16, weight: .semibold))
                                            .foregroundStyle(Theme.primary)
                                            .frame(width: 22)
                                        Text(instruction)
                                            .font(Theme.sans(16))
                                            .foregroundStyle(Theme.mutedForeground)
                                            .lineSpacing(3)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Metrics.contentInset)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
        } else {
            Color.clear.onAppear(perform: store.navigation.pop)
        }
    }
}

struct EquipmentPresetScreen: View {
    @ObservedObject private var store = AppStore.shared
    @State private var name = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !store.filters.selectedEquipment.isEmpty
    }

    var body: some View {
        RautaScreen(
            title: "Save preset",
            backLabel: "Back to equipment",
            onBack: store.navigation.pop
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Save the current \(store.filters.selectedEquipment.count)-item equipment selection.")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.mutedForeground)
                    AppTextField(placeholder: "Preset name", text: $name, onSubmit: save)
                    FlowLayout(items: store.filters.selectedEquipment)
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        } controls: {
            AppButton("Save preset", size: .cta, isDisabled: !canSave, expands: true, action: save)
        }
    }

    private func save() {
        guard canSave else { return }
        store.filters.saveEquipmentPreset(name)
        Haptics.trigger(.success)
        store.navigation.pop()
    }
}

private struct FlowLayout: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(Wording.titleCase(item))
                    .font(Theme.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.border))
            }
        }
    }
}
