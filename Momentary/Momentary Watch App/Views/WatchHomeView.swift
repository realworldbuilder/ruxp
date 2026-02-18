import SwiftUI

struct WatchHomeView: View {
    @Environment(WatchWorkoutManager.self) private var workoutManager

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image("AppIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Text("M2M")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(WatchTheme.textPrimary)
            
            Spacer()
            
            Button {
                workoutManager.startWorkout()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Start Workout")
                        .font(.system(.headline, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(WatchTheme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.horizontal, 8)
    }
}
