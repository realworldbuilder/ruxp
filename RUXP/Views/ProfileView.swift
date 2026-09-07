import SwiftUI

/// Player card: level, XP, career stats. No feed, no followers.
struct ProfileView: View {
    @Environment(ProgressionService.self) private var progression
    @Environment(InsightsStore.self) private var insightsStore
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(LiveSessionService.self) private var liveSessions

    @State private var showLiveHistory = false
    @State private var showNameEditor = false
    @State private var nameDraft = ""
    @State private var showPRs = false
    @State private var showLifetime = false
    @State private var showSettings = false
    @State private var showSeasonPass = false
    @State private var archivedSeason: Season?

    private var p: PlayerProgress { progression.progress }
    private var loadout: SeasonPassLoadout { SeasonPassCatalog.loadout(for: p, season: progression.season) }
    private var seasonPassSubtitle: String {
        let tier = SeasonPassCatalog.currentTier(level: p.level)
        if let next = SeasonPassCatalog.next(after: p.level, season: progression.season) {
            return "Tier \(tier) of \(SeasonPassCatalog.tierCount) · next: \(next.name.capitalized)"
        }
        return "All \(SeasonPassCatalog.tierCount) tiers unlocked"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    identity
                    XPBar(level: p.level, xpIntoLevel: p.xpIntoLevel, xpToNext: p.xpToNextLevel)
                        .padding(20)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    statsGrid
                    seasonsSection
                    links
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .statusBarBackdrop()
            .background(HUDBackground())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                #if DEBUG
                // -RUXPScreen settings|livehistory|archivedpass (pair with -RUXPTab profile).
                // Presented after a beat: a sheet requested during the very first appearance is dropped.
                guard let screen = DebugScreen.requested else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    switch screen {
                    case .settings: showSettings = true
                    case .liveHistory: showLiveHistory = true
                    case .archivedPass: archivedSeason = (p.seasonHistory ?? []).last.flatMap { SeasonCatalog.season(id: $0.seasonID) }
                    default: break
                    }
                }

