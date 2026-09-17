import Combine
import UIKit
import UserNotifications

/// The end of a rest, announced the way a navigation app announces a turn.
///
/// A notification with a sound is always left scheduled for the moment the
/// rest ends: it is what a suspended app has, since a suspended app cannot make
/// a sound of its own. Whenever the app is still running at that moment — on
/// screen, or kept running in the background by ``WorkoutBackgroundSession``
/// and its own audio — it withdraws the notification an instant before it
/// would go off and sounds the end itself:
///
/// - **In the app:** the last three seconds tick and the end sounds, over the
///   person's music. No notification.
/// - **Locked, still running:** the same ticks and sound, no notification.
/// - **In another app, still running:** the sound, and a silent banner saying
///   what it was.
/// - **Suspended:** the scheduled notification, with its sound.
///
/// The deadline lives here rather than in a view, so it survives navigation,
/// suspension and a relaunch.
@MainActor
final class RestAlerts {
    static let shared = RestAlerts()

    nonisolated static let notificationID = "rauta-rest-timer-complete"

    private(set) var deadline: Date?
    private var exerciseName: String?

    private let center = UNUserNotificationCenter.current()
    private let deadlineKey = "rauta-rest-timer-deadline"
    private var countdownTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// How long before the end the scheduled notification is taken back. Short,
    /// so an app that is running then is all but certain to still be running a
    /// moment later to make the sound.
    private static let withdrawLead: TimeInterval = 0.15

    private init() {
        let stored = UserDefaults.standard.double(forKey: deadlineKey)
        if stored > Date().timeIntervalSince1970 {
            deadline = Date(timeIntervalSince1970: stored)
        }
    }

    /// Picks a restored rest back up.
    func start() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.becameActive() }
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
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        clear()
    }

    private func clear() {
        deadline = nil
        exerciseName = nil
        countdownTask?.cancel()
        countdownTask = nil
        UserDefaults.standard.removeObject(forKey: deadlineKey)
    }

    private func becameActive() {
        // Anything that went off while the app was away has been seen.
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
        // A rest that ended while the app was suspended is over; its
        // notification already said so.
        if let deadline, deadline.timeIntervalSinceNow < -Self.withdrawLead {
            clear()
        }
    }

    // MARK: Countdown

    private func arm() {
        countdownTask?.cancel()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        guard let deadline else { return }
        if deadline.timeIntervalSinceNow > 0.5 {
            post(
                content(exerciseName: exerciseName, sound: true),
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: deadline.timeIntervalSinceNow, repeats: false)
            )
        }

        countdownTask = Task { @MainActor [weak self] in
            // Every step below runs only if the app is running at that moment:
            // a suspended app simply does not get here, and its notification
            // speaks for it.
            for secondsLeft in [3.0, 2.0, 1.0] {
                let wait = deadline.timeIntervalSinceNow - secondsLeft
                guard wait > -0.4 else { continue }
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, let self, self.deadline == deadline else { return }
                self.tick()
            }

            let untilWithdraw = deadline.timeIntervalSinceNow - Self.withdrawLead
            if untilWithdraw > 0 { try? await Task.sleep(for: .seconds(untilWithdraw)) }
            guard !Task.isCancelled, let self, self.deadline == deadline else { return }
            // Overdue by more than a moment means the app was suspended through
            // the end and the notification has already gone off.
            guard deadline.timeIntervalSinceNow > -0.6 else {
                self.clear()
                return
            }
            self.center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
            let untilEnd = deadline.timeIntervalSinceNow
            if untilEnd > 0 { try? await Task.sleep(for: .seconds(untilEnd)) }
            guard !Task.isCancelled, self.deadline == deadline else { return }
            self.finish()
        }
    }

    private func tick() {
        WorkoutAudio.tick()
        if UIApplication.shared.applicationState == .active { Haptics.trigger(.light) }
    }

    private func finish() {
        let name = exerciseName
        clear()

        let application = UIApplication.shared
        WorkoutAudio.go()
        if application.applicationState == .active {
            center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
            Haptics.trigger(.heavy)
        } else if application.isProtectedDataAvailable {
            // A locked phone has nothing to read; one in someone's hand, in
            // another app, gets a word on what the sound was.
            post(content(exerciseName: name, sound: false), trigger: nil)
        }
    }

    // MARK: Notifications

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
        let scheduledFor = deadline
        Task {
            try? await center.add(request)
            guard Self.isStale(scheduledFor: scheduledFor, now: deadline, hasTrigger: trigger != nil)
            else { return }
            center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
            if deadline != nil { arm() }
        }
    }

    /// Whether a scheduled notification that has just finished being added
    /// belongs to a rest that is no longer the current one. A rest skipped or
    /// replaced while the add was in flight has already cleared the pending
    /// request — before this one existed — so this one must go too.
    nonisolated static func isStale(scheduledFor: Date?, now current: Date?, hasTrigger: Bool) -> Bool {
        hasTrigger && scheduledFor != current
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
