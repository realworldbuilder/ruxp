import Foundation

// MARK: - XP awards

enum XPReason: String, Codable, CaseIterable {
    case workoutComplete
    case eventBonus
    case weeklyBonus
    case personalRecord
    /// A Live Ops rule in effect for this workout (PR WEEKEND, S00 FINALE). Label is the rule's title.
    case modifier

    var title: String {
        switch self {
        case .workoutComplete: return "WORKOUT COMPLETE"
        case .eventBonus: return "EVENT BONUS"
        case .weeklyBonus: return "WEEKLY BONUS"
        case .personalRecord: return "NEW PR"
        case .modifier: return "LIVE MODIFIER"
        }
    }
}

struct XPAward: Codable, Identifiable, Equatable {
    var id: UUID
    var reason: XPReason
    /// Display label. For event bonuses this is the event title (e.g. "FRIDAY NIGHT").
    var label: String
    var amount: Int
    /// For event bonuses: the `LiveEvent.id` occurrence this award was paid for.
    /// Optional so summaries encoded before this field existed still decode.
    var eventID: String?

    init(id: UUID = UUID(), reason: XPReason, label: String? = nil, amount: Int, eventID: String? = nil) {
        self.id = id
        self.reason = reason
        self.label = label ?? reason.title
        self.amount = amount
        self.eventID = eventID
    }
}

/// Everything the post-workout screen (and the watch summary) needs.
struct WorkoutRewardSummary: Codable, Equatable {
    let workoutID: UUID
    var awards: [XPAward]
    let levelBefore: Int
    var levelAfter: Int
    let seasonXPBefore: Int
    var seasonXPAfter: Int
    var eventTitle: String?
    let awardedAt: Date

    var totalXP: Int { awards.reduce(0) { $0 + $1.amount } }
    var didLevelUp: Bool { levelAfter > levelBefore }
    var prCount: Int { awards.filter { $0.reason == .personalRecord }.count }
    var isEmpty: Bool { awards.isEmpty }
    /// Event bonuses paid with this workout (Live Session completions).
    var eventAwards: [XPAward] { awards.filter { $0.reason == .eventBonus } }
}

// MARK: - Player state

struct PlayerProgress: Codable, Equatable {
    var displayName: String = "PLAYER"
    var joinDate: Date = Date()
    var lifetimeXP: Int = 0
    var seasonID: String = ""
    var seasonXP: Int = 0
    var workoutCount: Int = 0
    var seasonWorkoutCount: Int = 0
    var prCount: Int = 0
    var currentWeekStreak: Int = 0
    var longestWeekStreak: Int = 0
    /// Start dates of rewarded workouts (drives weekly counts and streaks).
    var workoutDates: [Date] = []
    var rewardedWorkoutIDs: Set<UUID> = []
    /// Number of PR bonuses already granted per workout (caps repeat awards).
    var prRewardsByWorkout: [UUID: Int] = [:]
    /// ISO week keys ("2026-W37") for which the weekly bonus was paid.
    var weeklyBonusWeeks: Set<String> = []
    /// Event occurrence IDs the player has earned a bonus for.
    var eventsJoined: [String: Date] = [:]
    /// Season Pass cosmetics by kind ("title", "nameColor", "badge") → reward ID ("S00-T05").
    /// Optional so progress files written before this field existed still decode.
    var equippedCosmetics: [String: String]? = nil

    // Every field below is Optional with a nil default for the same reason: `PlayerProgress`
    // uses synthesized Decodable, so a non-optional addition would blank every existing profile.

    /// Finished seasons, oldest first. Written once per rollover by `ProgressionService`.
    var seasonHistory: [SeasonRecord]? = nil
    /// PR bonuses counted inside the current season (zeroed at rollover; feeds the recap).
    var seasonPRCount: Int? = nil
    /// Season whose recap has not been shown yet ("S00"). Cleared by `acknowledgeSeasonRecap()`.
    var pendingSeasonRecapID: String? = nil
    /// Live Ops rules that applied to a rewarded workout, so the later PR bonus can honor a PR multiplier.
    var modifierIDsByWorkout: [UUID: [String]]? = nil
    /// Written by every save from build 5 on. Nil marks a file from builds 1–4 (see the legacy season rename).
    var schemaVersion: Int? = nil

    /// Live Sessions completed. An event bonus is paid once per occurrence and only for a
    /// qualifying workout, so the ledger size is the completion count.
    var liveSessionsCompleted: Int { eventsJoined.count }

    func seasonRecord(for seasonID: String) -> SeasonRecord? {
        seasonHistory?.first { $0.seasonID == seasonID }
    }

