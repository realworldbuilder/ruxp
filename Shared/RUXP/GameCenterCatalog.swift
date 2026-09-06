import Foundation

/// Every Game Center identifier the app uses, and the pure mapping from `PlayerProgress`
/// to scores and achievement progress. No GameKit import so this compiles for both targets.
///
/// App Store Connect configuration (all leaderboards Integer, High-to-Low, Best Score):
///
/// Set "Rankings" (Classic):
///   lifetime_xp, season_xp_s01 (one per season), week_streak
///
/// Set "Live" (Recurring; the score is always 1, only the occurrence's player count matters).
/// Windows are in US Eastern and padded so every US time zone's local event falls inside:
///   active_a            30 min, restarts every 30 min, first start :00
///   active_b            30 min, restarts every 30 min, first start :15
///   trained_today       24 h,   restarts daily,        start 00:00
///   event_friday_night  18 h,   restarts weekly,       start Friday 12:00
///   event_sunday_reset  30 h,   restarts weekly,       start Sunday 00:00
enum GameCenterCatalog {
    // MARK: Rankings

    static let lifetimeXP = "lifetime_xp"
    static let weekStreak = "week_streak"

    static func seasonXP(_ season: Season) -> String { "season_xp_\(season.id.lowercased())" }
    static func seasonGoal(_ season: Season) -> String { "season_goal_\(season.id.lowercased())" }

    static func rankingBoards(season: Season) -> [String] {
        [lifetimeXP, seasonXP(season), weekStreak]
    }

    // MARK: Live presence

    static let activeA = "active_a"
    static let activeB = "active_b"
    static let trainedToday = "trained_today"
    static let eventFridayNight = "event_friday_night"
    static let eventSundayReset = "event_sunday_reset"

    /// Two staggered 30-minute windows. The heartbeat pings both; readers take the max so the
    /// count never dips to zero at an occurrence boundary.
    static let activeBoards = [activeA, activeB]

    static func eventBoard(for event: LiveEvent) -> String? {
        switch event.kind {
        case .fridayNight: return eventFridayNight
        case .sundayReset: return eventSundayReset
        case .season: return nil
        }
    }

    /// Boards the presence poller reads. The season ranking board doubles as "players this season".
    static func presenceBoards(season: Season) -> [String] {
        [activeA, activeB, trainedToday, eventFridayNight, eventSundayReset, seasonXP(season)]
    }

    // MARK: Scores

    struct ScoreSubmission: Equatable {
        let leaderboardID: String
        let value: Int
    }

    /// Absolute totals, never deltas: Game Center keeps the best value, so resubmitting is idempotent.
    static func scores(for progress: PlayerProgress, season: Season) -> [ScoreSubmission] {
        [
            ScoreSubmission(leaderboardID: lifetimeXP, value: progress.lifetimeXP),
            ScoreSubmission(leaderboardID: seasonXP(season), value: progress.seasonXP),
            ScoreSubmission(leaderboardID: weekStreak, value: progress.longestWeekStreak)
        ].filter { $0.value > 0 }
    }

    // MARK: Achievements

    struct AchievementReport: Equatable {
        let id: String
        let percent: Double
    }

    static let levelMilestones = [5, 10, 25, 50]

    static func achievements(for progress: PlayerProgress, season: Season) -> [AchievementReport] {
        func percent(_ value: Int, of goal: Int) -> Double {
            guard goal > 0 else { return 0 }
            return min(100, Double(value) * 100 / Double(goal))
        }
        let joinedFridayNight = progress.eventsJoined.keys.contains { $0.hasPrefix("\(LiveEventKind.fridayNight.rawValue)-") }

        var reports: [AchievementReport] = [
            AchievementReport(id: "first_workout", percent: progress.workoutCount >= 1 ? 100 : 0),
            AchievementReport(id: "first_pr", percent: progress.prCount >= 1 ? 100 : 0),
            AchievementReport(id: "four_workout_week", percent: progress.weeklyBonusWeeks.isEmpty ? 0 : 100),
            AchievementReport(id: "four_week_streak", percent: percent(progress.longestWeekStreak, of: 4)),
            AchievementReport(id: "friday_night", percent: joinedFridayNight ? 100 : 0),
            AchievementReport(id: seasonGoal(season), percent: percent(progress.seasonWorkoutCount, of: season.goalWorkouts))
        ]
        for milestone in levelMilestones {
            reports.append(AchievementReport(id: "level_\(milestone)", percent: percent(progress.level, of: milestone)))
        }
        return reports.filter { $0.percent > 0 }
    }
}
