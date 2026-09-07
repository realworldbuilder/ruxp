import SwiftUI

/// Season Pass: a free, cosmetic reward track. Tier N unlocks at level N.
/// Pure functions of `PlayerProgress` + `Season`; nothing here writes XP.
enum SeasonPassRewardKind: String, CaseIterable {
    case title, nameColor, badge

    var label: String {
        switch self {
        case .title: return "TITLE"
        case .nameColor: return "NAME COLOR"
        case .badge: return "BADGE"
        }
    }

    var icon: String {
        switch self {
        case .title: return "textformat"
        case .nameColor: return "paintpalette.fill"
        case .badge: return "seal.fill"
        }
    }
}

struct SeasonPassReward: Identifiable, Equatable {
    let id: String
    /// Ladder this reward belongs to ("S00"). A reward stays resolvable after its season ends.
    let seasonID: String
    let tier: Int
    let kind: SeasonPassRewardKind
    /// Row label, e.g. "GRINDER", "TERMINAL GREEN", "BOLT BADGE".
    let name: String
    /// Title text, color key, or SF Symbol name depending on `kind`.
    let value: String

    var color: Color? { kind == .nameColor ? SeasonPassCatalog.color(forKey: value) : nil }
}

/// What the profile and share card actually draw.
struct SeasonPassLoadout: Equatable {
    var title: String?
    var nameColor: Color?
    var badge: String?
}

enum SeasonPassCatalog {
    static let tierCount = 20

    private typealias Entry = (SeasonPassRewardKind, String, String)

    /// Every season keeps its ladder forever. A cosmetic unlocked in a finished season is
    /// owned for good: `reward(id:)` resolves any season, and unlocks on a past ladder are judged
    /// by the level recorded in that season's `SeasonRecord`, never by the current level.
    private static let ladders: [String: [Entry]] = [
        SeasonCatalog.earlyAdopters.id: s00Ladder,
        SeasonCatalog.nightmareMode.id: s01Ladder,
        SeasonCatalog.pressStart.id: s02Ladder,
    ]

    /// Season 00. Tiers 1–2 are the early-adopter mark; SEASON ZERO and FOUNDER are never re-issued.
    private static let s00Ladder: [Entry] = [
        (.title, "EARLY ADOPTER", "EARLY ADOPTER"),
        (.badge, "EARLY ADOPTER BADGE", "sunrise.fill"),
        (.title, "REGULAR", "REGULAR"),
        (.nameColor, "MAGENTA NAME", "magenta"),
        (.title, "GRINDER", "GRINDER"),
        (.badge, "BOLT BADGE", "bolt.fill"),
        (.title, "IRON", "IRON"),
        (.nameColor, "TERMINAL GREEN", "green"),
        (.badge, "FLAME BADGE", "flame.fill"),
        (.title, "TWO PLATE ENERGY", "TWO PLATE ENERGY"),
        (.nameColor, "CYAN NAME", "cyan"),
        (.title, "FRIDAY NIGHT VET", "FRIDAY NIGHT VET"),
        (.badge, "TROPHY BADGE", "trophy.fill"),
        (.nameColor, "VIOLET NAME", "violet"),
        (.title, "SEASON ZERO", "SEASON ZERO"),
        (.badge, "CROWN BADGE", "crown.fill"),
        (.title, "HEAVY", "HEAVY"),
        (.nameColor, "GOLD NAME", "gold"),
        (.badge, "STAR BADGE", "star.fill"),
        (.title, "FOUNDER", "FOUNDER"),
    ]

    /// Season 01 — NIGHTMARE MODE. Same rhythm, its own marks: the spooky set is generic gaming
    /// vocabulary (difficulty tiers, bosses, the night shift). Nothing from S00 returns.
    private static let s01Ladder: [Entry] = [
        (.title, "NIGHTMARE MODE", "NIGHTMARE MODE"),
        (.badge, "MOON BADGE", "moon.fill"),
        (.title, "NIGHT SHIFT", "NIGHT SHIFT"),
        (.nameColor, "MAGENTA NAME", "magenta"),
        (.title, "SURVIVOR", "SURVIVOR"),
        (.badge, "BOLT BADGE", "bolt.fill"),
        (.title, "HARD MODE", "HARD MODE"),
        (.nameColor, "TERMINAL GREEN", "green"),
        (.badge, "FLAME BADGE", "flame.fill"),
        (.title, "TWO PLATE ENERGY", "TWO PLATE ENERGY"),
        (.nameColor, "CYAN NAME", "cyan"),
        (.title, "FRIDAY NIGHT VET", "FRIDAY NIGHT VET"),
        (.badge, "EYE BADGE", "eye.fill"),
        (.nameColor, "VIOLET NAME", "violet"),
        (.title, "SEASON ONE", "SEASON ONE"),
        (.badge, "CROWN BADGE", "crown.fill"),
        (.title, "FINAL BOSS", "FINAL BOSS"),
        (.nameColor, "GOLD NAME", "gold"),
        (.badge, "NIGHT SKY BADGE", "moon.stars.fill"),
        (.title, "NIGHTMARE CLEARED", "NIGHTMARE CLEARED"),
    ]

