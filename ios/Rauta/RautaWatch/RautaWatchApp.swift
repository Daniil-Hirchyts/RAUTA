import HealthKit
import SwiftUI
import UserNotifications
import WatchKit

@main
struct RautaWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
                .environment(WatchSessionModel.shared)
                .environment(WatchWorkoutManager.shared)
                .preferredColorScheme(.dark)
                .tint(WatchPalette.primary)
        }
    }
}

/// Starts the phone link and the workout that follows it at launch, before any
/// view exists — and after a crash, when the system relaunches the app into a
/// workout that is still running.
final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        // Hooked up before the link starts, so the first envelope it reads
        // already reaches the workout.
        WatchWorkoutManager.shared.follow(WatchSessionModel.shared)
        WatchSessionModel.shared.start()
        UNUserNotificationCenter.current().delegate = self
    }

    func handleActiveWorkoutRecovery() {
        WatchWorkoutManager.shared.recoverActiveWorkout()
    }

    /// The phone opened the app into its workout (`startWatchApp`).
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchWorkoutManager.shared.startForPhone()
    }

    /// The iPhone's "Rest complete" lands here too when the phone is locked.
    /// With the app open, its own tap and ring have already said it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        if identifier.hasPrefix("rauta-rest-timer") || identifier.hasPrefix("rauta-watch-rest") { return [] }
        return [.banner, .sound]
    }
}
