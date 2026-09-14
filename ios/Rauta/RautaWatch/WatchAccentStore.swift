import Foundation
import Observation

/// The accent chosen on iPhone, remembered on the watch so the app opens in it
/// before the phone is in reach.
@Observable
final class WatchAccentStore: @unchecked Sendable {
    static let shared = WatchAccentStore()

    private(set) var accent: RautaWatchAccent

    @ObservationIgnored private let storageKey = "rauta-watch-accent"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(RautaWatchAccent.self, from: data) {
            accent = stored
        } else {
            accent = .ember
        }
    }

    func apply(_ next: RautaWatchAccent) {
        guard next != accent else { return }
        accent = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
