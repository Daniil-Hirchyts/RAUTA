import AppIntents
import CoreSpotlight
import Foundation

nonisolated struct RautaWorkoutEntity: IndexedEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Workout"
    static let defaultQuery = RautaWorkoutQuery()

    var id: String
    var name: String
    var date: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(date)")
    }
}

nonisolated struct RautaWorkoutQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RautaWorkoutEntity] {
        await MainActor.run {
            WorkoutsStore.shared.workouts.filter { identifiers.contains($0.id) }.map {
                RautaWorkoutEntity(id: $0.id, name: $0.name, date: $0.date)
            }
        }
    }

    func suggestedEntities() async throws -> [RautaWorkoutEntity] {
        await MainActor.run {
            WorkoutTimeline(workouts: WorkoutsStore.shared.workouts,
                            records: TrainingRecordsStore.shared.data,
                            activeWorkoutId: ActiveWorkoutStore.shared.session?.workoutId)
                .upcoming.filter { $0.date >= CalendarDate.today }.prefix(12).map {
                    RautaWorkoutEntity(id: $0.id, name: $0.name, date: $0.date)
                }
        }
    }
}

nonisolated struct RautaExerciseEntity: IndexedEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Exercise"
    static let defaultQuery = RautaExerciseQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

nonisolated struct RautaExerciseQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RautaExerciseEntity] {
        ExerciseCatalogue.all.filter { identifiers.contains($0.id) }.map {
            RautaExerciseEntity(id: $0.id, name: $0.name)
        }
    }

    func suggestedEntities() async throws -> [RautaExerciseEntity] {
        Array(ExerciseCatalogue.allByName.prefix(30)).map {
            RautaExerciseEntity(id: $0.id, name: $0.name)
        }
    }
}

struct AskRautaIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask RAUTA"
    static let description = IntentDescription("Open RAUTA and ask about your training")
    static let openAppWhenRun = true

    @Parameter(title: "Question") var question: String?

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppSessionStore.shared.requestedAgentPrompt = question ?? ""
            AppSessionStore.shared.reset([.workouts])
        }
        return .result()
    }
}

nonisolated struct NextWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Next workout"
    static let description = IntentDescription("Hear which workout is next")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let next = await MainActor.run {
            WorkoutTimeline(workouts: WorkoutsStore.shared.workouts,
                            records: TrainingRecordsStore.shared.data,
                            activeWorkoutId: ActiveWorkoutStore.shared.session?.workoutId)
                .upcoming.first { $0.date >= CalendarDate.today }
        }
        guard let next else { return .result(dialog: "You have no upcoming workout.") }
        let when = await MainActor.run { () -> String in
            if next.date == CalendarDate.today { return "today" }
            return "on " + CalendarDate.format(next.date, "EEEEdMMMM")
        }
        return .result(dialog: "\(next.name) is next, \(when).")
    }
}

struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start workout"
    static let description = IntentDescription("Open RAUTA and start a scheduled workout")
    static let openAppWhenRun = true

    @Parameter(title: "Workout") var workout: RautaWorkoutEntity?

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            let selected = workout.flatMap { WorkoutsStore.shared.workout($0.id) }
                ?? WorkoutTimeline(workouts: WorkoutsStore.shared.workouts,
                                   records: TrainingRecordsStore.shared.data,
                                   activeWorkoutId: ActiveWorkoutStore.shared.session?.workoutId)
                    .upcoming.first { $0.date >= CalendarDate.today }
            guard let selected else { return }
            AppSessionStore.shared.requestedStartWorkoutId = selected.id
            AppSessionStore.shared.openWorkout(selected.id)
        }
        return .result()
    }
}

struct StartRestIntent: AppIntent {
    static let title: LocalizedStringResource = "Start rest"
    static let description = IntentDescription("Start a rest timer in the active workout")

    @Parameter(title: "Seconds") var seconds: Int?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { () -> String in
            guard ActiveWorkoutStore.shared.session != nil else { return "Start a workout first." }
            let duration = seconds ?? 90
            guard (15...600).contains(duration) else { return "Choose 15 to 600 seconds." }
            ActiveWorkoutStore.shared.startRest(seconds: Double(duration), exerciseName: nil)
            return "Rest started for \(duration) seconds."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

nonisolated struct RautaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskRautaIntent(),
                    phrases: ["Ask \(.applicationName)", "Talk to \(.applicationName)"],
                    shortTitle: "Ask RAUTA", systemImageName: "bubble.left.and.bubble.right")
        AppShortcut(intent: NextWorkoutIntent(),
                    phrases: ["What's my next workout in \(.applicationName)"],
                    shortTitle: "Next workout", systemImageName: "calendar")
        AppShortcut(intent: StartWorkoutIntent(),
                    phrases: ["Start my workout in \(.applicationName)"],
                    shortTitle: "Start workout", systemImageName: "play.circle")
    }
}

@MainActor
enum RautaSpotlight {
    static func indexWorkouts() async {
        let index = CSSearchableIndex.default()
        let entities = WorkoutsStore.shared.workouts.map {
            RautaWorkoutEntity(id: $0.id, name: $0.name, date: $0.date)
        }
        try? await index.deleteAppEntities(ofType: RautaWorkoutEntity.self)
        try? await index.indexAppEntities(entities)
    }

    static func indexExercises() async {
        let entities = ExerciseCatalogue.all.map {
            RautaExerciseEntity(id: $0.id, name: $0.name)
        }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}
