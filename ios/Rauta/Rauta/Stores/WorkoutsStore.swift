import Foundation
import Combine

enum HealthSyncStatus: String, Codable, Hashable, Sendable {
    case notRequested = "not-requested"
    case pending
    case synced
    case failed
}

struct WorkoutCompletion: Codable, Hashable, Sendable {
    var startedAt: String
    var completedAt: String
    var durationMs: Double
    var completedExerciseIds: [String]
    var activeCalories: Double
    var healthSyncStatus: HealthSyncStatus
}

/// The planned session an application workout stands for.
///
/// It is a reference into an immutable program snapshot, never a copy of the
/// prescription: sets, reps, RIR, load and rest are only ever read back from the
/// snapshot these two IDs name. A workout without it was built by hand and
/// belongs to nobody's plan.
struct PlannedWorkoutReference: Codable, Hashable, Sendable {
    var programId: String
    var sessionId: String
}

struct Workout: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var date: String
    var exerciseIds: [String]
    var completion: WorkoutCompletion?
    var createdAt: String
    var updatedAt: String
    var planned: PlannedWorkoutReference?
}

extension Sequence where Element == Workout {
    /// Soonest first: today's workouts, then the days ahead nearest first, then
    /// the days behind most recent first.
    func soonestFirst(today: String = CalendarDate.today) -> [Workout] {
        func band(_ workout: Workout) -> Int {
            if workout.date == today { return 0 }
            return workout.date > today ? 1 : 2
        }
        return sorted { left, right in
            let leftBand = band(left)
            let rightBand = band(right)
            if leftBand != rightBand { return leftBand < rightBand }
            if left.date != right.date {
                return leftBand == 2 ? left.date > right.date : left.date < right.date
            }
            return left.createdAt < right.createdAt
        }
    }
}

@MainActor
final class WorkoutsStore: ObservableObject {
    static let shared = WorkoutsStore()

    static let storageKey = "gym-lib-workouts"
    static let version = 2

    @Published private(set) var workouts: [Workout] = []

    /// Fired after every mutation, so the iCloud mirror and the session
    /// reconciler can follow the store rather than every call site.
    let changed = PassthroughSubject<Void, Never>()

    private var suppressPersist = false

    private init() {
        load()
    }

    // MARK: Hydration

    private func load() {
        guard let envelope = Storage.readEnvelope(Self.storageKey) else { return }
        workouts = Self.sanitize(envelope.state).workouts
    }

    func persist() {
        guard !suppressPersist else { return }
        Storage.writeEnvelope(
            Self.storageKey,
            state: .object(["workouts": .array(workouts.map { $0.jsonTree })]),
            version: Self.version
        )
    }

    private func mutate(_ body: () -> Void) {
        body()
        persist()
        changed.send()
    }

    struct PersistedWorkouts { var workouts: [Workout] }

    static func sanitize(_ value: JSONValue?) -> PersistedWorkouts {
        let raw = value?["workouts"]?.arrayValue ?? []
        var result: [Workout] = []

        for item in raw {
            guard let object = item.objectValue else { continue }
            let id = object["id"]?.stringValue ?? ""
            let date = object["date"]?.stringValue ?? ""
            guard !id.isEmpty, isCalendarDate(date) else { continue }

            let exerciseIds = Sanitize.uniqueStrings(object["exerciseIds"]) { ExerciseCatalogue.has($0) }
            let completion = sanitizeCompletion(object["completion"], exerciseIds: exerciseIds)
            let planned = sanitizePlannedReference(object["planned"])
            let name = (object["name"]?.stringValue ?? "Workout")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            result.append(Workout(
                id: id,
                name: name.isEmpty ? "Workout" : name,
                date: date,
                exerciseIds: exerciseIds,
                completion: completion,
                createdAt: object["createdAt"]?.stringValue ?? "",
                updatedAt: object["updatedAt"]?.stringValue ?? "",
                planned: planned
            ))
        }
        return PersistedWorkouts(workouts: result)
    }

