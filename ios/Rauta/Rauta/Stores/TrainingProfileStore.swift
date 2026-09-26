import Foundation
import Observation
import Combine

let TRAINING_PROFILE_STORAGE_KEY = "gym-lib-training-profile"

/// Bumping this re-runs sanitisation over stored values. It never touches the
/// onboarding record, which is persisted beside the profile rather than inside
/// it — a schema change is not a reason to ask someone to set the app up again.
let TRAINING_PROFILE_VERSION = 1
let MAX_PROFILE_NAME_LENGTH = 40

struct MusclePriority: Codable, Hashable, Sendable {
    var muscleId: MuscleId
    var level: MusclePriorityLevel
}

/// What RAUTA knows about the person training, kept stable so a generated week
/// never has to ask again. Deliberately not the engine's request object: this is
/// application state a person edits, versioned and migration-safe, while the
/// request is derived from it at the moment a plan is built.
struct TrainingProfile: Codable, Hashable, Sendable {
    var version: Int
    /// Empty when not given. The only field that opens a keyboard.
    var name: String
    var age: Double
    var trainingExperience: Experience
    var goal: TrainingGoal
    var preferredSessionDurationMinutes: Double
    var health: TrainingHealth
    /// Only muscles that differ from the engine's normal weighting.
    var priorityMuscles: [MusclePriority]

    static func createDefault() -> TrainingProfile {
        TrainingProfile(
            version: TRAINING_PROFILE_VERSION,
            name: "",
            age: 30,
            // The cautious end of the engine's scale: lower volume and more reps
            // in reserve is the safer thing to assume about someone who has not
            // said.
            trainingExperience: .beginner,
            goal: .generalFitness,
            preferredSessionDurationMinutes: 60,
            health: .healthy,
            priorityMuscles: []
        )
    }
}

struct OnboardingRecord: Codable, Hashable, Sendable {
    var completed: Bool
    var completedAt: String?

    static let empty = OnboardingRecord(completed: false, completedAt: nil)
}

@MainActor
@Observable
final class TrainingProfileStore {
    static let shared = TrainingProfileStore()

    private(set) var profile: TrainingProfile = .createDefault()
    private(set) var onboarding: OnboardingRecord = .empty
    let changed = PassthroughSubject<Void, Never>()

    private init() { load() }

    // MARK: Sanitisation

