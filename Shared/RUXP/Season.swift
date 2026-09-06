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

    /// SEASON 00 — EARLY ADOPTERS. The launch window. AI is on the house.
    static let earlyAdopters = Season(
        id: "S00",
        number: 0,
        name: "EARLY ADOPTERS",
        tagline: "First in. Set the bar.",
        start: day(2026, 9, 1),
        end: day(2026, 12, 1),
        goalWorkouts: 32
    )

    /// SEASON 01 — PRESS START. The first full season is all about the game.
    static let pressStart = Season(
        id: "S01",
        number: 1,
        name: "PRESS START",
        tagline: "Load in. Level up. Own the season.",
        start: day(2026, 12, 1),
        end: day(2027, 3, 1),
        goalWorkouts: 32
    )

    static let all: [Season] = [earlyAdopters, pressStart]

    /// TestFlight builds 1–3 shipped the launch window under this ID.
    /// `ProgressionService.rolloverSeasonIfNeeded` renames it to `earlyAdopters` in place.
    static let legacyLaunchID = "S01"

    /// The season active on `date`, else the most recently started one, else the first.
    static func season(at date: Date) -> Season {
        all.first { $0.isActive(at: date) }
            ?? all.last { $0.start <= date }
            ?? all[0]
    }

    static var current: Season { season(at: Date()) }
}
