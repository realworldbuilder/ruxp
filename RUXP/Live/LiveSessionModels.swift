import Foundation

/// One player's record of one Live Session occurrence (`LiveEvent.id`). Created when they
/// tap JOIN or start a workout during the event; completed only when the existing
/// HealthKit-backed reward flow pays the event bonus for a real workout.
struct LiveSessionParticipation: Codable, Identifiable, Equatable {
    let id: UUID
    /// `LiveEvent.id`, e.g. "sundayReset-2026-09-06".
    let sessionID: String
    /// Denormalized so history rows never depend on the schedule.
    let title: String
    /// `GKLocalPlayer.gamePlayerID` when signed in at join time; backfilled on later sign-in.
    var gameCenterPlayerID: String?
    let joinedAt: Date
    var completedAt: Date?
    var associatedWorkoutID: UUID?
    var xpEarned: Int
    /// Phase 3: most remote players seen in the Training Room during this session.
    var roomPeerCount: Int?

    init(
        id: UUID = UUID(),
        sessionID: String,
        title: String,
        gameCenterPlayerID: String? = nil,
        joinedAt: Date,
        completedAt: Date? = nil,
        associatedWorkoutID: UUID? = nil,
        xpEarned: Int = 0,
        roomPeerCount: Int? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.gameCenterPlayerID = gameCenterPlayerID
        self.joinedAt = joinedAt
        self.completedAt = completedAt
        self.associatedWorkoutID = associatedWorkoutID
        self.xpEarned = xpEarned
        self.roomPeerCount = roomPeerCount
    }

    var completed: Bool { completedAt != nil }

    /// The event's calendar day, taken from the occurrence ID so it survives schedule changes.
    var occurrenceDate: Date? {
        guard let dash = sessionID.firstIndex(of: "-") else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(sessionID[sessionID.index(after: dash)...]))
    }
}
