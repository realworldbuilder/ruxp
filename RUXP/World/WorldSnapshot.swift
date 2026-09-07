import Foundation

// MARK: - Snapshot

/// What the world looked like the last time this player was here. Diffed against the present
/// on return so Home can say what changed. Every fact is either from the clock or observed from
/// Game Center; a fact never observed stays nil and is never guessed.
struct WorldSnapshot: Codable, Equatable {
    var takenAt: Date
    var seasonID: String
    /// ISO week key ("2026-W37") of `takenAt`.
    var weekKey: String
    var seasonDaysLeft: Int
    /// This player's rewarded workouts in `weekKey`'s week.
    var workoutsThatWeek: Int
    /// Last observed join count per live occurrence while it was live ("fridayNight-2026-09-11": 41).
    var liveEventCounts: [String: Int] = [:]
    /// Game Center friends on the season board, by player ID. Nil until observed once.
    var friends: [String: FriendMark]? = nil
    /// Players with a score on the season board. A lower bound; nobody ever leaves a classic board.
    var playersThisSeason: Int? = nil
    /// This player's rank on the season XP board.
    var seasonRank: Int? = nil

    struct FriendMark: Codable, Equatable {
        var displayName: String
        var level: Int
        var seasonXP: Int
    }

    /// The clock-derived half of a snapshot; Game Center fields are carried over separately.
    static func clock(now: Date, season: Season, workoutsThisWeek: Int, calendar: Calendar = .ruxpWeek) -> WorldSnapshot {
        WorldSnapshot(
            takenAt: now,
            seasonID: season.id,
            weekKey: calendar.weekKey(for: now),
            seasonDaysLeft: season.daysRemaining(now: now),
            workoutsThatWeek: workoutsThisWeek
        )
    }
}

// MARK: - Items

/// One line on the WHILE YOU WERE GONE card.
struct ReturnItem: Identifiable, Equatable {
    enum Kind: Int, Comparable {
        case eventRan = 0, rankMoved, friendLeveled, weekRolled, seasonEnding, newPlayers, friendsTrained
        static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    enum Accent: Equatable { case neutral, live, xp, violet, warning }

    let kind: Kind
    let text: String
    let accent: Accent
    var id: String { "\(kind.rawValue)-\(text)" }
}

/// Pure diff. Nothing here reads the clock, a file, or Game Center.
enum ReturnLedger {
    /// Shorter absences show nothing; Home already covers "right now".
    static let absenceThreshold: TimeInterval = 6 * 3600
    static let maxItems = 4
    static let seasonThresholds = [30, 7, 1]

    /// `ranEvents` are timed occurrences that started and ended inside the gap.
    /// `streakWeeks` is the live week streak (for the new-week line).
    static func items(previous: WorldSnapshot, current: WorldSnapshot, ranEvents: [LiveEvent], streakWeeks: Int) -> [ReturnItem] {
        // A season boundary is the recap's moment, not this card's.
        guard previous.seasonID == current.seasonID else { return [] }
        var items: [ReturnItem] = []

        if let line = eventsLine(ranEvents, previous: previous) {
            items.append(ReturnItem(kind: .eventRan, text: line, accent: .live))
        }

        if let before = previous.seasonRank, let after = current.seasonRank, before != after, before > 0, after > 0 {
            if after < before {
                items.append(ReturnItem(kind: .rankMoved, text: "You moved #\(before) → #\(after) on season XP.", accent: .xp))
            } else {
                items.append(ReturnItem(kind: .rankMoved, text: "You slipped #\(before) → #\(after) on season XP.", accent: .neutral))
            }
        }

        var leveled: [(name: String, level: Int)] = []
        var trained = 0
        if let before = previous.friends, let after = current.friends {
            for (id, mark) in after {
                guard let old = before[id] else { continue }
                if mark.level > old.level {
                    leveled.append((mark.displayName, mark.level))
                } else if mark.seasonXP > old.seasonXP {
                    trained += 1
                }
            }
        }
        if let top = leveled.sorted(by: { $0.level > $1.level }).first {
            let rest = leveled.count - 1
            var line = "\(top.name) hit LVL \(top.level)."
            if rest == 1 { line += " 1 more friend leveled up." }
            if rest > 1 { line += " \(rest) more friends leveled up." }
            items.append(ReturnItem(kind: .friendLeveled, text: line, accent: .violet))
        }

        if previous.weekKey != current.weekKey {
            var line = "New week. \(current.workoutsThatWeek)/\(ProgressionRules.weeklyTargetWorkouts) for the weekly bonus."
            if streakWeeks > 0 { line += " Streak at \(streakWeeks) week\(streakWeeks == 1 ? "" : "s")." }
            items.append(ReturnItem(kind: .weekRolled, text: line, accent: .neutral))
        }

        if let threshold = seasonThresholds.first(where: { previous.seasonDaysLeft > $0 && current.seasonDaysLeft <= $0 }) {
            let text: String
            switch threshold {
            case 1: text = current.seasonDaysLeft == 0 ? "Last day of \(current.seasonID)." : "\(current.seasonID) ends tomorrow."
            default: text = "\(current.seasonID) ends in \(current.seasonDaysLeft) days."
            }
            items.append(ReturnItem(kind: .seasonEnding, text: text, accent: .warning))
        }

        if let before = previous.playersThisSeason, let after = current.playersThisSeason, after > before {
            let delta = after - before
            items.append(ReturnItem(kind: .newPlayers, text: "+\(delta.grouped) player\(delta == 1 ? "" : "s") joined the season.", accent: .neutral))
        }

        if trained > 0 {
            items.append(ReturnItem(kind: .friendsTrained, text: "\(trained) friend\(trained == 1 ? "" : "s") trained.", accent: .neutral))
        }

        return Array(items.sorted { $0.kind < $1.kind }.prefix(maxItems))
    }

    private static func eventsLine(_ events: [LiveEvent], previous: WorldSnapshot) -> String? {
        let timed = events.filter { !$0.isSeasonWide }
        guard !timed.isEmpty else { return nil }
        let byKind = Dictionary(grouping: timed, by: \.kind)
        if byKind.count == 1, let (_, occurrences) = byKind.first {
            let latest = occurrences.max { $0.start < $1.start }!
            if occurrences.count > 1 {
                return "\(occurrences.count) \(latest.title)S ran while you were out."
            }
            if let joined = previous.liveEventCounts[latest.id], joined > 0 {
                return "\(latest.title) ran. \(joined.grouped) player\(joined == 1 ? "" : "s") joined."
            }
            return "\(latest.title) ran while you were out."
        }
        let parts = byKind.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { kind -> String? in
            guard let occurrences = byKind[kind], let title = occurrences.first?.title else { return nil }
            return occurrences.count > 1 ? "\(occurrences.count) \(title)S" : title
        }
        return "\(parts.joined(separator: " and ")) ran while you were out."

    }

    /// "2D 4H", "9H", "45M"
    static func awayLabel(from: Date, to: Date) -> String {
        let seconds = max(0, Int(to.timeIntervalSince(from)))
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return hours > 0 ? "\(days)D \(hours)H" : "\(days)D" }
        if hours > 0 { return "\(hours)H" }
        return "\(max(1, minutes))M"
    }
}
