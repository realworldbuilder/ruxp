import Foundation

// MARK: - XP awards

enum XPReason: String, Codable, CaseIterable {
    case workoutComplete
    case eventBonus
    case weeklyBonus
    case personalRecord

    var title: String {
        switch self {
        case .workoutComplete: return "WORKOUT COMPLETE"
        case .eventBonus: return "EVENT BONUS"
        case .weeklyBonus: return "WEEKLY BONUS"
        case .personalRecord: return "NEW PR"
        }
    }
}

struct XPAward: Codable, Identifiable, Equatable {
    var id: UUID
    var reason: XPReason
    /// Display label. For event bonuses this is the event title (e.g. "FRIDAY NIGHT").
    var label: String
    var amount: Int

    init(id: UUID = UUID(), reason: XPReason, label: String? = nil, amount: Int) {
        self.id = id
        self.reason = reason
        self.label = label ?? reason.title
        self.amount = amount
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
