import Foundation

/// Validation of the persisted training record.
///
/// Everything here works over `JSONValue` rather than the typed model, because
/// what it guards is data that came back from storage and may be anything at
/// all. A typed value is checked by encoding it first, which drops `nil` fields
/// exactly the way `undefined` was dropped in the original.
enum PersistenceValidation {
    private static let setTypes: Set<String> = ["warmup", "working", "backoff", "drop", "other"]
    private static let plannedSetTypes: Set<String> = ["warmup", "working", "backoff"]
    private static let sides: Set<String> = ["both", "left", "right"]
    private static let confidences: Set<String> = ["none", "low", "medium", "high"]
    private static let loadAcquisitions: Set<String> = [
        "calibrate_by_rir", "history", "bodyweight", "band_resistance",
    ]
    private static let goals: Set<String> = [
        "strength", "hypertrophy", "strength_hypertrophy", "muscular_endurance",
        "general_fitness", "fat_loss_support", "power",
    ]

    // MARK: Primitives

    private static func nonEmptyString(_ value: JSONValue?) -> Bool {
        guard let text = value?.stringValue else { return false }
        return !text.isEmpty
    }

    private static func finite(_ value: JSONValue?, _ min: Double = 0, _ max: Double = 1_000_000) -> Bool {
        guard let number = value?.numberValue, number.isFinite else { return false }
        return number >= min && number <= max
    }

    private static func integer(_ value: JSONValue?, _ min: Double = 0, _ max: Double = 1_000_000) -> Bool {
        guard finite(value, min, max), let number = value?.numberValue else { return false }
        return number == number.rounded()
    }

    static func isValidIsoTimestamp(_ value: String) -> Bool {
        ISOTime.valid(value)
    }

    private static func isValidIsoTimestamp(_ value: JSONValue?) -> Bool {
        guard let text = value?.stringValue else { return false }
        return ISOTime.valid(text)
    }

    static func isValidResistance(_ resistance: ResistanceValue) -> Bool {
        isValidResistance(resistance.jsonTree)
    }

    private static func isValidResistance(_ value: JSONValue?) -> Bool {
        guard let object = value?.objectValue, let type = object["type"]?.stringValue else { return false }
        if type == "unknown" || type == "bodyweight" || type == "band_resistance" {
            return object.count == 1
        }
        guard type == "external_load" || type == "assistance" else { return false }
        let basis = object["basis"]?.stringValue
        return finite(object["kg"], 0, 2000)
            && (basis == "total" || basis == "per_implement")
            && nonEmptyString(object["stationId"])
    }

    private static func isValidRepRange(_ value: JSONValue?) -> Bool {
        guard let object = value?.objectValue else { return false }
        guard integer(object["min"], 1, 1000) else { return false }
        let minimum = object["min"]?.numberValue ?? 1
        return integer(object["max"], minimum, 1000)
    }

    private static func isValidScore(_ value: JSONValue?) -> Bool {
        guard let object = value?.objectValue,
              finite(object["total"], -1_000_000, 1_000_000),
              let contributions = object["contributions"]?.arrayValue
        else { return false }
        return contributions.allSatisfy { item in
            guard let entry = item.objectValue else { return false }
            return nonEmptyString(entry["factor"])
                && finite(entry["rawValue"], -1_000_000, 1_000_000)
                && finite(entry["weight"], -1_000_000, 1_000_000)
                && finite(entry["contribution"], -1_000_000, 1_000_000)
        }
    }

    private static func isValidPlanningIssue(_ value: JSONValue?) -> Bool {
        guard let object = value?.objectValue, nonEmptyString(object["code"]) else { return false }
        if let path = object["path"], path.stringValue == nil { return false }
        if let context = object["context"], context.objectValue == nil { return false }
        return true
    }

    private static func isValidProgression(_ value: JSONValue?) -> Bool {
        let actions: Set<String> = [
            "calibrate", "hold", "increase_load", "decrease_load", "increase_reps",
            "reduce_assistance", "increase_assistance", "coarse_grid_progression",
        ]
        guard let object = value?.objectValue,
              let action = object["action"]?.stringValue, actions.contains(action),
              isValidResistance(object["resistance"]),
              isValidRepRange(object["targetReps"]),
              let confidence = object["confidence"]?.stringValue, confidences.contains(confidence),
              let reasons = object["reasons"]?.arrayValue,
              reasons.allSatisfy({ nonEmptyString($0) })
        else { return false }
        if let strategies = object["suggestedStrategies"] {
            guard let items = strategies.arrayValue, items.allSatisfy({ nonEmptyString($0) }) else {
                return false
            }
        }
        return true
    }

    private static func isValidPlannedSet(_ value: JSONValue?) -> Bool {
        guard let object = value?.objectValue,
              nonEmptyString(object["id"]),
              let setType = object["setType"]?.stringValue, plannedSetTypes.contains(setType),
              isValidRepRange(object["targetReps"]),
              finite(object["targetRir"], 0, 10),
              isValidResistance(object["resistance"]),
              let acquisition = object["loadAcquisition"]?.stringValue,
              loadAcquisitions.contains(acquisition),
              object["side"]?.stringValue == "both"
        else { return false }
        if let groupId = object["groupId"], !nonEmptyString(groupId) { return false }
        return true
    }

    private static func isValidPlannedExercise(_ value: JSONValue?) -> Bool {
        guard let object = value?.objectValue,
              nonEmptyString(object["exerciseId"]),
              integer(object["order"], 0, 1000),
              let workingSets = object["workingSets"]?.arrayValue,
              workingSets.allSatisfy({ isValidPlannedSet($0) }),
              let warmupSets = object["warmupSets"]?.arrayValue,
              warmupSets.allSatisfy({ isValidPlannedSet($0) }),
              finite(object["restSeconds"], 0, 3600),
              let targetMuscles = object["targetMuscles"]?.arrayValue,
              targetMuscles.allSatisfy({ nonEmptyString($0) }),
              isValidScore(object["rationale"]),
              isValidProgression(object["progression"])
        else { return false }
        return true
    }

