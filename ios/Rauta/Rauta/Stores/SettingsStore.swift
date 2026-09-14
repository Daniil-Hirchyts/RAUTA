import Foundation
import Combine

enum HealthStatus: String, Codable, Hashable, Sendable {
    case idle, connected, unavailable, error
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
    var soundChimesEnabled: Bool
    var keepAwake: Bool
    var appearance: AppAppearance

    static let defaults = SettingsPreferences(
        appleHealthEnabled: false,
        healthStatus: .idle,
        healthBodyWeightKg: nil,
        healthLastConnectedAt: nil,
        autoSyncWorkouts: false,
        syncActiveCalories: true,
        hapticsEnabled: true,
        soundChimesEnabled: false,
        keepAwake: false,
        appearance: .system
    )
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    static let storageKey = "gym-lib-settings"
    static let version = 3

    @Published private(set) var preferences: SettingsPreferences = .defaults
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
            keepAwake: object["keepAwake"]?.boolValue == true,
            appearance: object["appearance"]?.stringValue
                .flatMap(AppAppearance.init(rawValue:)) ?? .system
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
    var keepAwake: Bool { preferences.keepAwake }
    var appearance: AppAppearance { preferences.appearance }
}
