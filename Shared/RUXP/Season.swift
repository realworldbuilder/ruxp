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

    var code: String { String(format: "S%02d", number) }
    var displayName: String { "SEASON \(String(format: "%02d", number)) — \(name)" }

    func isActive(at date: Date = Date()) -> Bool {
        date >= start && date < end
    }

    func daysRemaining(now: Date = Date()) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: now, to: end).day ?? 0)
    }
}

enum SeasonCatalog {
    /// SEASON 01 — BACK 2 SCHOOL. Summer is over. Start training again.
    static let backToSchool: Season = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let end = cal.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        return Season(
            id: "S01",
            number: 1,
            name: "BACK 2 SCHOOL",
            tagline: "Summer is over. Start training again.",
            start: start,
            end: end,
            goalWorkouts: 32
        )
    }()

    static var current: Season { backToSchool }
}
