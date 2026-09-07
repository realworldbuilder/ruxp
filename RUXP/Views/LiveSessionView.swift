import SwiftUI

/// The lobby. You joined an event; here is who is in it, what to do, and the one button that
/// matters. Presented full-screen from Home. Starting a workout hands off to Home via
/// `onStartWorkout` so the workout cover (owned by MainTabView) presents cleanly.
struct LiveSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(ProgressionService.self) private var progression
    @Environment(LiveSessionService.self) private var liveSessions
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(\.livePresence) private var presence

    let event: LiveEvent
    let onStartWorkout: () -> Void

    @State private var now = ScheduledEventService.now()
    @State private var friends: [GameCenterService.LiveFriend] = []
    @State private var durations: [UUID: TimeInterval] = [:]
    private let clock = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    private var participation: LiveSessionParticipation? { liveSessions.participation(for: event) }
    private var completed: Bool { participation?.completed ?? false }
    private var isLive: Bool { event.isActive(at: now) }
    private var participants: Int { liveSessions.participantCount(for: event) }
    private var presenceAvailable: Bool { presence?.snapshot.isAvailable ?? false }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                hero
                statusCard
                if !completed {
                    PrimaryButton(title: "START WORKOUT", icon: "bolt.fill") { onStartWorkout() }
                }
                friendsSection
                LiveRoomPanel(event: event)
                historySection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .statusBarBackdrop()
        .background(HUDBackground(glow: isLive))
        .onReceive(clock) { _ in now = ScheduledEventService.now() }
        .onAppear {
            now = ScheduledEventService.now()
            loadDurations()
        }
        .task { friends = await gameCenter.loadFriendsOnSeasonBoard() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("RUXP LIVE").eyebrow().foregroundStyle(Theme.live)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(Theme.Fonts.ui(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
        }
        .padding(.top, 6)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if isLive {
                    LiveDot(label: "LIVE")
                } else if event.isUpcoming(at: now) {
                    Text("STARTS \(event.startLabel(now: now))").eyebrow().foregroundStyle(Theme.warning)
                } else {
                    Text("ENDED").eyebrow().foregroundStyle(Theme.textTertiary)
                }
                if isLive {
                    Text(event.endsInLabel(now: now).uppercased()).eyebrow().foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                XPChip(amount: event.xpReward, prominent: true)
            }
            Text(event.title)
                .font(Theme.Fonts.display(30))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(event.description)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if completed {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.xp)
                    Text("\(event.title) COMPLETE").eyebrow().foregroundStyle(Theme.xp)
                }
                Text("+\(participation?.xpEarned.grouped ?? "0") XP")
                    .font(Theme.Fonts.number(30))
                    .foregroundStyle(Theme.xp)
                Text("You showed up.")
                    .font(Theme.Fonts.title(16))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text("YOU'RE IN").eyebrow().foregroundStyle(Theme.accent)
                Text("Complete any strength workout while it's live. Train however you want.")
                    .font(Theme.Fonts.title(16))
                    .foregroundStyle(Theme.textPrimary)
                Text("+\(event.xpReward.grouped) XP on completion, on top of your workout XP.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textSecondary)
            }

            Divider().overlay(Theme.divider)

            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(Theme.Fonts.ui(.caption, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                Text("Joined as \(gameCenter.alias ?? progression.progress.displayName)")
                    .font(Theme.Fonts.label)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                LiveDot(label: nil, size: 7)
                Text(participantsLine)
                    .font(Theme.Fonts.label).monospacedDigit()
                    .foregroundStyle(presenceAvailable ? Theme.textPrimary : Theme.textTertiary)
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.snappy, value: participants)
            }

            if completed, gameCenter.authState != .disabled {
                Button { gameCenter.presentLeaderboard(id: GameCenterCatalog.liveSessions) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.number")
                        Text("Live sessions leaderboard")
                    }
                    .font(Theme.Fonts.label)
                    .foregroundStyle(Theme.accent)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .stroke(Theme.borderNeon, lineWidth: 1)
        )
    }

    /// Real counts only. Small numbers are shown as they are.
    private var participantsLine: String {
        guard presenceAvailable else { return gameCenter.presenceUnavailableMessage }
        guard isLive else { return "Counts appear once it's live." }
        switch participants {
        case 0: return "Nobody's in yet. You could be first."
        case 1: return "You're the first one in."
        default: return "\(participants.grouped) players joined"
        }
    }

    // MARK: - Friends / invite

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !friends.isEmpty {
                Text("FRIENDS IN RUXP").eyebrow().foregroundStyle(Theme.textSecondary)
                VStack(spacing: 8) {
                    ForEach(friends.prefix(6)) { friend in
                        HStack {
                            Text(friend.displayName)
                                .font(Theme.Fonts.title(15))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("LVL \(friend.level)")
                                .font(Theme.Fonts.mono(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                Divider().overlay(Theme.divider)
            } else {
                Text("INVITE A FRIEND").eyebrow().foregroundStyle(Theme.textSecondary)
                Text("Nobody trains alone. Bring someone in.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            ShareLink(item: event.shareText) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text(friends.isEmpty ? "Invite a friend" : "Invite another friend")
                }
                .font(Theme.Fonts.ui(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.surfaceElevated, in: Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        let recent = liveSessions.history.filter { $0.sessionID != event.id }.prefix(5)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("YOUR HISTORY").eyebrow().foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(liveSessions.completedCount) COMPLETED").eyebrow().foregroundStyle(Theme.textTertiary)
                }
                ForEach(Array(recent)) { participation in
                    LiveHistoryRow(participation: participation, duration: participation.associatedWorkoutID.flatMap { durations[$0] })
                }
            }
        }
    }

    private func loadDurations() {
        for participation in liveSessions.history.prefix(6) {
            guard let id = participation.associatedWorkoutID, durations[id] == nil,
                  let duration = workoutManager.workoutStore.loadSession(id: id)?.duration else { continue }
            durations[id] = duration
        }
    }
}
