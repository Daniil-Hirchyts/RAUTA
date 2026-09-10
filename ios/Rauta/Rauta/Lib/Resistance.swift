import Foundation

/// What "80" means when someone logs it.
///
/// The engine already refuses a naked number: a `ResistanceValue` says whether a
/// kilogram is load or assistance, and whether it is carried by one implement or
/// by the pair. This file is the application side of that contract — it decides,
/// from the exercise the person is actually performing, which of those shapes
/// the set editor should collect and in what steps.
typealias ResistanceMode = ResistanceKind

/// Station and basis a set is measured against, plus the steps its load moves
/// in. The engine compares kilograms only within one station and basis, so every
/// logged set has to carry both.
struct StationContext: Hashable {
    var stationId: String
    var basis: LoadBasis
    var grid: LoadGrid
}

/// One station a set can be logged against, as the editor offers it.
struct StationChoice: Identifiable, Hashable {
    /// The saved configuration, or nil for the equipment default.
    var id: String?
    var label: String
    var context: StationContext
}

enum Resistance {
    /// How the load on a piece of equipment is held and what it moves in.
    ///
    /// `per_implement` is the "each" case: a 30 kg dumbbell in each hand is not
    /// 60 kg, and the engine must never add the two.
    struct EquipmentLoad {
        var basis: LoadBasis
        var incrementKg: Double
    }

    static let equipmentLoad: [String: EquipmentLoad] = [
        "dumbbell": EquipmentLoad(basis: .perImplement, incrementKg: 2),
        "kettlebell": EquipmentLoad(basis: .perImplement, incrementKg: 4),
        "barbell": EquipmentLoad(basis: .total, incrementKg: 2.5),
        "olympic barbell": EquipmentLoad(basis: .total, incrementKg: 2.5),
        "ez barbell": EquipmentLoad(basis: .total, incrementKg: 2.5),
        "trap bar": EquipmentLoad(basis: .total, incrementKg: 2.5),
        "smith machine": EquipmentLoad(basis: .total, incrementKg: 2.5),
        "cable": EquipmentLoad(basis: .total, incrementKg: 5),
        "leverage machine": EquipmentLoad(basis: .total, incrementKg: 5),
        "sled machine": EquipmentLoad(basis: .total, incrementKg: 5),
        "upper body ergometer": EquipmentLoad(basis: .total, incrementKg: 5),
        "assisted": EquipmentLoad(basis: .total, incrementKg: 5),
        "weighted": EquipmentLoad(basis: .total, incrementKg: 1.25),
        "medicine ball": EquipmentLoad(basis: .total, incrementKg: 1),
        "stability ball": EquipmentLoad(basis: .total, incrementKg: 1),
        "bosu ball": EquipmentLoad(basis: .total, incrementKg: 1),
        "wheel roller": EquipmentLoad(basis: .total, incrementKg: 1),
        "hammer": EquipmentLoad(basis: .total, incrementKg: 1),
        "tire": EquipmentLoad(basis: .total, incrementKg: 5),
        "rope": EquipmentLoad(basis: .total, incrementKg: 1),
    ]

    /// Equipment that carries no load of its own. Weight added to one of these —
    /// a belt on a dip, a vest on a push-up — is added load, not the station.
    static let addedLoadStation = "added load"
    /// Assistance is its own measurement, never a negative load.
    static let assistanceStation = "assistance"
    private static let defaultLoad = EquipmentLoad(basis: .total, incrementKg: 2.5)

    /// The equipment a load step can be described for: what someone has, that
    /// carries a weight worth describing. A mat has no next weight up.
    static func loadConfigurableEquipment(_ gymEquipment: [String]) -> [String] {
        ExerciseCatalogue.equipmentOptions.filter {
            gymEquipment.contains($0) && equipmentLoad[$0] != nil
        }
    }

    static func equipmentLoadSpec(_ equipment: String) -> EquipmentLoad? {
        equipmentLoad[equipment]
    }

    // MARK: Metadata

    private static let metadataCache = MetadataCache()

    private final class MetadataCache: @unchecked Sendable {
        private var storage: [String: ExerciseMetadata] = [:]
        private let lock = NSLock()