    private static func isValidPlannedSession(_ value: JSONValue?) -> Bool {
        guard let object = value?.objectValue,
              nonEmptyString(object["id"]),
              isValidIsoTimestamp(object["scheduledAt"]),
              let focus = object["focus"]?.arrayValue, focus.allSatisfy({ nonEmptyString($0) }),
              let exercises = object["exercises"]?.arrayValue,
              exercises.allSatisfy({ isValidPlannedExercise($0) }),
              let duration = object["duration"]?.objectValue
        else { return false }

        let seconds = [
            "generalWarmupSeconds", "specificWarmupSeconds", "workingSetSeconds",
            "restSeconds", "transitionSeconds", "totalSeconds",
        ]
        guard seconds.allSatisfy({ finite(duration[$0], 0, 86_400) }),
              let confidence = duration["confidence"]?.stringValue, confidences.contains(confidence)
        else { return false }
        return true
    }

    // MARK: Program records

    private static func validateProgramRecord(
        _ value: JSONValue?,
        _ path: String,
        _ issues: inout [TrainingPersistenceIssue]
    ) -> Bool {
        guard let object = value?.objectValue else {
            issues.append(TrainingPersistenceIssue(path: path, message: "program record must be an object"))
            return false
        }
        let snapshot = object["snapshot"]?.objectValue

        var valid = nonEmptyString(object["id"])
        if let kind = object["kind"]?.stringValue, !["plan", "workout"].contains(kind) { valid = false }
        else if object["kind"] != nil && object["kind"]?.stringValue == nil { valid = false }
        if let lifecycle = object["lifecycle"]?.stringValue {
            if !["active", "completed", "archived"].contains(lifecycle) { valid = false }
        } else { valid = false }
        if !isValidIsoTimestamp(object["createdAt"]) { valid = false }

        if let snapshot {
            let policy = snapshot["policy"]?.objectValue
            valid = valid
                && nonEmptyString(snapshot["id"])
                && snapshot["id"]?.stringValue == object["id"]?.stringValue
                && nonEmptyString(snapshot["engineVersion"])
                && nonEmptyString(snapshot["policyVersion"])
                && policy != nil
                && nonEmptyString(policy?["version"])
                && policy?["version"]?.stringValue == snapshot["policyVersion"]?.stringValue
                && nonEmptyString(snapshot["datasetFingerprint"])
                && isValidIsoTimestamp(snapshot["generatedAt"])
                && (snapshot["goal"]?.stringValue.map(goals.contains) ?? false)
                && integer(snapshot["durationWeeks"], 1, 52)
                && (snapshot["weeks"]?.arrayValue?.count == Int(snapshot["durationWeeks"]?.numberValue ?? -1))

            if let diagnostics = snapshot["diagnostics"]?.objectValue {
                let splitsValid = diagnostics["splits"]?.arrayValue?.allSatisfy { split in
                    guard let entry = split.objectValue else { return false }
                    return nonEmptyString(entry["name"])
                        && finite(entry["score"], -1_000_000, 1_000_000)
                        && entry["valid"]?.boolValue != nil
                } ?? false
                let warningsValid = diagnostics["warnings"]?.arrayValue?
                    .allSatisfy { isValidPlanningIssue($0) } ?? false
                valid = valid
                    && splitsValid
                    && integer(diagnostics["candidateCount"], 0, 1_000_000)
                    && integer(diagnostics["optimizerIterations"], 0, 10_000_000)
                    && diagnostics["selectedSplit"]?.stringValue != nil
                    && isValidScore(diagnostics["score"])
                    && warningsValid
            } else {
                valid = false
            }
        } else {
            valid = false
        }

        var plannedIds = Set<String>()
        var sessionIds = Set<String>()
        var weekIds = Set<String>()
        if let weeks = snapshot?["weeks"]?.arrayValue {
            for (weekIndex, week) in weeks.enumerated() {
                let weekPath = "\(path).snapshot.weeks.\(weekIndex)"
                guard let weekObject = week.objectValue,
                      let weekId = weekObject["id"]?.stringValue, !weekId.isEmpty,
                      !weekIds.contains(weekId),
                      isValidIsoTimestamp(weekObject["start"]),
                      let phase = weekObject["phase"]?.stringValue,
                      ["base", "reduced_volume"].contains(phase),
                      let sessions = weekObject["sessions"]?.arrayValue,
                      let targets = weekObject["targets"]?.arrayValue
                else {
                    issues.append(TrainingPersistenceIssue(
                        path: weekPath, message: "invalid persisted training week"
                    ))
                    valid = false
                    continue
                }
                weekIds.insert(weekId)

                for target in targets {
                    guard let entry = target.objectValue else {
                        issues.append(TrainingPersistenceIssue(
                            path: weekPath + ".targets", message: "invalid muscle target"
                        ))
                        valid = false
                        continue
                    }
                    let minimum = entry["minimum"]?.numberValue ?? -1
                    let preferred = entry["preferred"]?.numberValue ?? -1
                    let targetValid = nonEmptyString(entry["muscleId"])
                        && finite(entry["minimum"], 0, 100)
                        && finite(entry["preferred"], minimum, 100)
                        && finite(entry["upperGuideline"], preferred, 100)
                        && finite(entry["importance"], 0, 100)
                        && finite(entry["preferredExposures"], 0, 20)
                    if !targetValid {
                        issues.append(TrainingPersistenceIssue(
                            path: weekPath + ".targets", message: "invalid muscle target"
                        ))
                        valid = false
                    }
                }

                for session in sessions {
                    let sessionId = session["id"]?.stringValue ?? ""
                    guard isValidPlannedSession(session), !sessionIds.contains(sessionId) else {
                        issues.append(TrainingPersistenceIssue(
                            path: weekPath + ".sessions",
                            message: "invalid or duplicate planned session"
                        ))
                        valid = false
                        continue
                    }
                    sessionIds.insert(sessionId)
                    for exercise in session["exercises"]?.arrayValue ?? [] {
                        let sets = (exercise["workingSets"]?.arrayValue ?? [])
                            + (exercise["warmupSets"]?.arrayValue ?? [])
                        for set in sets {
                            let setId = set["id"]?.stringValue ?? ""
                            if plannedIds.contains(setId) {
                                issues.append(TrainingPersistenceIssue(
                                    path: weekPath + ".sets", message: "duplicate planned set ID"
                                ))
                                valid = false
                            }
                            plannedIds.insert(setId)
                        }
                    }
                }
            }
        }

        if let adaptation = snapshot?["adaptation"] {
            let entry = adaptation.objectValue
            let modeValid = entry?["mode"]?.stringValue.map {
                ["remaining_week", "next_week"].contains($0)
            } ?? false
            if entry == nil
                || !nonEmptyString(entry?["sourceProgramId"])
                || !isValidIsoTimestamp(entry?["asOf"])
                || !modeValid {
                issues.append(TrainingPersistenceIssue(
                    path: path + ".snapshot.adaptation", message: "invalid adaptation lineage"
                ))
                valid = false
            }
        }

        if let revision = object["revision"] {
            let entry = revision.objectValue
            let reasonValid = entry?["reason"]?.stringValue.map {
                ["remaining_week", "next_week", "manual_regeneration"].contains($0)
            } ?? false
            var idsValid = true
            for key in ["incorporatedSessionIds", "replacedSessionIds"] {
                guard let list = entry?[key] else { continue }
                guard let items = list.arrayValue,
                      items.allSatisfy({ nonEmptyString($0) }),
                      Set(items.compactMap(\.stringValue)).count == items.count
                else {
                    idsValid = false
                    break
                }
            }
            if entry == nil
                || !nonEmptyString(entry?["sourceProgramId"])
                || !reasonValid
                || !isValidIsoTimestamp(entry?["asOf"])
                || !idsValid {
                issues.append(TrainingPersistenceIssue(
                    path: path + ".revision", message: "invalid program revision lineage"
                ))
                valid = false
            }
        }

        if !valid {
            issues.append(TrainingPersistenceIssue(path: path, message: "invalid persisted program record"))
        }
        return valid
    }

