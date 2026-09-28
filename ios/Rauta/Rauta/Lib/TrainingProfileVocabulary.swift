import Foundation

/// The vocabulary the profile screens speak, taken from the engine rather than
/// restated next to it: the domain decides which goals, experience levels,
/// priority levels and health limitations exist, and this file only says how
/// each one is worded for a person.
struct ProfileChoice {
    var title: String
    var description: String
}

enum ProfileVocabulary {
    /// Declaration order is the presentation order; the policy decides which of
    /// those goals the planner can actually carry.
    static let goalChoices: [(goal: TrainingGoal, choice: ProfileChoice)] = [
        (.hypertrophy, ProfileChoice(
            title: "Build muscle", description: "Moderate reps, more weekly volume"
        )),
        (.strength, ProfileChoice(
            title: "Get stronger", description: "Heavier sets, longer rests"
        )),
        (.strengthHypertrophy, ProfileChoice(
            title: "Strength & size", description: "A mix of both"
        )),
        (.generalFitness, ProfileChoice(
            title: "General fitness", description: "Balanced, easier to keep up"
        )),
        (.fatLossSupport, ProfileChoice(
            title: "Support fat loss", description: "Keep muscle while eating less"
        )),
        (.muscularEndurance, ProfileChoice(
            title: "Muscular endurance", description: "Higher reps, shorter rests"
        )),
    ]

    static let supportedGoals: [TrainingGoal] = goalChoices
        .map(\.goal)
        .filter { DEFAULT_POLICY.goals[$0.rawValue] != nil }

    static func choice(for goal: TrainingGoal) -> ProfileChoice {
        goalChoices.first { $0.goal == goal }?.choice
            ?? ProfileChoice(title: goal.rawValue, description: "")
    }

    static func goalLabel(_ goal: TrainingGoal) -> String { choice(for: goal).title }

    static let experienceChoices: [(experience: Experience, choice: ProfileChoice)] = [
        (.beginner, ProfileChoice(
            title: "Beginner", description: "New to lifting, or back after a long break"
        )),
        (.intermediate, ProfileChoice(
            title: "Intermediate", description: "Training regularly for a year or so"
        )),
        (.advanced, ProfileChoice(
            title: "Advanced", description: "Years of consistent, structured training"
        )),
    ]

    static func choice(for experience: Experience) -> ProfileChoice {
        experienceChoices.first { $0.experience == experience }?.choice
            ?? ProfileChoice(title: experience.rawValue, description: "")
    }

    static func experienceLabel(_ experience: Experience) -> String {
        choice(for: experience).title
    }

    static let healthLimitationLabels: [(limitation: HealthLimitation, label: String)] = [
        (.activeInjury, "Injury I am training around"),
        (.rehabilitation, "In rehabilitation"),
        (.medicalCondition, "A relevant medical condition"),
        (.pregnancy, "Pregnant or postpartum"),
        (.other, "Something else"),
    ]

    static func label(for limitation: HealthLimitation) -> String {
        healthLimitationLabels.first { $0.limitation == limitation }?.label
            ?? limitation.rawValue
    }

    /// What the picker asks about. `other` stays in the vocabulary — a profile
    /// that already carries it still reads, and still stops the planner — but it
    /// is not offered: "something else" is the box people tick instead of the
    /// one that fits, and nobody can act on a limitation nobody has named.
    static let healthLimitations: [HealthLimitation] = healthLimitationLabels
        .map(\.limitation)
        .filter { $0 != .other }

    static let priorityLevelLabels: [MusclePriorityLevel: String] = [
        .low: "Less",
        .normal: "Normal",
        .high: "More",
        .specialization: "Focus",
    ]

    static func label(for level: MusclePriorityLevel) -> String {
        priorityLevelLabels[level] ?? level.rawValue
    }

    /// Ordered by how much weekly volume each level asks for, so the chips read
    /// left to right the way the engine weights them.
    static let priorityLevels: [MusclePriorityLevel] = MusclePriorityLevel.allCases
        .sorted { DEFAULT_POLICY.priorityMultiplier($0) < DEFAULT_POLICY.priorityMultiplier($1) }

    /// Singling a muscle out is a statement, so the first tap makes it the most
    /// the engine will spend on one. The second steps down to more than usual,
    /// and the third hands the muscle back to the engine's own weighting.
    private static let priorityCycle: [MusclePriorityLevel?] = [.specialization, .high, nil]

    /// The levels the map can hold, strongest first.
    static let selectablePriorityLevels: [MusclePriorityLevel] = priorityCycle.compactMap { $0 }

    static func nextPriorityLevel(_ current: MusclePriorityLevel?) -> MusclePriorityLevel? {
        let index = priorityCycle.firstIndex { $0 == current } ?? -1
        return priorityCycle[(index + 1) % priorityCycle.count]
    }

    /// The palest a prioritised muscle is ever drawn. Below this the figure
    /// reads as unpainted rather than as trained less.
    private static let minPaint = 0.42

    /// How strongly each level paints on the body map, spread across the
    /// engine's own multipliers so the map darkens in the order the planner
    /// weights.
    static let priorityPaintWeights: [MusclePriorityLevel: Double] = {
        let multipliers = selectablePriorityLevels.map { DEFAULT_POLICY.priorityMultiplier($0) }
        let lowest = multipliers.min() ?? 0
        let spread = (multipliers.max() ?? 0) - lowest
        let denominator = spread == 0 ? 1 : spread
        var weights: [MusclePriorityLevel: Double] = [:]
        for level in priorityLevels {
            let share = Num.clamp((DEFAULT_POLICY.priorityMultiplier(level) - lowest) / denominator)
            weights[level] = ((minPaint + (1 - minPaint) * share) * 1000).rounded() / 1000
        }
        return weights
    }()

    /// The dial starts where the planner does: `planningEligibility` refuses
    /// under-18s, and the request validator accepts an age up to 120.
    static let profileAge = NumericRange(min: 18, max: 75, step: 1)
    /// What the age dial paints, as opposed to what it accepts.
    static let profileAgeScale = (min: 0.0, max: 100.0)

    /// Whole five-minute steps across the range a single session realistically
    /// runs; the engine validates 1–300 minutes.
    static let sessionDuration = NumericRange(min: 20, max: 120, step: 5)
    /// What the session dial paints: the quarter hour either side of what the
    /// app will plan, greyed out.
    static let sessionDurationScale = (min: 0.0, max: 140.0)
}

/// The nearest value a stepped control can actually hold. Shared by the rotary
/// knob and by the stores that persist what it produced, so a restored value
/// always lands on the same notch a finger could have reached.
struct NumericRange {
    var min: Double
    var max: Double
    var step: Double

    func snap(_ value: Double?) -> Double {
        let numeric = (value?.isFinite == true) ? value! : min
        let stepped = min + ((numeric - min) / step).rounded() * step
        // Binary floating point turns 20 + 13 * 2.5 into 52.500000000000004;
        // the control only ever offers values a person could read off it.
        let rounded = (stepped * 1e6).rounded() / 1e6
        return Swift.min(max, Swift.max(min, rounded))
    }
}
