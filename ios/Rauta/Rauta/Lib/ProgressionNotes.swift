import Foundation

/// The engine's recommendation, in one line RAUTA can say. Every line is a
/// translation of a reason the engine actually returned, and nothing is added
/// on top. If a reason is ever added to the engine and not here, the line is
/// simply omitted: silence is the only honest fallback.
struct ProgressionNote {
    /// The load to put on, when the engine could name one.
    var kg: Double?
    /// Whether that load is measured on one implement or on the pair.
    var basis: LoadBasis?
    var text: String
}

enum ProgressionNotes {
    private static func delta(_ recommendation: ProgressionRecommendation, _ previousKg: Double) -> String? {
        guard let kg = recommendation.resistance.kg else { return nil }
        let difference = abs(kg - previousKg)
        return difference > 0 ? "\(Resistance.formatKg(difference)) kg" : nil
    }

    /// - Parameter previousKg: The load the recommendation moved away from,
    ///   when the caller knows it. Only used to say how large the step is.
    static func note(
        _ recommendation: ProgressionRecommendation,
        previousKg: Double? = nil
    ) -> ProgressionNote? {
        let action = recommendation.action
        let reason = recommendation.reasons.first
        let kg = recommendation.resistance.kg
        let basis = recommendation.resistance.basis
        let targetReps = recommendation.targetReps
        let step = previousKg.flatMap { delta(recommendation, $0) }

        func note(_ text: String) -> ProgressionNote {
            ProgressionNote(kg: kg, basis: basis, text: text)
        }

        switch action {
        case .increaseLoad:
            if reason == .coarseLoadGrid {
                return note("Last time every set reached the top of the range; the smallest step this equipment offers is\(step.map { " \($0)" } ?? " the next one"). Take it.")
            }
            return note("Last time every set reached the top of the range with reps to spare\(step.map { ", so add \($0)" } ?? ", so add a step").")

        case .decreaseLoad:
            return note(
                "The last two sessions fell short of the range\(step.map { ", so take off \($0)" } ?? ", so take off a step") and build back up."
            )

        case .reduceAssistance:
            return note("Last time every set reached the top of the range\(step.map { ", so use \($0) less assistance" } ?? ", so use less assistance").")

        case .increaseAssistance:
            return note("The last two sessions fell short of the range\(step.map { ", so use \($0) more assistance" } ?? ", so use more assistance").")

        case .increaseReps:
            if reason == .coarseLoadGrid {
                return note(
                    "The next load up is a big jump, so add reps first — up to \(Num.trimmed(targetReps.max)) at this load."
                )
            }
            return note("Last time every set reached the top of the range. Aim for \(Num.trimmed(targetReps.max)) reps this time.")

        case .coarseGridProgression:
            return note(
                "This equipment jumps too far in one step. Keep the load and work up to "
                    + "\(Num.trimmed(targetReps.max)) reps first."
            )

        case .hold:
            switch reason {
            case .incompleteSets: return note("Not every set was finished last time, so keep the same load.")
            case .missingEffort:
                return note("Reps left wasn't recorded last time, so RAUTA can't tell how hard it was and keeps the same load. Record reps left to progress.")
            case .incrementTooLarge: return note("A step down here is too big, so keep this load.")
            case .gridUnavailable: return note("RAUTA doesn't know this equipment's weight steps yet, so it keeps this load. Set them in Equipment › Load steps.")
            case .withinRange: return note("Keep this load until every set reaches the top of the range.")
            default: return nil
            }

        case .calibrate:
            switch reason {
            case .contextChanged: return note("Different equipment from last time, so this is a calibration: find a load that fits the target.")
            case .staleHistory: return note("It's been over four weeks, so this is a calibration: start easy and find the load again.")
            case .gridUnavailable: return note("Set this equipment's load step and RAUTA can progress it.")
            // No history is not a remark. The card already opens on the plan's
            // reps with the load at zero, which says the same thing.
            default: return nil
            }
        }
    }
}
