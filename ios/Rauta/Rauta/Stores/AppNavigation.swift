import Foundation
import Observation
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
    case addExercises(preferredWorkoutId: String?)
    case exerciseDetail(exerciseId: String)
    case workoutDestination(exerciseIds: [String], preferredWorkoutId: String?)
    case workoutForm(exerciseIds: [String], workoutId: String?, engineFocusMuscles: [MuscleId]?)
    case equipmentPreset
    case exerciseAlternatives(exerciseId: String, workoutId: String)
    case policies

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
        case .addExercises: return "add-exercises"
        case .exerciseDetail: return "exercise-detail"
        case .workoutDestination: return "workout-destination"
        case .workoutForm: return "workout-form"
        case .equipmentPreset: return "equipment-preset"
        case .exerciseAlternatives: return "exercise-alternatives"
        case .policies: return "policies"
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

    /// A page that is looked at over whatever it was opened from — an
    /// exercise, a replacement, a flow or a settings screen — opens as a modal
    /// of its own. Anything else opened from inside a modal is a step of that
    /// modal and is pushed within it.
    var opensAsModal: Bool {
        switch self {
        case .settings, .planWeek, .addExercises, .exerciseDetail, .exerciseAlternatives:
            return true
        default:
            return false
        }
    }

    var hasControls: Bool {
        switch self {
        case .settings, .workoutDestination, .exerciseAlternatives:
            return false
        default:
            return true
        }
    }

    var preferredWorkoutId: String? {
        switch self {
        case .addExercises(let id), .workoutDestination(_, let id):
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
        case .addExercises:
            return "\(typeName):\(preferredWorkoutId ?? "new")"
        case .workoutDestination(let exerciseIds, let id):
            return "\(typeName):\(id ?? "new"):\(exerciseIds.joined(separator: ","))"
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
        case .addExercises(let id):
            object["preferredWorkoutId"] = id.map(JSONValue.string) ?? .null
        case .workoutDestination(let exerciseIds, let id):
            object["exerciseIds"] = .array(exerciseIds.map(JSONValue.string))
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
        case "add-exercises":
            return .addExercises(preferredWorkoutId: optionalString("preferredWorkoutId"))
        case "workout-destination":
            return .workoutDestination(
                exerciseIds: Sanitize.uniqueStrings(object["exerciseIds"]) {
                    ExerciseCatalogue.has($0)
                },
                preferredWorkoutId: optionalString("preferredWorkoutId")
            )
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
    /// Whether this page is the first of a modal of its own, rather than a step
    /// pushed inside the modal below it. The root page is neither.
    var startsModal: Bool
    /// The on-screen view the page grew out of, as an ``View/appZoomSource(_:)``
    /// id. Closing the page returns it there.
    var zoomSource: String?
}

enum NavigationDirection { case forward, back }

/// Runtime-only page stack and transient selection state.
///
/// Navigation is deliberately never restored across launches. Durable domain
/// data belongs to its own stores; a fresh process always starts from the app
/// root (or first-run onboarding) and builds a new navigation stack.
@MainActor
@Observable
final class AppSessionStore {
    static let shared = AppSessionStore()

    static let storageKey = "gym-lib-app-session"
    static let version = 3

    private(set) var pages: [AppPageEntry] = []
    private(set) var direction: NavigationDirection = .forward
    var selectedIds: [String] = []
    /// A workout waiting to be shown on the Workout tab. Set by ``openWorkout(_:)``
    /// and cleared by the tab once it has opened it.
    var requestedWorkoutId: String?
    /// Set by a workout notification or Shortcuts; the Workout tab consumes it.
    var requestedStartWorkoutId: String?
    /// Foreground handoff from Ask RAUTA in Shortcuts or Spotlight.
    var requestedAgentPrompt: String?

    private var sequence = 0

    private init() {
        // Remove legacy session snapshots written by older builds. UI state is
        // process-local now, so reopening the app always starts cleanly.
        Storage.remove(Self.storageKey)
        pages = makeEntries(Self.initialPages())
    }

    private func makeEntry(_ page: AppPage, startsModal: Bool = false, zoomSource: String? = nil) -> AppPageEntry {
        sequence += 1
        return AppPageEntry(id: "page-\(sequence)", page: page, startsModal: startsModal, zoomSource: zoomSource)
    }

    /// Entries for a whole stack: the root, then pages as ``push(_:from:)``
    /// would have opened them one after another.
    private func makeEntries(_ nextPages: [AppPage]) -> [AppPageEntry] {
        nextPages.enumerated().map { index, page in
            makeEntry(page, startsModal: index == 1 || (index > 1 && page.opensAsModal))
        }
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
        // Straight to Settings → Policies & credits, onboarded or not.
        if ProcessInfo.processInfo.arguments.contains("--policies") {
            return [.workouts, .settings, .policies]
        }
#endif
        let onboarding = TrainingProfileStore.shared.onboarding
        if !onboarding.completed && !AppBackup.hasMeaningfulData() { return [.onboarding] }
        return [.workouts]
    }

    var activeEntry: AppPageEntry? { pages.last ?? pages.first }

    /// The modals open over the root, bottom first. Each is its own first page
    /// followed by the steps pushed inside it.
    var modals: [[AppPageEntry]] {
        var groups: [[AppPageEntry]] = []
        for entry in pages.dropFirst() {
            if entry.startsModal || groups.isEmpty {
                groups.append([entry])
            } else {
                groups[groups.count - 1].append(entry)
            }
        }
        return groups
    }

    // MARK: Navigation

    /// Opens a page. Over the root, or when the page is one that is looked at
    /// rather than stepped through, it opens as a modal growing out of
    /// `source`; otherwise it is pushed inside the modal it was opened from.
    func push(_ page: AppPage, from source: String? = nil) {
        guard page.isValid else { return }
        direction = .forward
        let startsModal = pages.count <= 1 || page.opensAsModal
        pages = pages + [makeEntry(page, startsModal: startsModal, zoomSource: startsModal ? source : nil)]
    }

    /// Closes the modal at `index` in ``modals`` and every modal over it — what
    /// a drag down on a modal, or the system dismissing it, asks for.
    func dismissModal(at index: Int) {
        let groups = modals
        guard groups.indices.contains(index), let first = groups[index].first,
              let position = pages.firstIndex(where: { $0.id == first.id })
        else { return }
        direction = .back
        pages = Array(pages.prefix(position))
    }

    /// Takes the steps pushed inside the modal at `index` from its navigation
    /// stack — a swipe back arrives here as a shorter path.
    func setSteps(_ steps: [AppPageEntry], inModal index: Int) {
        let groups = modals
        guard groups.indices.contains(index), let first = groups[index].first,
              let position = pages.firstIndex(where: { $0.id == first.id }),
              steps != Array(groups[index].dropFirst())
        else { return }
        direction = steps.count < groups[index].count - 1 ? .back : .forward
        // Modals opened over this one close with it.
        pages = Array(pages.prefix(position + 1)) + steps
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
        let replaced = nextPages[nextPages.count - 1]
        nextPages[nextPages.count - 1] = makeEntry(
            page, startsModal: replaced.startsModal, zoomSource: replaced.zoomSource
        )
        pages = nextPages
    }

    func reset(_ nextPages: [AppPage]) {
        guard !nextPages.isEmpty, nextPages.allSatisfy(\.isValid) else { return }
        direction = .back
        pages = makeEntries(nextPages)
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
