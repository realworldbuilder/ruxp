import Foundation

/// A lightweight season. Level and season XP live on `PlayerProgress`;
/// this only describes the window and the goal.
struct Season: Identifiable, Equatable {
    let id: String
    let number: Int
    let name: String
    let tagline: String
    let start: Date
    let end: Date
    let goalWorkouts: Int

    /// Two-digit season number, e.g. "00", "01".
    var numberLabel: String { String(format: "%02d", number) }
    var code: String { "S\(numberLabel)" }
    var displayName: String { "SEASON \(numberLabel) — \(name)" }

    func isActive(at date: Date = Date()) -> Bool {
        date >= start && date < end
    }

    func daysRemaining(now: Date = Date()) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: now, to: end).day ?? 0)
    }
}

enum SeasonCatalog {
    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// SEASON 00 — EARLY ADOPTERS. The TestFlight month. AI is on the house.
    /// Shortened from Nov 30 to Sep 30 when the App Store launch moved to Oct 1; the goal
    /// shrank with it so the frozen S00 record is honest for a 30-day season.
    static let earlyAdopters = Season(
        id: "S00",
        number: 0,
        name: "EARLY ADOPTERS",
        tagline: "First in. Set the bar.",
        start: day(2026, 9, 1),
        end: day(2026, 10, 1),
        goalWorkouts: 12
    )

    /// SEASON 01 — NIGHTMARE MODE. The App Store launch season. Spooky in gaming vocabulary
    /// only (difficulty tiers, bosses, night shifts); nothing here names a game.
    static let nightmareMode = Season(
        id: "S01",
        number: 1,
        name: "NIGHTMARE MODE",
        tagline: "Lights off. Same weights.",
        start: day(2026, 10, 1),
        end: day(2026, 12, 1),
        goalWorkouts: 20
    )

    /// SEASON 02 — PRESS START. The first full-length season is all about the game.
    static let pressStart = Season(
        id: "S02",
        number: 2,
        name: "PRESS START",
        tagline: "Load in. Level up. Own the season.",
        start: day(2026, 12, 1),
        end: day(2027, 3, 1),
        goalWorkouts: 32
    )

    static let all: [Season] = [earlyAdopters, nightmareMode, pressStart]

    /// TestFlight builds 1–3 shipped the launch window under this ID. `ProgressionService.rolloverSeasonIfNeeded`
    /// renames it to `earlyAdopters` in place, but only for a file with no schema version: from Oct 1 a real
    /// S01 (NIGHTMARE MODE) file carries one and must not be touched.
    static let legacyLaunchID = "S01"

    #if DEBUG
    /// `-RUXPSeason S01` (or the Developer picker, after a relaunch): pretend that season is
    /// current so the rollover, boards, and ladders can be exercised before its start date.
    /// The event clock cannot do this: it only ever picks the next Friday or Sunday.
    nonisolated(unsafe) static var overrideID: String?
    #endif

    static func season(id: String) -> Season? {
        all.first { $0.id == id }
    }

    /// The season active on `date`, else the most recently started one, else the first.
    static func season(at date: Date) -> Season {
        all.first { $0.isActive(at: date) }
            ?? all.last { $0.start <= date }
            ?? all[0]
    }

    /// The season that follows `season` in the catalog, if one is scheduled.
    static func next(after season: Season) -> Season? {
        all.first { $0.number == season.number + 1 }
    }

    static var current: Season {
        #if DEBUG
        if let id = overrideID, let season = season(id: id) { return season }
        #endif
        return season(at: Date())
    }
}