    // MARK: Completed sessions

    private static func isValidCompletedSet(_ value: JSONValue?) -> Bool {
        guard let object = value?.objectValue, nonEmptyString(object["id"]) else { return false }
        if let plannedSetId = object["plannedSetId"], !nonEmptyString(plannedSetId) { return false }
        let completed = object["completed"]?.boolValue
        guard let completed else { return false }
        guard integer(object["reps"], completed ? 1 : 0, 1000) else { return false }
        guard isValidResistance(object["resistance"]) else { return false }
        if let rir = object["rir"], !finite(rir, 0, 10) { return false }
        if let rpe = object["rpe"], !finite(rpe, 0, 10) { return false }
        if let rir = object["rir"]?.numberValue, let rpe = object["rpe"]?.numberValue,
           abs(rir + rpe - 10) > 1 { return false }
        guard let setType = object["setType"]?.stringValue, setTypes.contains(setType) else { return false }
        guard let side = object["side"]?.stringValue, sides.contains(side) else { return false }
        if let timestamp = object["timestamp"], !isValidIsoTimestamp(timestamp) { return false }
        return true
    }

    private static func validateCompletedSession(
        _ value: JSONValue?,
        _ path: String,
        _ issues: inout [TrainingPersistenceIssue],
        globalExerciseIds: inout Set<String>,
        globalSetIds: inout Set<String>
    ) -> Bool {
        guard let object = value?.objectValue,
              nonEmptyString(object["id"]),
              isValidIsoTimestamp(object["startedAt"]),
              isValidIsoTimestamp(object["completedAt"]),
              let startedAt = object["startedAt"]?.stringValue.flatMap(ISOTime.parse),
              let completedAt = object["completedAt"]?.stringValue.flatMap(ISOTime.parse),
              startedAt <= completedAt,
              let status = object["status"]?.stringValue,
              ["completed", "partial"].contains(status),
              let exercises = object["exercises"]?.arrayValue
        else {
            issues.append(TrainingPersistenceIssue(path: path, message: "invalid completed session"))
            return false
        }
        if let duration = object["durationSeconds"], !finite(duration, 0, 86_400) {
            issues.append(TrainingPersistenceIssue(path: path, message: "invalid completed session"))
            return false
        }
        for key in ["sourceWorkoutId", "plannedProgramId", "plannedSessionId"] {
            if let entry = object[key], !nonEmptyString(entry) {
                issues.append(TrainingPersistenceIssue(path: path, message: "invalid completed session"))
                return false
            }
        }
        if object["plannedSessionId"] != nil && object["plannedProgramId"] == nil {
            issues.append(TrainingPersistenceIssue(path: path, message: "invalid completed session"))
            return false
        }

        var valid = true
        var plannedSetUsage: [String: (exerciseId: String, sides: [String])] = [:]

        for (exerciseIndex, exercise) in exercises.enumerated() {
            let exercisePath = "\(path).exercises.\(exerciseIndex)"
            guard let entry = exercise.objectValue,
                  nonEmptyString(entry["id"]),
                  let exerciseId = entry["exerciseId"]?.stringValue, !exerciseId.isEmpty,
                  let sets = entry["sets"]?.arrayValue
            else {
                issues.append(TrainingPersistenceIssue(
                    path: exercisePath, message: "invalid completed exercise"
                ))
                valid = false
                continue
            }
            if let plannedExerciseId = entry["plannedExerciseId"], !nonEmptyString(plannedExerciseId) {
                issues.append(TrainingPersistenceIssue(
                    path: exercisePath, message: "invalid completed exercise"
                ))
                valid = false
                continue
            }
            if let snapshot = entry["exerciseNameSnapshot"], snapshot.stringValue == nil {
                issues.append(TrainingPersistenceIssue(
                    path: exercisePath, message: "invalid completed exercise"
                ))
                valid = false
                continue
            }

            let entryId = entry["id"]?.stringValue ?? ""
            if globalExerciseIds.contains(entryId) {
                issues.append(TrainingPersistenceIssue(
                    path: exercisePath + ".id", message: "duplicate completed exercise ID"
                ))
                valid = false
            }
            globalExerciseIds.insert(entryId)

            for (setIndex, set) in sets.enumerated() {
                let setPath = "\(exercisePath).sets.\(setIndex)"
                guard isValidCompletedSet(set), let setObject = set.objectValue else {
                    issues.append(TrainingPersistenceIssue(path: setPath, message: "invalid completed set"))
                    valid = false
                    continue
                }
                let setId = setObject["id"]?.stringValue ?? ""
                if globalSetIds.contains(setId) {
                    issues.append(TrainingPersistenceIssue(
                        path: setPath + ".id", message: "duplicate completed set ID"
                    ))
                    valid = false
                }
                globalSetIds.insert(setId)

                if let timestamp = setObject["timestamp"]?.stringValue.flatMap(ISOTime.parse),
                   timestamp < startedAt || timestamp > completedAt {
                    issues.append(TrainingPersistenceIssue(
                        path: setPath + ".timestamp", message: "set timestamp is outside the session"
                    ))
                    valid = false
                }

                if let plannedSetId = setObject["plannedSetId"]?.stringValue {
                    let side = setObject["side"]?.stringValue ?? ""
                    if let prior = plannedSetUsage[plannedSetId],
                       prior.exerciseId != exerciseId
                        || prior.sides.contains(side)
                        || prior.sides.contains("both")
                        || side == "both" {
                        issues.append(TrainingPersistenceIssue(
                            path: setPath + ".plannedSetId",
                            message: "invalid repeated planned-set linkage"
                        ))
                        valid = false
                    }
                    plannedSetUsage[plannedSetId] = (
                        exerciseId: exerciseId,
                        sides: (plannedSetUsage[plannedSetId]?.sides ?? []) + [side]
                    )
                }
            }
        }
        return valid
    }

