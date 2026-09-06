import SwiftUI

/// Player card: level, XP, career stats. No feed, no followers.
struct ProfileView: View {
    @Environment(ProgressionService.self) private var progression
    @Environment(InsightsStore.self) private var insightsStore

    @State private var showNameEditor = false
    @State private var nameDraft = ""
    @State private var showPRs = false
    @State private var showLifetime = false
    @State private var showSettings = false

    private var p: PlayerProgress { progression.progress }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    identity
                    XPBar(level: p.level, xpIntoLevel: p.xpIntoLevel, xpToNext: p.xpToNextLevel)
                        .padding(18)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                    statsGrid
                    links
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .alert("Display name", isPresented: $showNameEditor) {
            TextField("Name", text: $nameDraft)
            Button("Save") { progression.setDisplayName(nameDraft) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown on your player card.")
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
                            .font(Theme.Fonts.display(32))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Image(systemName: "pencil")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                Text("\(progression.season.code) · \(progression.season.name)")
                    .eyebrow()
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            VStack(spacing: 0) {
                Text("LVL").eyebrow().foregroundStyle(Theme.onAccent.opacity(0.7))
                Text("\(p.level)")
                    .font(Theme.Fonts.number(34))
                    .foregroundStyle(Theme.onAccent)
            }
            .frame(width: 84, height: 84)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.35), radius: 14, y: 4)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface, in: Circle())
            }
            .padding(.leading, 10)
        }
        .padding(.top, 10)
    }

    // MARK: - Stats

    private var statsGrid: some View {
        let joined = p.joinDate.formatted(.dateTime.month(.abbreviated).year())
        let (done, goal) = progression.seasonProgress
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatTile(title: "Lifetime XP", value: p.lifetimeXP.grouped, accent: true)
            StatTile(title: "Workouts", value: p.workoutCount.grouped)
            StatTile(title: "Week streak", value: "\(p.currentWeekStreak)")
            StatTile(title: "PRs", value: "\(max(p.prCount, insightsStore.personalRecords.count))")
            StatTile(title: "Season", value: "\(done) / \(goal)")
            StatTile(title: "Joined", value: joined)
        }
    }

    // MARK: - Links

    private var links: some View {
        VStack(spacing: 10) {
            linkRow(title: "Personal records", subtitle: "\(insightsStore.personalRecords.count) lifts tracked", icon: "trophy.fill") {
                showPRs = true
            }
            linkRow(title: "Career stats", subtitle: "Volume, sets, streaks", icon: "chart.bar.fill") {
                showLifetime = true
            }
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
                    Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }
}
