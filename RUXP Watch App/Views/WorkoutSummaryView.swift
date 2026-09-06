import SwiftUI

/// Post-workout on the wrist: XP earned (from the phone), level, and the essentials.
struct WorkoutSummaryView: View {
    let duration: TimeInterval
    let momentCount: Int
    let averageHeartRate: Double
    let totalCalories: Double
    let reward: WatchWorkoutManager.RewardSnapshot?
    let rewardStatus: WatchWorkoutManager.RewardSyncStatus
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("WORKOUT COMPLETE")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(WatchTheme.textPrimary)
                    .padding(.top, 4)

                rewardBlock

                HStack(spacing: 18) {
                    statCell(value: formattedDuration, label: "Time")
                    if averageHeartRate > 0 { statCell(value: "\(Int(averageHeartRate))", label: "BPM") }
                    if totalCalories > 0 { statCell(value: "\(Int(totalCalories))", label: "Cal") }
                    if momentCount > 0 { statCell(value: "\(momentCount)", label: momentCount == 1 ? "Note" : "Notes") }
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Continue")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(WatchTheme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(WatchTheme.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.horizontal, 6)
        }
        .containerBackground(WatchTheme.background.gradient, for: .navigation)
    }

    @ViewBuilder
    private var rewardBlock: some View {
        VStack(spacing: 4) {
            switch rewardStatus {
            case .received, .idle:
                if let reward {
                    Text("+\(reward.xp.grouped) XP")
                        .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(WatchTheme.accent)
                        .contentTransition(.numericText())
                    HStack(spacing: 6) {
                        Text("LVL \(reward.level)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(WatchTheme.textSecondary)
                        if reward.levelUp {
                            Text("LEVEL UP")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(WatchTheme.onAccent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(WatchTheme.accent, in: Capsule())
                        }
                        if reward.prCount > 0 {
                            Text("\(reward.prCount) PR")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(WatchTheme.accent)
                        }
                    }
                } else {
                    pending("XP syncs on iPhone")
                }
            case .waiting:
                HStack(spacing: 6) {
                    ProgressView().tint(WatchTheme.accent).controlSize(.small)
                    Text("Syncing XP").font(.system(.caption, design: .rounded)).foregroundStyle(WatchTheme.textSecondary)
                }
            case .phoneUnreachable:
                pending("XP syncs on iPhone")
            case .timedOut:
                pending("XP pending")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func pending(_ text: String) -> some View {
        VStack(spacing: 2) {
            Text("+\(ProgressionRules.workoutCompleteXP) XP")
                .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(WatchTheme.textSecondary)
            Text(text).font(.system(.caption2, design: .rounded)).foregroundStyle(WatchTheme.textTertiary)
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(WatchTheme.textPrimary)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(WatchTheme.textTertiary)
        }
    }

    private var formattedDuration: String {
        let total = Int(duration)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        return hrs > 0 ? String(format: "%d:%02d:%02d", hrs, mins, secs) : String(format: "%d:%02d", mins, secs)
    }
}
