import SwiftUI

@main
struct Mind2MuscleWatchApp: App {
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
