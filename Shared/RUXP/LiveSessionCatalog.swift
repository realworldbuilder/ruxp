import Foundation

/// A themed evening. Rituals (FRIDAY NIGHT, SUNDAY RESET) pay XP and live in
/// `ScheduledEventService`; every other night gets a theme from here. Nightly sessions carry
/// no XP: the reason to show up is the shared objective and the floor. Foundation only.
struct LiveSessionTheme: Equatable {
    /// Days from Monday: 0 = Monday … 6 = Sunday (matches `Calendar.ruxpWeek` offsets).
    let dayOffset: Int
    /// "SATURDAY NIGHT"
    let title: String
    /// Uppercase eyebrow: "NO PLANS · PUSH DAY"
    let subtitle: String
    /// One sentence, sentence case.
    let description: String
    /// Local wall-clock hours. `endHour` 24 means midnight.
    let startHour: Int
    let endHour: Int
}

enum LiveSessionCatalog {
    /// MOVE 1,000,000 LB TOGETHER. One number for every session; lower it when the honest
    /// player count makes it unreachable (a bar that never fills is worse than a smaller goal).
    static let objectiveTargetLB: Double = 1_000_000

    /// Monday to Thursday and Saturday. Friday and Sunday belong to the rituals.
    static let nightly: [LiveSessionTheme] = [
        LiveSessionTheme(dayOffset: 0, title: "CHEST DAY WORLDWIDE", subtitle: "EVERYBODY BENCHES",
                         description: "It's Monday. You know what's happening.", startHour: 17, endHour: 24),
        LiveSessionTheme(dayOffset: 1, title: "LEG DAY AFTER DARK", subtitle: "NOBODY SKIPS",
                         description: "Squats after sunset. Get under it.", startHour: 17, endHour: 24),
        LiveSessionTheme(dayOffset: 2, title: "MIDWEEK PULL", subtitle: "BACK AND BICEPS",
                         description: "Halfway through. Pull through.", startHour: 17, endHour: 24),
        LiveSessionTheme(dayOffset: 3, title: "THURSDAY THROWDOWN", subtitle: "FULL BODY",
                         description: "Whatever's left. Leave it here.", startHour: 17, endHour: 24),
        LiveSessionTheme(dayOffset: 5, title: "SATURDAY NIGHT", subtitle: "NO PLANS · PUSH DAY",
                         description: "No plans. Push day.", startHour: 17, endHour: 24)
    ]

    static func theme(dayOffset: Int) -> LiveSessionTheme? {
        nightly.first { $0.dayOffset == dayOffset }
    }
}
