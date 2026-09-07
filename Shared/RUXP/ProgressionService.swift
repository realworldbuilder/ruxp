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
    var seasonPRCount: Int { progress.seasonPRCount ?? 0 }

    /// The streak as of right now. The stored value is only refreshed when a workout is rewarded,
    /// so a card that read it directly could show a streak the player has already lost.
    var currentWeekStreak: Int { Self.weekStreak(workoutDates: progress.workoutDates, now: ScheduledEventService.now(), calendar: calendar) }

    /// The finished season whose recap has not been shown yet.
    var pendingSeasonRecap: SeasonRecord? {
        progress.pendingSeasonRecapID.flatMap { progress.seasonRecord(for: $0) }
    }

    func acknowledgeSeasonRecap() {
        guard progress.pendingSeasonRecapID != nil else { return }
        progress.pendingSeasonRecapID = nil
        save()
    }

    /// Resolves a Live Ops rule that covered a past workout (PR bonuses land later than completion).
    var modifierResolver: (String) -> LiveModifier? = { LiveOpsCatalog.current.modifier(id: $0) }

    // MARK: - Rewards

    /// Award XP for finishing a workout. Safe to call more than once for the same workout.
    /// `modifiers` are the Live Ops rules whose windows the workout overlapped.
    @discardableResult
    func rewardWorkoutCompletion(session: WorkoutSession, events: [LiveEvent], modifiers: [LiveModifier] = [], now: Date? = nil) -> WorkoutRewardSummary {
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
                summary.awards.append(XPAward(reason: .eventBonus, label: event.title, amount: event.xpReward, eventID: event.id))
                if summary.eventTitle == nil { summary.eventTitle = event.title }
            }

            let weekKey = calendar.weekKey(for: session.startedAt)
            if progress.workoutsThisWeek(now: session.startedAt, calendar: calendar) >= ProgressionRules.weeklyTargetWorkouts,
               !progress.weeklyBonusWeeks.contains(weekKey) {
                progress.weeklyBonusWeeks.insert(weekKey)
                summary.awards.append(XPAward(reason: .weeklyBonus, amount: ProgressionRules.weeklyBonusXP))
            }

            // Live Ops: rules that covered this workout. Remembered so a PR multiplier can still
            // apply when the AI parse lands minutes later.
            let covering = modifiers.filter { $0.covers(start: session.startedAt, end: session.endedAt ?? now) }
            if !covering.isEmpty {
                var map = progress.modifierIDsByWorkout ?? [:]
                map[session.id] = covering.map(\.id)
                progress.modifierIDsByWorkout = map
            }
            let baseAwards = summary.awards
            for modifier in covering {
                let bonus = modifier.bonus(baseAwards: baseAwards, workoutStart: session.startedAt)
                guard bonus > 0 else { continue }
                summary.awards.append(XPAward(reason: .modifier, label: modifier.title, amount: bonus))
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
        if already == 0 {
            progress.prCount += count
            progress.seasonPRCount = (progress.seasonPRCount ?? 0) + count
        }
        guard grant > 0 else { save(); return nil }
        progress.prRewardsByWorkout[workoutID] = already + grant

        var awards = (0..<grant).map { _ in XPAward(reason: .personalRecord, amount: ProgressionRules.personalRecordXP) }
        // A PR multiplier that covered this workout pays now, on the PR awards only.
        // (Only multipliers apply here, and they do not look at the start time.)
        for id in progress.modifierIDsByWorkout?[workoutID] ?? [] {
            guard let modifier = modifierResolver(id),
                  case .multiplier(.personalRecord, _) = modifier.rule else { continue }
            let bonus = modifier.bonus(baseAwards: awards, workoutStart: ScheduledEventService.now())

            if bonus > 0 { awards.append(XPAward(reason: .modifier, label: modifier.title, amount: bonus)) }
        }
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
    /// Finished seasons are kept: a rebuild must never erase "I was there".
    func rebuild(from sessions: [WorkoutSession], events: LiveEventProviding) {
        let joinDate = sessions.map(\.startedAt).min() ?? Date()
        progress = PlayerProgress(displayName: progress.displayName, joinDate: joinDate, seasonID: season.id,
                                  equippedCosmetics: progress.equippedCosmetics,
                                  seasonHistory: progress.seasonHistory,
                                  pendingSeasonRecapID: progress.pendingSeasonRecapID)
        var bestByExercise: [String: Double] = [:]
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            guard let endedAt = session.endedAt else { continue }
            let overlapping = events.events(overlapping: session.startedAt, end: endedAt)
            let modifiers = events.modifiers(overlapping: session.startedAt, end: endedAt)
            rewardWorkoutCompletion(session: session, events: overlapping, modifiers: modifiers, now: endedAt)
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
        let streak = Self.weekStreak(workoutDates: progress.workoutDates, now: now, calendar: calendar)
        progress.currentWeekStreak = streak
        progress.longestWeekStreak = max(progress.longestWeekStreak, streak)
    }

    /// Consecutive ISO weeks with a rewarded workout, ending at `now`'s week (or last week when
    /// the current one is still empty). Pure, so Profile can read it live.
    static func weekStreak(workoutDates: [Date], now: Date, calendar: Calendar = .ruxpWeek) -> Int {
        let weeks = Set(workoutDates.map { calendar.weekKey(for: $0) })
        guard !weeks.isEmpty else { return 0 }
        var streak = 0
        var cursor = calendar.startOfWeek(for: now)
        if !weeks.contains(calendar.weekKey(for: cursor)) {
            cursor = calendar.date(byAdding: .day, value: -7, to: cursor) ?? cursor
        }
        while weeks.contains(calendar.weekKey(for: cursor)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -7, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Files written by this build and later carry this. A nil marks builds 1–4.
    private static let schemaVersion = 2

    /// First launch inside a new season: close the old one into a `SeasonRecord` (the recap
    /// shows it once), then start fresh. Season XP and level begin again; lifetime totals,
    /// streaks, and equipped cosmetics survive. A player who never trained in the old season
    /// gets no record and no recap: an empty ceremony would be an inflated one.
    private func rolloverSeasonIfNeeded(now: Date = ScheduledEventService.now()) {
        if progress.seasonID == SeasonCatalog.legacyLaunchID, progress.schemaVersion == nil {
            // Builds 1–3 called the launch window S01. Same window, new code: rename in place,
            // keep XP, remap equipped reward IDs. Only a file without a schema version can be
            // legacy; after Dec 1 a real S01 file carries one and must not be renamed.
            progress.seasonID = SeasonCatalog.earlyAdopters.id
            progress.equippedCosmetics = progress.equippedCosmetics?.mapValues { id in
                id.hasPrefix("S01-") ? "S00-" + id.dropFirst(4) : id
            }
        }
        guard progress.seasonID != season.id else {
            if progress.schemaVersion == nil { save() }
            return
        }
        if let closed = SeasonCatalog.season(id: progress.seasonID), progress.seasonXP > 0 {
            let record = SeasonRecord.closing(progress, season: closed, closedAt: now)
            var history = (progress.seasonHistory ?? []).filter { $0.seasonID != closed.id }
            history.append(record)
            progress.seasonHistory = history
            progress.pendingSeasonRecapID = closed.id
            Self.logger.info("Closed \(closed.id) at level \(record.finalLevel), \(record.seasonWorkoutCount) workouts")
        }
        progress.seasonID = season.id
        progress.seasonXP = 0
        progress.seasonWorkoutCount = 0
        progress.seasonPRCount = nil
        save()
    }

    private func save() {
        progress.schemaVersion = Self.schemaVersion
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
