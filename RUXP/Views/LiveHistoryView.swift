import SwiftUI

/// "I was there." Every Live Session this player completed, newest first.
struct LiveHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LiveSessionService.self) private var liveSessions
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(GameCenterService.self) private var gameCenter

    @State private var durations: [UUID: TimeInterval] = [:]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                if liveSessions.history.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(liveSessions.history) { participation in
                            LiveHistoryRow(participation: participation, duration: duration(for: participation))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .statusBarBackdrop()
        .background(HUDBackground())
        .onAppear(perform: loadDurations)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            Text("Live sessions")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                BigNumber(value: liveSessions.completedCount, size: 44)
                Text(liveSessions.completedCount == 1 ? "SESSION COMPLETED" : "SESSIONS COMPLETED")
                    .eyebrow()
                    .foregroundStyle(Theme.textSecondary)
            }
            if gameCenter.authState != .disabled {
                Button { gameCenter.presentLeaderboard(id: GameCenterCatalog.liveSessions) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.number")
                        Text("Live sessions leaderboard")
                    }
                    .font(Theme.Fonts.label)
                    .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTHING YET").eyebrow().foregroundStyle(Theme.textSecondary)
            Text("Join a live session from Home and finish any strength workout while it's on. It lands here.")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(cornerRadius: Theme.radiusLarge)
    }

    private func duration(for participation: LiveSessionParticipation) -> TimeInterval? {
        participation.associatedWorkoutID.flatMap { durations[$0] }
    }

    private func loadDurations() {
        for participation in liveSessions.history {
            guard let id = participation.associatedWorkoutID, durations[id] == nil,
                  let session = workoutManager.workoutStore.loadSession(id: id),
                  let duration = session.duration else { continue }
            durations[id] = duration
        }
    }
}

/// One completed session. Shared by the lobby's history and the full list.
struct LiveHistoryRow: View {
    let participation: LiveSessionParticipation
    var duration: TimeInterval?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.xp)
                .frame(width: 30, height: 30)
                .background(Theme.xpSubtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(participation.title.capitalized)
                    .font(Theme.Fonts.title(16))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.Fonts.ui(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("+\(participation.xpEarned.grouped) XP")
                .font(Theme.Fonts.mono(14, weight: .heavy))
                .foregroundStyle(Theme.xp)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var subtitle: String {
        let date = (participation.occurrenceDate ?? participation.completedAt ?? participation.joinedAt)
            .formatted(.dateTime.month(.abbreviated).day().year())
        var parts = [date, "Completed"]
        if let duration {
            let minutes = Int(duration / 60)
            parts.append(minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes) min")
        }
        if let peers = participation.roomPeerCount, peers > 0 {
            parts.append(peers == 1 ? "1 player with you" : "\(peers) players with you")
        }
        return parts.joined(separator: " · ")
    }
}