    // MARK: Active draft

    private static func isValidSetTarget(_ value: JSONValue?) -> Bool {
        guard let object = value?.objectValue else { return false }
        return isValidRepRange(object["reps"])
            && finite(object["rir"], 0, 10)
            && isValidResistance(object["resistance"])
    }

    private static func isValidSetObservation(_ value: JSONValue?) -> Bool {
        guard let object = value?.objectValue, object["completed"]?.boolValue != nil else { return false }
        if let reps = object["reps"], !integer(reps, 0, 1000) { return false }
        if let resistance = object["resistance"], !isValidResistance(resistance) { return false }
        if let rir = object["rir"], !finite(rir, 0, 10) { return false }
        if let rpe = object["rpe"], !finite(rpe, 0, 10) { return false }
        if let rir = object["rir"]?.numberValue, let rpe = object["rpe"]?.numberValue,
           abs(rir + rpe - 10) > 1 { return false }
        if let timestamp = object["timestamp"], !isValidIsoTimestamp(timestamp) { return false }
        return true
    }

    private static func validateActiveWorkout(
        _ value: JSONValue?,
        _ path: String,
        _ issues: inout [TrainingPersistenceIssue]
    ) -> Bool {
        guard let object = value?.objectValue,
              nonEmptyString(object["id"]),
              isValidIsoTimestamp(object["startedAt"]),
              let startedAt = object["startedAt"]?.stringValue.flatMap(ISOTime.parse),
              let exercises = object["exercises"]?.arrayValue
        else {
            issues.append(TrainingPersistenceIssue(path: path, message: "invalid active workout draft"))
            return false
        }
        for key in ["sourceWorkoutId", "plannedProgramId", "plannedSessionId"] {
            if let entry = object[key], !nonEmptyString(entry) {
                issues.append(TrainingPersistenceIssue(path: path, message: "invalid active workout draft"))
                return false
            }
        }
        if object["plannedSessionId"] != nil && object["plannedProgramId"] == nil {
            issues.append(TrainingPersistenceIssue(path: path, message: "invalid active workout draft"))
            return false
        }

        var valid = true
        var exerciseIds = Set<String>()
        var setIds = Set<String>()

        for (exerciseIndex, exercise) in exercises.enumerated() {
            let exercisePath = "\(path).exercises.\(exerciseIndex)"
            guard let entry = exercise.objectValue,
                  let entryId = entry["id"]?.stringValue, !entryId.isEmpty,
                  !exerciseIds.contains(entryId),
                  nonEmptyString(entry["exerciseId"]),
                  let sets = entry["sets"]?.arrayValue
            else {
                issues.append(TrainingPersistenceIssue(
                    path: exercisePath, message: "invalid or duplicate active exercise"
                ))
                valid = false
                continue
            }
            if let plannedExerciseId = entry["plannedExerciseId"], !nonEmptyString(plannedExerciseId) {
                issues.append(TrainingPersistenceIssue(
                    path: exercisePath, message: "invalid or duplicate active exercise"
                ))
                valid = false
                continue
            }
            if let snapshot = entry["exerciseNameSnapshot"], snapshot.stringValue == nil {
                issues.append(TrainingPersistenceIssue(
                    path: exercisePath, message: "invalid or duplicate active exercise"
                ))
                valid = false
                continue
            }
            exerciseIds.insert(entryId)

            for (setIndex, set) in sets.enumerated() {
                let setPath = "\(exercisePath).sets.\(setIndex)"
                guard let setObject = set.objectValue,
                      let setId = setObject["id"]?.stringValue, !setId.isEmpty,
                      !setIds.contains(setId),
                      let setType = setObject["setType"]?.stringValue, setTypes.contains(setType),
                      let side = setObject["side"]?.stringValue, sides.contains(side)
                else {
                    issues.append(TrainingPersistenceIssue(
                        path: setPath, message: "invalid or duplicate active set"
                    ))
                    valid = false
                    continue
                }
                if let plannedSetId = setObject["plannedSetId"], !nonEmptyString(plannedSetId) {
                    issues.append(TrainingPersistenceIssue(
                        path: setPath, message: "invalid or duplicate active set"
                    ))
                    valid = false
                    continue
                }
                if let target = setObject["target"], !isValidSetTarget(target) {
                    issues.append(TrainingPersistenceIssue(
                        path: setPath, message: "invalid or duplicate active set"
                    ))
                    valid = false
                    continue
                }
                if let observation = setObject["observation"], !isValidSetObservation(observation) {
                    issues.append(TrainingPersistenceIssue(
                        path: setPath, message: "invalid or duplicate active set"
                    ))
                    valid = false
                    continue
                }
                setIds.insert(setId)

                if let timestamp = setObject["observation"]?["timestamp"]?.stringValue
                    .flatMap(ISOTime.parse), timestamp < startedAt {
                    issues.append(TrainingPersistenceIssue(
                        path: setPath + ".observation.timestamp", message: "observation predates workout"
                    ))
                    valid = false
                }
            }
        }
        return valid
    }

