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
    case workoutDetail(workoutId: String)
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
        case .workoutDetail: return "workout-detail"
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
        case .workoutDetail(let workoutId):
            return !workoutId.trimmingCharacters(in: .whitespaces).isEmpty
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
        case .workoutDetail(let workoutId): return "workout-detail:\(workoutId)"
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
        case .workoutDetail(let workoutId):
            object["workoutId"] = .string(workoutId)
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
        case "workout-detail":
            guard let workoutId = optionalString("workoutId") else { return nil }
            return .workoutDetail(workoutId: workoutId)
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

/// The page stack plus the ephemeral browse state persisted with it.
@MainActor
final class AppSessionStore: ObservableObject {
    static let shared = AppSessionStore()

    static let storageKey = "gym-lib-app-session"
    static let version = 3

    @Published private(set) var pages: [AppPageEntry] = []
    @Published private(set) var direction: NavigationDirection = .forward
    @Published var selectMode = false
    @Published var selectedIds: [String] = []
    @Published var detailExerciseId: String?

    private var sequence = 0

    private init() {
        let restored = Self.readSession()
        selectMode = restored.selectMode
        selectedIds = restored.selectedIds
        detailExerciseId = restored.detailExerciseId
        // The native shell always opens on the workout list; a restored deep page
        // would be an ambush after the app was closed.
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
        let onboarding = TrainingProfileStore.shared.onboarding
        if !onboarding.completed && !AppBackup.hasMeaningfulData() { return [.onboarding] }
        return [.workouts]
    }

    var activeEntry: AppPageEntry? { pages.last ?? pages.first }
    var activePage: AppPage { activeEntry?.page ?? .workouts }

    // MARK: Navigation

    func push(_ page: AppPage) {
        guard page.isValid else { return }
        direction = .forward
        pages = pages + [makeEntry(page)]
        persist()
    }

    func pop() {
        guard pages.count > 1 else { return }
        direction = .back
        pages = Array(pages.dropLast())
        persist()
    }

    func replace(_ page: AppPage) {
        guard page.isValid, !pages.isEmpty else { return }
        direction = .forward
        var nextPages = pages
        nextPages[nextPages.count - 1] = makeEntry(page)
        pages = nextPages
        persist()
    }

    func reset(_ nextPages: [AppPage]) {
        guard !nextPages.isEmpty, nextPages.allSatisfy(\.isValid) else { return }
        direction = .back
        pages = nextPages.map(makeEntry)
        persist()
    }

    // MARK: Persistence

    struct RestoredSession {
        var detailExerciseId: String?
        var pages: [AppPage]
        var selectedIds: [String]
        var selectMode: Bool
    }

    static func readSession() -> RestoredSession {
        guard let envelope = Storage.readEnvelope(storageKey), envelope.version == version else {
            return RestoredSession(
                detailExerciseId: nil, pages: [.workouts], selectedIds: [], selectMode: false
            )
        }
        let state = envelope.state
        let detailExerciseId = state["detailExerciseId"]?.stringValue
        var parsed = (state["pages"]?.arrayValue ?? [])
            .prefix(12)
            .compactMap(AppPage.parse)
        if parsed.isEmpty { parsed = [.workouts] }
        if parsed.first?.typeName != "workouts" { parsed.insert(.workouts, at: 0) }

        return RestoredSession(
            detailExerciseId: detailExerciseId.flatMap {
                ExerciseCatalogue.has($0) ? $0 : nil
            },
            pages: Array(parsed),
            selectedIds: Sanitize.uniqueStrings(state["selectedIds"]) {
                ExerciseCatalogue.has($0)
            },
            selectMode: state["selectMode"]?.boolValue == true
        )
    }

    func persist() {
        let detail: String? = {
            if case .exerciseDetail(let exerciseId) = activePage { return exerciseId }
            return nil
        }()
        Storage.writeEnvelope(
            Self.storageKey,
            state: .object([
                "detailExerciseId": detail.map(JSONValue.string) ?? .null,
                "pages": .array(pages.map { $0.page.tree }),
                "selectedIds": .array(selectedIds.map(JSONValue.string)),
                "selectMode": .bool(selectMode),
            ]),
            version: Self.version
        )
    }
}
