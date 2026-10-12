import Foundation

/// Why a planned workout is what it is, read from the plan's own snapshot:
/// the split the engine chose, the muscles this session covers, why each
/// exercise is there and what it asks of the load, how the time adds up, and
/// what has to be at hand.
struct WorkoutRationale: Hashable {
    struct ExerciseReason: Hashable, Identifiable {
        var exerciseId: String
        var name: String
        var trains: String
        var evidence: String
        var id: String { exerciseId }
    }

    var structure: String
    var focus: String
    var exercises: [ExerciseReason]
    var time: String
    var timeBreakdown: String
    /// What has to be there, in words: "a bench, dumbbells and a resistance band".
    var equipment: [String]

    @MainActor
    static func make(programId: String, sessionId: String) -> WorkoutRationale? {
        let data = TrainingRecordsStore.shared.data
        guard let planned = ProgramRecords.plannedSession(data, programId, sessionId) else { return nil }
        return make(
            program: planned.program,
            session: planned.session,
            preferredMinutes: TrainingProfileStore.shared.profile.preferredSessionDurationMinutes
        )
    }

    @MainActor
    static func make(program: TrainingProgram, session: PlannedSession, preferredMinutes: Double) -> WorkoutRationale {
        let index = TrainingWorkflow.trainingIndex()
        let structure: String = {
            let days = program.weeks.first?.sessions.count ?? 1
            switch program.diagnostics.selectedSplit {
            case "upper_lower": return "An upper/lower week: sessions alternate between upper and lower body, so each half gets a day to recover."
            case "push_pull_legs": return "A push/pull/legs week: pressing, pulling and legs each get their own session."
            case "full_body":
                return days == 1
                    ? "One full-body session this week, so it covers every major muscle."
                    : "A full-body week: each of the \(days) sessions trains every major muscle a little, which suits \(days) days a week."
            default: return "This session keeps the structure of the week it came from."
            }
        }()

        let focusNames = session.focus.filter { MAJOR_MUSCLES.contains($0) }.map { $0.label.lowercased() }
        let focus = focusNames.isEmpty ? "" : "Today's focus: \(Wording.list(focusNames))."

        let reasons = session.exercises.sorted { $0.order < $1.order }.map { exercise -> ExerciseReason in
            let metadata = index.byId[exercise.exerciseId]?.metadata
            let direct = metadata?.setRoles.filter { $0.role == .direct }.map { $0.muscleId.label.lowercased() } ?? []
            let helping = metadata?.setRoles.filter { $0.role == .indirect }.map { $0.muscleId.label.lowercased() } ?? []
            var trains = direct.isEmpty ? "" : "Works \(Wording.list(direct))"
            if !helping.isEmpty { trains += (trains.isEmpty ? "Helps " : ", with help from ") + Wording.list(helping) }
            trains += trains.isEmpty ? "" : "."
            let sets = Wording.countLabel(exercise.workingSets.count, "set")
            let reps = exercise.workingSets.first?.targetReps.label ?? ""
            let rir = exercise.workingSets.first.map { "stop with \(Num.trimmed($0.targetRir)) reps left" } ?? ""
            let load: String = {
                guard let first = exercise.workingSets.first else { return "" }
                switch first.loadAcquisition {
                case .calibrateByRir: return "First load is a calibration — pick one you could lift for \(reps) with about \(Num.trimmed(first.targetRir)) left."
                case .history:
                    guard let kg = first.resistance.kg else { return "" }
                    let each = first.resistance.basis == .perImplement ? " each" : ""
                    return "Suggested \(Resistance.formatKg(kg)) kg\(each). \(PlanChanges.progressionReason(exercise.progression))"
                case .bodyweight: return "Body weight; progress by adding reps."
                case .bandResistance: return "Band resistance; progress by adding reps, then a stronger band."
                }
            }()
            return ExerciseReason(
                exerciseId: exercise.exerciseId,
                name: ExerciseCatalogue.name(exercise.exerciseId)?.capitalized ?? "Exercise",
                trains: trains,
                evidence: "\(sets) of \(reps), \(rir). \(load)".trimmingCharacters(in: .whitespaces)
            )
        }

        let duration = session.duration
        let minutes = Int((duration.totalSeconds / 60).rounded())
        let preferred = Int(preferredMinutes)
        let time: String = {
            if Double(minutes) > preferredMinutes + 2 {
                return "About \(minutes) min — a little over your \(preferred)-minute target, inside the 10 minutes RAUTA allows past it."
            }
            if Double(minutes) < preferredMinutes * 0.75 {
                return "About \(minutes) min — shorter than your \(preferred)-minute target because this session's share of the week's sets is done by then. RAUTA doesn't add filler sets to reach a time."
            }
            return "About \(minutes) min, within your \(preferred)-minute target."
        }()
        func part(_ seconds: Double) -> Int { Int((seconds / 60).rounded()) }
        let breakdown = "Warm-up \(part(duration.generalWarmupSeconds + duration.specificWarmupSeconds)) min · "
            + "sets \(part(duration.workingSetSeconds)) min · rest \(part(duration.restSeconds)) min · "
            + "moving between exercises \(part(duration.transitionSeconds)) min. An estimate: your pace decides the rest."

        var needed: [String] = []
        for exercise in session.exercises {
            for item in index.byId[exercise.exerciseId]?.metadata.requiredEquipment ?? []
            where item != TrainingEngineAdapter.implicitEquipment && !needed.contains(item) {
                needed.append(item)
            }
        }

        return WorkoutRationale(
            structure: structure,
            focus: focus,
            exercises: reasons,
            time: time,
            timeBreakdown: breakdown,
            equipment: needed.map { TrainingEngineAdapter.fixtureLabel($0) }
        )
    }
}
