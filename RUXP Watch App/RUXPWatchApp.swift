import SwiftUI

@main
struct RUXPWatchApp: App {
    @State private var workoutManager = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(workoutManager)
                .task {
                    await workoutManager.healthKitService.requestAuthorization()
                }
        }
    }
}
