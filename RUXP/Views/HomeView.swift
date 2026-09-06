import SwiftUI

/// The lobby. Answers four questions in one glance:
/// who is training right now, is anything happening, what level am I, should I start lifting.
struct HomeView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(ProgressionService.self) private var progression
    @Environment(PlannedWorkoutStore.self) private var plannedWorkoutStore
    @Environment(\.livePresence) private var presence
    @Environment(\.liveEvents) private var events

    @State private var now = ScheduledEventService.now()
    private let clock = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    private var live: LiveSnapshot { presence?.snapshot ?? .empty }
    private var featured: LiveEvent { events.featuredEvent(at: now) }
    private var season: Season { progression.season }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                presenceBlock
                eventCard
                if let plan = pendingPlan { planRow(plan) }
                youCard
                seasonCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.background.ignoresSafeArea())
        .onReceive(clock) { _ in now = ScheduledEventService.now() }
        .onAppear { now = ScheduledEventService.now() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            RUXPWordmark(size: 30)
            Spacer()
            Text("\(season.code) · \(season.name)")
                .eyebrow()
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.secondary.opacity(0.14), in: Capsule())
        }
        .padding(.top, 6)
    }

    // MARK: - Presence

    private var presenceBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                BigNumber(value: live.liftingNow, size: 60)
                LiveDot(label: nil, size: 9)
                    .offset(y: -18)
            }
            Text("LIFTING NOW")
                .eyebrow()
                .foregroundStyle(Theme.textSecondary)
            Text("\(live.workoutsLastHour.grouped) workouts finished in the last hour")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Event

    private var eventCard: some View {
        let isLive = featured.isActive(at: now)
        let participants = presence?.participantCount(for: featured) ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                if isLive {
                    LiveDot(label: "LIVE NOW")
                } else if featured.isSeasonWide {
                    Text("SEASON \(String(format: "%02d", season.number))").eyebrow().foregroundStyle(Theme.secondary)
                } else {
                    Text("STARTS \(featured.startLabel(now: now))").eyebrow().foregroundStyle(Theme.warning)
                }
                Spacer()
                if featured.xpReward > 0 { XPChip(amount: featured.xpReward, prominent: isLive) }
            }

            Text(featured.title)
                .font(Theme.Fonts.display(38))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            VStack(alignment: .leading, spacing: 4) {
                if participants > 0 {
                    Text(participantsLine(count: participants, isLive: isLive))
                        .font(Theme.Fonts.title(16))
                        .foregroundStyle(isLive ? Theme.accent : Theme.textPrimary)
                }
                Text(featured.description)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textSecondary)
            }

            PrimaryButton(title: isLive ? "JOIN + START WORKOUT" : "START WORKOUT") {
                workoutManager.startWorkout()
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .stroke(isLive ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: 1)
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
                Text("\(plan.exercises.count) exercises").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                workoutManager.startWorkout(plan: plan)
            } label: {
                Text("START")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Theme.accent, in: Capsule())
            }
            Button { plannedWorkoutStore.clearPlan() } label: {
                Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
    }

    // MARK: - You

    private var youCard: some View {
        let p = progression.progress
        let thisWeek = progression.workoutsThisWeek
        let remaining = progression.workoutsUntilWeeklyBonus
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("YOU").eyebrow().foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(p.displayName).eyebrow().foregroundStyle(Theme.textTertiary)
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
                    .foregroundStyle(remaining == 0 ? Theme.accent : Theme.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 170, alignment: .trailing)
            }
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
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
        return VStack(alignment: .leading, spacing: 10) {
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
                    .font(Theme.Fonts.label).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(season.tagline)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
    }
}
