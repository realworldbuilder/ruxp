import SwiftUI

/// The lobby. Answers four questions in one glance:
/// who is training right now, is anything happening, what level am I, should I start lifting.
struct HomeView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(ProgressionService.self) private var progression
    @Environment(PlannedWorkoutStore.self) private var plannedWorkoutStore
    @Environment(\.livePresence) private var presence
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(LiveSessionService.self) private var liveSessions
    @Environment(\.liveEvents) private var events
    @Environment(WorldSnapshotService.self) private var world
    @Environment(CrewService.self) private var crew

    @State private var now = ScheduledEventService.now()
    @State private var showSeasonPass = false
    /// The Live Session lobby. Its START WORKOUT dismisses first, then Home starts the workout,
    /// so the workout cover (owned by MainTabView) never stacks on this one.
    @State private var lobbyEvent: LiveEvent?
    @State private var startAfterLobby = false
    private let clock = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    private var live: LiveSnapshot { presence?.snapshot ?? .unavailable }
    private var featured: LiveEvent { events.featuredEvent(at: now) }
    private var featuredModifier: LiveModifier? { events.featuredModifier(at: now) }
    private var season: Season { progression.season }
    private var loadout: SeasonPassLoadout { SeasonPassCatalog.loadout(for: progression.progress, season: season) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                presenceBlock
                CrewCard(now: now)
                if world.isLedgerVisible, let ledger = world.ledger {

                    ReturnLedgerCard(
                        items: ledger.items,
                        awayLabel: ReturnLedger.awayLabel(from: ledger.baselineAt, to: now),
                        onDismiss: { withAnimation(Theme.Motion.snappy) { world.dismissLedger() } }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                eventCard
                if let plan = pendingPlan { planRow(plan) }
                youCard
                seasonCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .statusBarBackdrop()
        .background(HUDBackground())
        .fullScreenCover(isPresented: $showSeasonPass) { SeasonPassView() }
        .fullScreenCover(item: $lobbyEvent, onDismiss: {
            if startAfterLobby {
                startAfterLobby = false
                workoutManager.startWorkout()
            }
        }) { event in
            LiveSessionView(event: event) {
                startAfterLobby = true
                lobbyEvent = nil
            }
        }
        .onReceive(clock) { _ in now = ScheduledEventService.now() }
        .onAppear {
            now = ScheduledEventService.now()
            #if DEBUG
            // -RUXPScreen seasonpass: open the Season Pass cover (screenshots without taps).
            // Presented after a beat: a cover requested during the very first appearance is dropped.
            if DebugScreen.requested == .seasonPass {
                Task { try? await Task.sleep(for: .milliseconds(500)); showSeasonPass = true }
            }


            // -RUXPLiveScene lobby: join the live event and open its lobby (simulator screenshots).
            let args = ProcessInfo.processInfo.arguments
            if let idx = args.firstIndex(of: "-RUXPLiveScene"), idx + 1 < args.count, args[idx + 1] == "lobby",
               lobbyEvent == nil, featured.isActive(at: now), !featured.isSeasonWide {
                liveSessions.join(featured, now: now)
                lobbyEvent = featured
            }
            #endif
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                RUXPWordmark(size: 30)
                Spacer()
                SlantTag(text: "\(season.code) · \(season.name)")
            }
            // The clock is part of the product. One mono line: now, what's next, when the season ends.
            Text(clockLine)
                .font(Theme.Fonts.mono(11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.top, 6)
    }

    private var clockLine: String {
        let day = now.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        let time = now.formatted(date: .omitted, time: .shortened).uppercased()
        var parts = ["\(day) \(time)"]
        if let liveEvent = events.activeEvent(at: now), !liveEvent.isSeasonWide {
            parts.append("\(liveEvent.title) LIVE · \(liveEvent.endsInLabel(now: now).uppercased())")
        } else if let next = events.nextEvent(at: now) {
            parts.append("\(next.title) IN \(countdown(to: next.start))")
        }
        if let modifier = featuredModifier {
            parts.append(modifier.isActive(at: now) ? "\(modifier.title) ON" : "\(modifier.title) \(modifier.windowLabel(now: now))")
        }
        let days = season.daysRemaining(now: now)
        parts.append(days == 0 ? "\(season.code) ENDS TODAY" : "\(season.code) ENDS IN \(days)D")
        return parts.joined(separator: " · ")
    }

    /// "3D 6H", "6H 12M", "12M"
    private func countdown(to date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86400, hours = (seconds % 86400) / 3600, minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)D \(hours)H" }
        if hours > 0 { return "\(hours)H \(minutes)M" }
        return "\(max(1, minutes))M"
    }

    // MARK: - Presence

    /// Real Game Center players. Small numbers are shown as they are; nothing is inflated.
    private var presenceBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if live.isAvailable {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BigNumber(value: live.liftingNow, size: 52)
                    LiveDot(label: nil, size: 9)
                        .offset(y: -18)
                }
            }
            Text("LIFTING NOW")
                .eyebrow()
                .foregroundStyle(Theme.textSecondary)
            Text(live.isAvailable ? presenceLine : gameCenter.presenceUnavailableMessage)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }

    private var presenceLine: String {
        if live.liftingNow == 0 { return "Nobody's on right now. Be first." }
        return live.trainedTodayLine
    }

    // MARK: - Event

    private var eventCard: some View {
        let isLive = featured.isActive(at: now)
        let participants = presence?.participantCount(for: featured) ?? 0
        let isSession = isLive && !featured.isSeasonWide
        let joined = isSession && liveSessions.isJoined(featured)
        let completed = isSession && liveSessions.hasCompleted(featured)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if isLive {
                    LiveDot(label: "LIVE NOW")
                    if completed {
                        SlantTag(text: "Complete", fill: Theme.xpSubtle, textColor: Theme.xp)
                    } else if joined {
                        SlantTag(text: "You're in")
                    }
                } else if featured.isSeasonWide {
                    Text("SEASON \(season.numberLabel)").eyebrow().foregroundStyle(Theme.secondary)
                } else {
                    Text("STARTS \(featured.startLabel(now: now))").eyebrow().foregroundStyle(Theme.warning)
                }
                Spacer()
                if featured.xpReward > 0 { XPChip(amount: featured.xpReward, prominent: isLive) }
            }

            Text(featured.title.capitalized)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            // Live Ops: a rule in effect (or starting soon) rides on the event card. No new screen.
            if let modifier = featuredModifier {
                let on = modifier.isActive(at: now)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        SlantTag(text: "\(modifier.title) · \(modifier.rule.summaryLabel)",
                                 fill: Theme.violetSubtle, textColor: Theme.violet, size: 10)
                        Text(on ? modifier.windowLabel(now: now) : "STARTS \(modifier.windowLabel(now: now))")
                            .eyebrow()
                            .foregroundStyle(on ? Theme.violet : Theme.textTertiary)
                    }
                    Text(modifier.description)
                        .font(Theme.Fonts.ui(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if isSession {
                    Text(featured.endsInLabel(now: now))
                        .font(Theme.Fonts.label).monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                if participants > 0 {
                    Text(participantsLine(count: participants, isLive: isLive))
                        .font(Theme.Fonts.title(16))
                        .foregroundStyle(Theme.textPrimary)
                }
                if completed {
                    Text("\(featured.title.capitalized) complete. +\(featured.xpReward.grouped) XP earned. You showed up.")
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.xp)
                } else {
                    Text(featured.description)
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if completed {
                SecondaryButton(title: "VIEW SESSION", icon: "checkmark.seal.fill") { lobbyEvent = featured }
                    .padding(.top, 4)
            } else if joined {
                PrimaryButton(title: "START WORKOUT", icon: "bolt.fill") {
                    workoutManager.startWorkout()
                }
                .padding(.top, 4)
                Button { lobbyEvent = featured } label: {
                    Text("Open lobby")
                        .font(Theme.Fonts.label)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, -4)
            } else if isSession {
                PrimaryButton(title: "JOIN SESSION", icon: "person.2.fill") {
                    liveSessions.join(featured, now: now)
                    lobbyEvent = featured
                }
                .padding(.top, 4)
            } else {
                PrimaryButton(title: "START WORKOUT") {
                    workoutManager.startWorkout()
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .stroke(isLive ? Theme.borderNeon : Theme.border, lineWidth: 1)
        )
    }

    private func participantsLine(count: Int, isLive: Bool) -> String {
        if featured.isSeasonWide { return "\(count.grouped) players this season" }
        return isLive ? "\(count.grouped) players joined" : "\(count.grouped) players in"
    }

    // MARK: - Plan

    private var pendingPlan: PlannedWorkout? {
        guard let plan = plannedWorkoutStore.currentPlan,
              Date().timeIntervalSince(plan.createdAt) < 24 * 3600 else { return nil }
        return plan
    }

    private func planRow(_ plan: PlannedWorkout) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TRAINER PLAN READY").eyebrow().foregroundStyle(Theme.secondary)
                Text(plan.title).font(Theme.Fonts.title(16)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text("\(plan.exercises.count) exercises").font(Theme.Fonts.ui(.caption)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            PillButton(title: "Start") {
                workoutManager.startWorkout(plan: plan)
            }
            Button { plannedWorkoutStore.clearPlan() } label: {
                Image(systemName: "xmark").font(Theme.Fonts.ui(.caption, weight: .bold)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - You

    private var youCard: some View {
        let p = progression.progress
        let thisWeek = progression.workoutsThisWeek
        let remaining = progression.workoutsUntilWeeklyBonus
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text("YOU").eyebrow().foregroundStyle(Theme.textSecondary)
                Spacer()
                if let badge = loadout.badge {
                    Image(systemName: badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(loadout.nameColor ?? Theme.accent)
                }
                Text(p.displayName).eyebrow().foregroundStyle(loadout.nameColor ?? Theme.textTertiary)
            }

            XPBar(level: p.level, xpIntoLevel: p.xpIntoLevel, xpToNext: p.xpToNextLevel)
            Divider().overlay(Theme.divider)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("THIS WEEK").eyebrow().foregroundStyle(Theme.textSecondary)
                    Text("\(thisWeek) workout\(thisWeek == 1 ? "" : "s")")
                        .font(Theme.Fonts.title(20))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Text(weeklyLine(remaining: remaining))
                    .font(Theme.Fonts.body)
                    .foregroundStyle(remaining == 0 ? Theme.xp : Theme.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 170, alignment: .trailing)
            }
        }
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func weeklyLine(remaining: Int) -> String {
        if progression.weeklyBonusEarnedThisWeek || remaining == 0 {
            return "Weekly bonus earned. +\(ProgressionRules.weeklyBonusXP) XP"
        }
        if remaining == 1 { return "One more for your weekly bonus." }
        return "\(remaining) more for your weekly bonus."
    }

    // MARK: - Season

    private var seasonCard: some View {
        let (done, goal) = progression.seasonProgress
        let fraction = goal > 0 ? min(1, Double(done) / Double(goal)) : 0
        let tier = SeasonPassCatalog.currentTier(level: progression.level)
        let next = SeasonPassCatalog.next(after: progression.level, season: season)
        return Button { showSeasonPass = true } label: {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(season.displayName).eyebrow().foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(season.daysRemaining(now: now)) DAYS LEFT").eyebrow().foregroundStyle(Theme.textTertiary)
            }
            Text("\(goal) workouts. Finish the season.")
                .font(Theme.Fonts.title(18))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 12) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surfaceElevated)
                        Capsule().fill(Theme.secondary).frame(width: max(6, geo.size.width * fraction))
                    }
                }
                .frame(height: 6)
                Text("\(done) / \(goal)")
                    .font(Theme.Fonts.mono(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(season.tagline)
                .font(Theme.Fonts.ui(.caption))
                .foregroundStyle(Theme.textTertiary)
            Divider().overlay(Theme.divider)
            HStack {
                Text("SEASON PASS · TIER \(tier) · NEXT: \(next?.name ?? "COMPLETE")")
                    .eyebrow()
                    .foregroundStyle(Theme.violet)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.Fonts.ui(.caption, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
          }
          .padding(20)
          .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).stroke(Theme.border, lineWidth: 1))
          .contentShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }
}
