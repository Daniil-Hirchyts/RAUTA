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

    /// What is counting down: a rest between sets, or the warm-up before the
    /// first one. The same countdown, told differently.
    enum Kind: String {
        case rest, warmup
    }

    nonisolated static let notificationID = "rauta-rest-timer-complete"

    private(set) var deadline: Date?
    private(set) var kind: Kind = .rest
    private var exerciseName: String?

    private let center = UNUserNotificationCenter.current()
    private let deadlineKey = "rauta-rest-timer-deadline"
    private let kindKey = "rauta-rest-timer-kind"
    private var countdownTask: Task<Void, Never>?
    /// Whether the music has been taken down for this countdown.
    private var countdownHeld = false
    private var cancellables = Set<AnyCancellable>()

    /// How long before the end the scheduled notification is taken back. Short,
    /// so an app that is running then is all but certain to still be running a
    /// moment later to make the sound.
    private static let withdrawLead: TimeInterval = 0.15

    private init() {
        let stored = Storage.defaults.double(forKey: deadlineKey)
        if stored > Date().timeIntervalSince1970 {
            deadline = Date(timeIntervalSince1970: stored)
            kind = Storage.defaults.string(forKey: kindKey).flatMap(Kind.init(rawValue:)) ?? .rest
        }
    }

    /// Picks a restored rest back up.
    func start() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.becameActive() }
            .store(in: &cancellables)
        if deadline != nil { arm() }
    }

    func schedule(deadline fireDate: Date, exerciseName: String?, kind: Kind = .rest) {
        deadline = fireDate
        self.kind = kind
        self.exerciseName = exerciseName
        Storage.defaults.set(fireDate.timeIntervalSince1970, forKey: deadlineKey)
        Storage.defaults.set(kind.rawValue, forKey: kindKey)
        // Under the unit tests the deadline is kept, but nothing is scheduled
        // with the system and nothing sounds.
        guard !AppEnvironment.isRunningTests else { return }
        requestPermissionIfNeeded()
        arm()
    }

    func cancel() {
        if !AppEnvironment.isRunningTests {
            center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        }
        clear()
    }

    private func clear() {
        deadline = nil
        exerciseName = nil
        countdownTask?.cancel()
        countdownTask = nil
        releaseCountdown()
        Storage.defaults.removeObject(forKey: deadlineKey)
        Storage.defaults.removeObject(forKey: kindKey)
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
        // A rest moved or replaced mid-countdown starts its countdown afresh.
        releaseCountdown()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        guard let deadline else { return }
        if deadline.timeIntervalSinceNow > 0.5 {
            post(
                content(exerciseName: exerciseName, kind: kind, sound: true),
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: deadline.timeIntervalSinceNow, repeats: false)
            )
        }

        countdownTask = Task { @MainActor [weak self] in
            // Every step below runs only if the app is running at that moment:
            // a suspended app simply does not get here, and its notification
            // speaks for it.
            for secondsLeft in [3, 2, 1] {
                let wait = deadline.timeIntervalSinceNow - Double(secondsLeft)
                guard wait > -0.4 else { continue }
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, let self, self.deadline == deadline else { return }
                self.tick(secondsLeft)
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

    /// One of the last seconds. The first one takes the music down for the
    /// whole countdown, through the sound at the end.
    private func tick(_ secondsLeft: Int) {
        if let deadline {
            countdownHeld = true
            WorkoutAudio.holdCountdown(endingAt: deadline, with: endSound(kind))
        }
        WorkoutAudio.tick(secondsLeft: secondsLeft)
    }

    private func endSound(_ kind: Kind) -> RautaSound {
        kind == .warmup ? .warmupOver : .restOver
    }

    /// The countdown is over or called off: the music comes back up once what
    /// is sounding has finished.
    private func releaseCountdown() {
        guard countdownHeld else { return }
        countdownHeld = false
        WorkoutAudio.endCountdown()
    }

    private func finish() {
        let name = exerciseName
        let finished = kind
        // Sounded before the countdown lets go, so the music stays down
        // through it and comes back up once, after.
        WorkoutAudio.play(endSound(finished))
        clear()

        let application = UIApplication.shared
        if application.applicationState == .active {
            center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
        } else if application.isProtectedDataAvailable {
            // A locked phone has nothing to read; one in someone's hand, in
            // another app, gets a word on what the sound was.
            post(content(exerciseName: name, kind: finished, sound: false), trigger: nil)
        }
    }

    // MARK: Notifications

    private func content(exerciseName: String?, kind: Kind, sound: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        switch kind {
        case .rest:
            content.title = "Rest complete"
            content.body = exerciseName.map { "Ready for your next set of \($0)." }
                ?? "Ready for your next set."
        case .warmup:
            content.title = "Warm-up done"
            content.body = exerciseName.map { "First up: \(Wording.titleCase($0))." }
                ?? "Time for the first set."
        }
        content.sound = sound
            ? UNNotificationSound(named: UNNotificationSoundName((kind == .warmup ? RautaSound.warmupOver : .restOver).notificationFile))
            : nil
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
