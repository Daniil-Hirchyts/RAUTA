import Foundation

/// The warm-up that opens a workout: a few short steps, each a part of the body
/// and what to do with it, picked for what the workout trains and sharing the
/// warm-up's time between them.
///
/// It starts by raising the pulse, then loosens what is about to work —
/// shoulders and chest before an upper-body day, hips and legs before a lower
/// one. The steps are shown, never logged: they are not part of the workout
/// and never enter its record.
enum WarmupRoutine {
    enum Region: Equatable { case upper, lower, full }

    /// A step as it is written: the part of the body, the movement in a word
    /// or two, how to do it in a few words, and the muscles it wakes up, which
    /// the body map lights.
    struct Plan: Hashable {
        var title: String
        var move: String
        var instruction: String
        var muscles: [MuscleId]
    }

    /// A step on the clock.
    struct Step: Hashable, Identifiable {
        var title: String
        var move: String
        var instruction: String
        var muscles: [MuscleId]
        /// When the step starts and ends, in seconds from the warm-up's start.
        var start: Double
        var end: Double

        var id: String { title }
        var seconds: Double { end - start }
    }

    /// Every warm-up opens with one of these, to raise the pulse.
    static let pulse: [Plan] = [
        Plan(
            title: "Raise your pulse",
            move: "Jog on the spot",
            instruction: "Knees a little higher as you go.",
            muscles: [.quadriceps, .hamstring, .calves, .gluteal]
        ),
        Plan(
            title: "Raise your pulse",
            move: "Jumping jacks",
            instruction: "Arms all the way up. Land softly.",
            muscles: [.quadriceps, .calves, .deltoids, .gluteal]
        ),
        Plan(
            title: "Raise your pulse",
            move: "March on the spot",
            instruction: "Swing your arms. Speed up halfway.",
            muscles: [.quadriceps, .hipFlexors, .calves, .deltoids]
        ),
    ]

    static let upper: [Plan] = [
        Plan(
            title: "Shoulders",
            move: "Arm circles",
            instruction: "Ten forwards, ten backwards.",
            muscles: [.deltoids, .trapezius]
        ),
        Plan(
            title: "Chest and upper back",
            move: "Hug and open",
            instruction: "Open wide, squeeze your shoulder blades.",
            muscles: [.chest, .upperBack, .serratus]
        ),
        Plan(
            title: "Arms and wrists",
            move: "Elbows and wrists",
            instruction: "Bend your elbows, then roll your wrists.",
            muscles: [.biceps, .triceps, .forearm]
        ),
        Plan(
            title: "Spine",
            move: "Torso twists",
            instruction: "Hands on hips. Keep your hips still.",
            muscles: [.obliques, .abs, .lowerBack]
        ),
    ]

    static let lower: [Plan] = [
        Plan(
            title: "Hips",
            move: "Leg swings",
            instruction: "Forwards and back, then side to side.",
            muscles: [.hipFlexors, .gluteal, .adductors]
        ),
        Plan(
            title: "Legs",
            move: "Bodyweight squats",
            instruction: "Slow. Chest up, knees over toes.",
            muscles: [.quadriceps, .gluteal, .hamstring]
        ),
        Plan(
            title: "Back of the legs",
            move: "Walkouts",
            instruction: "Walk out to a plank and back. Five times.",
            muscles: [.hamstring, .lowerBack, .calves]
        ),
        Plan(
            title: "Ankles and calves",
            move: "Ankle circles",
            instruction: "Both ways, then fifteen calf raises.",
            muscles: [.calves, .tibialis]
        ),
    ]

    static let full: [Plan] = [
        Plan(
            title: "Hips",
            move: "Leg swings",
            instruction: "Forwards and back, then side to side.",
            muscles: [.hipFlexors, .gluteal, .adductors]
        ),
        Plan(
            title: "Shoulders",
            move: "Arm circles",
            instruction: "Ten forwards, ten backwards.",
            muscles: [.deltoids, .trapezius, .chest]
        ),
        Plan(
            title: "Legs",
            move: "Bodyweight squats",
            instruction: "Slow. Chest up, knees over toes.",
            muscles: [.quadriceps, .gluteal, .hamstring]
        ),
        Plan(
            title: "Spine",
            move: "Torso twists",
            instruction: "Hands on hips. Keep your hips still.",
            muscles: [.obliques, .abs, .lowerBack]
        ),
    ]

    private static let upperMuscles: Set<MuscleId> = [
        .chest, .upperBack, .deltoids, .biceps, .triceps, .trapezius, .forearm, .serratus,
    ]
    /// The trunk works on both kinds of day, so it says nothing about which.
    private static let trunk: Set<MuscleId> = [.abs, .obliques, .lowerBack]

    /// Upper when seven in ten of the muscles the exercises train are upper
    /// body, lower when seven in ten are lower, the whole body otherwise.
    static func region(for exerciseIds: [String]) -> Region {
        var upperCount = 0
        var lowerCount = 0
        for id in exerciseIds {
            for muscle in ExerciseCatalogue.byId[id]?.muscles ?? [] where !trunk.contains(muscle) {
                if upperMuscles.contains(muscle) { upperCount += 1 } else { lowerCount += 1 }
            }
        }
        let total = upperCount + lowerCount
        guard total > 0 else { return .full }
        let share = Double(upperCount) / Double(total)
        if share >= 0.7 { return .upper }
        if share <= 0.3 { return .lower }
        return .full
    }

    /// The steps for a warm-up of `seconds` before these exercises: the pulse,
    /// then the parts about to work, in the order they loosen best — four
    /// steps, or five for a long warm-up. `seed` picks the pulse, varying it
    /// from workout to workout while one workout's warm-up stays the same.
    static func steps(for exerciseIds: [String], seconds: Double, seed: String) -> [Step] {
        guard seconds > 0 else { return [] }
        let count = seconds >= 600 ? 5 : 4
        let body: [Plan]
        switch region(for: exerciseIds) {
        case .upper: body = upper
        case .lower: body = lower
        case .full: body = full
        }
        let opener = pulse[Int(seed.stableHash % UInt64(pulse.count))]
        let plans = [opener] + body.prefix(count - 1)
        let share = seconds / Double(plans.count)
        return plans.enumerated().map { index, plan in
            Step(
                title: plan.title,
                move: plan.move,
                instruction: plan.instruction,
                muscles: plan.muscles,
                start: Double(index) * share,
                end: Double(index + 1) * share
            )
        }
    }

    /// The step for `elapsed` seconds into the warm-up; past the end, the last.
    static func current(_ steps: [Step], elapsed: Double) -> (index: Int, step: Step)? {
        guard !steps.isEmpty else { return nil }
        let index = steps.firstIndex { elapsed < $0.end } ?? steps.count - 1
        return (index, steps[index])
    }
}
