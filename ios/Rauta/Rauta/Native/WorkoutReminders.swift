import Combine
import Foundation
import UserNotifications

@MainActor
final class WorkoutReminders {
    static let shared = WorkoutReminders()

    nonisolated static let categoryId = "rauta-workout-reminder"
    nonisolated static let startAction = "rauta-reminder-start"
    nonisolated static let moveAction = "rauta-reminder-move"
    nonisolated static let snoozeAction = "rauta-reminder-snooze"
    private nonisolated static let prefix = "rauta-workout-"

    private struct Reminder: Codable {
        var workoutDate: String
        var fireDate: Date
    }

    private let center = UNUserNotificationCenter.current()
    private let key = "rauta-workout-reminders"
    private static let accessRequestedKey = "rauta-reminders-access-requested"
    private var reminders: [String: Reminder]
    private var cancellable: AnyCancellable?
    /// One reconcile at a time: two interleaved across their awaits could
    /// schedule the same reminder twice.
    private lazy var reconciling = CoalescedWork { [weak self] in await self?.reconcile() }

    private init() {
        reminders = Storage.defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: Reminder].self, from: $0) } ?? [:]
    }

    var hasRequestedAccess: Bool { Storage.defaults.bool(forKey: Self.accessRequestedKey) }

    func requestAccess() async -> Bool {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            Storage.defaults.set(true, forKey: Self.accessRequestedKey)
            return true
        }
        guard settings.authorizationStatus == .notDetermined else { return false }
        let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        Storage.defaults.set(true, forKey: Self.accessRequestedKey)
        return allowed
    }

    func start() {
        let category = UNNotificationCategory(identifier: Self.categoryId, actions: [
            UNNotificationAction(identifier: Self.startAction, title: "Start workout", options: [.foreground]),
            UNNotificationAction(identifier: Self.moveAction, title: "Move to tomorrow", options: []),
            UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 30 min", options: []),
        ], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
        guard cancellable == nil else { return }
        cancellable = WorkoutsStore.shared.changed.sink { [weak self] in
            self?.reconciling.request()
        }
        reconciling.request()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(reminders) { Storage.defaults.set(data, forKey: key) }
    }

    private func identifier(_ workoutId: String) -> String { Self.prefix + workoutId }

    private func defaultFireDate(for workout: Workout) -> Date? {
        guard let date = CalendarDate.parse(workout.date) else { return nil }
        let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date)
        if let morning, morning > Date() { return morning }
        if workout.date == CalendarDate.today { return Date().addingTimeInterval(5 * 60) }
        return nil
    }

    @discardableResult
    func schedule(_ workout: Workout, fireDate: Date? = nil) async throws -> Date {
        guard await requestAccess() else { throw ReminderError.denied }
        guard let current = WorkoutsStore.shared.workout(workout.id), current == workout,
              workout.completion == nil,
              let fire = fireDate ?? defaultFireDate(for: workout), fire > Date() else {
            throw ReminderError.stale
        }
        let content = UNMutableNotificationContent()
        content.title = "Time to train"
        content.body = workout.name
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        content.userInfo = ["workoutId": workout.id]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(
            identifier: identifier(workout.id), content: content, trigger: trigger
        ))
        reminders[workout.id] = Reminder(workoutDate: workout.date, fireDate: fire)
        persist()
        return fire
    }

    func remove(_ workoutId: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(workoutId)])
        center.removeDeliveredNotifications(withIdentifiers: [identifier(workoutId)])
        reminders[workoutId] = nil
        persist()
    }

    func removeAll() {
        for id in reminders.keys {
            center.removePendingNotificationRequests(withIdentifiers: [identifier(id)])
            center.removeDeliveredNotifications(withIdentifiers: [identifier(id)])
        }
        reminders.removeAll()
        persist()
    }

    func hasReminder(_ workoutId: String) -> Bool { reminders[workoutId] != nil }
    func fireDate(for workoutId: String) -> Date? { reminders[workoutId]?.fireDate }

    func handle(workoutId: String, requestId: String, actionId: String) async {
        guard requestId == identifier(workoutId) else { return }
        switch actionId {
        case Self.startAction, UNNotificationDefaultActionIdentifier:
            AppSessionStore.shared.requestedStartWorkoutId = workoutId
            AppSessionStore.shared.openWorkout(workoutId)
        case Self.moveAction:
            guard let workout = WorkoutsStore.shared.workout(workoutId) else { return }
            let tomorrow = CalendarDate.shift(max(workout.date, CalendarDate.today), by: 1)
            try? TrainingEdits.rescheduleWorkout(workoutId, date: tomorrow)
        case Self.snoozeAction:
            guard let workout = WorkoutsStore.shared.workout(workoutId) else { return }
            _ = try? await schedule(workout, fireDate: Date().addingTimeInterval(30 * 60))
        default: break
        }
    }

    private func reconcile() async {
        for (id, reminder) in reminders {
            guard let workout = WorkoutsStore.shared.workout(id), workout.completion == nil else {
                remove(id)
                continue
            }
            guard workout.date != reminder.workoutDate else { continue }
            if let fire = defaultFireDate(for: workout) {
                do { _ = try await schedule(workout, fireDate: fire) }
                catch { remove(id) }
            } else {
                remove(id)
            }
        }
    }
}

private enum ReminderError: LocalizedError {
    case denied, stale
    var errorDescription: String? {
        switch self {
        case .denied: "Allow notifications in Settings to use workout reminders."
        case .stale: "That workout can no longer have a reminder at this time."
        }
    }
}
