import SwiftUI

struct WatchRootView: View {
    @Environment(WatchWorkoutManager.self) private var workoutManager

    var body: some View {
        NavigationStack {
            if workoutManager.isWorkoutActive {
                ActiveWorkoutView()
            } else {
                WatchHomeView()
            }
        }
    }
}
