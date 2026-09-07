import SwiftUI

struct WatchRootView: View {
    @Environment(WatchWorkoutManager.self) private var workoutManager

    var body: some View {
        NavigationStack {
            if workoutManager.isWorkoutActive {
                // Keyed on the workout so a phone-started workout that replaces a lingering
                // summary never inherits the old view's `showSummary` state.
                ActiveWorkoutView()
                    .id(workoutManager.currentWorkoutID)
            } else {
                WatchHomeView()
            }
        }
    }
}
