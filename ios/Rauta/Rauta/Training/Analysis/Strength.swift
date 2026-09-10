import Foundation

struct ExerciseExposure {
    var session: CompletedSession
    var sets: [CompletedSet]
    var allSets: [CompletedSet]
}

enum Strength {
    /// Effort as reps in reserve, however the set recorded it.
    static func observedRir(_ set: CompletedSet) -> Double? {
        if let rir = set.rir { return rir }
        if let rpe = set.rpe { return 10 - rpe }
        return nil
    }

    enum Estimator: String {
        case epley, brzycki
    }

    static func estimate(_ set: CompletedSet, using estimator: Estimator) -> StrengthEstimate? {
        let rir = observedRir(set)
        guard Volume.isWorkingSet(set),
              set.side == .both,
              set.resistance.type == .externalLoad,
              let kg = set.resistance.kg, kg.isFinite, kg > 0,
              set.reps == set.reps.rounded(), set.reps >= 1, set.reps <= 10,
              let rir, rir >= 0, rir <= 2
        else { return nil }

        let actual = set.reps == 1 && rir == 0
        let value: Double
        if actual {
            value = kg
        } else if estimator == .epley {
            value = kg * (1 + set.reps / 30)
        } else {
            value = (kg * 36) / (37 - set.reps)
        }
        return StrengthEstimate(
            estimated1RMKg: value,
            confidence: actual ? .high : .low,
            estimator: estimator.rawValue,
            source: actual ? .actual1RM : .estimatedFromSet
        )
    }

    static func exposures(
        _ history: TrainingHistory,
        _ exerciseId: String,
        _ now: String
    ) -> [ExerciseExposure] {
        let cutoff = ISOTime.parse(now) ?? .greatestFiniteMagnitude
        return history.sessions
            .filter { (ISOTime.parse($0.completedAt) ?? .infinity) <= cutoff }
            .compactMap { session -> ExerciseExposure? in
                guard let performed = session.exercises.first(where: { $0.exerciseId == exerciseId }),
                      performed.sets.contains(where: Volume.isWorkingSet)
                else { return nil }
                return ExerciseExposure(
                    session: session,
                    sets: performed.sets.filter(Volume.isWorkingSet),
                    allSets: performed.sets
                )
            }
            .sorted { left, right in
                let a = ISOTime.parse(left.session.completedAt) ?? 0
                let b = ISOTime.parse(right.session.completedAt) ?? 0
                if a != b { return a < b }
                return compareIds(left.session.id, right.session.id) < 0
            }
    }

    static func analyzePerformance(
        _ history: TrainingHistory,
        _ exerciseId: String,
        _ now: String,
        _ policy: TrainingPolicy,
        allowStrengthEstimates: Bool = true
    ) -> ExercisePerformanceState {
        let all = exposures(history, exerciseId, now)
        let latest = all.last
        let latestLoad = latest?.sets.last?.resistance
        let nowMillis = ISOTime.parse(now) ?? 0

        var estimates: [Double] = []
        if allowStrengthEstimates {
            for exposure in all {
                let completedAt = ISOTime.parse(exposure.session.completedAt) ?? 0
                if nowMillis - completedAt > policy.staleAfterDays * DAY_MS { continue }
                let values = exposure.sets
                    .filter { set in
                        set.resistance.type == .externalLoad
                            && latestLoad?.type == .externalLoad
                            && set.resistance.stationId == latestLoad?.stationId
                            && set.resistance.basis == latestLoad?.basis
                    }
                    .compactMap { estimate($0, using: .epley)?.estimated1RMKg }
                if let median = Num.median(values) { estimates.append(median) }
            }
        }

        let recent = Num.median(Array(estimates.suffix(3)))
        let previous: Double? = estimates.count >= 6
            ? Num.median(Array(estimates[(estimates.count - 6)..<(estimates.count - 3)]))
            : nil
        let relativeChange: Double? = {
            guard let previous, previous != 0, let recent else { return nil }
            return (recent - previous) / previous
        }()

        let trend: PerformanceTrend = {
            guard let relativeChange else { return .insufficientData }
            if relativeChange > policy.trendThreshold { return .improving }
            if relativeChange < -policy.trendThreshold { return .declining }
            return .stable
        }()

        return ExercisePerformanceState(
            exerciseId: exerciseId,
            bestEstimated1RM: estimates.isEmpty ? nil : estimates.max(),
            recentEstimated1RM: recent,
            recentResistance: latestLoad,
            recentRepPerformance: latest.flatMap { Num.median($0.sets.map(\.reps)) },
            recentRir: latest.flatMap { Num.median($0.sets.compactMap(observedRir)) },
            trend: trend,
            relativeChange: relativeChange,
            lastPerformedAt: latest?.session.completedAt,
            exposureCount: Double(all.count),
            confidence: estimates.count >= 6 ? .medium : (estimates.isEmpty ? .none : .low)
        )
    }
}
