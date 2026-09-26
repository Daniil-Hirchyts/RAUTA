import Foundation

/// A small, optional signal from recent Health samples. Missing data remains
/// missing; RAUTA never turns it into a medical conclusion or records pain.
nonisolated struct HealthReadinessSnapshot: Sendable, Equatable {
    var sleepHours: Double?
    var hrvTodayMs: Double?
    var hrvBaselineMs: Double?
    var restingHeartRateToday: Double?
    var restingHeartRateBaseline: Double?
    var exerciseMinutesYesterday: Double?
    var activeEnergyYesterday: Double?
}

nonisolated struct ReadinessSummary: Sendable, Equatable {
    var readiness: Readiness
    var reasons: [String]
}

nonisolated enum ReadinessMapper {
    static func map(_ snapshot: HealthReadinessSnapshot) -> ReadinessSummary? {
        var reasons: [String] = []
        var low = false
        var hasSignal = false
        if let hours = snapshot.sleepHours {
            hasSignal = true
            if hours < 6 { low = true; reasons.append("Less than 6 hours of sleep recorded") }
            else { reasons.append("\(String(format: "%.1f", hours)) hours of sleep recorded") }
        }
        if let today = snapshot.hrvTodayMs, let baseline = snapshot.hrvBaselineMs,
           baseline > 0 {
            hasSignal = true
            if today < baseline * 0.85 {
                low = true
                reasons.append("HRV is below your recent average")
            }
        }
        if let today = snapshot.restingHeartRateToday,
           let baseline = snapshot.restingHeartRateBaseline, baseline > 0 {
            hasSignal = true
            if today > baseline * 1.10 {
                low = true
                reasons.append("Resting heart rate is above your recent average")
            }
        }
        guard hasSignal else { return nil }
        if reasons.isEmpty { reasons.append("Recent sleep and heart signals are near your usual range") }
        return ReadinessSummary(
            readiness: Readiness(perceivedReadiness: low ? .low : .normal,
                                 soreness: nil, pain: nil),
            reasons: reasons
        )
    }
}
