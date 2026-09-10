import Foundation

enum RoundDirection { case nearest, up, down }

enum Progression {
    static func roundLoad(
        _ load: Double,
        _ grid: LoadGrid,
        _ direction: RoundDirection = .nearest
    ) -> Double? {
        guard load.isFinite, load >= 0 else { return nil }

        if let available = grid.availableLoadsKg {
            let loads = Array(Set(available)).filter { $0.isFinite && $0 >= 0 }.sorted()
            let allowed = loads.filter { value in
                switch direction {
                case .up: return value >= load - 1e-6
                case .down: return value <= load + 1e-6
                case .nearest: return true
                }
            }
            return allowed.sorted { left, right in
                let a = abs(left - load)
                let b = abs(right - load)
                if a != b { return a < b }
                return left < right
            }.first
        }

        guard let increment = grid.incrementKg, increment.isFinite, increment > 0 else { return nil }
        let minimum = grid.minimumKg ?? 0
        let steps = (load - minimum) / increment
        let stepped: Double
        switch direction {
        case .up: stepped = (steps - 1e-8).rounded(.up)
        case .down: stepped = (steps + 1e-8).rounded(.down)
        case .nearest: stepped = steps.rounded()
        }
        let value = Num.round6(minimum + stepped * increment)
        if value < minimum { return nil }
        if let maximum = grid.maximumKg, value > maximum { return nil }
        return value
    }

    static func isAchievableLoad(_ load: Double, _ grid: LoadGrid) -> Bool {
        guard let rounded = roundLoad(load, grid) else { return false }
        return abs(rounded - load) < 1e-6
    }

    private static func adjacentLoad(_ load: Double, _ grid: LoadGrid, up: Bool) -> Double? {
        if let available = grid.availableLoadsKg {
            let sorted = available.sorted { up ? $0 < $1 : $0 > $1 }
            return sorted.first { up ? $0 > load + 1e-6 : $0 < load - 1e-6 }
        }
        guard let increment = grid.incrementKg else { return nil }
        return roundLoad(load + (up ? increment : -increment), grid, up ? .up : .down)
    }

    /// The baseline "we do not know yet" recommendation, patched by each branch.
    private static func recommendation(
        _ input: ProgressionInput,
        action: ProgressionAction = .calibrate,
        resistance: ResistanceValue? = nil,
        targetReps: RepRange? = nil,
        confidence: Confidence = .none,
        reasons: [ProgressionReason] = [.noHistory],
        suggestedStrategies: [ProgressionStrategySuggestion]? = nil
    ) -> ProgressionRecommendation {
        let fallback: ResistanceValue = {
            switch input.exercise.metadata.tracking {
            case .bodyweight: return .bodyweight
            case .bandResistance: return .bandResistance
            default: return .unknown
            }
        }()
        return ProgressionRecommendation(
            action: action,
            resistance: resistance ?? fallback,
            targetReps: targetReps ?? input.reps,
            confidence: confidence,
            reasons: reasons,
            suggestedStrategies: suggestedStrategies
        )
    }

    // MARK: Repetition progression

    static func repProgression(_ input: ProgressionInput) -> ProgressionRecommendation {
        let exposures = Strength.exposures(input.history, input.exercise.exercise.id, input.now)
        let tracking = input.exercise.metadata.tracking
        let compatible = exposures.filter { exposure in
            !exposure.sets.isEmpty && exposure.sets.allSatisfy {
                $0.resistance.type.rawValue == tracking.rawValue
            }
        }
        guard let latest = compatible.last else {
            return recommendation(input, reasons: exposures.isEmpty ? [.noHistory] : [.contextChanged])
        }
        let now = ISOTime.parse(input.now) ?? 0
        let completedAt = ISOTime.parse(latest.session.completedAt) ?? 0
        if now - completedAt > input.policy.staleAfterDays * DAY_MS {
            return recommendation(input, reasons: [.staleHistory])
        }

        let top = Volume.completedPairs(latest.sets) >= Double(input.requiredSets)
            && latest.sets.allSatisfy { set in
                set.reps >= input.reps.max
                    && (Strength.observedRir(set) ?? -1) >= input.rir - input.policy.rirTolerance
            }
        let progress = top && input.reps.max < input.policy.maxBodyweightReps

        return recommendation(
            input,
            action: progress ? .increaseReps : .hold,
            targetReps: progress
                ? RepRange(min: input.reps.min + 1, max: input.reps.max + 1)
                : input.reps,
            confidence: .low,
            reasons: [top ? .topOfRange : .withinRange]
        )
    }

    // MARK: Double progression

