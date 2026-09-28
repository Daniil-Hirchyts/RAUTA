import Foundation

// MARK: - Transcript

/// One planned or scheduled session as a card row. Enough to draw it in a
/// `WorkoutAgenda`, and plain enough to keep in the conversation file.
nonisolated struct AgentSessionRow: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var date: String
    var title: String
    var minutes: Int
    var exerciseIds: [String]
    /// Working sets, when the row comes from a prescription.
    var sets: Int? = nil
    /// The muscles the session is built around.
    var focus: [MuscleId]? = nil
}

/// Something RAUTA shows rather than says: what it changed, a plan waiting for
/// a yes, a list it looked up.
nonisolated enum AgentCard: Codable, Hashable, Sendable {
    /// A change already made. The item carries whether it can still be undone.
    case change(title: String, detail: String, systemImage: String)
    /// A change waiting for Apply.
    case proposal(AgentProposalCard)
    case sessions(title: String, rows: [AgentSessionRow])
    case exercises(title: String, ids: [String])
    case facts(title: String, lines: [String])
    /// Permission RAUTA needs before it can look something up.
    case permission(AgentPermission)
    /// RAUTA has no model yet.
    case download
}

nonisolated struct AgentProposalCard: Codable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        case pending, applied, dismissed
        /// Outlived its preview: the app changed, or it survived a relaunch.
        case expired
    }

    var id: String
    var title: String
    var detail: String
    var rows: [AgentSessionRow]
    var applyTitle: String
    var destructive: Bool
    var state: State
}

nonisolated enum AgentPermission: String, Codable, Hashable, Sendable {
    case health, calendar, notifications
}

nonisolated struct AgentItem: Identifiable, Codable, Hashable, Sendable {
    enum Content: Codable, Hashable, Sendable {
        case user(String)
        case rauta(String)
        /// What RAUTA is doing, while it does it.
        case activity(String)
        case card(AgentCard)
        case failure(String)
    }

    enum UndoState: String, Codable, Sendable {
        case available, undone
        /// Something changed since, or the app was relaunched.
        case gone
    }

    var id = UUID()
    var content: Content
    var at = Date()
    var undo: UndoState?
}

// MARK: - Tools

/// What a tool did: the line RAUTA says, what it shows, and how to take it back.
///
/// RAUTA's words about a change come from here, never from the model: in the
/// spike the model announced saves that had not happened.
struct ToolOutcome {
    var say: String
    var card: AgentCard?
    var undo: AgentUndo?
    /// Whether the turn is over once this has run. Changes, proposals and
    /// anything shown as a card end it; a lookup the model must still answer
    /// from continues with `note`.
    var endsTurn = true
    /// What the model reads back when the turn continues.
    var note: String?
    var proposalApplied = false

    /// A refusal or a question back, said as it is and ending the turn.
    static func reply(_ text: String) -> ToolOutcome {
        ToolOutcome(say: text)
    }
}

/// Thrown by a tool whose outcome ends the turn, so the session stops before
/// the model writes words of its own about it.
nonisolated struct AgentTurnEnded: Error {}

// MARK: - Undo

/// How to take one change back, exactly — and only while nothing has moved
/// since it was made.
enum AgentUndo {
    /// The whole record, for edits made while no workout runs.
    case records(before: PersistedTrainingState, after: PersistedTrainingState, workoutsBefore: [Workout], workoutsAfter: [Workout])
    case plan(before: PersistedTrainingState, after: PersistedTrainingState,
              workoutsBefore: [Workout], workoutsAfter: [Workout],
              profileBefore: TrainingProfile, profileAfter: TrainingProfile)
    /// One logged set, back to what it held.
    case set(entryId: String, setId: String, before: PersistedSetObservation?, after: PersistedSetObservation?)
    /// A set added by logging, removed again.
    case addedSet(entryId: String, setId: String)
    /// One live exercise, sets and all, as it was before a swap.
    case exercise(before: PersistedActiveExerciseDraft, after: PersistedActiveExerciseDraft,
                  workoutBefore: Workout, workoutAfter: Workout)
    case profile(before: TrainingProfile, after: TrainingProfile)
    case equipment(before: FiltersStore.PersistedFilters, after: FiltersStore.PersistedFilters)
    case pause(workoutId: String)
    case resume(workoutId: String)
    case reminder(id: String, fireDate: Date)
    case removedReminder(id: String, fireDate: Date)
    case calendarEvent(id: String)
}

// MARK: - Proposals

/// A change RAUTA prepared and the person has not yet said yes to.
enum AgentProposal {
    case plan(PlanPreview, sessionMinutes: Int?, healthSnapshot: HealthReadinessSnapshot?)
    case workout(date: String, name: String, exerciseIds: [String], focus: [MuscleId], basis: PlanBasis)
    case finishWorkout(workoutId: String, basis: PlanBasis)
    case discardWorkout(workoutId: String, basis: PlanBasis)
    case deleteWorkout(AgentWorkoutRef, basis: PlanBasis)
    case calendar(workout: AgentWorkoutRef, start: Date, end: Date)
}

// MARK: - The screen RAUTA acts through

/// What only the main screen can do: it owns starting and finishing a workout
/// (with the player and the celebration) and which workout is shown.
struct AgentUIBridge {
    var startWorkout: (Workout) -> WorkoutStartOutcome
    var finishWorkout: () -> Bool
    var openWorkout: (String) -> Void
    /// Closes the chat, then opens an exercise's page over the tabs.
    var openExercise: (String) -> Void
    var dismissChat: () -> Void
}