        func metadata(for exercise: ExerciseSummary) -> ExerciseMetadata {
            lock.lock()
            if let cached = storage[exercise.id] {
                lock.unlock()
                return cached
            }
            lock.unlock()
            let resolved = CuratedExercises.resolveMetadata(exercise)
            lock.lock()
            storage[exercise.id] = resolved
            lock.unlock()
            return resolved
        }
    }

    /// Catalogue metadata for one exercise, without paying for the whole engine
    /// index: the set editor only ever asks about the handful of exercises in
    /// the workout on screen.
    static func metadata(for exercise: ExerciseSummary) -> ExerciseMetadata {
        metadataCache.metadata(for: exercise)
    }

    static func metadata(forExerciseId exerciseId: String) -> ExerciseMetadata? {
        ExerciseCatalogue.byId[exerciseId].map(metadata(for:))
    }

    /// The resistance shapes this exercise can be logged in, best first.
    ///
    /// Most exercises have exactly one. The ones that have more are the
    /// body-weight movements: a pull-up is body weight, a weighted pull-up is
    /// added load, and an assisted pull-up is assistance — three different
    /// measurements of the same movement that progression must never confuse.
    static func modes(for exercise: ExerciseSummary) -> [ResistanceMode] {
        switch metadata(for: exercise).tracking {
        case .assistance: return [.assistance, .bodyweight, .externalLoad]
        case .bodyweight: return [.bodyweight, .externalLoad, .assistance]
        case .bandResistance: return [.bandResistance]
        case .externalLoad: return [.externalLoad]
        default:
            // repetition_only, timed, distance and unknown carry no load claim
            // of their own, so the equipment decides.
            if exercise.equipment == "band" || exercise.equipment == "resistance band" {
                return [.bandResistance]
            }
            return equipmentLoad[exercise.equipment] != nil
                ? [.externalLoad]
                : [.bodyweight, .externalLoad]
        }
    }

    /// Whether a mode carries kilograms at all. Body weight and bands do not:
    /// the app has no scale for a band, and inventing one would be fabricated
    /// evidence.
    static func isMeasuredInKg(_ mode: ResistanceMode) -> Bool {
        mode == .externalLoad || mode == .assistance
    }

    /// The measurement a saved station describes. A configuration written before
    /// assisted machines could be described is an external-load station.
    static func configurationMode(_ configuration: PersistedLoadConfiguration) -> ResistanceMode {
        configuration.effectiveMode == .assistance ? .assistance : .externalLoad
    }

    /// Where the kilograms are measured and in what steps.
    ///
    /// A saved load configuration wins whenever the person has made one: it
    /// names a real station in a real gym. Without one, the equipment family
    /// stands in — stable for the same exercise across sessions, and never
    /// shared between a dumbbell press and a machine press.
    static func loadContext(
        for exercise: ExerciseSummary,
        mode: ResistanceMode,
        configuration: PersistedLoadConfiguration? = nil,
        equipmentIncrementKg: Double? = nil
    ) -> StationContext {
        let equipment = equipmentLoad[exercise.equipment] ?? defaultLoad
        let incrementKg: Double = {
            if let value = equipmentIncrementKg, value.isFinite, value > 0 { return value }
            return equipment.incrementKg
        }()

        // A station describes one measurement. An assisted machine and a loaded
        // bar can both be saved against the same exercise, and neither may stand
        // in for the other.
        if let configuration, configurationMode(configuration) == mode {
            return StationContext(
                stationId: configuration.stationId,
                basis: configuration.basis,
                grid: configuration.grid
            )
        }

        if mode == .assistance {
            let assisted = exercise.equipment == "assisted"
            return StationContext(
                stationId: assisted ? exercise.equipment : assistanceStation,
                basis: .total,
                grid: LoadGrid(
                    incrementKg: assisted ? incrementKg : (equipmentLoad["assisted"]?.incrementKg ?? 5),
                    minimumKg: 0
                )
            )
        }

        return StationContext(
            stationId: equipmentLoad[exercise.equipment] != nil ? exercise.equipment : addedLoadStation,
            basis: equipment.basis,
            grid: LoadGrid(incrementKg: incrementKg, minimumKg: 0)
        )
    }

    /// The lightest load this station has: where a dial that has nothing to go
    /// on starts once somebody asks it for a number.
    static func firstLoad(_ grid: LoadGrid) -> Double {
        if let loads = grid.availableLoadsKg {
            return loads.filter(\.isFinite).min() ?? 0
        }
        return Swift.max(0, grid.minimumKg ?? 0)
    }

