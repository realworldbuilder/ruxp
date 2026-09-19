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
    /// Volume in lb per workout (UUID string), replaced on every parse so a re-parse never double counts.
    var volumeByWorkout: [String: Double]? = nil
    /// The shared objective as last seen while the session was live.
    var sessionTotalLB: Double? = nil
    var sessionContributors: Int? = nil
    /// Peak lifting-now count seen while the session was live.
    var sessionLifters: Int? = nil
    var objectiveTargetLB: Double? = nil
    /// Denormalized from the workout so the ticket never has to load it.
    var durationSeconds: TimeInterval? = nil

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

    /// Nil until a parse has landed; "No sets logged" is the honest copy for that.
    var volumeContributedLB: Double? {
        guard let volumeByWorkout, !volumeByWorkout.isEmpty else { return nil }
        return volumeByWorkout.values.reduce(0, +)
    }

    var objectiveMet: Bool {
        guard let total = sessionTotalLB, let target = objectiveTargetLB, target > 0 else { return false }
        return total >= target
    }

    /// The event's calendar day, taken from the occurrence ID so it survives schedule changes.
    var occurrenceDate: Date? {
        guard let dash = sessionID.firstIndex(of: "-") else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(sessionID[sessionID.index(after: dash)...]))
    }
}
