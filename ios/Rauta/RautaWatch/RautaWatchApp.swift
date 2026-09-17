import SwiftUI
import WatchKit

@main
struct RautaWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
                .environmentObject(WatchSessionModel.shared)
                .environmentObject(WatchWorkoutManager.shared)
                .preferredColorScheme(.dark)
                .tint(WatchPalette.primary)
        }
    }
}

/// Starts the phone link and the workout that follows it at launch, before any
/// view exists — and after a crash, when the system relaunches the app into a
/// workout that is still running.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchSessionModel.shared.start()
        WatchWorkoutManager.shared.follow(WatchSessionModel.shared)
    }

    func handleActiveWorkoutRecovery() {
        WatchWorkoutManager.shared.recoverActiveWorkout()
    }
}