    private static func isCalendarDate(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private static func sanitizeCompletion(
        _ value: JSONValue?,
        exerciseIds: [String]
    ) -> WorkoutCompletion? {
        guard let object = value?.objectValue else { return nil }
        let completedAt = object["completedAt"]?.stringValue ?? ""
        let startedAt = object["startedAt"]?.stringValue ?? ""
        guard !completedAt.isEmpty, !startedAt.isEmpty,
              let durationMs = nonNegative(object["durationMs"]),
              let activeCalories = nonNegative(object["activeCalories"])
        else { return nil }

        let status = object["healthSyncStatus"]?.stringValue
            .flatMap(HealthSyncStatus.init(rawValue:)) ?? .notRequested

        return WorkoutCompletion(
            startedAt: startedAt,
            completedAt: completedAt,
            durationMs: durationMs,
            completedExerciseIds: Sanitize.uniqueStrings(object["completedExerciseIds"]) {
                exerciseIds.contains($0)
            },
            activeCalories: activeCalories,
            healthSyncStatus: status
        )
    }

    /// A half-written reference names no session, so it is dropped rather than
    /// kept as a workout that claims a lineage it cannot prove.
    private static func sanitizePlannedReference(_ value: JSONValue?) -> PlannedWorkoutReference? {
        guard let object = value?.objectValue,
              let programId = object["programId"]?.stringValue, !programId.isEmpty,
              let sessionId = object["sessionId"]?.stringValue, !sessionId.isEmpty
        else { return nil }
        return PlannedWorkoutReference(programId: programId, sessionId: sessionId)
    }

    private static func nonNegative(_ value: JSONValue?) -> Double? {
        guard let number = value?.numberValue, number.isFinite, number >= 0 else { return nil }
        return number
    }

    static func makeId() -> String {
        let random = String(UUID().uuidString.prefix(6)).lowercased()
        return "\(Int(Date().timeIntervalSince1970 * 1000))-\(random)"
    }

    // MARK: Mutations

    func workout(_ id: String) -> Workout? { workouts.first { $0.id == id } }

    @discardableResult
    func createWorkout(
        name: String,
        date: String,
        exerciseIds: [String],
        planned: PlannedWorkoutReference? = nil
    ) -> String {
        let id = Self.makeId()
        let now = ISOTime.now()
        var unique: [String] = []
        var seen = Set<String>()
        for exerciseId in exerciseIds where seen.insert(exerciseId).inserted {
            unique.append(exerciseId)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let workout = Workout(
            id: id,
            name: trimmed.isEmpty ? "Workout" : trimmed,
            date: date,
            exerciseIds: unique,
            completion: nil,
            createdAt: now,
            updatedAt: now,
            planned: planned
        )
        mutate { workouts.append(workout) }
        return id
    }

    struct WorkoutPatch {
        var name: String?
        var date: String?
        var exerciseIds: [String]?
        var planned: PlannedWorkoutReference?
        var clearsPlanned = false

        init(
            name: String? = nil,
            date: String? = nil,
            exerciseIds: [String]? = nil,
            planned: PlannedWorkoutReference? = nil,
            clearsPlanned: Bool = false
        ) {
            self.name = name
            self.date = date
            self.exerciseIds = exerciseIds
            self.planned = planned
            self.clearsPlanned = clearsPlanned
        }
    }

    func updateWorkout(_ id: String, _ patch: WorkoutPatch) {
        guard let index = workouts.firstIndex(where: { $0.id == id }) else { return }
        mutate {
            var workout = workouts[index]
            if let name = patch.name {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                workout.name = trimmed.isEmpty ? workout.name : trimmed
            }
            if let date = patch.date { workout.date = date }
            if let exerciseIds = patch.exerciseIds { workout.exerciseIds = exerciseIds }
            if patch.clearsPlanned { workout.planned = nil }
            else if let planned = patch.planned { workout.planned = planned }
            workout.updatedAt = ISOTime.now()
            workouts[index] = workout
        }
    }

    func deleteWorkout(_ id: String) {
        mutate { workouts.removeAll { $0.id == id } }
    }

    /// Listed field by field on purpose: a copy is a workout somebody chose to
    /// repeat, not the session a program prescribed, so it starts life without a
    /// plan behind it.
    func duplicateWorkout(_ id: String) -> String? {
        guard let source = workout(id) else { return nil }
        let newId = Self.makeId()
        let now = ISOTime.now()
        let copy = Workout(
            id: newId,
            name: "\(source.name) copy",
            date: CalendarDate.today,
            exerciseIds: source.exerciseIds,
            completion: nil,
            createdAt: now,
            updatedAt: now,
            planned: nil
        )
        mutate { workouts.append(copy) }
        return newId
    }

    func completeWorkout(_ id: String, _ completion: WorkoutCompletion) {
        guard let index = workouts.firstIndex(where: { $0.id == id }) else { return }
        mutate {
            workouts[index].completion = completion
            workouts[index].updatedAt = ISOTime.now()
        }
    }

    func setHealthSyncStatus(_ id: String, _ status: HealthSyncStatus) {
        guard let index = workouts.firstIndex(where: { $0.id == id }),
              workouts[index].completion != nil
        else { return }
        mutate {
            workouts[index].completion?.healthSyncStatus = status
            workouts[index].updatedAt = ISOTime.now()
        }
    }

    // MARK: Wholesale replacement (backup restore, clear)

    func replaceAll(_ next: [Workout], persisting: Bool = true) {
        workouts = next
        if persisting { persist() }
        changed.send()
    }

    func isPast(_ workout: Workout, today: Date = Date()) -> Bool {
        workout.completion != nil || workout.date < CalendarDate.toISO(today)
    }

    func isCompleted(_ workout: Workout) -> Bool { workout.completion != nil }
}
