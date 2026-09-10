import Foundation

enum WorkoutSharing {
    static func title(_ workout: Workout) -> String {
        "RAUTA workout — \(CalendarDate.long(workout.date))"
    }

    static func text(_ workout: Workout) -> String {
        let date = CalendarDate.long(workout.date)
        let exercises = workout.exerciseIds.enumerated().flatMap { index, id -> [String] in
            guard let exercise = ExerciseCatalogue.byId[id] else { return [] }
            return [
                "\(index + 1). \(Wording.titleCase(exercise.name))",
                "   \(Wording.titleCase(exercise.equipment))",
            ]
        }
        return ([date, ""] + exercises + ["", "Shared from RAUTA"]).joined(separator: "\n")
    }
}