                #endif
            }
        }
        .alert("Display name", isPresented: $showNameEditor) {

            TextField("Name", text: $nameDraft)
            Button("Save") { progression.setDisplayName(nameDraft) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown on your player card.")
        }
        .fullScreenCover(isPresented: $showSeasonPass) {
            SeasonPassView()
        }
        .fullScreenCover(item: $archivedSeason) { season in
            SeasonPassView(season: season)
        }
        .fullScreenCover(isPresented: $showLiveHistory) {
            LiveHistoryView()
        }
        .fullScreenCover(isPresented: $showPRs) {
            PRDetailView(personalRecords: insightsStore.personalRecords)
        }
        .fullScreenCover(isPresented: $showLifetime) {
            LifetimeDetailView(stats: insightsStore.lifetimeStats, weeklySnapshots: insightsStore.weeklySnapshots)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Identity

    private var identity: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PLAYER").eyebrow().foregroundStyle(Theme.textSecondary)
                Button {
                    nameDraft = p.displayName
                    showNameEditor = true
                } label: {
                    HStack(spacing: 8) {
                        Text(p.displayName)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(loadout.nameColor ?? Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if let badge = loadout.badge {
                            Image(systemName: badge)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(loadout.nameColor ?? Theme.accent)
                        }
                        Image(systemName: "pencil")
                            .font(Theme.Fonts.ui(.caption, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                if let title = loadout.title {
                    Text(title)
                        .font(Theme.Fonts.mono(12))
                        .foregroundStyle(loadout.nameColor ?? Theme.textSecondary)
                }
                SlantTag(text: "\(progression.season.code) · \(progression.season.name)")
                    .padding(.top, 2)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("LVL").eyebrow().foregroundStyle(Theme.textSecondary)
                Text("\(p.level)")
                    .font(Theme.Fonts.number(28))
                    .foregroundStyle(loadout.nameColor ?? Theme.textPrimary)
            }
            .frame(width: 80, height: 80)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).stroke(Theme.border, lineWidth: 1))
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .padding(.leading, 10)
        }
        .padding(.top, 10)
    }

    // MARK: - Stats

    private var statsGrid: some View {
        let (done, goal) = progression.seasonProgress
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatTile(title: "Lifetime XP", value: p.lifetimeXP.grouped, accent: true)
            StatTile(title: "Workouts", value: p.workoutCount.grouped)
            StatTile(title: "Week streak", value: "\(progression.currentWeekStreak)")
            StatTile(title: "PRs", value: "\(max(p.prCount, insightsStore.personalRecords.count))")
            StatTile(title: "Season", value: "\(done) / \(goal)")
            StatTile(title: "Live sessions", value: "\(liveSessions.completedCount)")
        }
    }

    // MARK: - Seasons

    /// Where this player has been. Always shown: the header carries "SINCE SEP 2026" even
    /// before the first season closes.
    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "SEASONS", trailing: "SINCE \(p.sinceLabel)")
            ForEach((p.seasonHistory ?? []).reversed()) { record in
                Button {
                    archivedSeason = SeasonCatalog.season(id: record.seasonID)
                } label: {
                    HStack(spacing: 10) {
                        Text("\(record.seasonID) \(SeasonCatalog.season(id: record.seasonID)?.name ?? "") · LVL \(record.finalLevel) · \(record.seasonWorkoutCount)/\(record.goalWorkouts)")
                            .font(Theme.Fonts.mono(12))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        if record.reachedGoal {
                            SlantTag(text: "GOAL", fill: Theme.xpSubtle, textColor: Theme.xp, size: 10)
                        }
                        Image(systemName: "chevron.right").font(Theme.Fonts.ui(.caption, weight: .bold)).foregroundStyle(Theme.textTertiary)
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous).stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    // MARK: - Links

    private var links: some View {

        VStack(spacing: 10) {
            linkRow(title: "Season Pass", subtitle: seasonPassSubtitle, icon: "ticket.fill") {
                showSeasonPass = true
            }
            linkRow(title: "Live sessions", subtitle: liveSessionsSubtitle, icon: "dot.radiowaves.left.and.right") {
                showLiveHistory = true
            }
            linkRow(title: "Personal records", subtitle: "\(insightsStore.personalRecords.count) lifts tracked", icon: "trophy.fill") {
                showPRs = true
            }
            linkRow(title: "Career stats", subtitle: "Volume, sets, streaks", icon: "chart.bar.fill") {
                showLifetime = true
            }
            if gameCenter.authState != .disabled {
                linkRow(title: "Lifetime XP leaderboard", subtitle: gameCenter.statusLine, icon: "list.number") {
                    gameCenter.presentLeaderboard(id: GameCenterCatalog.lifetimeXP)
                }
                linkRow(title: "Season XP leaderboard", subtitle: progression.season.displayName, icon: "flag.checkered") {
                    gameCenter.presentLeaderboard(id: GameCenterCatalog.seasonXP(progression.season))
                }
                linkRow(title: "Week streak leaderboard", subtitle: "Longest run of weeks with a workout", icon: "flame.fill") {
                    gameCenter.presentLeaderboard(id: GameCenterCatalog.weekStreak)
                }
                linkRow(title: "Live sessions leaderboard", subtitle: "Who keeps showing up", icon: "list.number") {
                    gameCenter.presentLeaderboard(id: GameCenterCatalog.liveSessions)
                }
            }
        }
    }

    private var liveSessionsSubtitle: String {
        switch liveSessions.completedCount {
        case 0: return "Sunday Reset, Friday Night. Show up."
        case 1: return "1 completed"
        default: return "\(liveSessions.completedCount) completed"
        }
    }

    private func linkRow(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accentSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.Fonts.title(16)).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(Theme.Fonts.ui(.caption)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(Theme.Fonts.ui(.caption, weight: .bold)).foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
    }
}
