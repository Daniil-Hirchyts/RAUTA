import SwiftUI
import UIKit

@main
struct RautaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .environment(\.appStore, AppStore.shared)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppStore.shared.bootstrap()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        AppStore.shared.persistNow()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AppStore.shared.persistNow()
    }
}
