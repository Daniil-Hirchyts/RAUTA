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
                return note("Smallest step here is\(step.map { " \($0)" } ?? ""). Take it.")
            }
            return note("You hit the top of the range last time.\(step.map { " +\($0)." } ?? "")")

        case .decreaseLoad:
            return note(
                "Two sessions short of the range.\(step.map { " −\($0)." } ?? "") Rebuild from here."
            )

        case .reduceAssistance:
            return note("Top of the range last time.\(step.map { " \($0) less assist." } ?? "")")

        case .increaseAssistance:
            return note("Short of the range twice.\(step.map { " \($0) more assist." } ?? "")")

        case .increaseReps:
            if reason == .coarseLoadGrid {
                return note(
                    "Next load up is a big jump. Add reps first — up to \(Num.trimmed(targetReps.max))."
                )
            }
            return note("Top of the range last time. Go for \(Num.trimmed(targetReps.max)) reps.")

        case .coarseGridProgression:
            return note(
                "This station jumps too far in one step. Hold the load and work to "
                    + "\(Num.trimmed(targetReps.max)) reps."
            )

        case .hold:
            switch reason {
            case .incompleteSets: return note("Last session came up short. Same load again.")
            case .missingEffort: return note("No RIR logged last time, so nothing to progress from.")
            case .incrementTooLarge: return note("A step down here is too big. Hold this load.")
            case .gridUnavailable: return note("I do not know this station's steps yet. Hold this load.")
            case .withinRange: return note("Keep this load until you reach the top of the range.")
            default: return nil
            }

        case .calibrate:
            switch reason {
            case .contextChanged: return note("Different station today — recalibrating.")
            case .staleHistory: return note("It has been a while. Find the load again, easy first set.")
            case .gridUnavailable: return note("Set this station's load step and I can progress it.")
            // No history is not a remark. The card already opens on the plan's
            // reps with the load at zero, which says the same thing.
            default: return nil
            }
        }
    }
}
