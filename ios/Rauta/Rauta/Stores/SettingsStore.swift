import Foundation
import Observation
import Combine

enum HealthStatus: String, Codable, Hashable, Sendable {
    case idle, connected, unavailable, error
}

/// How long the warm-up that opens every workout runs.
enum WarmupLength: Int, CaseIterable, Hashable, Sendable {
    case off = 0
    case three = 180
    case five = 300
    case ten = 600

    /// The engine's own estimate of a warm-up, which session lengths count on.
    static let standard = WarmupLength.three

    var seconds: Double { Double(rawValue) }

    var label: String {
        switch self {
        case .off: return "Off"
        case .three: return "3 min"
        case .five: return "5 min"
        case .ten: return "10 min"
        }
    }

    init(seconds: Double?) {
        self = seconds.flatMap { value in Self.allCases.first { $0.seconds == value } } ?? .standard
    }
}

/// Which theme the app wears: the iPhone's own, or one chosen for good.
enum AppAppearance: String, Codable, Hashable, CaseIterable, Sendable {
    case system, light, dark
}

struct SettingsPreferences: Codable, Hashable, Sendable {
    var appleHealthEnabled: Bool
    var healthStatus: HealthStatus
    var healthBodyWeightKg: Double?
    var healthLastConnectedAt: String?
    var autoSyncWorkouts: Bool
    var syncActiveCalories: Bool
    var hapticsEnabled: Bool
    /// Sounds for the app's own taps and answers: RAUTA's menu, favourites,
    /// a saved change. The stored name is from when these were chimes.
    var soundChimesEnabled: Bool
    /// Sounds during a workout: countdowns, rest, a logged set.
    var workoutSoundsEnabled: Bool
    /// The warm-up at the start of every workout, in seconds; 0 is none.
    var warmupSeconds: Double
    var keepAwake: Bool
    var appearance: AppAppearance
    /// A preset's name, or `#RRGGBB` for a colour picked by hand.
    var accent: String

    static let defaults = SettingsPreferences(
        appleHealthEnabled: false,
        healthStatus: .idle,
        healthBodyWeightKg: nil,
        healthLastConnectedAt: nil,
        autoSyncWorkouts: false,
        syncActiveCalories: true,
        hapticsEnabled: true,
        soundChimesEnabled: false,
        workoutSoundsEnabled: true,
        warmupSeconds: WarmupLength.standard.seconds,
        keepAwake: false,
        appearance: .system,
        accent: "ember"
    )
}

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    static let storageKey = "gym-lib-settings"
    static let version = 3

    private(set) var preferences: SettingsPreferences = .defaults
    let changed = PassthroughSubject<Void, Never>()

    private init() { load() }

    static func sanitize(_ value: JSONValue?) -> SettingsPreferences {
        let object = value?.objectValue ?? [:]
        let bodyWeight: Double? = {
            guard let number = object["healthBodyWeightKg"]?.numberValue,
                  number.isFinite, number >= 30, number <= 300
            else { return nil }
            return number
        }()
        return SettingsPreferences(
            appleHealthEnabled: object["appleHealthEnabled"]?.boolValue == true,
            healthStatus: object["healthStatus"]?.stringValue
                .flatMap(HealthStatus.init(rawValue:)) ?? .idle,
            healthBodyWeightKg: bodyWeight,
            healthLastConnectedAt: object["healthLastConnectedAt"]?.stringValue,
            autoSyncWorkouts: object["autoSyncWorkouts"]?.boolValue == true,
            syncActiveCalories: object["syncActiveCalories"]?.boolValue != false,
            hapticsEnabled: object["hapticsEnabled"]?.boolValue != false,
            soundChimesEnabled: object["soundChimesEnabled"]?.boolValue == true,
            workoutSoundsEnabled: object["workoutSoundsEnabled"]?.boolValue != false,
            warmupSeconds: WarmupLength(seconds: object["warmupSeconds"]?.numberValue).seconds,
            keepAwake: object["keepAwake"]?.boolValue == true,
            appearance: object["appearance"]?.stringValue
                .flatMap(AppAppearance.init(rawValue:)) ?? .system,
            // Normalised through the accent's own parser, so a stored value is
            // always one the app can draw.
            accent: AppAccent(storage: object["accent"]?.stringValue).storage
        )
    }

    private func load() {
        guard let envelope = Storage.readEnvelope(Self.storageKey) else { return }
        preferences = Self.sanitize(envelope.state)
    }

    func persist() {
        Storage.writeEnvelope(Self.storageKey, state: preferences.jsonTree, version: Self.version)
    }

    func update(_ body: (inout SettingsPreferences) -> Void) {
        var next = preferences
        body(&next)
        preferences = next
        persist()
        changed.send()
    }

    func replaceAll(_ next: SettingsPreferences) {
        preferences = next
        persist()
        changed.send()
    }

    func resetSettings() { replaceAll(.defaults) }

    // Convenience accessors the views read directly.
    var appleHealthEnabled: Bool { preferences.appleHealthEnabled }
    var healthStatus: HealthStatus { preferences.healthStatus }
    var healthBodyWeightKg: Double? { preferences.healthBodyWeightKg }
    var autoSyncWorkouts: Bool { preferences.autoSyncWorkouts }
    var syncActiveCalories: Bool { preferences.syncActiveCalories }
    var hapticsEnabled: Bool { preferences.hapticsEnabled }
    var soundChimesEnabled: Bool { preferences.soundChimesEnabled }
    var workoutSoundsEnabled: Bool { preferences.workoutSoundsEnabled }
    var warmupLength: WarmupLength { WarmupLength(seconds: preferences.warmupSeconds) }
    var keepAwake: Bool { preferences.keepAwake }
    var appearance: AppAppearance { preferences.appearance }
    var accent: AppAccent { AppAccent(storage: preferences.accent) }

    /// Each change of accent, and nothing else: not the accent in use when it
    /// is subscribed to, and not a save that left the accent as it was. What
    /// follows the accent out of the app — the Lock Screen card, the watch,
    /// the theme — listens here.
    var accentChanges: AnyPublisher<AppAccent, Never> {
        changed
            .map { [unowned self] in accent }
            .prepend(accent)
            .removeDuplicates()
            .dropFirst()
            .eraseToAnyPublisher()
    }
}
