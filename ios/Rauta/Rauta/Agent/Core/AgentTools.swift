import Foundation
import FoundationModels

/// A tool returns by ending the turn. The host already holds the checked result,
/// so RAUTA never needs a second model pass to claim a change was made.
nonisolated struct AgentScheduleTool: Tool {
    let host: AgentToolHost
    let name = "get_schedule"
    let description = "Show the user's coming workouts."
    @Generable nonisolated struct Arguments {}
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.schedule()
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentWorkoutDetailsTool: Tool {
    let host: AgentToolHost
    let name = "get_workout"
    let description = "Show exercises in a scheduled workout."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Workout name or day as said.") var workout: String
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.workoutDetails(arguments.workout)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentAdjustWeekTool: Tool {
    let host: AgentToolHost
    let name = "propose_adjust_week"
    let description = "Preview changes to the remaining active week."
    @Generable nonisolated struct Arguments {}
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.proposeAdjustedWeek()
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentWorkoutProposalTool: Tool {
    let host: AgentToolHost
    let name = "propose_workout"
    let description = "Preview one new workout for muscles the user named."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Day as the user said it, or empty for today.") var day: String
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.proposeWorkout(arguments.day)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentFinishTool: Tool {
    let host: AgentToolHost
    let name = "propose_finish"
    let description = "Preview finishing the current workout."
    @Generable nonisolated struct Arguments {}
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.proposeFinish()
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentDiscardTool: Tool {
    let host: AgentToolHost
    let name = "propose_discard"
    let description = "Preview discarding the current workout."
    @Generable nonisolated struct Arguments {}
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.proposeDiscard()
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentDeleteTool: Tool {
    let host: AgentToolHost
    let name = "propose_delete"
    let description = "Preview deleting an upcoming workout."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Workout or day as the user said it.") var workout: String
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.proposeDelete(arguments.workout)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentFindExerciseTool: Tool {
    let host: AgentToolHost
    let name = "find_exercise"
    let description = "Search the exercise library."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Exercise or muscle as the user said it.") var query: String
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.findExercise(arguments.query)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentAlternativesTool: Tool {
    let host: AgentToolHost
    let name = "find_alternatives"
    let description = "Show fitting exercise replacements in a workout."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Exercise name as said.") var exercise: String
        @Guide(description: "Workout name, day or id as said; optional.") var workout: String?
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.alternatives(arguments.exercise, workoutPhrase: arguments.workout)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentSwapTool: Tool {
    let host: AgentToolHost
    let name = "swap_exercise"
    let description = "Replace one exercise in a workout with a fitting one."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Workout name, day or id as said.") var workout: String
        @Guide(description: "Exercise to replace as said.") var exercise: String
        @Guide(description: "New exercise if the user named one; otherwise omit.") var replacement: String?
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.swap(workoutPhrase: arguments.workout, exercisePhrase: arguments.exercise,
                        replacementPhrase: arguments.replacement)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentEditExercisesTool: Tool {
    let host: AgentToolHost
    let name = "edit_workout_exercises"
    let description = "Add or remove one named exercise from an upcoming workout."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Workout or day as said.") var workout: String
        @Guide(description: "Exercise name exactly as the user said it.") var exercise: String
        @Guide(description: "add or remove, matching the user's words.") var action: String
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.editExercises(workoutPhrase: arguments.workout, exercisePhrase: arguments.exercise,
                                 edit: ExerciseEdit(rawValue: arguments.action.lowercased()))
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentRescheduleTool: Tool {
    let host: AgentToolHost
    let name = "reschedule_workout"
    let description = "Move a workout to another day."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Workout name, current day or id as said.") var workout: String
        @Guide(description: "New day as said, for example Friday or tomorrow.") var day: String
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.reschedule(workoutPhrase: arguments.workout, dayPhrase: arguments.day)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentPlanTool: Tool {
    let host: AgentToolHost
    let name = "propose_plan"
    let description = "Build a training plan preview. The user must tap Apply."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Days per week only if the user said a number.") var daysPerWeek: Int?
        @Guide(description: "Session minutes only if the user said a number.") var sessionMinutes: Int?
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.proposePlan(daysPerWeek: arguments.daysPerWeek,
                               sessionMinutes: arguments.sessionMinutes)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentStartWorkoutTool: Tool {
    let host: AgentToolHost
    let name = "start_workout"
    let description = "Start a scheduled workout."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Workout name, day or id as said.") var workout: String
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.startWorkout(arguments.workout)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentProgressTool: Tool {
    let host: AgentToolHost
    let name = "get_progress"
    let description = "Show logged performance for one exercise."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Exercise name as said.") var exercise: String
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.progress(arguments.exercise)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentReadinessTool: Tool {
    let host: AgentToolHost
    let name = "get_readiness"
    let description = "Show recent Health readiness signals, with permission."
    @Generable nonisolated struct Arguments {}
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.readiness()
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentLogSetTool: Tool {
    let host: AgentToolHost
    let name = "log_set"
    let description = "Log a completed set in the running workout."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Exercise name as said.") var exercise: String
        @Guide(description: "Reps only if said by the user.") var reps: Int?
        @Guide(description: "Kilograms only if said by the user, including decimals.") var kilograms: Double?
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.logSet(exercisePhrase: arguments.exercise, reps: arguments.reps,
                          kilograms: arguments.kilograms)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentRestTool: Tool {
    let host: AgentToolHost
    let name = "start_rest"
    let description = "Start a rest timer in the running workout."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Number of seconds or minutes as said, or omit.") var duration: Int?
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.startRest(seconds: arguments.duration)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentPauseTool: Tool {
    let host: AgentToolHost
    let name = "pause_workout"
    let description = "Pause the running workout clock."
    @Generable nonisolated struct Arguments {}
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.setPaused(true)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentResumeTool: Tool {
    let host: AgentToolHost
    let name = "resume_workout"
    let description = "Resume the running workout clock."
    @Generable nonisolated struct Arguments {}
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.setPaused(false)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentProfileTool: Tool {
    let host: AgentToolHost
    let name = "update_profile"
    let description = "Change training goal or usual session minutes."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Goal phrase as said, or omit.") var goal: String?
        @Guide(description: "Minutes as said, or omit.") var minutes: Int?
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.updateProfile(goalPhrase: arguments.goal, minutes: arguments.minutes)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentPriorityTool: Tool {
    let host: AgentToolHost
    let name = "set_muscle_priority"
    let description = "Change emphasis on one muscle group."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Muscle as the user said it.") var muscle: String
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.setMusclePriority(arguments.muscle)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentEquipmentTool: Tool {
    let host: AgentToolHost
    let name = "set_equipment"
    let description = "Add, remove or replace gym equipment the user named."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Equipment names the user said.") var equipment: [String]
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.setEquipment(arguments.equipment)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentFreeSlotsTool: Tool {
    let host: AgentToolHost
    let name = "get_free_slots"
    let description = "Find open Calendar times on a day."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Day as the user said it.") var day: String
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.freeSlots(arguments.day)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentCalendarTool: Tool {
    let host: AgentToolHost
    let name = "propose_calendar"
    let description = "Preview adding a workout to Calendar; requires Apply."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Workout or day as the user said it.") var workout: String
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.proposeCalendar(arguments.workout)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentReminderTool: Tool {
    let host: AgentToolHost
    let name = "set_workout_reminder"
    let description = "Remind the user about an upcoming workout."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Workout or day as the user said it.") var workout: String
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.setReminder(arguments.workout)
        throw AgentTurnEnded()
    }
}

nonisolated struct AgentRemoveReminderTool: Tool {
    let host: AgentToolHost
    let name = "remove_reminder"
    let description = "Remove an existing workout reminder."
    @Generable nonisolated struct Arguments {
        @Guide(description: "Workout or day as the user said it.") var workout: String
    }
    @concurrent func call(arguments: Arguments) async throws -> String {
        await host.removeReminder(arguments.workout)
        throw AgentTurnEnded()
    }
}

@MainActor
enum AgentToolRouter {
    static func requiresTool(_ input: String) -> Bool {
        let words = Set(AgentWords.words(input))
        let commands: Set<String> = ["move", "reschedule", "swap", "replace", "start",
            "begin", "log", "pause", "resume", "remind", "notify", "delete", "remove",
            "create", "build", "adapt", "adjust", "set", "change", "add", "discard"]
        if !words.isDisjoint(with: commands) { return true }
        let trainingFacts: Set<String> = ["plan", "schedule", "workout", "exercise",
            "exercises", "progress", "readiness", "profile", "equipment"]
        return !words.isDisjoint(with: ["my", "mine", "next", "scheduled", "current"])
            && !words.isDisjoint(with: trainingFacts)
    }

    static func tools(for input: String, host: AgentToolHost) -> [any FoundationModels.Tool] {
        let words = Set(AgentWords.words(input))
        func has(_ choices: Set<String>) -> Bool { !words.isDisjoint(with: choices) }
        if has(["remind", "reminder", "notifications", "notify"]) {
            return has(["remove", "delete", "cancel", "stop"])
                ? [AgentRemoveReminderTool(host: host)]
                : [AgentReminderTool(host: host)]
        }
        if has(["finish", "complete"]) && has(["workout", "session", "training"]) {
            return [AgentFinishTool(host: host)]
        }
        if has(["discard", "abandon", "cancel"]) && has(["workout", "session", "training"]) {
            return [AgentDiscardTool(host: host)]
        }
        if has(["delete", "remove"]) && has(["workout", "session"]) {
            return [AgentDeleteTool(host: host), AgentEditExercisesTool(host: host)]
        }
        if has(["add", "remove"]) && has(["exercise", "exercises", "to", "from", "in"]) {
            return [AgentEditExercisesTool(host: host), AgentScheduleTool(host: host)]
        }
        if has(["adjust", "adapt", "reshape"]) && has(["week", "plan"]) {
            return [AgentAdjustWeekTool(host: host), AgentPlanTool(host: host)]
        }
        if has(["create", "build", "make"]) && has(["workout", "session"]) {
            return [AgentWorkoutProposalTool(host: host), AgentPlanTool(host: host)]
        }
        if has(["details", "inside", "what"]) && has(["workout", "session"]) {
            return [AgentWorkoutDetailsTool(host: host), AgentScheduleTool(host: host)]
        }
        if has(["calendar", "free", "available", "slot", "slots"]) {
            return has(["free", "available", "slot", "slots", "when"])
                ? [AgentFreeSlotsTool(host: host), AgentCalendarTool(host: host)]
                : [AgentCalendarTool(host: host), AgentFreeSlotsTool(host: host)]
        }
        if has(["readiness", "recovery", "recovered", "sleep", "hrv"]) {
            return [AgentReadinessTool(host: host), AgentPlanTool(host: host)]
        }
        if has(["progress", "stronger", "improving", "improved", "trend", "going", "last"]) {
            return [AgentProgressTool(host: host), AgentFindExerciseTool(host: host)]
        }
        if has(["log", "logged", "reps", "rep"]) {
            return [AgentLogSetTool(host: host), AgentRestTool(host: host)]
        }
        if has(["rest", "timer", "break"]) {
            return [AgentRestTool(host: host), AgentLogSetTool(host: host)]
        }
        if has(["pause"]) { return [AgentPauseTool(host: host)] }
        if has(["resume", "continue"]) { return [AgentResumeTool(host: host)] }
        if has(["equipment", "dumbbell", "dumbbells", "barbell", "barbells", "gym"]) {
            return [AgentEquipmentTool(host: host), AgentFindExerciseTool(host: host)]
        }
        if has(["priority", "prioritize", "emphasize", "focus"]) {
            return [AgentPriorityTool(host: host), AgentProfileTool(host: host)]
        }
        if has(["profile", "goal", "usual", "duration"]) {
            return [AgentProfileTool(host: host), AgentPlanTool(host: host)]
        }
        if has(["hurt", "hurts", "pain", "alternative", "alternatives"]) {
            return [AgentAlternativesTool(host: host), AgentFindExerciseTool(host: host)]
        }
        if has(["swap", "replace", "substitute"]) {
            return [AgentSwapTool(host: host), AgentAlternativesTool(host: host), AgentFindExerciseTool(host: host)]
        }
        if has(["move", "reschedule", "shift", "postpone", "calendar", "tomorrow"]) {
            return [AgentRescheduleTool(host: host), AgentScheduleTool(host: host)]
        }
        if has(["plan", "rebuild", "adapt", "adjust", "week", "weekly", "minutes", "min"]) {
            return [AgentPlanTool(host: host), AgentScheduleTool(host: host)]
        }
        if has(["start", "begin", "train"]) {
            return [AgentStartWorkoutTool(host: host), AgentScheduleTool(host: host)]
        }
        if has(["exercise", "exercises", "find", "search", "show"]) {
            return [AgentFindExerciseTool(host: host), AgentScheduleTool(host: host)]
        }
        return [AgentScheduleTool(host: host), AgentFindExerciseTool(host: host)]
    }
}
