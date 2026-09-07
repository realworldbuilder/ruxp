import SwiftUI

/// The season ceremony. Shown once, on the first launch after a season closes: where you
/// finished, what you showed up for, what you keep. Then the next season starts.
struct SeasonRecapView: View {
    @Environment(ProgressionService.self) private var progression

    let record: SeasonRecord
    let closed: Season
    let next: Season

    @State private var revealed = 0
    @State private var revealTask: Task<Void, Never>?

    private var kept: [SeasonPassReward] { SeasonPassCatalog.kept(from: record) }

    var body: some View {
        ZStack {
            HUDBackground(glow: true)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if revealed >= 1 { levelBlock.transition(.move(edge: .bottom).combined(with: .opacity)) }
                    if revealed >= 2 { statsBlock.transition(.move(edge: .bottom).combined(with: .opacity)) }
                    if revealed >= 3 { keptBlock.transition(.move(edge: .bottom).combined(with: .opacity)) }
                    if revealed >= 4 { nextBlock.transition(.move(edge: .bottom).combined(with: .opacity)) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .statusBarBackdrop(fade: 24)
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
        .onAppear(perform: runReveal)
        .onDisappear { revealTask?.cancel() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SEASON \(closed.numberLabel) COMPLETE").eyebrow().foregroundStyle(Theme.violet)
            Text(closed.name.capitalized)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            SlantTag(text: "\(closed.code) · \(closed.name)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }

    private var levelBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                BigNumber(value: record.finalLevel, size: 64)
                Text("LVL").eyebrow().foregroundStyle(Theme.textSecondary)
            }
            Text("FINAL LEVEL · \(record.finalSeasonXP.grouped) XP")
                .font(Theme.Fonts.mono(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsBlock: some View {
        VStack(spacing: 0) {
            statRow("WORKOUTS", "\(record.seasonWorkoutCount) / \(record.goalWorkouts)", note: goalNote)
            divider
            statRow("LIVE SESSIONS", "\(record.liveSessionsCompleted)")
            divider
            statRow("FRIDAY NIGHTS", "\(record.fridayNightsAttended)")
            divider
            statRow("SUNDAY RESETS", "\(record.sundayResetsAttended)")
            divider
            statRow("PRS", "\(record.prCount)")
            divider
            statRow("PASS TIER", "\(SeasonPassCatalog.currentTier(level: record.finalLevel)) / \(SeasonPassCatalog.tierCount)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var goalNote: String? {
        if record.reachedGoal { return "Season goal done." }
        if record.goalWorkouts - record.seasonWorkoutCount <= 3 { return "Close." }
        return nil
    }

    private var divider: some View { Divider().overlay(Theme.divider) }

    private func statRow(_ title: String, _ value: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).eyebrow().foregroundStyle(Theme.textSecondary)
            Spacer()
            if let note {
                Text(note).font(Theme.Fonts.ui(.caption)).foregroundStyle(record.reachedGoal ? Theme.xp : Theme.textTertiary)
            }
            Text(value)
                .font(Theme.Fonts.mono(16))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 12)
    }

    private var keptBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("KEPT").eyebrow().foregroundStyle(Theme.textSecondary)
            if kept.isEmpty {
                Text("No tiers unlocked this season.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(keptLine)
                    .font(Theme.Fonts.mono(12))
                    .foregroundStyle(Theme.violet)
                    .lineLimit(3)
                Text("Yours for good. Equip them any time in Profile → Season Pass.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).stroke(Theme.borderNeon, lineWidth: 1))
    }

    private var keptLine: String {
        let names = kept.map(\.name)
        let shown = names.prefix(3)
        let extra = names.count - shown.count
        return extra > 0 ? shown.joined(separator: " · ") + " · +\(extra) more" : shown.joined(separator: " · ")
    }

    private var nextBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT: \(next.displayName)").eyebrow().foregroundStyle(Theme.secondary)
            Text("Everyone starts at LVL 1. \(next.goalWorkouts) workouts. \(next.tagline)")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textSecondary)
            PrimaryButton(title: "Start Season \(next.numberLabel)") {
                revealTask?.cancel()
                progression.acknowledgeSeasonRecap()
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Reveal

    private func runReveal() {
        guard revealed == 0 else { return }
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            for step in 1...4 {
                try? await Task.sleep(for: .milliseconds(step == 1 ? 350 : 500))
                guard !Task.isCancelled else { return }
                withAnimation(Theme.Motion.reveal) { revealed = step }
                if step == 1 { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
        }
    }
}
