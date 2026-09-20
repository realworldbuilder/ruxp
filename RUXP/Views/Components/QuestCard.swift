import SwiftUI

/// The quest tracker. Full form on Home: the chain eyebrow, the featured quest, how to clear it,
/// one segment per quest in the chain. Compact form on the workout screen: one line. Quiet on
/// purpose; the event card owns the hero number.
struct QuestCard: View {
    let entry: QuestService.Entry
    /// Quests cleared in this entry's chain.
    let cleared: Int
    var compact = false
    /// Shown as a Start pill when the featured quest is PRESS START and nothing is running.
    var onStart: (() -> Void)? = nil
    var onOpen: () -> Void = {}

    private var eyebrow: String {
        "\(entry.chain.name) · QUEST \(entry.number) OF \(entry.chain.quests.count)"
    }

    var body: some View {
        if compact {
            compactBody
        } else {
            Button(action: onOpen) { fullBody }
                .buttonStyle(PressableButtonStyle())
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow).eyebrow().foregroundStyle(Theme.secondary)
            Text(entry.quest.how)
                .font(Theme.Fonts.label)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.5))
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(eyebrow).eyebrow().foregroundStyle(Theme.secondary)
                Spacer()
                if case .perQuest(let amount) = entry.chain.reward {
                    XPChip(amount: amount, prominent: false)
                }
            }
            Text(entry.quest.title.capitalized)
                .font(Theme.Fonts.title(18))
                .foregroundStyle(Theme.textPrimary)
            Text(entry.quest.how)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if case .onClear(let amount, _) = entry.chain.reward {
                Text("+\(amount.grouped) XP when all \(entry.chain.quests.count) are cleared")
                    .font(Theme.Fonts.mono(12, weight: .semibold))
                    .foregroundStyle(Theme.xp)
            }
            HStack(spacing: 6) {
                ForEach(0..<entry.chain.quests.count, id: \.self) { index in
                    Capsule()
                        .fill(index < cleared ? Theme.xp : Theme.surfaceElevated)
                        .frame(height: 3)
                }
                if let onStart {
                    PillButton(title: "Start", action: onStart)
                        .padding(.leading, 8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(Theme.Fonts.ui(.caption, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 6)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
    }
}
