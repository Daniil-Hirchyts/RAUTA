import Foundation
import Observation
import Combine

struct EquipmentPreset: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var equipment: [String]
}

@MainActor
@Observable
final class FiltersStore {
    static let shared = FiltersStore()

    static let storageKey = "gym-lib-filters"
    static let version = 1

    private(set) var selectedMuscles: [MuscleId] = []
    private(set) var selectedEquipment: [String] = []
    /// The equipment you actually have, as opposed to `selectedEquipment`, which
    /// filters one browse and is cleared whenever a new one starts. Kept in this
    /// store so there is one equipment vocabulary, one preset list, and one
    /// place either selection is sanitised.
    private(set) var gymEquipment: [String] = []
    /// The fixtures the person said they have — a pull-up bar, a bench —
    /// separate from the equipment they lift with. Nil until they first
    /// choose; until then the fixtures their equipment used to imply stand in
    /// (see ``effectiveFixtures``).
    private(set) var gymFixtures: [String]?
    private(set) var equipmentPresets: [EquipmentPreset] = []
    /// Physical load step offered by the user's actual equipment. The basis
    /// (total vs each) remains catalogue-defined; this only describes the rack,
    /// stack or plates the person has access to.
    private(set) var equipmentLoadIncrements: [String: Double] = [:]

    let changed = PassthroughSubject<Void, Never>()

    private static let equipmentSet = Set(ExerciseCatalogue.equipmentOptions)

    private init() { load() }

    static func validEquipment(_ value: String) -> Bool { equipmentSet.contains(value) }
    static func validFixture(_ value: String) -> Bool {
        TrainingEngineAdapter.selectableFixtures.contains(value)
    }

    /// The fixtures planning uses: the person's own choice, or, for a profile
    /// saved before fixtures could be chosen, what its equipment implied then.
    var effectiveFixtures: [String] {
        gymFixtures ?? TrainingEngineAdapter.legacyFixtures(for: gymEquipment)
    }

    struct PersistedFilters: Equatable {
        var selectedMuscles: [MuscleId]
        var selectedEquipment: [String]
        var gymEquipment: [String]
        var gymFixtures: [String]? = nil
        var equipmentPresets: [EquipmentPreset]
        var equipmentLoadIncrements: [String: Double]
    }

