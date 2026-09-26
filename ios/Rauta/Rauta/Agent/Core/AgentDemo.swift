#if DEBUG
import Foundation

/// Sample conversations for reviewing the chat's design without running the
/// model or changing any training data.
@MainActor
enum AgentDemo {
    static func items(page: Int) -> [AgentItem] {
        let today = CalendarDate.today
        let monday = AgentWords.shift(AgentWords.monday(of: today), by: 7)
        func ids(_ query: String, _ count: Int) -> [String] {
            ExerciseResolver.resolve(query, limit: count).map(\.exercise.id)
        }
        func row(_ offset: Int, _ title: String, _ minutes: Int, _ query: String) -> AgentSessionRow {
            AgentSessionRow(id: "demo-\(offset)", date: AgentWords.shift(monday, by: offset),
                            title: title, minutes: minutes, exerciseIds: ids(query, 4))
        }
        func upcoming(_ offset: Int, _ id: String, _ title: String, _ minutes: Int, _ query: String, _ count: Int) -> AgentSessionRow {
            AgentSessionRow(id: "demo-\(id)", date: AgentWords.shift(today, by: offset),
                            title: title, minutes: minutes, exerciseIds: ids(query, count))
        }
        switch page {
        case 4:
            return []
        case 2, 3:
            var moved = AgentItem(content: .card(.change(
                title: "Workout moved", detail: "Upper body → \(CalendarDate.format(AgentWords.shift(today, by: 6), "EEEdMMM"))",
                systemImage: "calendar")))
            moved.undo = .available
            var items = [
                AgentItem(content: .user("What's on my schedule this week?")),
                AgentItem(content: .rauta("Here's this week: 7 workouts.")),
                AgentItem(content: .card(.sessions(title: "This week", rows: [
                    upcoming(0, "a", "Full body", 66, "barbell squat", 7),
                    upcoming(1, "b", "Upper body", 45, "bench press", 4),
                    upcoming(1, "c", "Mobility", 20, "stretch", 3),
                    upcoming(3, "d", "Lower body", 50, "romanian deadlift", 5),
                    upcoming(4, "e", "Upper body", 46, "dumbbell row", 6),
                    upcoming(5, "f", "Full body", 55, "lunge", 5),
                    upcoming(6, "g", "Conditioning", 30, "kettlebell swing", 4),
                ]))),
                AgentItem(content: .user("Move Thursday's workout to Friday")),
                AgentItem(content: .rauta("Moved Upper body to \(CalendarDate.format(AgentWords.shift(today, by: 6), "EEEdMMM")).")),
                moved,
            ]
            if page == 3 { items.append(AgentItem(content: .user("Make the rest of my week lighter"))) }
            return items
        case 1:
            return [
                AgentItem(content: .user("How's my bench press going?")),
                AgentItem(content: .rauta("Here's how barbell bench press is going.")),
                AgentItem(content: .card(.facts(title: "Barbell bench press", lines: [
                    "Logged sessions: 6", "Trend: improving", "Recent load: 62.5 kg", "Recent reps: 8",
                ]))),
                AgentItem(content: .user("What can I do for rear delts with dumbbells?")),
                AgentItem(content: .rauta("I found these exercises.")),
                AgentItem(content: .card(.exercises(title: "Exercises", ids: ids("dumbbell rear delt", 3)))),
                AgentItem(content: .user("Am I recovered enough to train hard today?")),
                AgentItem(content: .rauta("I can check your recent sleep and heart trends if you allow Health access.")),
                AgentItem(content: .card(.permission(.health))),
            ]
        default:
            var swapped = AgentItem(content: .card(.change(
                title: "Exercise swapped", detail: "Walking lunge → Lever leg press",
                systemImage: "arrow.triangle.2.circlepath")))
            swapped.undo = .available
            return [
                AgentItem(content: .user("My knee hurts, swap the lunges on Friday")),
                AgentItem(content: .rauta("Swapped walking lunge for lever leg press in Full body.")),
                swapped,
                AgentItem(content: .user("Make me a new plan, 3 days a week, 45 minutes")),
                AgentItem(content: .rauta("I built a plan for you to review. It hasn't been saved yet.")),
                AgentItem(content: .card(.proposal(AgentProposalCard(
                    id: "demo-plan", title: "Your new plan", detail: "3 workouts · 45 min",
                    rows: [row(0, "Full body", 45, "barbell squat"),
                           row(2, "Full body", 44, "bench press"),
                           row(4, "Full body", 46, "romanian deadlift")],
                    applyTitle: "Apply plan", destructive: false, state: .pending)))),
            ]
        }
    }
}
#endif
