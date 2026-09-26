import SwiftUI
import UIKit
import UserNotifications

@main
struct RautaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if AgentLab.isRequested {
                AgentLabScreen()
            } else {
                RootView()
                    .environment(\.appStore, AppStore.shared)
            }
#else
            RootView()
                .environment(\.appStore, AppStore.shared)
#endif
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AppStore.shared.bootstrap()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        RautaAgent.shared.stop()
        AgentModelStore.shared.evict()
        AppStore.shared.persistNow()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AppStore.shared.persistNow()
    }

    // Navigation, selected tabs, open sheets, search and filters are runtime UI
    // state. Domain stores persist their own data; UIKit must not restore the
    // previous interface hierarchy on the next launch.
    func application(
        _ application: UIApplication,
        shouldSaveSecureApplicationState coder: NSCoder
    ) -> Bool {
        false
    }

    func application(
        _ application: UIApplication,
        shouldRestoreSecureApplicationState coder: NSCoder
    ) -> Bool {
        false
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let workoutId = response.notification.request.content.userInfo["workoutId"] as? String else { return }
        let requestId = response.notification.request.identifier
        let actionId = response.actionIdentifier
        await WorkoutReminders.shared.handle(workoutId: workoutId, requestId: requestId, actionId: actionId)
    }

    /// Called on the notification center's own queue; it reads only the
    /// request identifier, so it stays off the main actor.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // A rest ending in the app is announced by sound, not a banner.
        if notification.request.identifier == RestAlerts.notificationID { return [] }
        return [.banner, .list, .sound]
    }
}
