import Foundation
import Combine

/// The pages the training profile is edited on. Grouped the way Settings groups
/// its rows, so one page answers several related questions.
enum AppPage: Hashable {
    case workouts
    case settings
    case onboarding
    case profileBasics
    case profileTraining
    case profileHealth
    case profileEquipment
    case profileLoadSteps
    case profilePriorities
    case planWeek(sourceProgramId: String?)
    case muscles(preferredWorkoutId: String?)
    case equipment(preferredWorkoutId: String?)
    case exercises(preferredWorkoutId: String?)
    case exerciseDetail(exerciseId: String)
    case workoutDestination(preferredWorkoutId: String?)
    case workoutForm(exerciseIds: [String], workoutId: String?, engineFocusMuscles: [MuscleId]?)
    case equipmentPreset
    case exerciseAlternatives(exerciseId: String, workoutId: String)

    var typeName: String {
        switch self {
        case .workouts: return "workouts"
        case .settings: return "settings"
        case .onboarding: return "onboarding"
        case .profileBasics: return "profile-basics"
        case .profileTraining: return "profile-training"
        case .profileHealth: return "profile-health"
        case .profileEquipment: return "profile-equipment"
        case .profileLoadSteps: return "profile-load-steps"
        case .profilePriorities: return "profile-priorities"
        case .planWeek: return "plan-week"
        case .muscles: return "muscles"
        case .equipment: return "equipment"
        case .exercises: return "exercises"
        case .exerciseDetail: return "exercise-detail"
        case .workoutDestination: return "workout-destination"
        case .workoutForm: return "workout-form"
        case .equipmentPreset: return "equipment-preset"
        case .exerciseAlternatives: return "exercise-alternatives"
        }
    }

    /// Runtime guard for restored state and any imperative navigation boundary.
    var isValid: Bool {
        switch self {
        case .planWeek(let sourceProgramId):
            guard let sourceProgramId else { return true }
            return !sourceProgramId.trimmingCharacters(in: .whitespaces).isEmpty
        case .exerciseDetail(let exerciseId):
            return ExerciseCatalogue.has(exerciseId)
        case .exerciseAlternatives(let exerciseId, let workoutId):
            return !workoutId.trimmingCharacters(in: .whitespaces).isEmpty
                && ExerciseCatalogue.has(exerciseId)
        case .workoutForm(let exerciseIds, let workoutId, let engineFocusMuscles):
            if let workoutId, workoutId.trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
            guard !exerciseIds.isEmpty, exerciseIds.allSatisfy(ExerciseCatalogue.has) else {
                return false
            }
            if let engineFocusMuscles, engineFocusMuscles.isEmpty { return false }
            return true
        default:
            return true
        }
    }

    var hasControls: Bool {
        switch self {
        case .settings, .workoutDestination, .exerciseAlternatives, .exerciseDetail:
            return false
        default:
            return true
        }
    }

    var preferredWorkoutId: String? {
        switch self {
        case .muscles(let id), .equipment(let id), .exercises(let id), .workoutDestination(let id):
            return id
        default:
            return nil
        }
    }

    var key: String {
        switch self {
        case .exerciseDetail(let exerciseId): return "exercise-detail:\(exerciseId)"
        case .exerciseAlternatives(let exerciseId, let workoutId):
            return "exercise-alternatives:\(workoutId):\(exerciseId)"
        case .workoutForm(let exerciseIds, let workoutId, let focus):
            let focusKey = focus.map { $0.map(\.rawValue).joined(separator: ",") } ?? "manual"
            return "workout-form:\(workoutId ?? "new"):\(exerciseIds.joined(separator: ",")):\(focusKey)"
        case .muscles, .equipment, .exercises, .workoutDestination:
            return "\(typeName):\(preferredWorkoutId ?? "new")"
        default:
            return typeName
        }
    }

    // MARK: Persistence

    var tree: JSONValue {
        var object: [String: JSONValue] = ["type": .string(typeName)]
        switch self {
        case .planWeek(let sourceProgramId):
            if let sourceProgramId { object["sourceProgramId"] = .string(sourceProgramId) }
        case .exerciseDetail(let exerciseId):
            object["exerciseId"] = .string(exerciseId)
        case .muscles(let id), .equipment(let id), .exercises(let id), .workoutDestination(let id):
            object["preferredWorkoutId"] = id.map(JSONValue.string) ?? .null
        case .workoutForm(let exerciseIds, let workoutId, _):
            object["exerciseIds"] = .array(exerciseIds.map(JSONValue.string))
            object["workoutId"] = workoutId.map(JSONValue.string) ?? .null
        case .exerciseAlternatives(let exerciseId, let workoutId):
            object["exerciseId"] = .string(exerciseId)
            object["workoutId"] = .string(workoutId)
        default:
            break
        }
        return .object(object)
    }

