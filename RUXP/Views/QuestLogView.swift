import SwiftUI

/// Every quest, both chains, with what is cleared and when. Opened from the Home card and
/// Profile. Stays after everything is clear: it is history.
struct QuestLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(QuestService.self) private var quests

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                if quests.isAllClear { allClear }
                ForEach(QuestCatalog.chains) { chain in
                    chainSection(chain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .statusBarBackdrop()
        .background(HUDBackground())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("QUESTS").eyebrow().foregroundStyle(Theme.secondary)
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
            Text("Quests")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                BigNumber(value: quests.clearedCount, size: 44)
                Text("OF \(quests.totalCount) CLEARED")
                    .eyebrow()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, 6)
    }

    private var allClear: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALL CLEAR").eyebrow().foregroundStyle(Theme.xp)
            Text("From here it's rituals: Friday night, Sunday reset, and whatever is on tonight.")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(cornerRadius: Theme.radiusLarge)
    }

    private func chainSection(_ chain: QuestChain) -> some View {
        let count = quests.count(in: chain)
        let locked = !quests.isUnlocked(chain)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: chain.name, trailing: "\(count.cleared) OF \(count.total)")
            if locked, let required = chain.requires, let parent = QuestCatalog.chain(id: required) {
                Text("Clear \(parent.name) first.")
                    .font(Theme.Fonts.ui(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(quests.entries(in: chain)) { entry in
                QuestRow(entry: entry)
            }
            .opacity(locked ? 0.5 : 1)
        }
    }
}

/// One quest: cleared or not, when, and what it paid.
struct QuestRow: View {
    let entry: QuestService.Entry

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if entry.isCleared {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.xp)
                } else {
                    Text("\(entry.number)")
                        .font(Theme.Fonts.mono(13, weight: .heavy))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 30, height: 30)
            .background(entry.isCleared ? Theme.xpSubtle : Theme.surfaceElevated,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.quest.title.capitalized)
                    .font(Theme.Fonts.title(16))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.Fonts.ui(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var subtitle: String {
        guard let completion = entry.completion else { return entry.quest.how }
        return "Cleared · " + completion.completedAt.formatted(date: .abbreviated, time: .omitted)
    }

    @ViewBuilder
    private var trailing: some View {
        if let completion = entry.completion {
            if completion.backfilled {
                SlantTag(text: "Cleared", fill: Theme.xpSubtle, textColor: Theme.xp, size: 10)
            } else if case .perQuest(let amount) = entry.chain.reward {
                Text("+\(amount.grouped) XP")
                    .font(Theme.Fonts.mono(14, weight: .heavy))
                    .foregroundStyle(Theme.xp)
            }
        }
    }
}