    static func doubleProgression(_ input: ProgressionInput) -> ProgressionRecommendation {
        let exposures = Strength.exposures(input.history, input.exercise.exercise.id, input.now)
        guard let latest = exposures.last else { return recommendation(input) }

        let now = ISOTime.parse(input.now) ?? 0
        let completedAt = ISOTime.parse(latest.session.completedAt) ?? 0
        if now - completedAt > input.policy.staleAfterDays * DAY_MS {
            return recommendation(input, reasons: [.staleHistory])
        }

        guard let load = latest.sets.first?.resistance else {
            return recommendation(input, reasons: [.contextChanged])
        }
        let tracking = input.exercise.metadata.tracking
        guard load.type.rawValue == tracking.rawValue,
              load.type == .externalLoad || load.type == .assistance,
              let loadKg = load.kg, let loadStation = load.stationId, let loadBasis = load.basis
        else {
            return recommendation(input, reasons: [.contextChanged])
        }
        guard let context = input.loadContext,
              context.stationId == loadStation,
              context.basis == loadBasis
        else {
            return recommendation(input, reasons: [.contextChanged])
        }
        guard let grid = input.loadGrid, isAchievableLoad(loadKg, grid) else {
            return recommendation(input, reasons: [.gridUnavailable])
        }

        func same(_ resistance: ResistanceValue) -> Bool {
            resistance.type == load.type
                && (resistance.type == .externalLoad || resistance.type == .assistance)
                && resistance.stationId == loadStation
                && resistance.basis == loadBasis
                && resistance.kg == loadKg
        }

        func hold(_ reason: ProgressionReason) -> ProgressionRecommendation {
            recommendation(input, action: .hold, resistance: load, confidence: .low, reasons: [reason])
        }

        let incompleteWorking = latest.allSets.contains { !$0.completed && $0.setType == .working }
        if Volume.completedPairs(latest.sets) < Double(input.requiredSets)
            || incompleteWorking
            || !latest.sets.allSatisfy({ same($0.resistance) }) {
            return hold(.incompleteSets)
        }
        if latest.sets.contains(where: { Strength.observedRir($0) == nil }) {
            return hold(.missingEffort)
        }

        let top = latest.sets.allSatisfy { set in
            guard let rir = Strength.observedRir(set) else { return false }
            return set.reps >= input.reps.max && rir >= input.rir - input.policy.rirTolerance
        }

        let lastTwo = Array(exposures.suffix(2))
        let repeatedLow = lastTwo.count == 2 && lastTwo.allSatisfy { exposure in
            let at = ISOTime.parse(exposure.session.completedAt) ?? 0
            guard now - at <= input.policy.staleAfterDays * DAY_MS,
                  Volume.completedPairs(exposure.sets) >= Double(input.requiredSets),
                  exposure.sets.allSatisfy({ same($0.resistance) })
            else { return false }
            let under = exposure.sets.filter {
                $0.reps < input.reps.min && (Strength.observedRir($0) ?? 10) <= input.rir
            }.count
            return Double(under) > Double(exposure.sets.count) / 2
        }

        if !top && !repeatedLow { return hold(.withinRange) }

        let assistance = load.type == .assistance
        guard let next = adjacentLoad(loadKg, grid, up: top ? !assistance : assistance) else {
            return hold(.gridUnavailable)
        }

        let permittedFraction = top ? input.policy.maxLoadIncreaseFraction : input.policy.reductionFraction
        let coarseStep = abs(next - loadKg) > Swift.max(loadKg, 1) * permittedFraction

        if coarseStep {
            if !top { return hold(.incrementTooLarge) }
            let extendedMax = Swift.min(50, input.reps.max + input.policy.coarseGridMaxExtraReps)
            let completedFloor = latest.sets.map(\.reps).min() ?? 0

            if completedFloor < extendedMax {
                let upper = Swift.min(extendedMax, Swift.max(input.reps.max + 1, completedFloor + 1))
                return recommendation(
                    input,
                    action: .increaseReps,
                    resistance: load,
                    targetReps: RepRange(min: input.reps.min, max: upper),
                    confidence: .low,
                    reasons: [.coarseLoadGrid]
                )
            }

            let strongAtExtended = exposures
                .suffix(input.policy.coarseGridRequiredTopExposures)
                .filter { exposure in
                    let at = ISOTime.parse(exposure.session.completedAt) ?? 0
                    guard now - at <= input.policy.staleAfterDays * DAY_MS,
                          Volume.completedPairs(exposure.sets) >= Double(input.requiredSets)
                    else { return false }
                    return exposure.sets.allSatisfy { set in
                        same(set.resistance)
                            && set.reps >= extendedMax
                            && (Strength.observedRir(set) ?? -1) >= input.rir - input.policy.rirTolerance
                    }
                }
                .count

            if strongAtExtended < input.policy.coarseGridRequiredTopExposures {
                return recommendation(
                    input,
                    action: .coarseGridProgression,
                    resistance: load,
                    targetReps: RepRange(min: input.reps.min, max: extendedMax),
                    confidence: .low,
                    reasons: [.coarseLoadGrid],
                    suggestedStrategies: [.continueRepetitionProgression]
                )
            }

            if abs(next - loadKg) > Swift.max(loadKg, 1) * input.policy.coarseGridMaxLoadIncreaseFraction {
                return recommendation(
                    input,
                    action: .coarseGridProgression,
                    resistance: load,
                    targetReps: RepRange(min: input.reps.min, max: extendedMax),
                    confidence: .medium,
                    reasons: [.coarseGridRequiresAlternativeProgression],
                    suggestedStrategies: [
                        .continueRepetitionProgression,
                        .useSmallerIncrementIfAvailable,
                        .useDifferentVariation,
                    ]
                )
            }
        }

        var nextResistance = load
        nextResistance.kg = next
        let action: ProgressionAction = top
            ? (assistance ? .reduceAssistance : .increaseLoad)
            : (assistance ? .increaseAssistance : .decreaseLoad)
        let reason: ProgressionReason = coarseStep
            ? .coarseLoadGrid
            : (top ? .topOfRange : .repeatedUnderperformance)

        return recommendation(
            input,
            action: action,
            resistance: nextResistance,
            confidence: .medium,
            reasons: [reason]
        )
    }

    static func recommend(_ input: ProgressionInput) -> ProgressionRecommendation {
        let tracking = input.exercise.metadata.tracking
        return (tracking == .externalLoad || tracking == .assistance)
            ? doubleProgression(input)
            : repProgression(input)
    }
}
