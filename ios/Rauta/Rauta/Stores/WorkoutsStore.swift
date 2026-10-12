import Foundation
import Observation
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
    /// The muscles RAUTA was asked to build this workout around, when RAUTA
    /// built it. Until it is started, RAUTA can build it again around them.
    var rautaFocus: [MuscleId]? = nil
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
@Observable
final class WorkoutsStore {
    static let shared = WorkoutsStore()

    static let storageKey = "gym-lib-workouts"
    static let version = 2

    private(set) var workouts: [Workout] = []
    /// Workouts deleted here, by id, with when. A copy arriving from another
    /// device is merged rather than swallowed whole, and this is how the merge
    /// tells a workout deleted here from one that device never had.
    private(set) var deletions: [String: String] = [:]
    /// Moves on with every change to `workouts`, so what is derived from them
    /// can tell they changed without comparing them.
    private(set) var revision = 0

    /// How long a deletion is remembered for merging.
    static let deletionMemoryDays = 90

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
        let state = Self.sanitize(envelope.state)
        workouts = state.workouts
        deletions = state.deletions
        revision += 1
    }

    func persist() {
        guard !suppressPersist else { return }
        Storage.writeEnvelope(Self.storageKey, state: snapshotTree, version: Self.version)
    }

    /// The store as the backup and the workout file carry it.
    var snapshotTree: JSONValue {
        .object([
            "workouts": .array(workouts.map { $0.jsonTree }),
            "deleted": .object(deletions.mapValues(JSONValue.string)),
        ])
    }

    private func mutate(_ body: () -> Void) {
        body()
        revision += 1
        persist()
        changed.send()
    }

    struct PersistedWorkouts {
        var workouts: [Workout]
        var deletions: [String: String] = [:]
    }

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
            let rautaFocus = (object["rautaFocus"]?.arrayValue ?? [])
                .compactMap { $0.stringValue.flatMap(MuscleId.init(rawValue:)) }

            result.append(Workout(
                id: id,
                name: name.isEmpty ? "Workout" : name,
                date: date,
                exerciseIds: exerciseIds,
                completion: completion,
                createdAt: object["createdAt"]?.stringValue ?? "",
                updatedAt: object["updatedAt"]?.stringValue ?? "",
                planned: planned,
                rautaFocus: rautaFocus.isEmpty ? nil : rautaFocus
            ))
        }
        var deletions: [String: String] = [:]
        for (id, at) in value?["deleted"]?.objectValue ?? [:] {
            guard !id.isEmpty, let at = at.stringValue, ISOTime.valid(at) else { continue }
            deletions[id] = at
        }
        return PersistedWorkouts(workouts: result, deletions: deletions)
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
        planned: PlannedWorkoutReference? = nil,
        rautaFocus: [MuscleId]? = nil
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
            planned: planned,
            rautaFocus: rautaFocus?.isEmpty == false ? rautaFocus : nil
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
        mutate {
            workouts.removeAll { $0.id == id }
            deletions[id] = ISOTime.now()
            deletions = Self.pruned(deletions)
        }
    }

    /// Remembers that a workout removed by a wholesale replacement — a plan
    /// revision withdrawing its session — was deleted, for merging.
    func rememberDeletion(_ id: String) {
        guard workout(id) == nil else { return }
        mutate {
            deletions[id] = ISOTime.now()
            deletions = Self.pruned(deletions)
        }
    }

    private static func pruned(_ deletions: [String: String], now: String = ISOTime.now()) -> [String: String] {
        let cutoff = ISOTime.addDays(now, -Double(deletionMemoryDays))
        return deletions.filter { $0.value >= cutoff }
    }

    /// Two copies of the workout list made one, losing nothing either side
    /// still has: a workout on both sides keeps its most recent edit; one on
    /// a single side stays, unless the other side deleted it after that edit.
    /// A running workout is always this device's own version.
    static func merge(
        local: PersistedWorkouts,
        remote: PersistedWorkouts,
        runningId: String? = nil
    ) -> PersistedWorkouts {
        var deletions = local.deletions
        for (id, at) in remote.deletions where at > (deletions[id] ?? "") { deletions[id] = at }

        let localById = Dictionary(local.workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteById = Dictionary(remote.workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var merged: [Workout] = []
        var seen = Set<String>()
        for workout in local.workouts + remote.workouts where seen.insert(workout.id).inserted {
            let mine = localById[workout.id]
            let theirs = remoteById[workout.id]
            if workout.id == runningId, let mine { merged.append(mine); continue }
            let chosen: Workout
            switch (mine, theirs) {
            case let (mine?, theirs?): chosen = theirs.updatedAt > mine.updatedAt ? theirs : mine
            case let (mine?, nil): chosen = mine
            case let (nil, theirs?): chosen = theirs
            case (nil, nil): continue
            }
            if let deletedAt = deletions[chosen.id], deletedAt >= chosen.updatedAt { continue }
            merged.append(chosen)
        }
        return PersistedWorkouts(workouts: merged, deletions: pruned(deletions))
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
        revision += 1
        if persisting { persist() }
        changed.send()
    }

    /// Deletes every workout, remembering each deletion, so a copy of the old
    /// list on another device is cleared too rather than merged back.
    func clearAll() {
        let now = ISOTime.now()
        var next = deletions
        for workout in workouts { next[workout.id] = now }
        deletions = Self.pruned(next)
        replaceAll([])
    }

    /// Replaces the list and the deletions it was merged with.
    func replaceAll(_ next: PersistedWorkouts) {
        deletions = next.deletions
        replaceAll(next.workouts)
    }

    func isPast(_ workout: Workout, today: Date = Date()) -> Bool {
        workout.completion != nil || workout.date < CalendarDate.toISO(today)
    }

}
