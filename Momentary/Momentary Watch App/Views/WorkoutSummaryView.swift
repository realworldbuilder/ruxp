import SwiftUI

struct WorkoutSummaryView: View {
    let duration: TimeInterval
    let momentCount: Int
    let averageHeartRate: Double
    let totalCalories: Double
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Success icon
                ZStack {
                    Circle()
                        .fill(WatchTheme.accent.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(WatchTheme.accent)
                }

                Text("Workout Complete")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(WatchTheme.textPrimary)

                // Stats grid
                HStack(spacing: 20) {
                    statCell(value: formattedDuration, label: "Duration", icon: "clock.fill", color: WatchTheme.accent)
                    statCell(value: "\(momentCount)", label: "Moments", icon: "waveform", color: WatchTheme.accent)
                }

                if averageHeartRate > 0 || totalCalories > 0 {
                    HStack(spacing: 20) {
                        if averageHeartRate > 0 {
                            statCell(value: "\(Int(averageHeartRate))", label: "Avg BPM", icon: "heart.fill", color: .red)
                        }
                        if totalCalories > 0 {
                            statCell(value: "\(Int(totalCalories))", label: "Calories", icon: "flame.fill", color: .orange)
                        }
                    }
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: WatchTheme.accentGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal)
        }
    }

    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(WatchTheme.textSecondary)
        }
    }

    private var formattedDuration: String {
        let total = Int(duration)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}
