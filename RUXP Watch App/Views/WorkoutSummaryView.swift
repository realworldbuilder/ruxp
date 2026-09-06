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
                    .font(.system(size: 13, weight: .semibold))
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
                        .font(WatchTheme.Fonts.tagline(15))
                        .foregroundStyle(WatchTheme.onButton)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(WatchTheme.button, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.horizontal, 6)
        }
        .containerBackground(WatchTheme.backgroundGradient, for: .navigation)
    }

    @ViewBuilder
    private var rewardBlock: some View {
        VStack(spacing: 4) {
            switch rewardStatus {
            case .received, .idle:
                if let reward {
                    Text("+\(reward.xp.grouped) XP")
                        .font(WatchTheme.Fonts.number(26))
                        .foregroundStyle(WatchTheme.xp)
                        .contentTransition(.numericText())
                    HStack(spacing: 6) {
                        Text("LVL \(reward.level)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WatchTheme.textSecondary)
                        if reward.levelUp {
                            Text("LEVEL UP")
                                .font(WatchTheme.Fonts.tagline(9))
                                .foregroundStyle(WatchTheme.onAccent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(WatchTheme.accent, in: Capsule())
                        }
                        if reward.prCount > 0 {
                            Text("\(reward.prCount) PR")
                                .font(WatchTheme.Fonts.tagline(9))
                                .foregroundStyle(WatchTheme.accent)
                        }
                    }
                } else {
                    pending("XP syncs on iPhone")
                }
            case .waiting:
                HStack(spacing: 6) {
                    ProgressView().tint(WatchTheme.accent).controlSize(.small)
                    Text("Syncing XP").font(WatchTheme.Fonts.caption).foregroundStyle(WatchTheme.textSecondary)
                }
            case .phoneUnreachable:
                pending("XP syncs on iPhone")
            case .timedOut:
                pending("XP pending")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func pending(_ text: String) -> some View {
        VStack(spacing: 2) {
            Text("+\(ProgressionRules.workoutCompleteXP) XP")
                .font(WatchTheme.Fonts.number(22))
                .foregroundStyle(WatchTheme.textSecondary)
            Text(text).font(WatchTheme.Fonts.caption2).foregroundStyle(WatchTheme.textTertiary)
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(WatchTheme.Fonts.mono(14))
                .foregroundStyle(WatchTheme.textPrimary)
            Text(label)
                .watchEyebrow()
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
