import SwiftUI

struct WatchHomeView: View {
    @Environment(WatchWorkoutManager.self) private var workoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Logo / Brand
                VStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(WatchTheme.accent)
                    
                    Text("M2M")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(WatchTheme.textPrimary)
                    
                    Text("Voice-First Training")
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.textSecondary)
                }
                .padding(.top, 4)

                // Start Workout Button
                Button {
                    workoutManager.startWorkout()
                } label: {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(WatchTheme.accent.opacity(0.15))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: "mic.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        Text("Start Workout")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text("Tap to begin voice tracking")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: WatchTheme.accentGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start workout")
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("M2M")
    }
}
