import Foundation

/// A plan the engine has built and nobody has kept yet.
///
/// Building and keeping are separate so a plan can be shown first and saved only
/// when somebody says so. Keeping goes through `TrainingPlan.commit(_:)`, the
/// same save the plan screens use.
struct PlanPreview: Identifiable {
    enum Kind: Equatable {
        /// A new program from chosen dates; keeping it archives the active one.
        case newPlan
        /// The rest of the active program's week, reshaped.
        case adjustWeek
    }

    let id = UUID().uuidString.lowercased()
    var kind: Kind
    var program: TrainingProgram
    var sessions: [PlannedSessionView]
    var issues: [PlanningIssue]
    var sourceProgramId: String?
    /// What the plan was built from. A plan kept after any of it changed would
    /// answer a question nobody is asking any more.
    var basis: PlanBasis

    /// Whether the state the plan was built from is still the state now.
    func isCurrent(now: String = ISOTime.now()) -> Bool {
        basis == PlanBasis.current(now: now, readiness: basis.readiness)
    }
}

enum PlanPreviewOutcome {
    case ready(PlanPreview)
    case blocked(PlanBlock)
}

/// Everything a plan request reads from the stores, compared whole.
///
/// Arrays that have not changed compare cheaply, and a deleted workout, a new
/// session, a changed profile or equipment list, or a new day all count as a
/// change. Readiness is carried because it is an input nobody else stores.
struct PlanBasis: Equatable {
    var day: String
    var activeProgramId: String?
    var programIds: [String]
    var sessionCount: Int
    var lastSessionId: String?
    var activeWorkoutId: String?
    var settings: PersistedTrainingSettings
    var workouts: [Workout]
    var profile: TrainingProfile
    var gymEquipment: [String]
    var equipmentLoadIncrements: [String: Double]
    var readiness: Readiness?

    static func current(now: String = ISOTime.now(), readiness: Readiness? = nil) -> PlanBasis {
        let data = TrainingRecordsStore.shared.data
        let filters = FiltersStore.shared
        return PlanBasis(
            day: ISOTime.localDay(now),
            activeProgramId: data.activeProgramId,
            programIds: data.programs.map(\.id),
            sessionCount: data.sessions.count,
            lastSessionId: data.sessions.last?.id,
            activeWorkoutId: data.activeWorkout?.id,
            settings: data.settings,
            workouts: WorkoutsStore.shared.workouts,
            profile: TrainingProfileStore.shared.profile,
            gymEquipment: filters.gymEquipment,
            equipmentLoadIncrements: filters.equipmentLoadIncrements,
            readiness: readiness
        )
    }
}
