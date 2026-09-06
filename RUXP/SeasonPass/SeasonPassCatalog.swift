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

    private static let ladder: [(SeasonPassRewardKind, String, String)] = [
        (.title, "ROOKIE", "ROOKIE"),
        (.title, "PRESSED START", "PRESSED START"),
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
        (.title, "SEASON ONE", "SEASON ONE"),
        (.badge, "CROWN BADGE", "crown.fill"),
        (.title, "HEAVY", "HEAVY"),
        (.nameColor, "GOLD NAME", "gold"),
        (.badge, "STAR BADGE", "star.fill"),
        (.title, "FOUNDER", "FOUNDER"),
    ]

    static func rewards(for season: Season) -> [SeasonPassReward] {
        ladder.enumerated().map { index, entry in
            let tier = index + 1
            return SeasonPassReward(id: "\(season.code)-T\(tier)", tier: tier, kind: entry.0, name: entry.1, value: entry.2)
        }
    }

    /// Resolves a stored reward ID. Only the current season's ladder exists today, so
    /// legacy IDs from a past season resolve as long as the code matches.
    static func reward(id: String) -> SeasonPassReward? {
        rewards(for: SeasonCatalog.current).first { $0.id == id }
    }

    static func isUnlocked(_ reward: SeasonPassReward, level: Int) -> Bool {
        level >= reward.tier
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

    static func loadout(for progress: PlayerProgress, season: Season) -> SeasonPassLoadout {
        var loadout = SeasonPassLoadout()
        if let id = equippedID(for: .title, in: progress), let r = reward(id: id) {
            loadout.title = r.value
        } else {
            loadout.title = rewards(for: season).first { $0.kind == .title }?.value
        }
        if let id = equippedID(for: .nameColor, in: progress), let r = reward(id: id) {
            loadout.nameColor = r.color
        }
        if let id = equippedID(for: .badge, in: progress), let r = reward(id: id) {
            loadout.badge = r.value
        }
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