    static func parse(_ value: JSONValue?) -> AppPage? {
        guard let object = value?.objectValue, let type = object["type"]?.stringValue else {
            return nil
        }
        func optionalString(_ key: String) -> String? {
            guard let text = object[key]?.stringValue, !text.isEmpty else { return nil }
            return text
        }

        switch type {
        case "workouts": return .workouts
        case "settings": return .settings
        case "equipment-preset": return .equipmentPreset
        case "profile-basics": return .profileBasics
        case "profile-training": return .profileTraining
        case "profile-health": return .profileHealth
        case "profile-equipment": return .profileEquipment
        case "profile-load-steps": return .profileLoadSteps
        case "profile-priorities": return .profilePriorities
        case "plan-week":
            if object["sourceProgramId"] == nil { return .planWeek(sourceProgramId: nil) }
            guard let id = optionalString("sourceProgramId") else { return nil }
            return .planWeek(sourceProgramId: id)
        // First-run setup is decided from the profile at launch, never restored
        // from a session: whether it is due is the profile's answer to give.
        case "onboarding": return nil
        case "muscles": return .muscles(preferredWorkoutId: optionalString("preferredWorkoutId"))
        case "equipment": return .equipment(preferredWorkoutId: optionalString("preferredWorkoutId"))
        case "exercises": return .exercises(preferredWorkoutId: optionalString("preferredWorkoutId"))
        case "workout-destination":
            return .workoutDestination(preferredWorkoutId: optionalString("preferredWorkoutId"))
        case "exercise-detail":
            guard let exerciseId = optionalString("exerciseId"),
                  ExerciseCatalogue.has(exerciseId)
            else { return nil }
            return .exerciseDetail(exerciseId: exerciseId)
        case "workout-form":
            return .workoutForm(
                exerciseIds: Sanitize.uniqueStrings(object["exerciseIds"]) {
                    ExerciseCatalogue.has($0)
                },
                workoutId: optionalString("workoutId"),
                engineFocusMuscles: nil
            )
        case "exercise-alternatives":
            guard let exerciseId = optionalString("exerciseId"),
                  ExerciseCatalogue.has(exerciseId),
                  let workoutId = optionalString("workoutId")
            else { return nil }
            return .exerciseAlternatives(exerciseId: exerciseId, workoutId: workoutId)
        default:
            return nil
        }
    }
}

struct AppPageEntry: Identifiable, Hashable {
    var id: String
    var page: AppPage
}

enum NavigationDirection { case forward, back }

/// Runtime-only page stack and transient selection state.
///
/// Navigation is deliberately never restored across launches. Durable domain
/// data belongs to its own stores; a fresh process always starts from the app
/// root (or first-run onboarding) and builds a new navigation stack.
@MainActor
final class AppSessionStore: ObservableObject {
    static let shared = AppSessionStore()

    static let storageKey = "gym-lib-app-session"
    static let version = 3

    @Published private(set) var pages: [AppPageEntry] = []
    @Published private(set) var direction: NavigationDirection = .forward
    @Published var selectMode = false
    @Published var selectedIds: [String] = []
    /// A workout waiting to be shown on the Workout tab. Set by ``openWorkout(_:)``
    /// and cleared by the tab once it has opened it.
    @Published var requestedWorkoutId: String?

    private var sequence = 0

    private init() {
        // Remove legacy session snapshots written by older builds. UI state is
        // process-local now, so reopening the app always starts cleanly.
        Storage.remove(Self.storageKey)
        pages = Self.initialPages().map(makeEntry)
    }

    private func makeEntry(_ page: AppPage) -> AppPageEntry {
        sequence += 1
        return AppPageEntry(id: "page-\(sequence)", page: page)
    }

    /// First-run setup is offered to a genuinely new install only. Someone whose
    /// library, presets or settings already exist has been using RAUTA for a
    /// while; a wizard in front of their workouts would be an ambush, and every
    /// answer it asks for is in Settings anyway.
    private static func initialPages() -> [AppPage] {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--onboarding") {
            return [.onboarding]
        }
#endif
        let onboarding = TrainingProfileStore.shared.onboarding
        if !onboarding.completed && !AppBackup.hasMeaningfulData() { return [.onboarding] }
        return [.workouts]
    }

    var activeEntry: AppPageEntry? { pages.last ?? pages.first }

    // MARK: Navigation

    func push(_ page: AppPage) {
        guard page.isValid else { return }
        direction = .forward
        pages = pages + [makeEntry(page)]
    }

    func pop() {
        guard pages.count > 1 else { return }
        direction = .back
        pages = Array(pages.dropLast())
    }

    func replace(_ page: AppPage) {
        guard page.isValid, !pages.isEmpty else { return }
        direction = .forward
        var nextPages = pages
        nextPages[nextPages.count - 1] = makeEntry(page)
        pages = nextPages
    }

    func reset(_ nextPages: [AppPage]) {
        guard !nextPages.isEmpty, nextPages.allSatisfy(\.isValid) else { return }
        direction = .back
        pages = nextPages.map(makeEntry)
    }

    /// Shows a workout where workouts live: everything pushed over the tabs is
    /// closed and the Workout tab opens on that workout. A workout has one page,
    /// and it is that one.
    func openWorkout(_ workoutId: String) {
        requestedWorkoutId = workoutId
        direction = .back
        if let root = pages.first, root.page == .workouts {
            pages = [root]
        } else {
            pages = [makeEntry(.workouts)]
        }
    }

}
