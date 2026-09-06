import Foundation
import os

/// Rules for earning XP. Reward healthy, useful behavior; do not reward grinding.
enum ProgressionRules {
    static let workoutCompleteXP = 500
    static let weeklyBonusXP = 500
    static let personalRecordXP = 250
    static let weeklyTargetWorkouts = 4
    static let maxRewardedWorkoutsPerDay = 2
    static let maxPRBonusesPerWorkout = 2
    /// Workouts shorter than this earn nothing. Adjustable in DEBUG from Settings › Developer.
    nonisolated(unsafe) static var minimumWorkoutDuration: TimeInterval = 10 * 60
}

/// Centralized progression: season XP, lifetime XP, level, workout count, weekly streak.
/// Persisted to Documents/player_progress.json. Synchronous and offline; never depends on AI.
@Observable
@MainActor
final class ProgressionService {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "ProgressionService")

    private(set) var progress: PlayerProgress
    /// The most recent reward. The completion screen renders this; PR bonuses append to it later.
    private(set) var lastReward: WorkoutRewardSummary?
    /// Fired whenever a reward is created or amended (used to push XP to the watch).
    var onRewardChanged: ((WorkoutRewardSummary) -> Void)?
    /// Fired after every persisted change (used to sync Game Center). Receivers coalesce.
    var onProgressChanged: ((PlayerProgress) -> Void)?

    let season: Season
    private let fileURL: URL
    private let calendar = Calendar.ruxpWeek

    init(season: Season = SeasonCatalog.current, fileURL: URL? = nil) {
        self.season = season
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = fileURL ?? docs.appendingPathComponent("player_progress.json")
        self.progress = PlayerProgress(seasonID: season.id)
        load()
        rolloverSeasonIfNeeded()
    }

    // MARK: - Derived

    var level: Int { progress.level }
    var context: ProgressionContext { ProgressionContext(progress: progress) }

    var workoutsThisWeek: Int { progress.workoutsThisWeek(now: ScheduledEventService.now(), calendar: calendar) }
    var workoutsUntilWeeklyBonus: Int { max(0, ProgressionRules.weeklyTargetWorkouts - workoutsThisWeek) }
    var weeklyBonusEarnedThisWeek: Bool {
        progress.weeklyBonusWeeks.contains(calendar.weekKey(for: ScheduledEventService.now()))
    }
    var seasonProgress: (workouts: Int, goal: Int) { (progress.seasonWorkoutCount, season.goalWorkouts) }

    // MARK: - Rewards

    /// Award XP for finishing a workout. Safe to call more than once for the same workout.
    @discardableResult
    func rewardWorkoutCompletion(session: WorkoutSession, events: [LiveEvent], now: Date? = nil) -> WorkoutRewardSummary {
        let now = now ?? ScheduledEventService.now()
        let before = progress
        var summary = WorkoutRewardSummary(
            workoutID: session.id,
            awards: [],
            levelBefore: before.level,
            levelAfter: before.level,
            seasonXPBefore: before.seasonXP,
            seasonXPAfter: before.seasonXP,
            eventTitle: nil,
            awardedAt: now
        )

        guard !progress.rewardedWorkoutIDs.contains(session.id) else {
            Self.logger.info("Workout \(session.id) already rewarded")
            summary = lastReward?.workoutID == session.id ? lastReward! : summary
            return summary
        }

        let duration = (session.endedAt ?? now).timeIntervalSince(session.startedAt)
        let qualifies = duration >= ProgressionRules.minimumWorkoutDuration
        let dayCount = progress.workouts(onDayOf: session.startedAt, calendar: calendar)
        let underDailyCap = dayCount < ProgressionRules.maxRewardedWorkoutsPerDay

        progress.rewardedWorkoutIDs.insert(session.id)

        if qualifies && underDailyCap {
            progress.workoutDates.append(session.startedAt)
            progress.workoutCount += 1
            if season.isActive(at: session.startedAt) { progress.seasonWorkoutCount += 1 }

            summary.awards.append(XPAward(reason: .workoutComplete, amount: ProgressionRules.workoutCompleteXP))

            for event in events where !event.isSeasonWide && event.xpReward > 0 {
                guard progress.eventsJoined[event.id] == nil else { continue }
                progress.eventsJoined[event.id] = now
                summary.awards.append(XPAward(reason: .eventBonus, label: event.title, amount: event.xpReward))
                if summary.eventTitle == nil { summary.eventTitle = event.title }
            }

            let weekKey = calendar.weekKey(for: session.startedAt)
            if progress.workoutsThisWeek(now: session.startedAt, calendar: calendar) >= ProgressionRules.weeklyTargetWorkouts,
               !progress.weeklyBonusWeeks.contains(weekKey) {
                progress.weeklyBonusWeeks.insert(weekKey)
                summary.awards.append(XPAward(reason: .weeklyBonus, amount: ProgressionRules.weeklyBonusXP))
            }

            recomputeWeekStreak(now: now)
        } else {
            Self.logger.info("Workout \(session.id) not rewarded (qualifies=\(qualifies), underDailyCap=\(underDailyCap))")
        }

        apply(xp: summary.totalXP)
        summary.seasonXPAfter = progress.seasonXP
        summary.levelAfter = progress.level
        lastReward = summary
        save()
        onRewardChanged?(summary)
        Self.logger.info("Rewarded workout \(session.id): +\(summary.totalXP) XP, level \(summary.levelBefore) → \(summary.levelAfter)")
        return summary
    }

    /// Award PR bonuses once AI parsing identifies new records. Idempotent per workout.
    @discardableResult
    func rewardPersonalRecords(workoutID: UUID, count: Int) -> WorkoutRewardSummary? {
        guard count > 0 else { return nil }
        let already = progress.prRewardsByWorkout[workoutID] ?? 0
        let grant = min(count, ProgressionRules.maxPRBonusesPerWorkout) - already
        if already == 0 { progress.prCount += count }
        guard grant > 0 else { save(); return nil }
        progress.prRewardsByWorkout[workoutID] = already + grant

        let awards = (0..<grant).map { _ in XPAward(reason: .personalRecord, amount: ProgressionRules.personalRecordXP) }
        apply(xp: awards.reduce(0) { $0 + $1.amount })

        var summary: WorkoutRewardSummary
        if var existing = lastReward, existing.workoutID == workoutID {
            existing.awards.append(contentsOf: awards)
            existing.seasonXPAfter = progress.seasonXP
            existing.levelAfter = progress.level
            summary = existing
        } else {
            let levelBefore = LevelCurve.level(forSeasonXP: progress.seasonXP - awards.reduce(0) { $0 + $1.amount })
            summary = WorkoutRewardSummary(
                workoutID: workoutID,
                awards: awards,
                levelBefore: levelBefore,
                levelAfter: progress.level,
                seasonXPBefore: progress.seasonXP - awards.reduce(0) { $0 + $1.amount },
                seasonXPAfter: progress.seasonXP,
                eventTitle: nil,
                awardedAt: ScheduledEventService.now()
            )
        }
        lastReward = summary
        save()
        onRewardChanged?(summary)
        return summary
    }

    func clearLastReward() {
        lastReward = nil
    }

    // MARK: - Profile

    func setDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        progress.displayName = trimmed.isEmpty ? "PLAYER" : String(trimmed.prefix(18)).uppercased()
        save()
    }

    /// Season Pass: equip (or clear with nil) one cosmetic slot. The catalog lives in the iOS target.
    func setEquippedCosmetic(kind: String, rewardID: String?) {
        var map = progress.equippedCosmetics ?? [:]
        map[kind] = rewardID
        progress.equippedCosmetics = map.isEmpty ? nil : map
        save()
    }

    func resetAll() {
        progress = PlayerProgress(seasonID: season.id)
        lastReward = nil
        save()
        Self.logger.info("Progression reset")
    }

    /// Replay history so an existing user (or the sample-data loader) gets a believable profile.
    func rebuild(from sessions: [WorkoutSession], events: LiveEventProviding) {
        let joinDate = sessions.map(\.startedAt).min() ?? Date()
        progress = PlayerProgress(displayName: progress.displayName, joinDate: joinDate, seasonID: season.id,
                                  equippedCosmetics: progress.equippedCosmetics)
        var bestByExercise: [String: Double] = [:]
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            guard let endedAt = session.endedAt else { continue }
            let overlapping = events.events(overlapping: session.startedAt, end: endedAt)
            rewardWorkoutCompletion(session: session, events: overlapping, now: endedAt)
            if let log = session.structuredLog {
                var newPRs = 0
                for exercise in log.exercises {
                    let maxWeight = exercise.sets.compactMap(\.weight).max() ?? 0
                    guard maxWeight > 0 else { continue }
                    if let best = bestByExercise[exercise.exerciseName] {
                        if maxWeight > best { newPRs += 1; bestByExercise[exercise.exerciseName] = maxWeight }
                    } else {
                        bestByExercise[exercise.exerciseName] = maxWeight
                    }
                }
                rewardPersonalRecords(workoutID: session.id, count: newPRs)
            }
        }
        lastReward = nil
        save()
        Self.logger.info("Rebuilt progression from \(sessions.count) workouts: level \(self.progress.level)")
    }

    // MARK: - Internals

    private func apply(xp: Int) {
        guard xp > 0 else { return }
        progress.lifetimeXP += xp
        progress.seasonXP += xp
    }

    private func recomputeWeekStreak(now: Date) {
        let weeks = Set(progress.workoutDates.map { calendar.weekKey(for: $0) })
        guard !weeks.isEmpty else {
            progress.currentWeekStreak = 0
            return
        }
        var streak = 0
        var cursor = calendar.startOfWeek(for: now)
        // The current week counts if it has a workout; otherwise start from last week.
        if !weeks.contains(calendar.weekKey(for: cursor)) {
            cursor = calendar.date(byAdding: .day, value: -7, to: cursor) ?? cursor
        }
        while weeks.contains(calendar.weekKey(for: cursor)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -7, to: cursor) else { break }
            cursor = previous
        }
        progress.currentWeekStreak = streak
        progress.longestWeekStreak = max(progress.longestWeekStreak, streak)
    }

    private func rolloverSeasonIfNeeded() {
        guard progress.seasonID != season.id else { return }
        if progress.seasonID == SeasonCatalog.legacyLaunchID, season.id == SeasonCatalog.earlyAdopters.id {
            // Builds 1–3 called the launch window S01. Same window, new code:
            // rename in place, keep XP, remap equipped reward IDs.
            progress.seasonID = season.id
            progress.equippedCosmetics = progress.equippedCosmetics?.mapValues { id in
                id.hasPrefix("S01-") ? "S00-" + id.dropFirst(4) : id
            }
            save()
            return
        }
        progress.seasonID = season.id
        progress.seasonXP = 0
        progress.seasonWorkoutCount = 0
        save()
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(progress)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save progression: \(error)")
        }
        onProgressChanged?(progress)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            progress = try decoder.decode(PlayerProgress.self, from: Data(contentsOf: fileURL))
        } catch {
            Self.logger.error("Failed to load progression: \(error)")
        }
    }
}