    /// One step up or down the loads the station actually offers.
    static func stepLoad(_ kg: Double, _ direction: Int, _ grid: LoadGrid) -> Double {
        let delta: Double = grid.availableLoadsKg != nil
            ? Double(direction) * 0.001
            : Double(direction) * (grid.incrementKg ?? 2.5)
        let snapped = Progression.roundLoad(
            Swift.max(0, kg + delta),
            grid,
            direction == 1 ? .up : .down
        )
        return Swift.max(0, snapped ?? kg)
    }

    static func makeResistance(
        _ mode: ResistanceMode,
        _ kg: Double,
        _ context: StationContext
    ) -> ResistanceValue {
        guard mode == .externalLoad || mode == .assistance else {
            return ResistanceValue(type: mode)
        }
        return ResistanceValue(type: mode, kg: kg, basis: context.basis, stationId: context.stationId)
    }

    /// Kilograms as a gym writes them: 80, 82.5, 1.25 — never 82.50.
    static func formatKg(_ kg: Double) -> String {
        let rounded = (kg * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%g", rounded)
    }

    static func modeLabel(_ mode: ResistanceMode) -> String {
        switch mode {
        case .externalLoad: return "Load"
        case .assistance: return "Assist"
        case .bodyweight: return "Body weight"
        case .bandResistance: return "Band"
        case .unknown: return "Unrecorded"
        }
    }

    /// The one-line reading of a performed set's resistance. "each" is
    /// load-bearing wording, not decoration: it is the difference between two
    /// 30 kg dumbbells and a 30 kg bar.
    static func format(_ resistance: ResistanceValue) -> String {
        if resistance.type == .externalLoad || resistance.type == .assistance {
            let value = "\(formatKg(resistance.kg ?? 0)) kg"
            if resistance.type == .assistance { return "\(value) assist" }
            return resistance.basis == .perImplement ? "\(value) each" : value
        }
        if resistance.type == .bodyweight { return "Body weight" }
        if resistance.type == .bandResistance { return "Band" }
        return "—"
    }

    /// Sides worth offering. Paired limbs stay `both` — the engine counts three
    /// sets each side as three records — so only a genuinely one-sided movement
    /// needs the choice.
    static func sideOptions(for exercise: ExerciseSummary) -> [SetSide] {
        metadata(for: exercise).laterality == .unilateral ? [.both, .left, .right] : [.both]
    }

    /// Whether a station this app minted belongs to a piece of equipment. Ids
    /// from a backup, or written by hand, name themselves.
    private static func isDerivedStationId(_ stationId: String, _ defaultStationId: String) -> Bool {
        for separator in ["#", "-"] {
            let prefix = defaultStationId + separator
            if stationId.hasPrefix(prefix) {
                return stationId.count > prefix.count
            }
        }
        return false
    }

    /// What to call a station on screen.
    ///
    /// A number, not an identity. Kilograms are compared by `stationId`, which
    /// is minted once and never reused; what a person reads is simply which of
    /// their stations this is, counted in the order they described them.
    static func stationLabel(
        _ stationId: String,
        _ defaultStationId: String,
        ordinal: Int? = nil
    ) -> String {
        if stationId == defaultStationId { return Wording.titleCase(defaultStationId) }
        if !isDerivedStationId(stationId, defaultStationId) { return Wording.titleCase(stationId) }
        guard let ordinal else {
            // A station nothing describes any more: sets logged at it are still
            // its own, and must never read as one of the stations that exist.
            return "Earlier \(defaultStationId)"
        }
        return "\(Wording.titleCase(defaultStationId)) \(ordinal)"
    }

    /// A station identity that will never be handed out twice.
    static func newStationId(_ defaultStationId: String) -> String {
        let unique = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12)
        return "\(defaultStationId)#\(unique)"
    }

