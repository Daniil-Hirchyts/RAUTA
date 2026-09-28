import Foundation
import FoundationModels
import Testing
@testable import Rauta

/// Pins which tools the keyword router hands the model for a request, so the
/// router can be reorganised without changing what RAUTA can reach. The
/// expected lists were recorded from the router as it stood.
@MainActor
@Suite("Agent tool router")
struct AgentToolRouterTests {
    private func tools(_ input: String) -> [String] {
        AgentToolRouter.tools(for: input, host: AgentToolHost()).map(\.name)
    }

    @Test func requestsThatNeedATool() {
        #expect(AgentToolRouter.requiresTool("Move my workout to Friday"))
        #expect(AgentToolRouter.requiresTool("What's my next workout?"))
        #expect(AgentToolRouter.requiresTool("Show my current plan"))
        #expect(!AgentToolRouter.requiresTool("Hello there"))
        #expect(!AgentToolRouter.requiresTool("What is a deadlift?"))
        #expect(!AgentToolRouter.requiresTool("How many sets should I do?"))
    }

    @Test func routesEachRequestToItsTools() {
        let table: [(String, [String])] = [
            ("Remind me to train at 6", ["set_workout_reminder"]),
            ("Stop the workout reminder", ["remove_reminder"]),
            ("Finish my workout", ["propose_finish"]),
            ("Discard this workout", ["propose_discard"]),
            ("Delete tomorrow's workout", ["propose_delete", "edit_workout_exercises"]),
            ("Add face pulls to Thursday", ["edit_workout_exercises", "get_schedule"]),
            ("Adjust my week", ["propose_adjust_week", "propose_plan"]),
            ("Build a workout for legs", ["propose_workout", "propose_plan"]),
            ("What's inside today's workout?", ["get_workout", "get_schedule"]),
            ("Put it in my calendar", ["propose_calendar", "get_free_slots"]),
            ("When am I free this week?", ["get_free_slots", "propose_calendar"]),
            ("How is my readiness?", ["get_readiness", "propose_plan"]),
            ("Am I getting stronger on bench?", ["get_progress", "find_exercise"]),
            ("Log 8 reps at 60", ["log_set", "start_rest"]),
            ("Start a rest timer", ["start_rest", "log_set"]),
            ("Pause", ["pause_workout"]),
            ("Resume", ["resume_workout"]),
            ("I only have dumbbells", ["set_equipment", "find_exercise"]),
            ("Prioritize shoulders", ["set_muscle_priority", "update_profile"]),
            ("Change my goal", ["update_profile", "propose_plan"]),
            ("My knee hurts", ["find_alternatives", "find_exercise"]),
            ("Swap squats", ["swap_exercise", "find_alternatives", "find_exercise"]),
            ("Move Thursday to tomorrow", ["reschedule_workout", "get_schedule"]),
            ("Make a new plan, 3 days", ["propose_plan", "get_schedule"]),
            ("Start training", ["start_workout", "get_schedule"]),
            ("Find a chest exercise", ["find_exercise", "get_schedule"]),
            ("Hello", ["get_schedule", "find_exercise"]),
        ]
        for (input, expected) in table {
            #expect(tools(input) == expected, "\(input)")
        }
    }
}