    // MARK: Settings

    private static func validateLoadConfiguration(
        _ value: JSONValue?,
        _ path: String,
        _ issues: inout [TrainingPersistenceIssue]
    ) -> Bool {
        guard let object = value?.objectValue,
              nonEmptyString(object["id"]),
              nonEmptyString(object["exerciseId"]),
              nonEmptyString(object["stationId"]),
              let basis = object["basis"]?.stringValue,
              ["total", "per_implement"].contains(basis),
              let grid = object["grid"]?.objectValue
        else {
            issues.append(TrainingPersistenceIssue(path: path, message: "invalid load configuration"))
            return false
        }
        if let mode = object["mode"]?.stringValue, mode != "external_load", mode != "assistance" {
            issues.append(TrainingPersistenceIssue(path: path, message: "invalid load configuration"))
            return false
        }

        let valid: Bool
        if let loads = grid["availableLoadsKg"]?.arrayValue {
            let numbers = loads.compactMap(\.numberValue)
            valid = !loads.isEmpty
                && loads.count <= 1000
                && loads.allSatisfy { finite($0, 0, 2000) }
                && Set(numbers).count == loads.count
        } else {
            let minimum = grid["minimumKg"]?.numberValue ?? 0
            var gridValid = finite(grid["incrementKg"], 0.001, 100)
            if let minimumValue = grid["minimumKg"], !finite(minimumValue, 0, 2000) { gridValid = false }
            if let maximumValue = grid["maximumKg"], !finite(maximumValue, minimum, 2000) { gridValid = false }
            valid = gridValid
        }
        if !valid { issues.append(TrainingPersistenceIssue(path: path + ".grid", message: "invalid load grid")) }
        return valid
    }

    /// The transition journal. An intent is a promise about identities and
    /// instants, so every one it names has to be there and well formed before
    /// recovery is allowed to act on it.
    private static func validateTransitionIntent(
        _ value: JSONValue?,
        _ path: String,
        _ issues: inout [TrainingPersistenceIssue]
    ) -> Bool {
        func fail(_ message: String) -> Bool {
            issues.append(TrainingPersistenceIssue(path: path, message: message))
            return false
        }

        guard let object = value?.objectValue,
              nonEmptyString(object["id"]),
              let kind = object["kind"]?.stringValue,
              ["start", "finish", "cancel"].contains(kind),
              isValidIsoTimestamp(object["recordedAt"]),
              nonEmptyString(object["sourceWorkoutId"])
        else { return fail("invalid transition intent") }
        if let draftId = object["draftId"], !nonEmptyString(draftId) {
            return fail("invalid transition intent")
        }

        if let planned = object["planned"] {
            guard let entry = planned.objectValue,
                  nonEmptyString(entry["programId"]),
                  nonEmptyString(entry["sessionId"])
            else { return fail("invalid transition planned lineage") }
        }

        if let shell = object["shell"] {
            guard let entry = shell.objectValue,
                  entry["workoutName"]?.stringValue != nil,
                  entry["workoutDate"]?.stringValue != nil,
                  let exerciseIds = entry["exerciseIds"]?.arrayValue,
                  exerciseIds.allSatisfy({ nonEmptyString($0) }),
                  let startedAtMs = entry["startedAtMs"]?.numberValue,
                  startedAtMs.isFinite, startedAtMs > 0
            else { return fail("invalid transition shell") }
        }

        if kind == "start" {
            guard let shell = object["shell"]?.objectValue,
                  let exerciseIds = shell["exerciseIds"]?.arrayValue,
                  !exerciseIds.isEmpty,
                  Set(exerciseIds.compactMap(\.stringValue)).count == exerciseIds.count,
                  let recordedAt = object["recordedAt"]?.stringValue.flatMap(ISOTime.parse),
                  recordedAt == shell["startedAtMs"]?.numberValue
            else { return fail("invalid start transition") }
        }

        if kind == "cancel" {
            guard isValidIsoTimestamp(object["completedAt"]), nonEmptyString(object["sessionId"]) else {
                return fail("invalid cancel transition")
            }
        }

        if kind == "finish" {
            guard isValidIsoTimestamp(object["completedAt"]),
                  nonEmptyString(object["sessionId"]),
                  let status = object["status"]?.stringValue,
                  status == "completed" || status == "partial"
            else { return fail("invalid finish transition") }

            guard let legacy = object["legacy"]?.objectValue,
                  isValidIsoTimestamp(legacy["startedAt"]),
                  isValidIsoTimestamp(legacy["completedAt"]),
                  legacy["completedAt"]?.stringValue == object["completedAt"]?.stringValue,
                  let legacyStartedAt = legacy["startedAt"]?.stringValue.flatMap(ISOTime.parse),
                  let legacyCompletedAt = legacy["completedAt"]?.stringValue.flatMap(ISOTime.parse),
                  legacyStartedAt <= legacyCompletedAt,
                  finite(legacy["durationMs"], 0, 1000 * 60 * 60 * 24 * 7),
                  finite(legacy["activeCalories"], 0, 100_000),
                  let completedExerciseIds = legacy["completedExerciseIds"]?.arrayValue,
                  completedExerciseIds.allSatisfy({ nonEmptyString($0) }),
                  let syncStatus = legacy["healthSyncStatus"]?.stringValue,
                  syncStatus == "not-requested" || syncStatus == "pending"
            else { return fail("invalid finish transition completion") }
        }

        return true
    }

