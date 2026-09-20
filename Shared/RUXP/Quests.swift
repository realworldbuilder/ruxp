import Foundation

// MARK: - Quests
//
// Two finite chains that teach the game by playing it. NEW GAME is the first workout broken
// into three steps; STAGE 2 is the mechanics, one at a time. Nothing repeats, nothing is daily,
// and a cleared chain leaves Home. Foundation only: both targets compile this file.

enum QuestID: String, Codable, CaseIterable {
    // NEW GAME: the first workout.
    case pressStart
    case sayItOutLoud
    case finish
    // STAGE 2: the mechanics.
    case showUpTonight
    case ritual
    case beatYourself
    case fourInAWeek
}

struct Quest: Identifiable, Equatable {
    let id: QuestID
    /// Uppercase, two or three words.
    let title: String
    /// One sentence-case line: how to clear it. No exclamation marks.
    let how: String
}

/// How a chain pays. Steps that are taps (start, mic) pay nothing on their own; the chain does.
enum QuestReward: Equatable {
    /// One award, once, when the last quest in the chain lands. `label` is the reward row.
    case onClear(Int, label: String)
    /// One award per quest, labeled with the quest title.
    case perQuest(Int)
}

struct QuestChain: Identifiable, Equatable {
    let id: String
    /// Uppercase eyebrow ("NEW GAME").
    let name: String
    let quests: [Quest]
    let reward: QuestReward
    /// Chain id that must be cleared before this one starts listening.
    let requires: String?

    func contains(_ id: QuestID) -> Bool { quests.contains { $0.id == id } }
}

enum QuestCatalog {
    static let newGameID = "newGame"
    static let stage2ID = "stage2"

    static let chains: [QuestChain] = [
        QuestChain(
            id: newGameID, name: "NEW GAME",
            quests: [
                Quest(id: .pressStart, title: "PRESS START", how: "Start a workout. The timer is all you need."),
                Quest(id: .sayItOutLoud, title: "SAY IT OUT LOUD", how: "Hold the mic and say one set: the lift, the weight, the reps."),
                Quest(id: .finish, title: "FINISH", how: "End it after ten minutes. That is +500 XP."),
            ],
            reward: .onClear(ProgressionRules.questXP, label: "NEW GAME CLEARED"),
            requires: nil
        ),
        QuestChain(
            id: stage2ID, name: "STAGE 2",
            quests: [
                Quest(id: .showUpTonight, title: "SHOW UP TONIGHT", how: "Finish a workout while a session is live. There is one every evening from 5 PM."),
                Quest(id: .ritual, title: "RITUAL", how: "Finish a workout during FRIDAY NIGHT or SUNDAY RESET. Those two pay +500."),
                Quest(id: .beatYourself, title: "BEAT YOURSELF", how: "Log a lift heavier than you have before. Your first log of a lift sets the bar."),
                Quest(id: .fourInAWeek, title: "FOUR IN A WEEK", how: "Four workouts in one week, Monday to Sunday. The weekly bonus pays +500."),
            ],
            reward: .perQuest(ProgressionRules.questXP),
            requires: newGameID
        ),
    ]

    /// Every quest, catalog order.
    static var all: [Quest] { chains.flatMap(\.quests) }

    static func chain(id: String) -> QuestChain? { chains.first { $0.id == id } }

    static func chain(containing id: QuestID) -> QuestChain {
        chains.first { $0.contains(id) } ?? chains[0]
    }

    static func quest(_ id: QuestID) -> Quest {
        all.first { $0.id == id } ?? Quest(id: id, title: id.rawValue.uppercased(), how: "")
    }
}

/// One cleared quest. `backfilled` marks a quest derived from state that already existed when the
/// feature shipped: no XP was paid for it.
struct QuestCompletion: Codable, Equatable {
    var completedAt: Date
    var workoutID: UUID?
    var backfilled: Bool
}

/// Pure. Answers "which quests does this signal satisfy?" Nothing here reads a file or the clock.
enum QuestEvaluator {
    /// Quests a reward summary satisfies. Fires 2–3 times per workout (completion, PR bonus, crew
    /// week); the ledger in `ProgressionService` makes the repeats harmless.
    static func satisfied(by summary: WorkoutRewardSummary) -> Set<QuestID> {
        var ids: Set<QuestID> = []
        let reasons = Set(summary.awards.map(\.reason))
        if reasons.contains(.workoutComplete) { ids.insert(.finish) }
        if reasons.contains(.personalRecord) { ids.insert(.beatYourself) }
        if reasons.contains(.weeklyBonus) { ids.insert(.fourInAWeek) }
        let sessions = summary.completedSessionIDs ?? []
        if !sessions.isEmpty { ids.insert(.showUpTonight) }
        if sessions.contains(where: isRitualID) { ids.insert(.ritual) }
        return ids
    }

    /// What an existing player has already done, from persisted state. `hasAnyWorkout` is
    /// whether any workout is stored at all (rewarded or not); `hasVoiceMoment` whether any of
    /// them carries a recorded moment.
    static func backfill(progress: PlayerProgress, hasAnyWorkout: Bool, hasVoiceMoment: Bool) -> Set<QuestID> {
        var ids: Set<QuestID> = []
        if hasAnyWorkout || progress.workoutCount >= 1 { ids.insert(.pressStart) }
        if progress.workoutCount >= 1 { ids.insert(.finish) }
        if hasVoiceMoment { ids.insert(.sayItOutLoud) }
        if !progress.eventsJoined.isEmpty { ids.insert(.showUpTonight) }
        if progress.eventsJoined.keys.contains(where: isRitualID) { ids.insert(.ritual) }
        if progress.prCount >= 1 { ids.insert(.beatYourself) }
        if !progress.weeklyBonusWeeks.isEmpty { ids.insert(.fourInAWeek) }
        return ids
    }

    /// The same test `SeasonRecord.closing` uses: an occurrence id of one of the two rituals.
    static func isRitualID(_ id: String) -> Bool {
        id.hasPrefix(LiveEventKind.fridayNight.rawValue + "-") || id.hasPrefix(LiveEventKind.sundayReset.rawValue + "-")
    }
}
