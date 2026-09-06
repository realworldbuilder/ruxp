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
                        .font(WatchTheme.Fonts.display(15))
                        .foregroundStyle(WatchTheme.textPrimary)
                    Spacer()
                    if let level = workoutManager.progression?.level {
                        Text("LVL \(level)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WatchTheme.accent)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(WatchTheme.accent.opacity(0.14), in: Capsule())
                    }
                }

                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(live.isFresh() ? live.liftingNow.grouped : "—")
                            .font(WatchTheme.Fonts.number(26))
                            .foregroundStyle(WatchTheme.textPrimary)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: live.liftingNow)
                        WatchLiveDot(size: 5).offset(y: -8)
                    }
                    Text("LIFTING NOW")
                        .watchEyebrow()
                        .foregroundStyle(WatchTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)

                if let event = activeEvent {
                    HStack(spacing: 5) {
                        WatchLiveDot(size: 4)
                        Text(event.title)
                            .font(WatchTheme.Fonts.tagline(11))
                            .foregroundStyle(WatchTheme.accent)
                        Spacer(minLength: 0)
                        Text("+\(event.xpReward) XP")
                            .font(WatchTheme.Fonts.mono(10))
                            .foregroundStyle(WatchTheme.xp)
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
                            .font(WatchTheme.Fonts.tagline(15))
                    }
                    .foregroundStyle(WatchTheme.onButton)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(WatchTheme.button, in: Capsule())
                }
                .buttonStyle(.plain)

                if let daysSince = daysSinceLastWorkout, daysSince > 0 {
                    Text("\(daysSince) day\(daysSince == 1 ? "" : "s") since your last lift")
                        .font(WatchTheme.Fonts.caption2)
                        .foregroundStyle(WatchTheme.textTertiary)
                }
            }
            .padding(.horizontal, 6)
        }
        .containerBackground(WatchTheme.backgroundGradient, for: .navigation)
    }

    private var daysSinceLastWorkout: Int? {
        guard let last = UserDefaults.standard.object(forKey: "lastWorkoutDate") as? Date else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }
}
