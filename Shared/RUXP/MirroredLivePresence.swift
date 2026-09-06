import Foundation
import Observation

/// Presence numbers received from the phone over WatchConnectivity. The watch never polls
/// Game Center for counts; it shows the phone's last snapshot and lets it go stale honestly.
@Observable
@MainActor
final class MirroredLivePresence: LivePresenceProviding {
    private(set) var snapshot: LiveSnapshot
    private static let cacheKey = "cachedPresence"

    init() {
        if let dict = UserDefaults.standard.dictionary(forKey: Self.cacheKey), let cached = LiveSnapshot.from(dict) {
            snapshot = cached
        } else {
            snapshot = .unavailable
        }
    }

    func start() {}
    func stop() {}

    /// Event participant counts are not mirrored; the watch shows only the lifting-now count.
    func participantCount(for event: LiveEvent) -> Int { 0 }

    func apply(_ snapshot: LiveSnapshot) {
        self.snapshot = snapshot
        UserDefaults.standard.set(snapshot.toDictionary(), forKey: Self.cacheKey)
    }
}