    static func sanitizeProfile(_ value: JSONValue?) -> TrainingProfile {
        let defaults = TrainingProfile.createDefault()
        let object = value?.objectValue ?? [:]

        var seen = Set<MuscleId>()
        let priorityMuscles = (object["priorityMuscles"]?.arrayValue ?? [])
            .compactMap { entry -> MusclePriority? in
                guard let record = entry.objectValue,
                      let raw = record["muscleId"]?.stringValue,
                      let muscleId = MuscleId(rawValue: raw),
                      let levelRaw = record["level"]?.stringValue,
                      let level = MusclePriorityLevel(rawValue: levelRaw),
                      seen.insert(muscleId).inserted
                else { return nil }
                return MusclePriority(muscleId: muscleId, level: level)
            }

        let name = (object["name"]?.stringValue ?? defaults.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = object["goal"]?.stringValue.flatMap(TrainingGoal.init(rawValue:))
        let supportedGoal = goal.flatMap { ProfileVocabulary.supportedGoals.contains($0) ? $0 : nil }

        return TrainingProfile(
            version: TRAINING_PROFILE_VERSION,
            name: String(name.prefix(MAX_PROFILE_NAME_LENGTH)),
            age: ProfileVocabulary.profileAge.snap(object["age"]?.numberValue ?? defaults.age),
            trainingExperience: object["trainingExperience"]?.stringValue
                .flatMap(Experience.init(rawValue:)) ?? defaults.trainingExperience,
            goal: supportedGoal ?? defaults.goal,
            preferredSessionDurationMinutes: ProfileVocabulary.sessionDuration.snap(
                object["preferredSessionDurationMinutes"]?.numberValue
                    ?? defaults.preferredSessionDurationMinutes
            ),
            health: sanitizeHealth(object["health"]),
            priorityMuscles: priorityMuscles
        )
    }

    private static func sanitizeHealth(_ value: JSONValue?) -> TrainingHealth {
        guard let object = value?.objectValue,
              object["status"]?.stringValue == "unsupported"
        else { return .healthy }

        var seen = Set<HealthLimitation>()
        let reasons = (object["reasons"]?.arrayValue ?? [])
            .compactMap { $0.stringValue.flatMap(HealthLimitation.init(rawValue:)) }
            .filter { seen.insert($0).inserted }
        // The engine rejects an unsupported status with no reason behind it.
        return reasons.isEmpty ? .healthy : .unsupported(reasons)
    }

    private static func sanitizeOnboarding(_ value: JSONValue?) -> OnboardingRecord {
        let object = value?.objectValue ?? [:]
        let completed = object["completed"]?.boolValue == true
        return OnboardingRecord(
            completed: completed,
            completedAt: completed ? object["completedAt"]?.stringValue : nil
        )
    }

    struct PersistedProfileState {
        var profile: TrainingProfile
        var onboarding: OnboardingRecord
    }

    static func sanitizeState(_ value: JSONValue?) -> PersistedProfileState {
        PersistedProfileState(
            profile: sanitizeProfile(value?["profile"]),
            onboarding: sanitizeOnboarding(value?["onboarding"])
        )
    }

    /// Whether anything in the profile has been said rather than assumed. Used
    /// to decide a first-run conflict against a cloud copy the same way the
    /// other stores do.
    static func isConfigured(_ state: PersistedProfileState) -> Bool {
        state.onboarding.completed || state.profile != TrainingProfile.createDefault()
    }

    var isConfigured: Bool {
        Self.isConfigured(PersistedProfileState(profile: profile, onboarding: onboarding))
    }

    // MARK: Persistence

    private func load() {
        guard let envelope = Storage.readEnvelope(TRAINING_PROFILE_STORAGE_KEY) else { return }
        let state = Self.sanitizeState(envelope.state)
        profile = state.profile
        onboarding = state.onboarding
    }

    func persist() {
        Storage.writeEnvelope(
            TRAINING_PROFILE_STORAGE_KEY,
            state: .object(["profile": profile.jsonTree, "onboarding": onboarding.jsonTree]),
            version: TRAINING_PROFILE_VERSION
        )
    }

    private func mutate(_ body: () -> Void) {
        body()
        persist()
        changed.send()
    }

    // MARK: Mutations

    struct ProfilePatch {
        var name: String?
        var age: Double?
        var trainingExperience: Experience?
        var goal: TrainingGoal?
        var preferredSessionDurationMinutes: Double?
        var health: TrainingHealth?

        init(
            name: String? = nil,
            age: Double? = nil,
            trainingExperience: Experience? = nil,
            goal: TrainingGoal? = nil,
            preferredSessionDurationMinutes: Double? = nil,
            health: TrainingHealth? = nil
        ) {
            self.name = name
            self.age = age
            self.trainingExperience = trainingExperience
            self.goal = goal
            self.preferredSessionDurationMinutes = preferredSessionDurationMinutes
            self.health = health
        }
    }

    func updateProfile(_ patch: ProfilePatch) {
        mutate {
            var next = profile
            if let name = patch.name { next.name = name }
            if let age = patch.age { next.age = age }
            if let experience = patch.trainingExperience { next.trainingExperience = experience }
            if let goal = patch.goal { next.goal = goal }
            if let duration = patch.preferredSessionDurationMinutes {
                next.preferredSessionDurationMinutes = duration
            }
            if let health = patch.health { next.health = health }
            profile = Self.sanitizeProfile(next.jsonTree)
        }
    }

    /// Restore an exact, validated profile after a guarded agent change.
    func restoreProfile(_ previous: TrainingProfile) {
        mutate { profile = Self.sanitizeProfile(previous.jsonTree) }
    }

    func setMusclePriority(_ muscleId: MuscleId, _ level: MusclePriorityLevel?) {
        mutate {
            var rest = profile.priorityMuscles.filter { $0.muscleId != muscleId }
            if let level { rest.append(MusclePriority(muscleId: muscleId, level: level)) }
            profile.priorityMuscles = rest
        }
    }

    /// Walk one muscle to its next level. Decided inside the update from what is
    /// stored, so a quick second tap advances rather than repeating the first.
    func cycleMusclePriority(_ muscleId: MuscleId) {
        let current = profile.priorityMuscles.first { $0.muscleId == muscleId }?.level
        setMusclePriority(muscleId, ProfileVocabulary.nextPriorityLevel(current))
    }

    func clearMusclePriorities() {
        mutate { profile.priorityMuscles = [] }
    }

    func setHealthy() {
        mutate { profile.health = .healthy }
    }

    func toggleHealthLimitation(_ limitation: HealthLimitation) {
        mutate {
            let current = profile.health.status == .unsupported
                ? (profile.health.reasons ?? [])
                : []
            let reasons = Sanitize.toggle(current, limitation)
            profile.health = reasons.isEmpty ? .healthy : .unsupported(reasons)
        }
    }

    func completeOnboarding(_ completedAt: String = ISOTime.now()) {
        mutate { onboarding = OnboardingRecord(completed: true, completedAt: completedAt) }
    }

    func resetTrainingProfile() {
        mutate {
            profile = .createDefault()
            onboarding = .empty
        }
    }

    func replaceAll(_ state: PersistedProfileState) {
        profile = state.profile
        onboarding = state.onboarding
        persist()
        changed.send()
    }
}
