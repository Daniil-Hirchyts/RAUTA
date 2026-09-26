import Foundation
import Testing
@testable import Rauta

/// Plain requests are read in Swift and never wait on — or fail in — the model;
/// the model's own words are cleaned before RAUTA says them.
@Suite("Agent intents")
struct AgentIntentTests {
    private let today = "2026-09-26"

    private func read(_ text: String, running: Bool = false) -> AgentIntent? {
        AgentIntent.parse(text, today: today, running: running)
    }

    @Test func planRequestsAreReadWithoutTheModel() {
        #expect(read("What's coming up?") == .schedule)
        #expect(read("What's on my schedule?") == .schedule)
        #expect(read("What's on my schedule this week?") == .schedule)
        #expect(read("When is my next workout?") == .schedule)
        #expect(read("What's in tomorrow's workout?") == .workoutDetails)
        #expect(read("Build the workout for shoulders and legs") == .buildWorkout)
        #expect(read("Build a workout for today focusing on shoulders and legs") == .buildWorkout)
        #expect(read("I want to train shoulders today") == .buildWorkout)
        #expect(read("Make me a new plan, 3 days a week, 45 minutes") == .newPlan(days: 3, minutes: 45))
        #expect(read("Make the rest of my week lighter") == .adjustWeek)
        #expect(read("Make the rest of my week lighter", running: true) == .adjustWeek)
        #expect(read("Move Thursday's workout to Friday")
                == .reschedule(workout: "move thursday's workout", day: "friday"))
        #expect(read("Delete tomorrow's workout") == .deleteWorkout)
        #expect(read("Start today's workout") == .startWorkout)
    }

    @Test func exerciseChangesNameTheExerciseAsSaid() {
        #expect(read("Swap the lunges on Friday") == .swap(exercise: "lunges", replacement: nil))
        #expect(read("My knee hurts, swap the lunges on Friday") == .swap(exercise: "lunges", replacement: nil))
        #expect(read("Replace squats with leg press") == .swap(exercise: "squats", replacement: "leg press"))
        #expect(read("Swap barbell squat for something else") == .swap(exercise: "barbell squat", replacement: nil))
        #expect(read("Add face pulls to Thursday's workout") == .editExercise(exercise: "face pulls", adding: true))
        #expect(read("Remove curls from today's workout") == .editExercise(exercise: "curls", adding: false))
        #expect(read("How's my bench press going?") == .progress(exercise: "bench press"))
        #expect(read("What can I do for rear delts with dumbbells?") == .findExercises(query: "rear delts dumbbells"))
    }

    @Test func liveControlsOnlyWhileAWorkoutRuns() {
        #expect(read("Start a 2 minute rest", running: true) == .rest)
        #expect(read("Pause my workout", running: true) == .pause)
        #expect(read("Log 8 reps at 60 kg", running: true) == .logSet(exercise: nil, reps: 8, kilograms: 60))
        #expect(read("Finish my workout", running: true) == .finishWorkout)
        #expect(read("Take a rest day tomorrow") != .rest)
    }

    @Test func appleFeaturesAndSettings() {
        #expect(read("Remind me about Sunday's workout") == .reminder)
        #expect(read("Remind me") == .reminder)
        #expect(read("Cancel the reminder for tomorrow") == .removeReminder)
        #expect(read("Add it to my calendar") == .addToCalendar)
        #expect(read("When am I free tomorrow?") == .freeSlots)
        #expect(read("Am I recovered enough to train hard today?") == .readiness)
        #expect(read("I only have dumbbells") == .equipment)
        #expect(read("Prioritize glutes") == .priority)
        #expect(read("Change my goal to strength") == .profile(minutes: nil))
    }

    @Test func smallTalkAndAdviceStayOutOfTools() {
        #expect(read("hi") == .greeting)
        #expect(read("Thanks!") == .thanks)
        #expect(read("What can you do?") == .help)
        #expect(read("Is it bad to train with sore legs?") == nil)
        #expect(read("What should I eat after training?") == nil)
        // After a model failure, a named muscle is still worth a workout.
        #expect(AgentIntent.parse("legs please", today: today, running: false, loose: true) == .buildWorkout)
    }

    @Test func quantitiesAreReadWithTheirUnits() {
        #expect(AgentWords.minutes(in: "sessions of 45 minutes") == 45)
        #expect(AgentWords.minutes(in: "about an hour") == 60)
        #expect(AgentWords.minutes(in: "half an hour") == 30)
        #expect(AgentWords.count(of: ["days", "times"], in: "three times a week") == 3)
        #expect(AgentWords.reps(in: "10 x 60kg") == 10)
        #expect(AgentWords.kilograms(in: "8 reps at 22,5 kg") == 22.5)
        #expect(AgentWords.kilograms(in: "8 reps") == nil)
    }

    @Test func modelRepliesAreCleanedOrDropped() {
        #expect(AgentReply.clean("**Shoulders**:\n- Overhead press\n- *Lateral* raise")
                == "Shoulders:\n• Overhead press\n• Lateral raise")
        #expect(AgentReply.clean("<think>they want rest</think>Rest well tonight.") == "Rest well tonight.")
        #expect(AgentReply.clean("## Tip\nWarm up first.") == "Tip\nWarm up first.")
        #expect(AgentReply.clean("I can't access the tools to build a workout.") == nil)
        #expect(AgentReply.clean("As an AI language model, I cannot train with you.") == nil)
        #expect(AgentReply.clean("<tool_call>{\"name\":\"x\"}</tool_call>") == nil)
        let long = String(repeating: "Keep your back straight and brace. ", count: 30)
        #expect((AgentReply.clean(long)?.count ?? 0) <= AgentReply.maximumLength + 1)
    }
}
