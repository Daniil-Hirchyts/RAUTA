import Foundation

@MainActor
enum AgentContext {
    static func instructions(items: [AgentItem]) -> String {
        let profile = TrainingProfileStore.shared.profile
        let today = CalendarDate.today
        let timeline = WorkoutTimeline(
            workouts: WorkoutsStore.shared.workouts,
            records: TrainingRecordsStore.shared.data,
            activeWorkoutId: ActiveWorkoutStore.shared.session?.workoutId
        )
        let ahead = timeline.upcoming.filter { $0.date >= today }.prefix(4)
            .map { "\($0.id) \($0.date) \($0.name)" }.joined(separator: "; ")
        let recent = items.reversed().compactMap { item -> String? in
            switch item.content {
            case .user(let text): return "User: \(String(text.prefix(90)))"
            case .rauta(let text): return "RAUTA: \(String(text.prefix(90)))"
            default: return nil
            }
        }.prefix(3).reversed().joined(separator: " / ")
        let running = ActiveWorkoutStore.shared.session?.workoutName ?? "none"
        return """
        You are RAUTA, a concise strength coach. Use a tool for app facts or actions. \
        Only a tool can change training. Repeat names, dates and numbers as said; \
        Swift resolves them. Never claim a change without a tool. \
        General advice: at most two sentences. Today \(today). \
        Goal \(profile.goal.rawValue); \(profile.trainingExperience.rawValue); \
        usual \(Int(profile.preferredSessionDurationMinutes)) min. \
        Running: \(running). Ahead: \(ahead.isEmpty ? "none" : ahead). \
        Recent: \(recent.isEmpty ? "none" : recent).
        """
    }
}