    private static func validateSettings(
        _ value: JSONValue?,
        _ path: String,
        _ issues: inout [TrainingPersistenceIssue]
    ) -> Bool {
        guard let object = value?.objectValue,
              let coverage = object["historyCoverage"]?.objectValue,
              let configurations = object["loadConfigurations"]?.arrayValue
        else {
            issues.append(TrainingPersistenceIssue(path: path, message: "invalid training settings"))
            return false
        }

        var valid = coverage["status"]?.stringValue == "unknown"
            || (coverage["status"]?.stringValue == "complete"
                && isValidIsoTimestamp(coverage["coverageStart"]))
        if !valid {
            issues.append(TrainingPersistenceIssue(
                path: path + ".historyCoverage", message: "invalid history coverage"
            ))
        }

        var ids = Set<String>()
        var contexts = Set<String>()
        for (index, configuration) in configurations.enumerated() {
            let configPath = "\(path).loadConfigurations.\(index)"
            guard validateLoadConfiguration(configuration, configPath, &issues),
                  let entry = configuration.objectValue
            else {
                valid = false
                continue
            }
            let id = entry["id"]?.stringValue ?? ""
            let contextKey = [
                entry["exerciseId"]?.stringValue ?? "",
                entry["stationId"]?.stringValue ?? "",
                entry["basis"]?.stringValue ?? "",
                entry["mode"]?.stringValue ?? "external_load",
            ].joined(separator: "\u{0}")
            if ids.contains(id) || contexts.contains(contextKey) {
                issues.append(TrainingPersistenceIssue(
                    path: configPath, message: "duplicate load configuration"
                ))
                valid = false
            }
            ids.insert(id)
            contexts.insert(contextKey)
        }

        // A selection is a preference, not evidence. It is checked for shape
        // only: one that no longer names a saved station resolves to the
        // equipment default rather than taking the settings down with it.
        if let active = object["activeLoadConfigurations"] {
            guard let entries = active.objectValue,
                  entries.allSatisfy({ !$0.key.isEmpty && nonEmptyString($0.value) })
            else {
                issues.append(TrainingPersistenceIssue(
                    path: path + ".activeLoadConfigurations",
                    message: "invalid active load configuration selection"
                ))
                return false
            }
        }
        return valid
    }

    // MARK: Whole state

    static func validate(_ value: JSONValue?) -> [TrainingPersistenceIssue] {
        var issues: [TrainingPersistenceIssue] = []
        guard let object = value?.objectValue else {
            return [TrainingPersistenceIssue(
                path: "state", message: "training persistence must be an object"
            )]
        }
        guard object["schemaVersion"]?.numberValue == Double(TRAINING_PERSISTENCE_SCHEMA_VERSION) else {
            return [TrainingPersistenceIssue(
                path: "schemaVersion", message: "unsupported training persistence schema version"
            )]
        }
        guard let programs = object["programs"]?.arrayValue,
              let sessions = object["sessions"]?.arrayValue
        else {
            return [TrainingPersistenceIssue(
                path: "state", message: "programs and sessions must be arrays"
            )]
        }

        var programIds = Set<String>()
        var programsById: [String: JSONValue] = [:]
        for (index, record) in programs.enumerated() {
            let path = "programs.\(index)"
            guard validateProgramRecord(record, path, &issues) else { continue }
            let id = record["id"]?.stringValue ?? ""
            if programIds.contains(id) {
                issues.append(TrainingPersistenceIssue(path: path + ".id", message: "duplicate program ID"))
            }
            programIds.insert(id)
            programsById[id] = record
        }

        for (index, record) in programs.enumerated() {
            guard let id = record["id"]?.stringValue, !id.isEmpty else { continue }
            let sourceId = record["revision"]?["sourceProgramId"]?.stringValue
                ?? record["snapshot"]?["adaptation"]?["sourceProgramId"]?.stringValue
            if let sourceId, !sourceId.isEmpty, sourceId == id || programsById[sourceId] == nil {
                issues.append(TrainingPersistenceIssue(
                    path: "programs.\(index).revision",
                    message: "program revision source is missing or self-referential"
                ))
            }
        }

        if let activeProgramId = object["activeProgramId"] {
            let id = activeProgramId.stringValue ?? ""
            if id.isEmpty || programsById[id] == nil {
                issues.append(TrainingPersistenceIssue(
                    path: "activeProgramId", message: "active program does not exist"
                ))
            }
        }

        var sessionIds = Set<String>()
        var completedExerciseIds = Set<String>()
        var completedSetIds = Set<String>()
        for (index, session) in sessions.enumerated() {
            let path = "sessions.\(index)"
            guard validateCompletedSession(
                session, path, &issues,
                globalExerciseIds: &completedExerciseIds,
                globalSetIds: &completedSetIds
            ) else { continue }

            let id = session["id"]?.stringValue ?? ""
            if sessionIds.contains(id) {
                issues.append(TrainingPersistenceIssue(
                    path: path + ".id", message: "duplicate completed session ID"
                ))
            }
            sessionIds.insert(id)

            guard let plannedProgramId = session["plannedProgramId"]?.stringValue else { continue }
            guard let program = programsById[plannedProgramId] else {
                issues.append(TrainingPersistenceIssue(
                    path: path + ".plannedProgramId", message: "planned program does not exist"
                ))
                continue
            }
            let allSessions = (program["snapshot"]?["weeks"]?.arrayValue ?? [])
                .flatMap { $0["sessions"]?.arrayValue ?? [] }
            guard let plannedSession = allSessions.first(where: {
                $0["id"]?.stringValue == session["plannedSessionId"]?.stringValue
            }) else {
                issues.append(TrainingPersistenceIssue(
                    path: path + ".plannedSessionId",
                    message: "planned session does not exist in program snapshot"
                ))
                continue
            }

            let plannedExercises = plannedSession["exercises"]?.arrayValue ?? []
            let plannedExerciseIds = Set(plannedExercises.compactMap { $0["exerciseId"]?.stringValue })
            let plannedSetIds = Set(plannedExercises.flatMap { exercise in
                ((exercise["workingSets"]?.arrayValue ?? []) + (exercise["warmupSets"]?.arrayValue ?? []))
                    .compactMap { $0["id"]?.stringValue }
            })
            for exercise in session["exercises"]?.arrayValue ?? [] {
                if let plannedExerciseId = exercise["plannedExerciseId"]?.stringValue,
                   !plannedExerciseIds.contains(plannedExerciseId) {
                    issues.append(TrainingPersistenceIssue(
                        path: path + ".plannedExerciseId",
                        message: "planned exercise lineage is absent from snapshot"
                    ))
                }
                for set in exercise["sets"]?.arrayValue ?? [] {
                    if let plannedSetId = set["plannedSetId"]?.stringValue,
                       !plannedSetIds.contains(plannedSetId) {
                        issues.append(TrainingPersistenceIssue(
                            path: path + ".plannedSetId",
                            message: "planned set lineage is absent from snapshot"
                        ))
                    }
                }
            }
        }

        if let activeWorkout = object["activeWorkout"], !activeWorkout.isNull {
            if validateActiveWorkout(activeWorkout, "activeWorkout", &issues),
               let plannedProgramId = activeWorkout["plannedProgramId"]?.stringValue {
                if let program = programsById[plannedProgramId] {
                    let allSessions = (program["snapshot"]?["weeks"]?.arrayValue ?? [])
                        .flatMap { $0["sessions"]?.arrayValue ?? [] }
                    let exists = allSessions.contains {
                        $0["id"]?.stringValue == activeWorkout["plannedSessionId"]?.stringValue
                    }
                    if !exists {
                        issues.append(TrainingPersistenceIssue(
                            path: "activeWorkout.plannedSessionId", message: "planned session does not exist"
                        ))
                    }
                } else {
                    issues.append(TrainingPersistenceIssue(
                        path: "activeWorkout.plannedProgramId", message: "planned program does not exist"
                    ))
                }
            }
        }

        if let transition = object["transition"] {
            _ = validateTransitionIntent(transition, "transition", &issues)
        }
        _ = validateSettings(object["settings"], "settings", &issues)
        return issues
    }

