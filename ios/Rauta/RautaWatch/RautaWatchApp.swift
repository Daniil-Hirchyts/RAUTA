import SwiftUI

@main
struct RautaWatchApp: App {
    @StateObject private var watchSession = WatchSessionModel()
    @StateObject private var workoutManager = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
                .environmentObject(watchSession)
                .environmentObject(workoutManager)
                .preferredColorScheme(.dark)
        }
    }
}