    /// "SEP 2026": when this player first showed up.
    var sinceLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f.string(from: joinDate).uppercased()
    }

    var levelProgress: LevelCurve.Progress { LevelCurve.progress(seasonXP: seasonXP) }
    var level: Int { levelProgress.level }
    var xpIntoLevel: Int { levelProgress.xpIntoLevel }
    var xpToNextLevel: Int { levelProgress.xpToNext }

    func workoutsThisWeek(now: Date = Date(), calendar: Calendar = .ruxpWeek) -> Int {
        let key = calendar.weekKey(for: now)
        return workoutDates.filter { calendar.weekKey(for: $0) == key }.count
    }

    func workouts(onDayOf date: Date, calendar: Calendar = .ruxpWeek) -> Int {
        workoutDates.filter { calendar.isDate($0, inSameDayAs: date) }.count
    }
}

/// Compact progression state pushed to the watch via application context.
struct ProgressionContext: Equatable {
    var level: Int
    var seasonXP: Int
    var xpIntoLevel: Int
    var xpToNext: Int

    init(level: Int, seasonXP: Int, xpIntoLevel: Int, xpToNext: Int) {
        self.level = level
        self.seasonXP = seasonXP
        self.xpIntoLevel = xpIntoLevel
        self.xpToNext = xpToNext
    }

    init(progress: PlayerProgress) {
        let p = progress.levelProgress
        self.init(level: p.level, seasonXP: progress.seasonXP, xpIntoLevel: p.xpIntoLevel, xpToNext: p.xpToNext)
    }

    func toDictionary() -> [String: Any] {
        [
            ConnectivityConstants.contextLevelKey: level,
            ConnectivityConstants.contextSeasonXPKey: seasonXP,
            ConnectivityConstants.contextXPIntoLevelKey: xpIntoLevel,
            ConnectivityConstants.contextXPToNextKey: xpToNext
        ]
    }

    static func from(_ dict: [String: Any]) -> ProgressionContext? {
        guard let level = dict[ConnectivityConstants.contextLevelKey] as? Int else { return nil }
        return ProgressionContext(
            level: level,
            seasonXP: dict[ConnectivityConstants.contextSeasonXPKey] as? Int ?? 0,
            xpIntoLevel: dict[ConnectivityConstants.contextXPIntoLevelKey] as? Int ?? 0,
            xpToNext: dict[ConnectivityConstants.contextXPToNextKey] as? Int ?? LevelCurve.xpToAdvance(from: level)
        )
    }
}

// MARK: - Season record

/// Final state of a finished season, captured at rollover. This is what "I was there" means:
/// the level, the attendance, and the ladder position are frozen here and never recomputed.
struct SeasonRecord: Codable, Equatable, Identifiable {
    var id: String { seasonID }
    let seasonID: String
    let finalLevel: Int
    let finalSeasonXP: Int
    let seasonWorkoutCount: Int
    let goalWorkouts: Int
    let liveSessionsCompleted: Int
    let fridayNightsAttended: Int
    let sundayResetsAttended: Int
    let prCount: Int
    let weeklyBonusWeeks: Int
    let closedAt: Date

    var reachedGoal: Bool { seasonWorkoutCount >= goalWorkouts }

    /// The record for `season` as it stands in `progress` right now (pure; nothing is mutated).
    static func closing(_ progress: PlayerProgress, season: Season, closedAt: Date, calendar: Calendar = .ruxpWeek) -> SeasonRecord {
        let inSeason = progress.eventsJoined.filter { season.isActive(at: $0.value) }
        let weeks = Set(progress.workoutDates.filter { season.isActive(at: $0) }.map { calendar.weekKey(for: $0) })
        return SeasonRecord(
            seasonID: season.id,
            finalLevel: progress.level,
            finalSeasonXP: progress.seasonXP,
            seasonWorkoutCount: progress.seasonWorkoutCount,
            goalWorkouts: season.goalWorkouts,
            liveSessionsCompleted: inSeason.count,
            fridayNightsAttended: inSeason.keys.filter { $0.hasPrefix(LiveEventKind.fridayNight.rawValue + "-") }.count,
            sundayResetsAttended: inSeason.keys.filter { $0.hasPrefix(LiveEventKind.sundayReset.rawValue + "-") }.count,
            prCount: progress.seasonPRCount ?? 0,
            weeklyBonusWeeks: progress.weeklyBonusWeeks.intersection(weeks).count,
            closedAt: closedAt
        )
    }
}

// MARK: - Calendar helpers


extension Calendar {
    /// ISO-8601 weeks (Monday start) in the user's local time zone.
    static var ruxpWeek: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        return cal
    }

    func weekKey(for date: Date) -> String {
        let year = component(.yearForWeekOfYear, from: date)
        let week = component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}

extension Int {
    /// "12,481"
    var grouped: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: self)) ?? String(self)
    }

    /// "+500"
    var signedGrouped: String {
        self >= 0 ? "+\(grouped)" : grouped
    }
}
