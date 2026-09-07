import SwiftUI

/// The free Season Pass ladder. Tier N unlocks at level N; unlocked cosmetics can be equipped.
/// Pass a finished `season` to open its archived ladder: what was unlocked stays equippable,
/// what was not stays locked for good.
struct SeasonPassView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProgressionService.self) private var progression

    var season: Season? = nil

    private var p: PlayerProgress { progression.progress }
    private var shown: Season { season ?? progression.season }
    private var archived: Bool { shown.id != progression.season.id }
    private var record: SeasonRecord? { p.seasonRecord(for: shown.id) }
    private var unlockLevel: Int { SeasonPassCatalog.unlockLevel(seasonID: shown.id, progress: p, currentSeason: progression.season) }
    private var rewards: [SeasonPassReward] { SeasonPassCatalog.rewards(for: shown) }
    private var currentTier: Int { SeasonPassCatalog.currentTier(level: unlockLevel) }
    private var next: SeasonPassReward? { SeasonPassCatalog.next(after: unlockLevel, season: shown) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                VStack(spacing: 10) {
                    ForEach(rewards) { reward in
                        tierRow(reward)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .statusBarBackdrop()
        .background(HUDBackground())
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("SEASON PASS · \(shown.code)").eyebrow().foregroundStyle(Theme.violet)
                if archived {
                    SlantTag(text: "ARCHIVED", fill: Theme.surfaceElevated, textColor: Theme.textSecondary, size: 10)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.surfaceElevated, in: Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Text(shown.name)
                .font(Theme.Fonts.title(24))
                .foregroundStyle(Theme.textPrimary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("TIER").eyebrow().foregroundStyle(Theme.textSecondary)
                Text("\(currentTier)")
                    .font(Theme.Fonts.number(36))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("/ \(SeasonPassCatalog.tierCount)")
                    .font(Theme.Fonts.mono(14))
                    .foregroundStyle(Theme.textTertiary)
            }
            if archived {
                Text(record.map { "FINAL · LVL \($0.finalLevel) · \($0.seasonWorkoutCount) / \($0.goalWorkouts) WORKOUTS" } ?? "NOT PLAYED")
                    .font(Theme.Fonts.mono(12))
                    .foregroundStyle(Theme.textSecondary)
                Text("Locked tiers stay locked. Unlocked ones are yours for good.")
                    .font(Theme.Fonts.ui(.caption))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                XPBar(level: p.level, xpIntoLevel: p.xpIntoLevel, xpToNext: p.xpToNextLevel, compact: true)
                Text(next.map { "NEXT: TIER \($0.tier) · \($0.name)" } ?? "ALL \(SeasonPassCatalog.tierCount) TIERS UNLOCKED")
                    .font(Theme.Fonts.mono(12))
                    .foregroundStyle(Theme.textSecondary)
                Text("Free track. Every level unlocks something. Cosmetics only, no purchases. Finish the pass by showing up: both rituals, every week.")
                    .font(Theme.Fonts.ui(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .padding(.top, 10)
    }

    // MARK: - Tier rows

    private func tierRow(_ reward: SeasonPassReward) -> some View {
        let unlocked = SeasonPassCatalog.isUnlocked(reward, level: unlockLevel)
        let equipped = unlocked && SeasonPassCatalog.isEquipped(reward, in: p)
        return HStack(spacing: 14) {
            Text("\(reward.tier)")
                .font(Theme.Fonts.number(18))
                .foregroundStyle(unlocked ? Theme.violet : Theme.textTertiary)
                .frame(width: 44, height: 44)
                .background(unlocked ? Theme.violetSubtle : Theme.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    if reward.kind == .badge {
                        Image(systemName: reward.value)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(unlocked ? Theme.textPrimary : Theme.textTertiary)
                    }
                    Text(reward.name)
                        .font(Theme.Fonts.title(16))
                        .foregroundStyle(unlocked ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(spacing: 6) {
                    SlantTag(text: reward.kind.label, fill: Theme.violetSubtle, textColor: Theme.violet, size: 10)
                    if let color = reward.color {
                        Circle().fill(color).frame(width: 10, height: 10)
                    }
                    if !unlocked && !archived {
                        Text("LVL \(reward.tier)")
                            .font(Theme.Fonts.mono(11))
                            .foregroundStyle(Theme.textTertiary)
                    }

                }
            }
            Spacer(minLength: 8)
            if !unlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 32)
            } else if equipped {
                SlantTag(text: "EQUIPPED", fill: Theme.xpSubtle, textColor: Theme.xp, size: 10)
            } else {
                PillButton(title: "Equip") { equip(reward) }
            }
        }
        .padding(14)
        .opacity(unlocked ? 1 : 0.55)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .stroke(equipped ? Theme.borderNeon : Theme.border, lineWidth: 1)
        )
    }

    private func equip(_ reward: SeasonPassReward) {
        withAnimation(Theme.Motion.snappy) {
            progression.setEquippedCosmetic(kind: reward.kind.rawValue, rewardID: reward.id)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