    /// The stations saved for one exercise in one measurement, plus the
    /// equipment default they sit above. The default is always offered and
    /// always first.
    static func stationChoices(
        for exercise: ExerciseSummary,
        mode: ResistanceMode,
        settings: PersistedTrainingSettings,
        equipmentIncrementKg: Double? = nil
    ) -> [StationChoice] {
        let fallback = loadContext(
            for: exercise, mode: mode, configuration: nil, equipmentIncrementKg: equipmentIncrementKg
        )
        var choices: [StationChoice] = [
            StationChoice(id: nil, label: Wording.titleCase(fallback.stationId), context: fallback)
        ]

        for configuration in settings.loadConfigurations {
            guard configuration.exerciseId == exercise.id,
                  configurationMode(configuration) == mode
            else { continue }
            let context = loadContext(
                for: exercise,
                mode: mode,
                configuration: configuration,
                equipmentIncrementKg: equipmentIncrementKg
            )
            // A configuration on the default station is that station described
            // properly — a stack that starts at 5 rather than 0 — not a second.
            if configuration.stationId == fallback.stationId {
                choices[0] = StationChoice(
                    id: configuration.id, label: choices[0].label, context: context
                )
            } else {
                choices.append(StationChoice(
                    id: configuration.id,
                    // Counted from where it sits in the list, so the names read
                    // 1, 2, 3 however many have come and gone.
                    label: stationLabel(
                        configuration.stationId,
                        fallback.stationId,
                        ordinal: choices.count + 1
                    ),
                    context: context
                ))
            }
        }
        return choices
    }

    /// Where a set that has already been logged was measured. A station nobody
    /// describes any more still steps: it falls back to the equipment's own grid
    /// so an old set can be read and corrected.
    static func recordedLoadContext(
        for exercise: ExerciseSummary,
        resistance: ResistanceValue,
        settings: PersistedTrainingSettings,
        equipmentIncrementKg: Double? = nil
    ) -> StationContext {
        let fallback = loadContext(
            for: exercise,
            mode: resistance.type,
            configuration: nil,
            equipmentIncrementKg: equipmentIncrementKg
        )
        guard resistance.kg != nil,
              let stationId = resistance.stationId,
              let basis = resistance.basis
        else { return fallback }

        let configuration = settings.loadConfigurations.first {
            $0.exerciseId == exercise.id
                && configurationMode($0) == resistance.type
                && $0.stationId == stationId
                && $0.basis == basis
        }
        return StationContext(
            stationId: stationId,
            basis: basis,
            grid: configuration?.grid ?? fallback.grid
        )
    }

    /// Whether two measurements can be compared: the same machine, held the same
    /// way. Kilograms mean nothing across this line.
    static func sameLoadContext(
        _ leftStation: String?, _ leftBasis: LoadBasis?,
        _ rightStation: String?, _ rightBasis: LoadBasis?
    ) -> Bool {
        leftStation == rightStation && leftBasis == rightBasis
    }

    /// The load to open the editor on, or nil when there is nothing honest to
    /// offer. A kilogram is only carried over when it was measured at the same
    /// station, in the same basis, and is a load this station actually offers.
    static func carryOverLoad(
        _ resistance: ResistanceValue?,
        _ mode: ResistanceMode,
        _ context: StationContext
    ) -> Double? {
        guard let resistance, resistance.type == mode, let kg = resistance.kg else { return nil }
        guard sameLoadContext(resistance.stationId, resistance.basis, context.stationId, context.basis)
        else { return nil }
        guard let rounded = Progression.roundLoad(kg, context.grid), abs(rounded - kg) < 1e-6
        else { return nil }
        return kg
    }

    /// The station this exercise is currently trained at, or nil for the
    /// equipment default. A selection that no longer names a saved station in
    /// this measurement is not an error and not a guess.
    static func activeConfiguration(
        _ exerciseId: String,
        _ mode: ResistanceMode,
        _ settings: PersistedTrainingSettings
    ) -> PersistedLoadConfiguration? {
        let selectedId = settings.activeLoadConfigurations?[exerciseId]
        let forExercise = settings.loadConfigurations.filter {
            $0.exerciseId == exerciseId && configurationMode($0) == mode
        }
        if let selectedId, let selected = forExercise.first(where: { $0.id == selectedId }) {
            return selected
        }
        return forExercise.count == 1 ? forExercise[0] : nil
    }

    /// The station and grid a set of this exercise is measured against now.
    static func resolveLoadContext(
        for exercise: ExerciseSummary,
        mode: ResistanceMode,
        settings: PersistedTrainingSettings,
        equipmentIncrementKg: Double? = nil
    ) -> StationContext {
        loadContext(
            for: exercise,
            mode: mode,
            configuration: activeConfiguration(exercise.id, mode, settings),
            equipmentIncrementKg: equipmentIncrementKg
        )
    }
}
