import Foundation

/// A ready-made request, from what the app knows right now. Some are sent as
/// they are; others need a last word, and land in the field to finish.
struct AgentSuggestion: Identifiable {
    var title: String
    var prompt: String
    var sends: Bool
    var systemImage: String
    var id: String { title }

    @MainActor
    static func current() -> [AgentSuggestion] {
        let active = ActiveWorkoutStore.shared.session
        if let active {
            var list: [AgentSuggestion] = []
            if let current = active.currentExerciseId.flatMap({ ExerciseCatalogue.byId[$0] }) {
                list.append(.init(title: "Swap \(current.name.capitalized)",
                                  prompt: "Swap \(current.name) for something else", sends: true,
                                  systemImage: "arrow.triangle.2.circlepath"))
            }
            list.append(.init(title: "Rest 2 minutes", prompt: "Start a 2 minute rest", sends: true,
                              systemImage: "timer"))
            list.append(.init(title: active.runningSince == nil ? "Resume" : "Pause",
                              prompt: active.runningSince == nil ? "Resume my workout" : "Pause my workout",
                              sends: true,
                              systemImage: active.runningSince == nil ? "play" : "pause"))
            list.append(.init(title: "Finish workout", prompt: "Finish my workout", sends: true,
                              systemImage: "flag.checkered"))
            return list
        }
        let today = CalendarDate.today
        let next = WorkoutTimeline(
            workouts: WorkoutsStore.shared.workouts,
            records: TrainingRecordsStore.shared.data,
            activeWorkoutId: nil
        ).upcoming.first { $0.date >= today }

        var list: [AgentSuggestion] = [
            .init(title: "What's coming up?", prompt: "What's on my schedule?", sends: true,
                  systemImage: "calendar"),
        ]
        if let next {
            let day = next.date == today ? "today's" : CalendarDate.format(next.date, "EEEE") + "'s"
            list.append(.init(title: "Move \(day) workout…", prompt: "Move \(day) workout to ", sends: false,
                              systemImage: "arrow.right.circle"))
            list.append(.init(title: "Remind me", prompt: "Remind me about \(day) workout", sends: true,
                              systemImage: "bell"))
        }
        if let source = TrainingPlan.activeProgramRecord(),
           !TrainingWorkflow.remainingTrainingSlots(source, ISOTime.now()).sessions.isEmpty {
            list.append(.init(title: "Adjust my week", prompt: "Adjust the rest of my week", sends: true,
                              systemImage: "slider.horizontal.3"))
        }
        list.append(.init(title: "Build a workout…", prompt: "Build a workout for today focusing on ",
                          sends: false, systemImage: "dumbbell"))
        list.append(.init(title: "New plan…", prompt: "Make me a new plan with ", sends: false,
                          systemImage: "calendar.badge.plus"))
        return list
    }
}
