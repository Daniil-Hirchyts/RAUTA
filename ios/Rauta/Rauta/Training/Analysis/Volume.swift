import Foundation

typealias MuscleVolumeMap = [MuscleId: MuscleVolume]

nonisolated enum Volume {
    static func empty() -> MuscleVolumeMap {
        var volume: MuscleVolumeMap = [:]
        for muscle in MuscleId.allCases {
            volume[muscle] = MuscleVolume(direct: 0, indirect: 0, effective: 0)
        }
        return volume
    }

    static func effectiveSetCredit(
        _ exercise: IndexedExercise,
        _ muscle: MuscleId,
        _ policy: TrainingPolicy
    ) -> MuscleVolume {
        let role = exercise.metadata.setRoles.first { $0.muscleId == muscle }?.role
        let direct: Double = role == .direct ? 1 : 0
        let indirect: Double = role == .indirect ? policy.indirectCredit : 0
        return MuscleVolume(direct: direct, indirect: indirect, effective: direct + indirect)
    }

    static func isWorkingSet(_ set: CompletedSet) -> Bool {
        set.completed && set.reps > 0 && (set.setType == .working || set.setType == .backoff)
    }

    static func addExerciseVolume(
        _ volume: inout MuscleVolumeMap,
        _ exercise: IndexedExercise,
        _ count: Double,
        _ policy: TrainingPolicy
    ) {
        for role in exercise.metadata.setRoles {
            let credit: Double
            switch role.role {
            case .direct: credit = count
            case .indirect: credit = count * policy.indirectCredit
            case .incidental: credit = 0
            }
            var entry = volume[role.muscleId] ?? MuscleVolume(direct: 0, indirect: 0, effective: 0)
            if role.role == .direct { entry.direct += credit }
            if role.role == .indirect { entry.indirect += credit }
            entry.effective += credit
            volume[role.muscleId] = entry
        }
    }

    private static func setTime(_ set: CompletedSet, _ session: CompletedSession) -> Double {
        ISOTime.parse(set.timestamp ?? session.completedAt) ?? .nan
    }

    private static func inWindow(_ time: Double, _ from: Double, _ to: Double, _ inclusiveStart: Bool) -> Bool {
        guard time.isFinite else { return false }
        return (inclusiveStart ? time >= from : time > from) && time <= to
    }

    static func historyVolume(
        _ history: TrainingHistory,
        _ index: ExerciseIndex,
        _ policy: TrainingPolicy,
        from: Double,
        to: Double,
        inclusiveStart: Bool = false
    ) -> MuscleVolumeMap {
        var volume = empty()
        for session in history.sessions {
            for performed in session.exercises {
                guard let exercise = index.byId[performed.exerciseId] else { continue }
                for set in performed.sets where isWorkingSet(set)
                    && inWindow(setTime(set, session), from, to, inclusiveStart) {
                    addExerciseVolume(&volume, exercise, set.side == .both ? 1 : 0.5, policy)
                }
            }
        }
        return volume
    }

    static func historyFrequency(
        _ history: TrainingHistory,
        _ index: ExerciseIndex,
        _ policy: TrainingPolicy,
        from: Double,
        to: Double,
        inclusiveStart: Bool = false
    ) -> [MuscleId: Double] {
        var frequency: [MuscleId: Double] = [:]
        for muscle in MuscleId.allCases { frequency[muscle] = 0 }

        for session in history.sessions {
            var volume = empty()
            for performed in session.exercises {
                guard let exercise = index.byId[performed.exerciseId] else { continue }
                for set in performed.sets where isWorkingSet(set)
                    && inWindow(setTime(set, session), from, to, inclusiveStart) {
                    addExerciseVolume(&volume, exercise, set.side == .both ? 1 : 0.5, policy)
                }
            }
            for muscle in MuscleId.allCases
            where (volume[muscle]?.effective ?? 0) >= policy.meaningfulExposureSets {
                frequency[muscle, default: 0] += 1
            }
        }
        return frequency
    }

    static func historyExerciseFrequency(
        _ history: TrainingHistory,
        _ policy: TrainingPolicy,
        from: Double,
        to: Double,
        inclusiveStart: Bool = false
    ) -> [String: Double] {
        var frequency: [String: Double] = [:]
        for session in history.sessions {
            for performed in session.exercises {
                let units = performed.sets.reduce(0.0) { sum, set in
                    inWindow(setTime(set, session), from, to, inclusiveStart)
                        ? sum + completedWorkingSetUnits(set)
                        : sum
                }
                if units >= policy.meaningfulExposureSets {
                    frequency[performed.exerciseId, default: 0] += 1
                }
            }
        }
        return frequency
    }

    static func sessionVolume(
        _ exercises: [PlannedExercise],
        _ index: ExerciseIndex,
        _ policy: TrainingPolicy
    ) -> MuscleVolumeMap {
        var volume = empty()
        for planned in exercises {
            guard let exercise = index.byId[planned.exerciseId] else { continue }
            let count = Double(planned.workingSets.filter { $0.setType != .warmup }.count)
            addExerciseVolume(&volume, exercise, count, policy)
        }
        return volume
    }

    static func programVolume(
        _ program: TrainingProgram,
        _ index: ExerciseIndex
    ) -> [(weekId: String, muscles: MuscleVolumeMap)] {
        program.weeks.map { week in
            var total = empty()
            for session in week.sessions {
                let sessionTotals = sessionVolume(session.exercises, index, program.policy)
                for muscle in MuscleId.allCases {
                    guard let part = sessionTotals[muscle] else { continue }
                    var entry = total[muscle] ?? MuscleVolume(direct: 0, indirect: 0, effective: 0)
                    entry.direct += part.direct
                    entry.indirect += part.indirect
                    entry.effective += part.effective
                    total[muscle] = entry
                }
            }
            return (weekId: week.id, muscles: total)
        }
    }

    static func programFrequency(
        _ program: TrainingProgram,
        _ index: ExerciseIndex
    ) -> [(weekId: String, muscles: [MuscleId: Double])] {
        program.weeks.map { week in
            let perSession = week.sessions.map {
                sessionVolume($0.exercises, index, program.policy)
            }
            var muscles: [MuscleId: Double] = [:]
            for muscle in MuscleId.allCases {
                muscles[muscle] = Double(perSession.filter {
                    ($0[muscle]?.effective ?? 0) >= program.policy.meaningfulExposureSets
                }.count)
            }
            return (weekId: week.id, muscles: muscles)
        }
    }

    /// Paired muscle-group set units; distinct left/right records each contribute half.
    static func completedWorkingSetUnits(_ set: CompletedSet) -> Double {
        isWorkingSet(set) ? (set.side == .both ? 1 : 0.5) : 0
    }

    static func completedPairs(_ sets: [CompletedSet]) -> Double {
        let working = sets.filter(isWorkingSet)
        let both = working.filter { $0.side == .both }.count
        let left = working.filter { $0.side == .left }.count
        let right = working.filter { $0.side == .right }.count
        return Double(both + Swift.min(left, right))
    }
}