    /// Season 02 — PRESS START. Its own marks; nothing from S00 or S01 returns.
    private static let s02Ladder: [Entry] = [
        (.title, "PRESS START", "PRESS START"),
        (.badge, "PLAYER ONE BADGE", "gamecontroller.fill"),
        (.title, "LOADED IN", "LOADED IN"),
        (.nameColor, "MAGENTA NAME", "magenta"),
        (.title, "CONSISTENT", "CONSISTENT"),
        (.badge, "BOLT BADGE", "bolt.fill"),
        (.title, "IRON", "IRON"),
        (.nameColor, "TERMINAL GREEN", "green"),
        (.badge, "FLAME BADGE", "flame.fill"),
        (.title, "TWO PLATE ENERGY", "TWO PLATE ENERGY"),
        (.nameColor, "CYAN NAME", "cyan"),
        (.title, "FRIDAY NIGHT VET", "FRIDAY NIGHT VET"),
        (.badge, "TROPHY BADGE", "trophy.fill"),
        (.nameColor, "VIOLET NAME", "violet"),
        (.title, "SEASON TWO", "SEASON TWO"),
        (.badge, "CROWN BADGE", "crown.fill"),
        (.title, "HEAVY", "HEAVY"),
        (.nameColor, "GOLD NAME", "gold"),
        (.badge, "STAR BADGE", "star.fill"),
        (.title, "COMPLETIONIST", "COMPLETIONIST"),
    ]

    static func rewards(forSeasonID seasonID: String) -> [SeasonPassReward] {
        guard let ladder = ladders[seasonID] else {
            assertionFailure("No Season Pass ladder for \(seasonID)")
            return []
        }
        return ladder.enumerated().map { index, entry in
            let tier = index + 1
            return SeasonPassReward(id: "\(seasonID)-T\(tier)", seasonID: seasonID, tier: tier, kind: entry.0, name: entry.1, value: entry.2)
        }
    }

    static func rewards(for season: Season) -> [SeasonPassReward] {
        rewards(forSeasonID: season.id)
    }

    /// Resolves a stored reward ID ("S00-T5") against its own season's ladder, forever.
    static func reward(id: String) -> SeasonPassReward? {
        guard let code = id.split(separator: "-").first, ladders[String(code)] != nil else { return nil }
        return rewards(forSeasonID: String(code)).first { $0.id == id }
    }

    static func isUnlocked(_ reward: SeasonPassReward, level: Int) -> Bool {
        level >= reward.tier
    }

    /// The level that governs unlocks on a season's ladder: the live level for the current
    /// season, the recorded final level for a finished one, 0 for a season never played.
    static func unlockLevel(seasonID: String, progress: PlayerProgress, currentSeason: Season) -> Int {
        if seasonID == currentSeason.id { return progress.level }
        return progress.seasonRecord(for: seasonID)?.finalLevel ?? 0
    }

    /// Does this player own the reward? Past-season rewards are owned by the recorded level.
    static func isUnlocked(_ reward: SeasonPassReward, progress: PlayerProgress, currentSeason: Season) -> Bool {
        reward.tier <= unlockLevel(seasonID: reward.seasonID, progress: progress, currentSeason: currentSeason)
    }

    /// Cosmetics kept from a finished season, by its recorded level.
    static func kept(from record: SeasonRecord) -> [SeasonPassReward] {
        rewards(forSeasonID: record.seasonID).filter { $0.tier <= record.finalLevel }
    }

    static func currentTier(level: Int) -> Int {
        min(max(level, 0), tierCount)
    }

    static func next(after level: Int, season: Season) -> SeasonPassReward? {
        rewards(for: season).first { $0.tier > level }
    }

    /// Tiers crossed by a level change, clamped to the ladder.
    static func newlyUnlocked(from before: Int, to after: Int, season: Season) -> [SeasonPassReward] {
        guard after > before else { return [] }
        let low = max(before + 1, 1)
        let high = min(after, tierCount)
        guard low <= high else { return [] }
        return rewards(for: season).filter { (low...high).contains($0.tier) }
    }

    static func equippedID(for kind: SeasonPassRewardKind, in progress: PlayerProgress) -> String? {
        progress.equippedCosmetics?[kind.rawValue]
    }

    static func isEquipped(_ reward: SeasonPassReward, in progress: PlayerProgress) -> Bool {
        if let id = equippedID(for: reward.kind, in: progress) { return id == reward.id }
        // Tier 1 title is the default when nothing is equipped.
        return reward.kind == .title && reward.tier == 1
    }

    /// What to draw. An equipped ID only counts if the player still owns it (a rebuilt or reset
    /// profile could otherwise show a cosmetic it never earned).
    static func loadout(for progress: PlayerProgress, season: Season) -> SeasonPassLoadout {
        func owned(_ kind: SeasonPassRewardKind) -> SeasonPassReward? {
            guard let id = equippedID(for: kind, in: progress), let r = reward(id: id),
                  isUnlocked(r, progress: progress, currentSeason: season) else { return nil }
            return r
        }
        var loadout = SeasonPassLoadout()
        loadout.title = owned(.title)?.value ?? rewards(for: season).first { $0.kind == .title }?.value
        loadout.nameColor = owned(.nameColor)?.color
        loadout.badge = owned(.badge)?.value
        return loadout
    }


    static func color(forKey key: String) -> Color? {
        switch key {
        case "magenta": return Theme.accent
        case "green": return Theme.xp
        case "cyan": return Theme.cyan
        case "violet": return Theme.violet
        case "gold": return Theme.warning
        case "white": return Theme.textPrimary
        case "red": return Theme.live
        default: return nil
        }
    }
}