    static func sanitize(_ value: JSONValue?) -> PersistedFilters {
        let presets = (value?["equipmentPresets"]?.arrayValue ?? []).compactMap {
            item -> EquipmentPreset? in
            guard let object = item.objectValue else { return nil }
            let id = object["id"]?.stringValue ?? ""
            let name = (object["name"]?.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let equipment = Sanitize.uniqueStrings(object["equipment"], isValid: validEquipment)
            guard !id.isEmpty, !name.isEmpty, !equipment.isEmpty else { return nil }
            return EquipmentPreset(id: id, name: name, equipment: equipment)
        }

        var increments: [String: Double] = [:]
        for (equipment, entry) in value?["equipmentLoadIncrements"]?.objectValue ?? [:] {
            guard validEquipment(equipment),
                  let number = entry.numberValue, number.isFinite,
                  number >= 0.25, number <= 50
            else { continue }
            increments[equipment] = (number * 100).rounded() / 100
        }

        return PersistedFilters(
            // Browse/workflow selections are transient UI state. Older backups
            // may contain them, but a restore must still open with a clean flow.
            selectedMuscles: [],
            selectedEquipment: [],
            gymEquipment: Sanitize.uniqueStrings(value?["gymEquipment"], isValid: validEquipment),
            // Absent means never chosen, which is not the same as none.
            gymFixtures: value?["gymFixtures"]?.arrayValue == nil
                ? nil
                : Sanitize.uniqueStrings(value?["gymFixtures"], isValid: validFixture),
            equipmentPresets: presets,
            equipmentLoadIncrements: increments
        )
    }

    private func load() {
        guard let envelope = Storage.readEnvelope(Self.storageKey) else { return }
        apply(Self.sanitize(envelope.state), persisting: false)
    }

    func apply(_ state: PersistedFilters, persisting: Bool = true) {
        selectedMuscles = state.selectedMuscles
        selectedEquipment = state.selectedEquipment
        gymEquipment = state.gymEquipment
        gymFixtures = state.gymFixtures
        equipmentPresets = state.equipmentPresets
        equipmentLoadIncrements = state.equipmentLoadIncrements
        if persisting { persist() }
        changed.send()
    }

    func persist() {
        Storage.writeEnvelope(Self.storageKey, state: snapshotTree, version: Self.version)
    }

    /// Everything `apply` restores, as it is now.
    var snapshot: PersistedFilters {
        PersistedFilters(
            selectedMuscles: selectedMuscles,
            selectedEquipment: selectedEquipment,
            gymEquipment: gymEquipment,
            gymFixtures: gymFixtures,
            equipmentPresets: equipmentPresets,
            equipmentLoadIncrements: equipmentLoadIncrements
        )
    }

    var snapshotTree: JSONValue {
        .object([
            // Keep the portable schema compatible while explicitly serializing
            // transient selections as empty.
            "selectedMuscles": .array([]),
            "selectedEquipment": .array([]),
            "gymEquipment": .array(gymEquipment.map(JSONValue.string)),
            "gymFixtures": gymFixtures.map { .array($0.map(JSONValue.string)) } ?? .null,
            "equipmentPresets": .array(equipmentPresets.map { $0.jsonTree }),
            "equipmentLoadIncrements": .object(
                equipmentLoadIncrements.mapValues { JSONValue.number($0) }
            ),
        ])
    }

    private func mutatePersistent(_ body: () -> Void) {
        body()
        persist()
        changed.send()
    }

    private func mutateTransient(_ body: () -> Void) {
        body()
        changed.send()
    }

    // MARK: Mutations

    func toggleMuscle(_ muscle: MuscleId) {
        mutateTransient { selectedMuscles = Sanitize.toggle(selectedMuscles, muscle) }
    }

    func toggleEquipment(_ equipment: String) {
        guard Self.validEquipment(equipment) else { return }
        mutateTransient { selectedEquipment = Sanitize.toggle(selectedEquipment, equipment) }
    }

    func toggleGymEquipment(_ equipment: String) {
        guard Self.validEquipment(equipment) else { return }
        mutatePersistent { gymEquipment = Sanitize.toggle(gymEquipment, equipment) }
    }

    func setMuscles(_ muscles: [MuscleId]) {
        mutateTransient {
            var seen = Set<MuscleId>()
            selectedMuscles = muscles.filter { seen.insert($0).inserted }
        }
    }

    func setEquipment(_ equipment: [String]) {
        mutateTransient {
            var seen = Set<String>()
            selectedEquipment = equipment.filter {
                Self.validEquipment($0) && seen.insert($0).inserted
            }
        }
    }

    func setGymEquipment(_ equipment: [String]) {
        mutatePersistent {
            var seen = Set<String>()
            gymEquipment = equipment.filter {
                Self.validEquipment($0) && seen.insert($0).inserted
            }
        }
    }

    func toggleGymFixture(_ fixture: String) {
        guard Self.validFixture(fixture) else { return }
        let current = effectiveFixtures
        mutatePersistent {
            let next = Sanitize.toggle(current, fixture)
            gymFixtures = TrainingEngineAdapter.selectableFixtures.filter(next.contains)
        }
    }

    func setGymFixtures(_ fixtures: [String]) {
        mutatePersistent {
            gymFixtures = TrainingEngineAdapter.selectableFixtures.filter {
                fixtures.contains($0)
            }
        }
    }

    func setEquipmentLoadIncrement(_ equipment: String, _ incrementKg: Double) {
        guard Self.validEquipment(equipment), incrementKg.isFinite,
              incrementKg >= 0.25, incrementKg <= 50
        else { return }
        mutatePersistent { equipmentLoadIncrements[equipment] = (incrementKg * 100).rounded() / 100 }
    }

    func clearEquipmentLoadIncrement(_ equipment: String) {
        guard equipmentLoadIncrements[equipment] != nil else { return }
        mutatePersistent { equipmentLoadIncrements.removeValue(forKey: equipment) }
    }

    /// Saving takes an explicit selection so the same preset list can be filled
    /// from the browse filter or from the equipment the profile holds, rather
    /// than either surface growing a preset store of its own.
    func saveEquipmentPreset(_ name: String, equipment: [String]? = nil) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        let selection = (equipment ?? selectedEquipment).filter {
            Self.validEquipment($0) && seen.insert($0).inserted
        }
        guard !normalizedName.isEmpty, !selection.isEmpty else { return }

        mutatePersistent {
            if let index = equipmentPresets.firstIndex(where: {
                $0.name.lowercased() == normalizedName.lowercased()
            }) {
                equipmentPresets[index].equipment = selection
            } else {
                let random = String(UUID().uuidString.prefix(6)).lowercased()
                equipmentPresets.append(EquipmentPreset(
                    id: "\(Int(Date().timeIntervalSince1970 * 1000))-\(random)",
                    name: normalizedName,
                    equipment: selection
                ))
            }
        }
    }

    func deleteEquipmentPreset(_ id: String) {
        mutatePersistent { equipmentPresets.removeAll { $0.id == id } }
    }

    func reset() {
        mutateTransient {
            selectedMuscles = []
            selectedEquipment = []
        }
    }

    func clearAll() {
        apply(PersistedFilters(
            selectedMuscles: [],
            selectedEquipment: [],
            gymEquipment: [],
            gymFixtures: nil,
            equipmentPresets: [],
            equipmentLoadIncrements: [:]
        ))
    }
}

@MainActor
@Observable
final class FavoritesStore {
    static let shared = FavoritesStore()

    static let storageKey = "gym-lib-favorites"
    static let version = 1

    private(set) var favoriteIds: [String] = []
    let changed = PassthroughSubject<Void, Never>()

    private init() { load() }

    static func sanitize(_ value: JSONValue?) -> [String] {
        Sanitize.uniqueStrings(value?["favoriteIds"]) { ExerciseCatalogue.has($0) }
    }

    private func load() {
        guard let envelope = Storage.readEnvelope(Self.storageKey) else { return }
        favoriteIds = Self.sanitize(envelope.state)
    }

    func persist() {
        Storage.writeEnvelope(
            Self.storageKey,
            state: .object(["favoriteIds": .array(favoriteIds.map(JSONValue.string))]),
            version: Self.version
        )
    }

    func toggleFavorite(_ exerciseId: String) {
        guard ExerciseCatalogue.has(exerciseId) else { return }
        favoriteIds = Sanitize.toggle(favoriteIds, exerciseId)
        persist()
        changed.send()
    }

    func isFavorite(_ exerciseId: String) -> Bool { favoriteIds.contains(exerciseId) }

    func replaceAll(_ ids: [String]) {
        favoriteIds = ids
        persist()
        changed.send()
    }
}
