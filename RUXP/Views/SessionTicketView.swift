import SwiftUI

/// Proof you were there. One card per completed session: the night's numbers and yours.
/// Presented as a sheet from history, the lobby, and the reward screen.
struct SessionTicketView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProgressionService.self) private var progression
    @Environment(GameCenterService.self) private var gameCenter
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue

    let participation: LiveSessionParticipation
    /// Loaded by the presenter when the record predates `durationSeconds`.
    var duration: TimeInterval? = nil

    @State private var shareImage: Image?

    var body: some View {
        ZStack {
            HUDBackground()
            VStack(spacing: 20) {
                HStack {
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
                SessionTicketCard(participation: participation, duration: duration, weightUnit: weightUnit,
                                  alias: gameCenter.alias ?? progression.progress.displayName)
                if let shareImage {
                    ShareLink(item: shareImage, preview: SharePreview("\(participation.title.capitalized) on RUXP", image: shareImage)) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share ticket")
                        }
                        .font(Theme.Fonts.ui(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.surfaceElevated, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: renderShareImage)
    }

    private func renderShareImage() {
        let renderer = ImageRenderer(content:
            SessionTicketCard(participation: participation, duration: duration, weightUnit: weightUnit,
                              alias: gameCenter.alias ?? progression.progress.displayName)
                .padding(20)
                .background(Theme.background)
                .frame(width: 390)
        )
        renderer.scale = 3
        if let image = renderer.uiImage { shareImage = Image(uiImage: image) }
    }
}

/// The card itself, also rendered to an image for sharing. No environment reads so
/// `ImageRenderer` gets everything it needs.
struct SessionTicketCard: View {
    let participation: LiveSessionParticipation
    var duration: TimeInterval?
    let weightUnit: String
    let alias: String

    private var minutes: Int? {
        (participation.durationSeconds ?? duration).map { Int($0 / 60) }
    }

    private var dateLine: String {
        (participation.occurrenceDate ?? participation.completedAt ?? participation.joinedAt)
            .formatted(.dateTime.month(.wide).day().year())
            .uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                LiveDot(label: nil, size: 7)
                Text("RUXP LIVE").eyebrow().foregroundStyle(Theme.live)
                Spacer()
                RUXPWordmark(size: 14)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(participation.title)
                    .font(Theme.Fonts.display(28))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(dateLine)
                    .font(Theme.Fonts.mono(12))
                    .foregroundStyle(Theme.textSecondary)
            }

            if participation.sessionLifters != nil || participation.sessionTotalLB != nil {
                HStack(spacing: 18) {
                    if let lifters = participation.sessionLifters, lifters > 0 {
                        stat(value: lifters.grouped, label: lifters == 1 ? "LIFTER" : "LIFTERS")
                    }
                    if let total = participation.sessionTotalLB, total > 0 {
                        stat(value: VolumeFormat.amount(total, unit: weightUnit).groupedLB,
                             label: "\(VolumeFormat.unitLabel(weightUnit)) MOVED\(participation.objectiveMet ? " · GOAL" : "")")
                    }
                }
            }

            Divider().overlay(Theme.divider)

            VStack(alignment: .leading, spacing: 6) {
                Text("YOU CONTRIBUTED").eyebrow().foregroundStyle(Theme.textSecondary)
                if let volume = participation.volumeContributedLB, volume > 0 {
                    Text(VolumeFormat.text(volume, unit: weightUnit))
                        .font(Theme.Fonts.number(34))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Text("No sets logged")
                        .font(Theme.Fonts.title(18))
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 10) {
                    if let minutes, minutes > 0 {
                        Text("\(minutes) MIN").font(Theme.Fonts.mono(12)).foregroundStyle(Theme.textSecondary)
                    }
                    if participation.xpEarned > 0 {
                        Text("+\(participation.xpEarned.grouped) XP").font(Theme.Fonts.mono(12, weight: .heavy)).foregroundStyle(Theme.xp)
                    }
                    if let peers = participation.roomPeerCount, peers > 0 {
                        Text("ROOM OF \(peers + 1)").font(Theme.Fonts.mono(12)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            Divider().overlay(Theme.divider)

            HStack {
                Text("YOU WERE HERE.").eyebrow().foregroundStyle(Theme.accent)
                Spacer()
                Text(alias.uppercased())
                    .font(Theme.Fonts.mono(11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(22)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).stroke(Theme.borderNeon, lineWidth: 1))
        .overlay(HUDCorners(length: 12, inset: -1).stroke(Theme.violet.opacity(0.7), lineWidth: 1.5))
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(Theme.Fonts.number(22))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).eyebrow().foregroundStyle(Theme.textTertiary)
        }
    }
}
