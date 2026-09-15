import Combine
import UIKit
import UserNotifications

/// The end of a rest, announced the way a navigation app announces a turn.
///
/// - **In the app:** the last three seconds tick and the end sounds, over the
///   person's music. No notification.
/// - **Locked, with the app kept running** (see ``WorkoutBackgroundSession``):
///   the same ticks and sound, still no notification.
/// - **In another app, kept running:** the sound, and a silent banner to say
///   what it was.
/// - **Not kept running** — an older iOS, or the system refused the workout
///   session: the app is suspended in the background and cannot make a sound
///   of its own, so a notification with a sound is left scheduled for the
///   moment the rest ends.
///
/// The deadline lives here rather than in a view, so it survives navigation,
/// suspension and a relaunch.
@MainActor
final class RestAlerts {
    static let shared = RestAlerts()

    static let notificationID = "rauta-rest-timer-complete"

    private(set) var deadline: Date?
    private var exerciseName: String?

    private let center = UNUserNotificationCenter.current()
    private let deadlineKey = "rauta-rest-timer-deadline"
    private var countdownTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let stored = UserDefaults.standard.double(forKey: deadlineKey)
        if stored > Date().timeIntervalSince1970 {
            deadline = Date(timeIntervalSince1970: stored)
        }
    }

    /// Picks a restored rest back up, and follows whether the app will stay
    /// awake in the background.
    func start() {
        WorkoutBackgroundSession.shared.changed
            .sink { [weak self] in self?.updateFallbackNotification() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                // Anything that went off while the app was away has been seen.
                guard let self else { return }
                self.center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
            }
            .store(in: &cancellables)
        if deadline != nil { arm() }
    }

    func schedule(deadline fireDate: Date, exerciseName: String?) {
        deadline = fireDate
        self.exerciseName = exerciseName
        UserDefaults.standard.set(fireDate.timeIntervalSince1970, forKey: deadlineKey)
        requestPermissionIfNeeded()
        arm()
    }

    func cancel() {
        deadline = nil
        exerciseName = nil
        countdownTask?.cancel()
        countdownTask = nil
        UserDefaults.standard.removeObject(forKey: deadlineKey)
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    // MARK: Countdown

    private func arm() {
        countdownTask?.cancel()
        updateFallbackNotification()
        guard let deadline else { return }
        countdownTask = Task { @MainActor [weak self] in
            // The last three seconds tick, then the end sounds.
            for secondsLeft in [3.0, 2.0, 1.0, 0.0] {
                let wait = deadline.timeIntervalSinceNow - secondsLeft
                if wait < -0.4 { continue }
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, let self, self.deadline == deadline else { return }
                if secondsLeft > 0 {
                    self.tick()
                } else {
                    self.finish()
                }
            }
        }
    }

    private var canSoundHere: Bool {
        UIApplication.shared.applicationState == .active || WorkoutBackgroundSession.shared.isRunning
    }

    private func tick() {
        guard canSoundHere else { return }
        WorkoutAudio.tick()
        if UIApplication.shared.applicationState == .active { Haptics.trigger(.light) }
    }

    private func finish() {
        let name = exerciseName
        deadline = nil
        exerciseName = nil
        countdownTask = nil
        UserDefaults.standard.removeObject(forKey: deadlineKey)

        let application = UIApplication.shared
        if application.applicationState == .active {
            center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
            center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
            WorkoutAudio.go()
            Haptics.trigger(.heavy)
        } else if WorkoutBackgroundSession.shared.isRunning {
            WorkoutAudio.go()
            // A locked phone has nothing to read; one in someone's hand, in
            // another app, gets a word on what the sound was.
            if application.isProtectedDataAvailable {
                post(content(exerciseName: name, sound: false), trigger: nil)
            }
        }
        // Otherwise the scheduled notification is going off right now.
    }

    // MARK: Notifications

    /// Leaves a notification with a sound scheduled only for when the app may
    /// be suspended by the time the rest ends; while it is kept running it
    /// makes the sound itself.
    private func updateFallbackNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        guard let deadline, deadline.timeIntervalSinceNow > 0.5,
              !WorkoutBackgroundSession.shared.isRunning
        else { return }
        post(
            content(exerciseName: exerciseName, sound: true),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: deadline.timeIntervalSinceNow, repeats: false)
        )
    }

    private func content(exerciseName: String?, sound: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = exerciseName.map { "Ready for your next set of \($0)." }
            ?? "Ready for your next set."
        content.sound = sound ? .default : nil
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        return content
    }

    private func post(_ content: UNMutableNotificationContent, trigger: UNNotificationTrigger?) {
        let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger)
        Task { try? await center.add(request) }
    }

    private func requestPermissionIfNeeded() {
        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
        }
    }
}
