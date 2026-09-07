import Foundation

/// A Game Center friend who lifts, as far as the boards can tell. Counts are rewarded workouts.
struct CrewMember: Identifiable, Codable, Equatable {
    let id: String
    var displayName: String
    var level: Int
    var thisWeek: Int
    var lastWeek: Int
    var liftingNow: Bool

    /// In the crew: trained this ISO week or last. A quiet friend drops out silently and
    /// rejoins by training; nobody is ever listed as "out".
    var isActive: Bool { thisWeek > 0 || lastWeek > 0 }
}

/// One read of the crew boards. Persisted so Home can show the last known crew offline.
struct CrewSnapshot: Codable, Equatable {
    var members: [CrewMember]
    /// This player's score on the crew board last week (the board's previous occurrence), for settlement.
    var localLastWeek: Int
    var weekKey: String
    var fetchedAt: Date
}

/// The crew as the ledger and Home read it. Pure functions of a snapshot plus the local count.
struct CrewState: Codable, Equatable {
    /// Active members only.
    var names: [String: String]
    var counts: [String: Int]
    var size: Int
    var inCount: Int
    var met: Bool

    static func from(_ snapshot: CrewSnapshot, localThisWeek: Int) -> CrewState {
        let crew = snapshot.members.filter(\.isActive)
        let others = crew.filter { $0.thisWeek > 0 }.count
        let me = localThisWeek > 0 ? 1 : 0
        let met = crew.count >= ProgressionRules.crewMinimumOthers && others == crew.count && me == 1
        return CrewState(
            names: Dictionary(uniqueKeysWithValues: crew.map { ($0.id, $0.displayName) }),
            counts: Dictionary(uniqueKeysWithValues: crew.map { ($0.id, $0.thisWeek) }),
            size: crew.count + 1,
            inCount: others + me,
            met: met
        )
    }
}