    static func validate(_ state: PersistedTrainingState) -> [TrainingPersistenceIssue] {
        validate(state.jsonTree)
    }

    // MARK: Normalisation, migration, recovery

    static func normalize(_ state: PersistedTrainingState) -> PersistedTrainingState {
        var copy = state
        copy.programs.sort { $0.id.compare($1.id) == .orderedAscending }
        copy.sessions.sort { left, right in
            left.id == right.id
                ? left.startedAt.compare(right.startedAt) == .orderedAscending
                : left.id.compare(right.id) == .orderedAscending
        }
        copy.settings.loadConfigurations.sort { $0.id.compare($1.id) == .orderedAscending }
        return copy
    }

    static func migrate(_ value: JSONValue?) throws -> PersistedTrainingState {
        guard let value, !value.isNull else { return .empty() }
        guard let object = value.objectValue else {
            throw TrainingPersistenceValidationError(issues: [TrainingPersistenceIssue(
                path: "state", message: "training persistence must be an object"
            )])
        }

        let schemaVersion = Int(object["schemaVersion"]?.numberValue ?? -1)
        var migratedTree: JSONValue
        if schemaVersion == TRAINING_PERSISTENCE_SCHEMA_VERSION {
            migratedTree = value
        } else if schemaVersion == 0 {
            migratedTree = .object([
                "schemaVersion": .number(Double(TRAINING_PERSISTENCE_SCHEMA_VERSION)),
                "programs": object["programs"] ?? .array([]),
                "sessions": object["sessions"] ?? .array([]),
                "activeWorkout": object["activeWorkout"] ?? .null,
                "activeProgramId": object["activeProgramId"] ?? .null,
                "settings": .object([
                    "historyCoverage": .object(["status": .string("unknown")]),
                    "loadConfigurations": object["settings"]?["loadConfigurations"] ?? .array([]),
                ]),
            ])
        } else {
            throw TrainingPersistenceValidationError(issues: [TrainingPersistenceIssue(
                path: "schemaVersion", message: "unsupported training persistence schema version"
            )])
        }

        guard let decoded = JSONCoding.value(migratedTree, as: PersistedTrainingState.self) else {
            throw TrainingPersistenceValidationError(issues: [TrainingPersistenceIssue(
                path: "state", message: "training persistence could not be read"
            )])
        }
        let normalized = normalize(decoded)
        let issues = validate(normalized)
        if !issues.isEmpty { throw TrainingPersistenceValidationError(issues: issues) }
        return normalized
    }

    struct Recovery {
        var state: PersistedTrainingState
        var issues: [TrainingPersistenceIssue]
    }

