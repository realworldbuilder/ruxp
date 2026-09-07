import SwiftUI

/// The Training Room, in the lobby (full) or during a workout (compact). Members are real
/// Game Center players; when nobody is connected the panel says so instead of pretending.
struct LiveRoomPanel: View {
    @Environment(\.liveRoom) private var room
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(ProgressionService.self) private var progression


    let event: LiveEvent
    var compact = false

    var body: some View {
        if let room, room.isAvailable {
            Group {
                if compact {
                    compactBody(room)
                } else {
                    fullBody(room)
                }
            }
        }
    }

    // MARK: - Lobby

    private func fullBody(_ room: any LiveRoomProviding) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR ROOM").eyebrow().foregroundStyle(Theme.textSecondary)
                Spacer()
                if room.state.isLive {
                    Text("\(room.members.count + 1) TRAINING").eyebrow().foregroundStyle(Theme.accent)
                }
            }

            switch room.state {
            case .idle:
                Text("Train alongside a few other players in this session. Reactions only, no chat. The room stays open while RUXP is on screen.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textSecondary)
                SecondaryButton(title: "JOIN A ROOM", icon: "person.2.fill") { room.join(event: event) }

            case .unavailable(let message):
                Text(message).font(Theme.Fonts.body).foregroundStyle(Theme.textTertiary)

            case .searching, .connecting:
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.accent).controlSize(.small)
                    Text(room.state == .searching ? "Looking for players…" : "Connecting…")
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    PillButton(title: "Cancel", fill: Theme.surfaceElevated, textColor: Theme.textPrimary) { room.leave() }
                }

            case .live:
                memberRow(room)
                reactionBar(room)
                Button { room.leave() } label: {
                    Text("Leave room").font(Theme.Fonts.label).foregroundStyle(Theme.textTertiary)
                }

            case .failed(let message):
                Text(message).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                SecondaryButton(title: "TRY AGAIN", icon: "arrow.clockwise") { room.join(event: event) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .stroke(room.state.isLive ? Theme.borderNeon : Theme.border, lineWidth: 1)
        )
    }

    private func memberRow(_ room: any LiveRoomProviding) -> some View {
        let names = [gameCenter.alias ?? "You"] + room.members.map(\.displayName)
        let shown = names.prefix(4)
        let extra = names.count - shown.count
        let loadout = SeasonPassCatalog.loadout(for: progression.progress, season: progression.season)
        return HStack(spacing: 8) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, name in
                HStack(spacing: 4) {
                    // Your own pill carries your Season Pass badge; other players' loadouts are not shared.
                    if index == 0, let badge = loadout.badge {
                        Image(systemName: badge).font(.system(size: 9, weight: .bold)).foregroundStyle(loadout.nameColor ?? Theme.accent)
                    }
                    Text(name)
                        .font(Theme.Fonts.mono(12))
                        .foregroundStyle(index == 0 ? (loadout.nameColor ?? Theme.textPrimary) : Theme.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.surfaceElevated, in: Capsule())
            }

            if extra > 0 {
                Text("+\(extra)").font(Theme.Fonts.mono(12)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func reactionBar(_ room: any LiveRoomProviding) -> some View {
        HStack(spacing: 10) {
            ForEach(LiveReaction.allCases) { reaction in
                Button {
                    room.send(reaction)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Text(reaction.glyph).font(.system(size: 18, weight: .bold))
                        if let count = room.reactionCounts[reaction], count > 0 {
                            Text("\(count)").font(Theme.Fonts.mono(12)).foregroundStyle(Theme.textSecondary)
                                .contentTransition(.numericText())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    // MARK: - During workout

    /// One quiet row under the event chip: room size, reaction totals, and the four buttons.
    @ViewBuilder
    private func compactBody(_ room: any LiveRoomProviding) -> some View {
        if room.state.isLive {
            HStack(spacing: 12) {
                Text("Your room: \(room.members.count + 1)")
                    .font(Theme.Fonts.label).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                if let latest = room.recentReactions.last {
                    Text("\(latest.senderName) \(latest.reaction.glyph)")
                        .font(Theme.Fonts.label)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .transition(.opacity)
                        .id(latest.id)
                }
                Spacer()
                ForEach(LiveReaction.allCases) { reaction in
                    Button {
                        room.send(reaction)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 1) {
                            Text(reaction.glyph).font(.system(size: 15, weight: .bold))
                            Text("\(room.reactionCounts[reaction] ?? 0)")
                                .font(Theme.Fonts.mono(9))
                                .foregroundStyle(Theme.textTertiary)
                                .contentTransition(.numericText())
                        }
                        .frame(width: 34)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .animation(Theme.Motion.snappy, value: room.recentReactions.count)
            .overlay(alignment: .bottom) { Divider().overlay(Theme.divider) }
        }
    }
}
