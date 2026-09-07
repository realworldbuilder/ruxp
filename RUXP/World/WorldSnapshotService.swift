import Foundation
import Observation
import os

/// The world keeps moving while the player is gone; this is how Home knows what happened.
/// Persists a `WorldSnapshot` on background, diffs it against the present on foreground after
/// an absence, then asks Game Center (friends, standing) to fill in the lines the clock cannot.
/// Persisted to Documents/world_snapshot.json.
@Observable
@MainActor
final class WorldSnapshotService {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "WorldSnapshotService")

    struct Ledger: Equatable {
        /// Identifies the absence; dismissal is remembered per baseline.
        let baselineAt: Date
        var items: [ReturnItem]
        var awaitingGameCenter: Bool
    }

    private(set) var ledger: Ledger?
    private(set) var current: WorldSnapshot
    private var baseline: WorldSnapshot?
    private var dismissedBaselineAt: Date?
    private var consumedForeground = false
    private var fetchTask: Task<Void, Never>?

    private let events: LiveEventProviding
    private let season: Season
    private let progression: ProgressionService
    private let gameCenter: GameCenterService
    private weak var presence: (any LivePresenceProviding)?
    private let fileURL: URL
    private static let dismissedKey = "world.dismissedLedgerAt"

    #if DEBUG
    /// -RUXPLastSeen 3d|18h|45m: pretend the last visit was that long ago.
    nonisolated(unsafe) static var debugLastSeen: TimeInterval?
    /// -RUXPWorldDemo: seed Game Center facts so every ledger line can be screenshotted offline.
    nonisolated(unsafe) static var debugDemo = false
    #endif

    init(events: LiveEventProviding, season: Season, progression: ProgressionService,
         gameCenter: GameCenterService, presence: (any LivePresenceProviding)?, fileURL: URL? = nil) {
        self.events = events
        self.season = season
        self.progression = progression
        self.gameCenter = gameCenter
        self.presence = presence
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = fileURL ?? docs.appendingPathComponent("world_snapshot.json")
        let now = ScheduledEventService.now()
        self.current = .clock(now: now, season: season, workoutsThisWeek: progression.workoutsThisWeek)
        if let stamp = UserDefaults.standard.object(forKey: Self.dismissedKey) as? Double {
            dismissedBaselineAt = Date(timeIntervalSince1970: stamp)
        }

        if var loaded = load() {
            #if DEBUG
            if let ago = Self.debugLastSeen { loaded = Self.shifted(loaded, to: now.addingTimeInterval(-ago), season: season) }
            if Self.debugDemo { loaded = Self.demoBaseline(loaded) }
            #endif
            baseline = loaded
        } else {
            #if DEBUG
            if let ago = Self.debugLastSeen {
                var synthetic = Self.shifted(current, to: now.addingTimeInterval(-ago), season: season)
                if Self.debugDemo { synthetic = Self.demoBaseline(synthetic) }
                baseline = synthetic
            }
            #endif
            // First launch: nothing to compare against. Persist so the next return has a baseline.
            if baseline == nil { persist(current) }
        }
    }

    // MARK: - Lifecycle

    /// Launch and every return to the foreground.
    func noteForeground(now: Date = ScheduledEventService.now()) {
        guard !consumedForeground else { return }
        consumedForeground = true
        guard let previous = baseline else { return }
        let gap = now.timeIntervalSince(previous.takenAt)
        var next = WorldSnapshot.clock(now: now, season: season, workoutsThisWeek: progression.workoutsThisWeek)
        next.liveEventCounts = previous.liveEventCounts
        next.friends = previous.friends
        next.playersThisSeason = previous.playersThisSeason
        next.seasonRank = previous.seasonRank
        current = next
        guard gap >= ReturnLedger.absenceThreshold else { return }

        let ran = ranEvents(from: previous.takenAt, to: now)
        ledger = Ledger(
            baselineAt: previous.takenAt,
            items: ReturnLedger.items(previous: previous, current: current, ranEvents: ran, streakWeeks: progression.currentWeekStreak),
            awaitingGameCenter: gameCenter.authState != .disabled
        )
        startGameCenterFill(previous: previous)
    }

    /// Going to the background: this is the moment the next absence is measured from.
    func noteBackground(now: Date = ScheduledEventService.now()) {
        consumedForeground = false
        current.takenAt = now
        current.workoutsThatWeek = progression.workoutsThisWeek
        if let live = events.activeEvent(at: now), !live.isSeasonWide, let presence {
            let count = presence.participantCount(for: live)
            if count > 0 { current.liveEventCounts[live.id] = count }
        }
        pruneEventCounts(now: now)
        persist(current)
        // The next foreground compares against what was just written.
        baseline = current
    }

    /// Chained from the presence poller: remember the join count while an event is live.
    func notePresenceUpdated(now: Date = ScheduledEventService.now()) {
        guard let live = events.activeEvent(at: now), !live.isSeasonWide, let presence else { return }
        let count = presence.participantCount(for: live)
        if count > 0 { current.liveEventCounts[live.id] = count }
    }

    var isLedgerVisible: Bool {
        guard let ledger, !ledger.items.isEmpty else { return false }
        return dismissedBaselineAt != ledger.baselineAt
    }

    func dismissLedger() {
        guard let ledger else { return }
        dismissedBaselineAt = ledger.baselineAt
        UserDefaults.standard.set(ledger.baselineAt.timeIntervalSince1970, forKey: Self.dismissedKey)
    }

    // MARK: - Game Center fill

    private func startGameCenterFill(previous: WorldSnapshot) {
        fetchTask?.cancel()
        guard gameCenter.authState != .disabled else {
            #if DEBUG
            if Self.debugDemo { applyDemoFill(previous: previous) }
            #endif
            ledger?.awaitingGameCenter = false
            return
        }
        fetchTask = Task { [weak self] in
            // Sign-in usually lands within a couple of seconds of launch.
            for _ in 0..<20 {
                guard let self, !Task.isCancelled else { return }
                if self.gameCenter.isActive { break }
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self, !Task.isCancelled, self.gameCenter.isActive else {
                self?.ledger?.awaitingGameCenter = false
                return
            }
            async let friends = self.gameCenter.loadFriendsOnSeasonBoard()
            async let standing = self.gameCenter.loadLocalStanding(boardID: GameCenterCatalog.seasonXP(self.season))
            let (friendList, localStanding) = await (friends, standing)
            guard !Task.isCancelled else { return }
            var next = self.current
            next.friends = Dictionary(uniqueKeysWithValues: friendList.map {
                ($0.id, WorldSnapshot.FriendMark(displayName: $0.displayName, level: $0.level, seasonXP: $0.seasonXP))
            })
            if let localStanding {
                next.playersThisSeason = localStanding.totalPlayers
                next.seasonRank = localStanding.rank
            }
            self.current = next
            self.recomputeLedger(previous: previous)
            self.persist(next)
        }
    }

    private func recomputeLedger(previous: WorldSnapshot) {
        guard var ledger else { return }
        let ran = ranEvents(from: previous.takenAt, to: current.takenAt)
        ledger.items = ReturnLedger.items(previous: previous, current: current, ranEvents: ran, streakWeeks: progression.currentWeekStreak)
        ledger.awaitingGameCenter = false
        self.ledger = ledger
    }

    // MARK: - Events in the gap

    /// Timed occurrences that started and ended between the two dates. The provider only knows
    /// the weeks around a date, so walk the gap week by week.
    private func ranEvents(from start: Date, to end: Date) -> [LiveEvent] {
        let calendar = Calendar.ruxpWeek
        var seen: [String: LiveEvent] = [:]
        var cursor = calendar.startOfWeek(for: start)
        var guardCount = 0
        while cursor <= end, guardCount < 60 {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: cursor) ?? end
            for event in events.events(overlapping: cursor, end: weekEnd) { seen[event.id] = event }
            cursor = weekEnd
            guardCount += 1
        }
        return seen.values
            .filter { !$0.isSeasonWide && $0.start >= start && $0.end <= end }
            .sorted { $0.start < $1.start }
    }

    private func pruneEventCounts(now: Date) {
        let cutoff = now.addingTimeInterval(-21 * 24 * 3600)
        current.liveEventCounts = current.liveEventCounts.filter { key, _ in
            guard let dash = key.firstIndex(of: "-") else { return false }
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.dateFormat = "yyyy-MM-dd"
            guard let date = f.date(from: String(key[key.index(after: dash)...])) else { return false }
            return date >= cutoff
        }
    }

    // MARK: - Persistence

    private func persist(_ snapshot: WorldSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save world snapshot: \(error)")
        }
    }

    private func load() -> WorldSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WorldSnapshot.self, from: Data(contentsOf: fileURL))
        } catch {
            // A bad file is a first launch, not a crash.
            Self.logger.error("Failed to load world snapshot: \(error)")
            return nil
        }
    }

    // MARK: - Debug

    #if DEBUG
    func debugResetSnapshot() {
        try? FileManager.default.removeItem(at: fileURL)
        UserDefaults.standard.removeObject(forKey: Self.dismissedKey)
        dismissedBaselineAt = nil
        ledger = nil
        baseline = nil
    }

    var debugDescription: String {
        "taken \(current.takenAt.formatted(date: .abbreviated, time: .shortened)) · week \(current.weekKey) · rank \(current.seasonRank.map(String.init) ?? "—") · friends \(current.friends?.count ?? 0)"
    }

    private static func shifted(_ snapshot: WorldSnapshot, to date: Date, season: Season) -> WorldSnapshot {
        var s = snapshot
        s.takenAt = date
        s.weekKey = Calendar.ruxpWeek.weekKey(for: date)
        s.seasonDaysLeft = season.daysRemaining(now: date)
        s.seasonID = season.id
        return s
    }

    private static func demoBaseline(_ snapshot: WorldSnapshot) -> WorldSnapshot {
        var s = snapshot
        s.friends = [
            "demo-1": .init(displayName: "MARCUS", level: 8, seasonXP: 11_000),
            "demo-2": .init(displayName: "JADE", level: 5, seasonXP: 5_100),
            "demo-3": .init(displayName: "TOBI", level: 3, seasonXP: 2_400),
        ]
        s.playersThisSeason = 210
        s.seasonRank = 14
        let lastFriday = Calendar.current.nextDate(after: snapshot.takenAt.addingTimeInterval(-8 * 86400),
                                                    matching: DateComponents(weekday: 6), matchingPolicy: .nextTime) ?? snapshot.takenAt
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        s.liveEventCounts["fridayNight-\(f.string(from: lastFriday))"] = 41
        return s
    }

    private func applyDemoFill(previous: WorldSnapshot) {
        var next = current
        next.friends = [
            "demo-1": .init(displayName: "MARCUS", level: 9, seasonXP: 12_600),
            "demo-2": .init(displayName: "JADE", level: 5, seasonXP: 5_600),
            "demo-3": .init(displayName: "TOBI", level: 3, seasonXP: 2_400),
        ]
        next.playersThisSeason = 248
        next.seasonRank = 11
        current = next
        recomputeLedger(previous: previous)
    }
    #endif
}
