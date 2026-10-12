import Foundation

/// One line about what changed in a session, and why.
struct PlanChangeLine: Hashable, Identifiable {
    enum Kind: Hashable {
        case kept, progressed, swapped, added, removed, sets, moved, note
    }
    var kind: Kind
    var text: String
    var id: String { "\(kind)-\(text)" }

    var systemImage: String {
        switch kind {
        case .kept: return "equal.circle"
        case .progressed: return "arrow.up.right.circle"
        case .swapped: return "arrow.triangle.2.circlepath"
        case .added: return "plus.circle"
        case .removed: return "minus.circle"
        case .sets: return "square.stack.3d.up"
        case .moved: return "calendar"
        case .note: return "info.circle"
        }
    }
}

/// A session as it will be after a change, set against what it was.
struct PlanSessionChange: Hashable, Identifiable {
    var id: String
    var date: String
    var previousDate: String?
    /// How the earlier session relates: moved from it, or followed on from it.
    var previousIsSource = false
    var title: String
    var minutes: Int
    var previousMinutes: Int?
    var exerciseIds: [String]
    var lines: [PlanChangeLine]

    var isUnchanged: Bool { !lines.contains { $0.kind != .kept } }
}

/// Explains a change to the plan from the engine's own decisions: which
/// exercises stay, which were swapped and what the old one needs that is not
/// there, what the progression rule decided for each load, and what moved.
///
/// It reads the programs; it never decides anything itself.
@MainActor
enum PlanChanges {
    struct Context {
        var equipment: [String]
        var fixtures: [String]
        var experience: Experience
        /// Minutes the person asked to fit, when that is the change.
        var minutes: Int?
    }

    static func currentContext(overrides: TrainingEngineAdapter.PreferenceOverrides = .init()) -> Context {
        Context(
            equipment: overrides.equipment ?? FiltersStore.shared.gymEquipment,
            fixtures: overrides.fixtures ?? FiltersStore.shared.effectiveFixtures,
            experience: TrainingProfileStore.shared.profile.trainingExperience,
            minutes: overrides.sessionMinutes.map { Int($0) }
        )
    }

