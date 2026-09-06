import Foundation
import GameKit
import Observation
import os

/// Real presence from Game Center recurring leaderboards. Each count is the current
/// occurrence's `totalPlayerCount`: how many players pinged that board in its window.
/// Polls while the app is in the foreground; refreshes immediately after our own pings.
@Observable
@MainActor
final class GameCenterLivePresence: LivePresenceProviding {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "GameCenterLivePresence")

    private(set) var snapshot: LiveSnapshot = .unavailable
    /// Latest count per board (shown in Settings › Developer).
    private(set) var counts: [String: Int] = [:]
    private(set) var lastError: String?
    var onSnapshotChanged: ((LiveSnapshot) -> Void)?

    private let gameCenter: GameCenterService
    private let season: Season
    private let pollInterval: Duration
    private var boards: [String: GKLeaderboard] = [:]
    private var pollTask: Task<Void, Never>?
    private var refreshing = false

    init(gameCenter: GameCenterService, season: Season, pollInterval: Duration = .seconds(60)) {
        self.gameCenter = gameCenter
        self.season = season
        self.pollInterval = pollInterval
        gameCenter.onAuthenticated = { [weak self] in self?.refreshNow() }
        gameCenter.onPresenceSubmitted = { [weak self] in self?.refreshNow() }
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshNow() {
        Task { await refresh() }
    }

    func participantCount(for event: LiveEvent) -> Int {
        guard snapshot.isAvailable else { return 0 }
        if event.isSeasonWide { return counts[GameCenterCatalog.seasonXP(season)] ?? 0 }
        guard event.isActive(at: ScheduledEventService.now()),
              let id = GameCenterCatalog.eventBoard(for: event) else { return 0 }
        return counts[id] ?? 0
    }

    // MARK: - Polling

    private func refresh() async {
        guard gameCenter.isActive else {
            if snapshot.isAvailable {
                snapshot = .unavailable
                onSnapshotChanged?(snapshot)
            }
            return
        }
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let now = Date()
        // Recurring boards roll over; reload the occurrence objects once any window has ended.
        let rolled = boards.values.contains { ($0.nextStartDate ?? .distantFuture) <= now }
        if boards.isEmpty || rolled {
            do {
                let loaded = try await GKLeaderboard.loadLeaderboards(IDs: GameCenterCatalog.presenceBoards(season: season))
                boards = loaded.reduce(into: [:]) { $0[$1.baseLeaderboardID] = $1 }
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                Self.logger.error("Failed to load presence boards: \(error.localizedDescription)")
                return
            }
        }

        var fresh: [String: Int] = [:]
        for (id, board) in boards {
            do {
                let (_, _, total) = try await board.loadEntries(for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 1))
                fresh[id] = total
            } catch {
                lastError = error.localizedDescription
                Self.logger.error("Failed to read \(id): \(error.localizedDescription)")
            }
        }
        guard !fresh.isEmpty else { return }

        counts.merge(fresh) { $1 }
        snapshot = LiveSnapshot(
            liftingNow: max(counts[GameCenterCatalog.activeA] ?? 0, counts[GameCenterCatalog.activeB] ?? 0),
            workoutsToday: counts[GameCenterCatalog.trainedToday] ?? 0,
            isAvailable: true,
            updatedAt: now
        )
        onSnapshotChanged?(snapshot)
    }
}
