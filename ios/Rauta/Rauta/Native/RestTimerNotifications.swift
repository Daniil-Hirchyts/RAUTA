import Foundation
import UserNotifications

/// Owns the rest deadline outside the workout view so it survives navigation,
/// suspension, a locked screen, and an app relaunch.
@MainActor
final class RestTimerNotifications: ObservableObject {
    static let shared = RestTimerNotifications()

    @Published private(set) var deadline: Date?

    private let center = UNUserNotificationCenter.current()
    private let deadlineKey = "rauta-rest-timer-deadline"
    private let notificationID = "rauta-rest-timer-complete"

    private init() {
        let stored = UserDefaults.standard.double(forKey: deadlineKey)
        if stored > Date().timeIntervalSince1970 {
            deadline = Date(timeIntervalSince1970: stored)
        }
    }

    func schedule(seconds: TimeInterval, exerciseName: String?) {
        let duration = Swift.max(1, seconds.rounded())
        schedule(deadline: Date().addingTimeInterval(duration), exerciseName: exerciseName)
    }

    func schedule(deadline fireDate: Date, exerciseName: String?) {
        let duration = Swift.max(1, fireDate.timeIntervalSinceNow)
        deadline = fireDate
        UserDefaults.standard.set(fireDate.timeIntervalSince1970, forKey: deadlineKey)

        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = exerciseName.map { "Ready for your next set of \($0)." }
            ?? "Ready for your next set."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: duration, repeats: false)
        )
        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            try? await center.add(request)
        }
    }

    func cancel() {
        deadline = nil
        UserDefaults.standard.removeObject(forKey: deadlineKey)
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
}
