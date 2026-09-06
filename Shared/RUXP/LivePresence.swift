import Foundation
import Observation

// MARK: - Snapshot

/// Real presence numbers. Every count is the number of Game Center players who submitted a
/// score to a recurring leaderboard window (see `GameCenterCatalog`). Nothing here is generated.
struct LiveSnapshot: Equatable {
    /// Players who pinged an active-workout window within the last 15–30 minutes.
    var liftingNow: Int
    /// Players who finished a rewarded workout today.
    var workoutsToday: Int
    /// False until Game Center is signed in and at least one poll has succeeded.
    var isAvailable: Bool
    var updatedAt: Date?

    static let unavailable = LiveSnapshot(liftingNow: 0, workoutsToday: 0, isAvailable: false, updatedAt: nil)

    /// True when the numbers are recent enough to show. Mirrored copies (watch) go stale.
    func isFresh(now: Date = Date(), maxAge: TimeInterval = 10 * 60) -> Bool {
        guard isAvailable, let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) <= maxAge
    }

    /// "1 person trained today." / "38 people trained today."
    var trainedTodayLine: String {
        switch workoutsToday {
        case 0: return "Nobody has trained yet today."
        case 1: return "1 person trained today."
        default: return "\(workoutsToday.grouped) people trained today."
        }
    }

    // MARK: Wire format (phone → watch application context)

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            ConnectivityConstants.contextLiftingNowKey: liftingNow,
            ConnectivityConstants.contextTrainedTodayKey: workoutsToday,
            ConnectivityConstants.contextPresenceAvailableKey: isAvailable
        ]
        if let updatedAt { dict[ConnectivityConstants.contextPresenceUpdatedAtKey] = updatedAt.timeIntervalSince1970 }
        return dict
    }

    static func from(_ dict: [String: Any]) -> LiveSnapshot? {
        guard let liftingNow = dict[ConnectivityConstants.contextLiftingNowKey] as? Int else { return nil }
        return LiveSnapshot(
            liftingNow: liftingNow,
            workoutsToday: dict[ConnectivityConstants.contextTrainedTodayKey] as? Int ?? 0,
            isAvailable: dict[ConnectivityConstants.contextPresenceAvailableKey] as? Bool ?? false,
            updatedAt: (dict[ConnectivityConstants.contextPresenceUpdatedAtKey] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        )
    }
}

// MARK: - Provider

/// The feeling RUXP sells: other people are doing this with you.
/// The phone implements this with Game Center (`GameCenterLivePresence`); the watch mirrors
/// the phone's numbers (`MirroredLivePresence`). Views only ever see this protocol.
@MainActor
protocol LivePresenceProviding: AnyObject {
    var snapshot: LiveSnapshot { get }
    func start()
    func stop()
    func participantCount(for event: LiveEvent) -> Int
}
