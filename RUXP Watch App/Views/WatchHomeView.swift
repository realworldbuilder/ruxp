import SwiftUI

/// Watch home: who's lifting, what's live, your level, Start Workout. Training, not browsing.
struct WatchHomeView: View {
    @Environment(WatchWorkoutManager.self) private var workoutManager

    private var live: LiveSnapshot { workoutManager.livePresence.snapshot }
    private var activeEvent: LiveEvent? { workoutManager.events.activeEvent(at: ScheduledEventService.now()) }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    Text("RUXP")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(WatchTheme.textPrimary)
                    Spacer()
                    if let level = workoutManager.progression?.level {
                        Text("LVL \(level)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(WatchTheme.onAccent)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(WatchTheme.accent, in: Capsule())
                    }
                }

                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(live.liftingNow.grouped)
                            .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(WatchTheme.textPrimary)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: live.liftingNow)
                        WatchLiveDot(size: 5).offset(y: -8)
                    }
                    Text("LIFTING NOW")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(WatchTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)

                if let event = activeEvent {
                    HStack(spacing: 5) {
                        WatchLiveDot(size: 4)
                        Text(event.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(WatchTheme.accent)
                        Spacer(minLength: 0)
                        Text("+\(event.xpReward) XP")
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(WatchTheme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    workoutManager.startWorkout()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 15, weight: .bold))
                        Text("Start Workout")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(WatchTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(WatchTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                if let daysSince = daysSinceLastWorkout, daysSince > 0 {
                    Text("\(daysSince) day\(daysSince == 1 ? "" : "s") since your last lift")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(WatchTheme.textTertiary)
                }
            }
            .padding(.horizontal, 6)
        }
        .containerBackground(WatchTheme.background.gradient, for: .navigation)
    }

    private var daysSinceLastWorkout: Int? {
        guard let last = UserDefaults.standard.object(forKey: "lastWorkoutDate") as? Date else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }
}