    /// Fail-safe hydration: corrupt payloads cannot crash startup or be
    /// reinterpreted as observations.
    static func recover(_ value: JSONValue?) -> Recovery {
        do {
            return Recovery(state: try migrate(value), issues: [])
        } catch {
            let issues = (error as? TrainingPersistenceValidationError)?.issues
                ?? [TrainingPersistenceIssue(path: "state", message: "unknown persistence error")]

            guard let object = value?.objectValue,
                  let schemaVersion = object["schemaVersion"]?.numberValue,
                  schemaVersion == 0 || schemaVersion == 1
            else { return Recovery(state: .empty(), issues: issues) }

            let candidate: [String: JSONValue] = schemaVersion == 0
                ? [
                    "schemaVersion": .number(1),
                    "programs": object["programs"] ?? .array([]),
                    "sessions": object["sessions"] ?? .array([]),
                    "activeWorkout": object["activeWorkout"] ?? .null,
                    "activeProgramId": object["activeProgramId"] ?? .null,
                    "settings": .object([
                        "historyCoverage": .object(["status": .string("unknown")]),
                        "loadConfigurations": object["settings"]?["loadConfigurations"] ?? .array([]),
                    ]),
                ]
                : object

            var recovered = PersistedTrainingState.empty()

            var keptPrograms: [JSONValue] = []
            for item in candidate["programs"]?.arrayValue ?? [] {
                var itemIssues: [TrainingPersistenceIssue] = []
                if validateProgramRecord(item, "program", &itemIssues) { keptPrograms.append(item) }
            }
            var programIds = Set(keptPrograms.compactMap { $0["id"]?.stringValue })
            keptPrograms = keptPrograms.filter { program in
                let sourceProgramId = program["revision"]?["sourceProgramId"]?.stringValue
                    ?? program["snapshot"]?["adaptation"]?["sourceProgramId"]?.stringValue
                guard let sourceProgramId else { return true }
                return sourceProgramId != program["id"]?.stringValue && programIds.contains(sourceProgramId)
            }
            programIds = Set(keptPrograms.compactMap { $0["id"]?.stringValue })
            recovered.programs = keptPrograms.compactMap {
                JSONCoding.value($0, as: PersistedProgramRecord.self)
            }

            var sessionIds = Set<String>()
            var exerciseIds = Set<String>()
            var setIds = Set<String>()
            var keptSessions: [JSONValue] = []
            for item in candidate["sessions"]?.arrayValue ?? [] {
                var itemIssues: [TrainingPersistenceIssue] = []
                var localExerciseIds = Set<String>()
                var localSetIds = Set<String>()
                let valid = validateCompletedSession(
                    item, "session", &itemIssues,
                    globalExerciseIds: &localExerciseIds,
                    globalSetIds: &localSetIds
                )
                let id = item["id"]?.stringValue ?? ""
                if !valid
                    || sessionIds.contains(id)
                    || localExerciseIds.contains(where: exerciseIds.contains)
                    || localSetIds.contains(where: setIds.contains) { continue }

                if let plannedProgramId = item["plannedProgramId"]?.stringValue {
                    guard let program = keptPrograms.first(where: {
                        $0["id"]?.stringValue == plannedProgramId
                    }) else { continue }
                    let allSessions = (program["snapshot"]?["weeks"]?.arrayValue ?? [])
                        .flatMap { $0["sessions"]?.arrayValue ?? [] }
                    guard let plannedSession = allSessions.first(where: {
                        $0["id"]?.stringValue == item["plannedSessionId"]?.stringValue
                    }) else { continue }

                    let plannedExercises = plannedSession["exercises"]?.arrayValue ?? []
                    let plannedExerciseIds = Set(
                        plannedExercises.compactMap { $0["exerciseId"]?.stringValue }
                    )
                    let plannedSetIds = Set(plannedExercises.flatMap { exercise in
                        ((exercise["workingSets"]?.arrayValue ?? [])
                            + (exercise["warmupSets"]?.arrayValue ?? []))
                            .compactMap { $0["id"]?.stringValue }
                    })
                    let lineageBroken = (item["exercises"]?.arrayValue ?? []).contains { exercise in
                        if let plannedExerciseId = exercise["plannedExerciseId"]?.stringValue,
                           !plannedExerciseIds.contains(plannedExerciseId) { return true }
                        return (exercise["sets"]?.arrayValue ?? []).contains { set in
                            guard let plannedSetId = set["plannedSetId"]?.stringValue else { return false }
                            return !plannedSetIds.contains(plannedSetId)
                        }
                    }
                    if lineageBroken { continue }
                } else if item["plannedSessionId"] != nil {
                    continue
                }

                sessionIds.insert(id)
                exerciseIds.formUnion(localExerciseIds)
                setIds.formUnion(localSetIds)
                keptSessions.append(item)
            }
            recovered.sessions = keptSessions.compactMap {
                JSONCoding.value($0, as: PersistedCompletedSession.self)
            }

            if let activeWorkout = candidate["activeWorkout"], !activeWorkout.isNull {
                var ignored: [TrainingPersistenceIssue] = []
                if validateActiveWorkout(activeWorkout, "activeWorkout", &ignored) {
                    let plannedProgramId = activeWorkout["plannedProgramId"]?.stringValue
                    let validLineage: Bool = {
                        guard let plannedProgramId else { return true }
                        guard programIds.contains(plannedProgramId),
                              let program = keptPrograms.first(where: {
                                  $0["id"]?.stringValue == plannedProgramId
                              })
                        else { return false }
                        let allSessions = (program["snapshot"]?["weeks"]?.arrayValue ?? [])
                            .flatMap { $0["sessions"]?.arrayValue ?? [] }
                        return allSessions.contains {
                            $0["id"]?.stringValue == activeWorkout["plannedSessionId"]?.stringValue
                        }
                    }()
                    if validLineage {
                        recovered.activeWorkout = JSONCoding.value(
                            activeWorkout, as: PersistedActiveWorkoutDraft.self
                        )
                    }
                }
            }

            if let activeProgramId = candidate["activeProgramId"]?.stringValue,
               programIds.contains(activeProgramId) {
                recovered.activeProgramId = activeProgramId
            }

            // A corrupt intent is simply not carried over: recovery then falls
            // back to reconciling the restored stores, which preserves
            // observations anyway.
            if let transition = candidate["transition"] {
                var ignored: [TrainingPersistenceIssue] = []
                if validateTransitionIntent(transition, "transition", &ignored) {
                    recovered.transition = JSONCoding.value(
                        transition, as: PersistedTransitionIntent.self
                    )
                }
            }

            var settingsIssues: [TrainingPersistenceIssue] = []
            if validateSettings(candidate["settings"], "settings", &settingsIssues),
               let settings = candidate["settings"].flatMap({
                   JSONCoding.value($0, as: PersistedTrainingSettings.self)
               }) {
                recovered.settings = settings
            }

            let normalized = normalize(recovered)
            let recoveredIssues = validate(normalized)
            return recoveredIssues.isEmpty
                ? Recovery(state: normalized, issues: issues)
                : Recovery(state: .empty(), issues: issues + recoveredIssues)
        }
    }

}
