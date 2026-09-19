import Foundation

// MARK: - What may leave the phone

/// Who may see a moment. Workout data is private by default; a moment is a gameplay event
/// carved out of it on purpose.
enum SharePolicy: String, Codable {
    case privateOnly = "private"
    case crew
    case event
    case everyone = "public"

    var leavesTheDevice: Bool { self == .event || self == .everyone }
}

/// One publishable gameplay event. Never a set. Numbers here are gameplay numbers (a lift, an
/// XP amount, a count of lifters); body and health data have no field to land in.
struct CommunityMoment: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        // Player moments: opt-in, carry the alias.
        case sessionJoined
        case personalRecord
        case levelUp
        case sessionComplete
        // Aggregate moments: no identity, one per threshold per occurrence.
        case lifterMilestone
        case volumeMilestone
        // Produced by the relay's schedule, never by a phone (listed so the wire format is one).
        case sessionLive
        case eventComplete
    }

    /// Dedup key, stable across phones: "volumeMilestone:fridayNight-2026-09-18:250000".
    let id: String
    let kind: Kind
    let at: Date
    var audience: SharePolicy
    var eventID: String? = nil
    var eventTitle: String? = nil
    var guildID: String? = nil
    var channelID: String? = nil
    var liftingNow: Int? = nil
    var lifters: Int? = nil
    var totalLB: Double? = nil
    var targetLB: Double? = nil
    var exercise: String? = nil
    var weightLB: Double? = nil
    var reps: Int? = nil
    var xp: Int? = nil
    var level: Int? = nil
    /// Game Center alias, only on player moments and only when the player opted in.
    var alias: String? = nil
    var joinURL: URL? = nil

    var isPlayerMoment: Bool { MomentPolicy.isPlayerMoment(kind) }
}

/// The player's choice. Off by default.
struct CommunitySharing: Equatable {
    var shareMoments: Bool = false
}

// MARK: - Policy

/// Pure rules for what goes out. Routine sets stay in RUXP; this is the whole list.
enum MomentPolicy {
    /// Lifters in one occurrence: post once per threshold crossed.
    static let lifterThresholds = [10, 25, 50, 100, 250, 500, 1000]
    /// Volume moved together: same step as the floor.
    static let volumeStepLB: Double = 250_000
    /// PR moments per workout, same cap as PR XP.
    static var maxPRsPerWorkout: Int { ProgressionRules.maxPRBonusesPerWorkout }

    static func isPlayerMoment(_ kind: CommunityMoment.Kind) -> Bool {
        switch kind {
        case .sessionJoined, .personalRecord, .levelUp, .sessionComplete: return true
        case .lifterMilestone, .volumeMilestone, .sessionLive, .eventComplete: return false
        }
    }

    /// Where a moment may go. Aggregates go to the event's channel when it has one; player
    /// moments only when the player said so.
    static func audience(for kind: CommunityMoment.Kind, sharing: CommunitySharing, hasCommunity: Bool) -> SharePolicy {
        guard hasCommunity else { return .privateOnly }
        if isPlayerMoment(kind) { return sharing.shareMoments ? .event : .privateOnly }
        return .event
    }

    /// The highest lifter threshold crossed between two reads, if any.
    static func lifterMilestone(previous: Int, current: Int) -> Int? {
        lifterThresholds.filter { previous < $0 && current >= $0 }.max()
    }

    /// The volume step crossed between two reads, if any.
    static func volumeMilestone(previous: Double, current: Double) -> Double? {
        let before = Int(previous / volumeStepLB)
        let after = Int(current / volumeStepLB)
        return after > before ? Double(after) * volumeStepLB : nil
    }
}