    /// Pairs `before` with `after` — by date when the dates match, otherwise
    /// in order, so a new week lines up with the week it follows — and
    /// explains each pair.
    static func compare(
        before: [PlannedSession],
        after: [PlannedSession],
        afterProgram: TrainingProgram,
        context: Context,
        pairByDate: Bool
    ) -> [PlanSessionChange] {
        let old = before.sorted { $0.scheduledAt < $1.scheduledAt }
        let new = after.sorted { $0.scheduledAt < $1.scheduledAt }
        var used = Set<String>()
        var result: [PlanSessionChange] = []
        for (index, session) in new.enumerated() {
            let day = String(session.scheduledAt.prefix(10))
            let partner: PlannedSession? = pairByDate
                ? old.first { String($0.scheduledAt.prefix(10)) == day && !used.contains($0.id) }
                : (index < old.count ? old[index] : nil)
            if let partner { used.insert(partner.id) }
            result.append(explain(session, against: partner, program: afterProgram, context: context))
        }
        if pairByDate {
            for session in old where !used.contains(session.id) {
                result.append(PlanSessionChange(
                    id: "removed-\(session.id)",
                    date: String(session.scheduledAt.prefix(10)),
                    previousDate: nil,
                    title: "No session",
                    minutes: 0,
                    previousMinutes: minutes(session),
                    exerciseIds: [],
                    lines: [PlanChangeLine(kind: .removed, text: "The session that was here is withdrawn.")]
                ))
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    static func explain(
        _ session: PlannedSession,
        against previous: PlannedSession?,
        program: TrainingProgram,
        context: Context
    ) -> PlanSessionChange {
        let title = TrainingPlan.plannedSessionTitle(program.diagnostics.selectedSplit, session.focus)
        let ordered = session.exercises.sorted { $0.order < $1.order }
        var lines: [PlanChangeLine] = []

        guard let previous else {
            lines.append(PlanChangeLine(kind: .added, text: "A new session: \(Wording.countLabel(ordered.count, "exercise")), about \(minutes(session)) min."))
            for exercise in ordered where exercise.progression.action == .calibrate {
                lines.append(PlanChangeLine(kind: .note, text: "\(name(exercise.exerciseId)): \(progressionReason(exercise.progression))"))
            }
            return PlanSessionChange(
                id: session.id, date: String(session.scheduledAt.prefix(10)), previousDate: nil,
                title: title, minutes: minutes(session), previousMinutes: nil,
                exerciseIds: ordered.map(\.exerciseId), lines: lines
            )
        }

        let oldIds = previous.exercises.map(\.exerciseId)
        let newIds = ordered.map(\.exerciseId)
        var removed = previous.exercises.filter { !newIds.contains($0.exerciseId) }
        var added = ordered.filter { !oldIds.contains($0.exerciseId) }

        for exercise in ordered where oldIds.contains(exercise.exerciseId) {
            guard let before = previous.exercises.first(where: { $0.exerciseId == exercise.exerciseId }) else { continue }
            lines.append(continuityLine(exercise, before: before))
        }

        // A removed exercise and an added one that train the same muscles
        // read as one swap.
        let index = TrainingWorkflow.trainingIndex()
        for old in removed {
            let oldDirect = Set(index.byId[old.exerciseId]?.metadata.setRoles.filter { $0.role == .direct }.map(\.muscleId) ?? [])
            guard let match = added.first(where: { candidate in
                let direct = index.byId[candidate.exerciseId]?.metadata.setRoles.filter { $0.role == .direct }.map(\.muscleId) ?? []
                return !oldDirect.isDisjoint(with: direct)
            }) else { continue }
            removed.removeAll { $0.exerciseId == old.exerciseId }
            added.removeAll { $0.exerciseId == match.exerciseId }
            lines.append(PlanChangeLine(
                kind: .swapped,
                text: "\(name(old.exerciseId)) → \(name(match.exerciseId)): \(swapReason(old.exerciseId, context: context))"
            ))
        }
        for exercise in added {
            let muscles = exercise.targetMuscles.prefix(2).map { $0.label.lowercased() }
            lines.append(PlanChangeLine(
                kind: .added,
                text: "Added \(name(exercise.exerciseId)) (\(Wording.countLabel(exercise.workingSets.count, "set"))) for \(Wording.list(muscles))."
            ))
        }
        for exercise in removed {
            let reason = removalReason(exercise.exerciseId, context: context)
            lines.append(PlanChangeLine(kind: .removed, text: "Dropped \(name(exercise.exerciseId)): \(reason)"))
        }

        let previousDay = String(previous.scheduledAt.prefix(10))
        let day = String(session.scheduledAt.prefix(10))
        return PlanSessionChange(
            id: session.id,
            date: day,
            previousDate: previousDay == day ? nil : previousDay,
            previousIsSource: WeekProgress.mondayOf(previousDay) != WeekProgress.mondayOf(day),
            title: title,
            minutes: minutes(session),
            previousMinutes: minutes(previous),
            exerciseIds: newIds,
            lines: lines
        )
    }

    // MARK: Lines

    private static func continuityLine(_ exercise: PlannedExercise, before: PlannedExercise) -> PlanChangeLine {
        let label = name(exercise.exerciseId)
        let sets = exercise.workingSets.count
        let oldSets = before.workingSets.count
        let newKg = exercise.workingSets.first?.resistance.kg
        let oldKg = before.workingSets.first?.resistance.kg
        let newReps = exercise.workingSets.first?.targetReps
        let oldReps = before.workingSets.first?.targetReps
        var changes: [String] = []
        if sets != oldSets { changes.append("\(oldSets) → \(sets) sets") }
        if let newKg, let oldKg, newKg != oldKg {
            let each = exercise.workingSets.first?.resistance.basis == .perImplement ? " each" : ""
            changes.append("\(Resistance.formatKg(oldKg)) → \(Resistance.formatKg(newKg)) kg\(each) suggested")
        } else if let newKg, oldKg == nil {
            let each = exercise.workingSets.first?.resistance.basis == .perImplement ? " each" : ""
            changes.append("\(Resistance.formatKg(newKg)) kg\(each) suggested from your last session")
        }
        if let newReps, let oldReps, newReps != oldReps { changes.append("\(oldReps.label) → \(newReps.label) reps") }
        let reason = progressionReason(exercise.progression)
        if changes.isEmpty {
            return PlanChangeLine(kind: .kept, text: "\(label): same as before. \(reason)")
        }
        let kind: PlanChangeLine.Kind = sets != oldSets && newKg == oldKg ? .sets : .progressed
        return PlanChangeLine(kind: kind, text: "\(label): \(changes.joined(separator: ", ")). \(reason)")
    }

    /// The progression rule's reason, in words.
    static func progressionReason(_ recommendation: ProgressionRecommendation) -> String {
        switch recommendation.reasons.first {
        case .noHistory?: return "No logged sets yet, so the load is a calibration: pick one that fits the target."
        case .staleHistory?: return "Over four weeks since it was logged, so the load is found again."
        case .contextChanged?: return "Logged on other equipment before, so the load is found again."
        case .missingEffort?: return "Reps left wasn't recorded, so the load holds."
        case .incompleteSets?: return "Not every set was finished last time, so the load holds."
        case .topOfRange?: return "Every set reached the top of the range last time."
        case .repeatedUnderperformance?: return "Two sessions fell short of the range, so the load comes down."
        case .withinRange?: return "Reps are still inside the range, so the load holds."
        case .gridUnavailable?: return "The equipment's weight steps aren't set, so the load holds."
        case .incrementTooLarge?: return "The next step down is too big, so the load holds."
        case .coarseLoadGrid?, .coarseGridRequiresAlternativeProgression?:
            return "The next weight step is large, so reps go up first."
        case nil: return ""
        }
    }

    /// Why the engine can no longer plan an exercise for this person, in the
    /// words of the decision that ruled it out. Nil when it still could.
    static func ineligibility(_ exerciseId: String, context: Context) -> String? {
        let missing = TrainingEngineAdapter.missingRequirements(
            exerciseId, equipment: context.equipment, fixtures: context.fixtures
        )
        if !missing.isEmpty {
            let needs = Wording.list(missing.map { withArticle(TrainingEngineAdapter.fixtureLabel($0).lowercased()) })
            return "it needs \(needs), which isn't on your equipment list."
        }
        guard let metadata = TrainingWorkflow.trainingIndex().byId[exerciseId]?.metadata else { return nil }
        if metadata.automaticProgramming != .allowed {
            if let decision = ReviewedRequirements.decision(exerciseId), decision.automaticProgramming != nil {
                return "RAUTA no longer plans it automatically. \(decision.reason)"
            }
            return "RAUTA doesn't plan it automatically; you can still add it yourself."
        }
        if !ExerciseData.suits(metadata, context.experience) {
            return "it's a harder variation than RAUTA prescribes at your experience level."
        }
        return nil
    }

    /// "a bench", "an ab wheel", "dip bars".
    static func withArticle(_ item: String) -> String {
        if item.hasSuffix("s") { return item }
        return ("aeiou".contains(item.prefix(1)) ? "an " : "a ") + item
    }

    private static func swapReason(_ exerciseId: String, context: Context) -> String {
        ineligibility(exerciseId, context: context) ?? "a better fit for this session's muscles and time."
    }

    private static func removalReason(_ exerciseId: String, context: Context) -> String {
        if let reason = ineligibility(exerciseId, context: context) { return reason }
        if let minutes = context.minutes {
            return "to fit about \(minutes) min."
        }
        return "those muscles already get their sets this week."
    }

    static func name(_ exerciseId: String) -> String {
        ExerciseCatalogue.name(exerciseId)?.capitalized ?? "An exercise"
    }

    static func minutes(_ session: PlannedSession) -> Int {
        Int((session.duration.totalSeconds / 60).rounded())
    }
}
