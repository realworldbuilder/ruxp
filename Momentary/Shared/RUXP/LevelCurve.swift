import Foundation

/// Season level curve, levels 1–100.
/// Level is derived from season XP. Early levels come every 2–3 workouts,
/// later levels slow down gradually. Level 100 is intentionally far away.
enum LevelCurve {
    static let minLevel = 1
    static let maxLevel = 100

    /// XP needed to go from `level` to `level + 1`.
    static func xpToAdvance(from level: Int) -> Int {
        let clamped = min(max(level, minLevel), maxLevel)
        return 1000 + 150 * (clamped - 1)
    }

    /// Cumulative XP required to have reached `level` (level 1 = 0 XP).
    static func xpToReach(level: Int) -> Int {
        guard level > minLevel else { return 0 }
        return (minLevel..<min(level, maxLevel)).reduce(0) { $0 + xpToAdvance(from: $1) }
    }

    struct Progress: Equatable {
        let level: Int
        let xpIntoLevel: Int
        let xpToNext: Int
        var fraction: Double {
            xpToNext > 0 ? min(1, Double(xpIntoLevel) / Double(xpToNext)) : 1
        }
        var isMaxLevel: Bool { level >= LevelCurve.maxLevel }
    }

    static func progress(seasonXP: Int) -> Progress {
        var level = minLevel
        var remaining = max(0, seasonXP)
        while level < maxLevel {
            let need = xpToAdvance(from: level)
            if remaining < need { break }
            remaining -= need
            level += 1
        }
        if level >= maxLevel {
            return Progress(level: maxLevel, xpIntoLevel: 0, xpToNext: 0)
        }
        return Progress(level: level, xpIntoLevel: remaining, xpToNext: xpToAdvance(from: level))
    }

    static func level(forSeasonXP xp: Int) -> Int {
        progress(seasonXP: xp).level
    }
}
