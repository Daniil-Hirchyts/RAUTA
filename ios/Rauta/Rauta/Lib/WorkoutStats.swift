import Foundation

enum WorkoutStats {
    /// Moderate-to-vigorous resistance training, expressed as a MET estimate.
    private static let strengthTrainingMET = 6.0
    private static let fallbackBodyWeightKg = 75.0

    /// Standard MET energy estimate: MET × 3.5 × kilograms / 200 × minutes.
    /// HealthKit weight is used when available; the conservative fallback keeps
    /// history useful without pretending the number is a measurement.
    static func estimateStrengthCalories(_ durationMs: Double, bodyWeightKg: Double?) -> Double {
        let minutes = Swift.max(0, durationMs) / 60_000
        let kilograms: Double = {
            if let bodyWeightKg, bodyWeightKg >= 30, bodyWeightKg <= 300 { return bodyWeightKg }
            return fallbackBodyWeightKg
        }()
        let estimate = (strengthTrainingMET * 3.5 * kilograms * minutes / 200).rounded()
        return Swift.max(durationMs > 0 ? 1 : 0, estimate)
    }
}
