import Foundation
import GameKit
import Observation
import os

/// The shared objective from a Game Center recurring board. Every player submits their own
/// session volume in lb; this reads the window's entries and sums them. No server, nothing
/// generated: when the board is empty the total is 0 and says so.
@Observable
@MainActor
final class GameCenterSessionObjective: SessionObjectiveProviding {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "GameCenterSessionObjective")
    /// Game Center pages 100 entries at a time. Two pages is plenty for now; a backend replaces
    /// this class long before the sum needs more.
    static let pageSize = 100
    static let maxEntries = 200

    private(set) var state: SessionObjectiveState
    private(set) var lastError: String?
    var onStateChanged: ((SessionObjectiveState) -> Void)?

    private let gameCenter: GameCenterService
    private let events: LiveEventProviding
    private let pollInterval: Duration
    private var board: GKLeaderboard?
    private var pollTask: Task<Void, Never>?
    private var refreshing = false

    init(gameCenter: GameCenterService, events: LiveEventProviding, pollInterval: Duration = .seconds(90)) {
        self.gameCenter = gameCenter
        self.events = events
        self.pollInterval = pollInterval
        self.state = .unavailable(targetLB: LiveSessionCatalog.objectiveTargetLB)
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

    // MARK: - Submit

    func submit(volumeLB: Double, for event: LiveEvent) async {
        guard gameCenter.isActive, volumeLB > 0 else { return }
        do {
            try await loadBoardIfNeeded(now: Date())
            guard let board, Self.window(of: board, covers: event) else {
                Self.logger.info("Board window rolled past \(event.id); keeping the contribution local")
                return
            }
            try await GKLeaderboard.submitScore(Int(volumeLB.rounded()), context: 0, player: GKLocalPlayer.local,
                                                leaderboardIDs: [GameCenterCatalog.sessionVolume])
            Self.logger.info("Submitted \(Int(volumeLB)) lb to \(GameCenterCatalog.sessionVolume)")
            await refresh()
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("Volume submit failed: \(error.localizedDescription)")
        }
    }

    /// The board's current occurrence overlaps the session (a parse landing after the window
    /// rolled must not credit the next night).
    private static func window(of board: GKLeaderboard, covers event: LiveEvent) -> Bool {
        let start = board.startDate ?? .distantPast
        let end = board.nextStartDate ?? .distantFuture
        return event.end > start && event.start < end
    }

    // MARK: - Polling

    private func loadBoardIfNeeded(now: Date) async throws {
        let rolled = (board?.nextStartDate ?? .distantFuture) <= now
        guard board == nil || rolled else { return }
        board = try await GKLeaderboard.loadLeaderboards(IDs: [GameCenterCatalog.sessionVolume]).first
    }

    private func refresh() async {
        let target = events.activeEvent(at: ScheduledEventService.now())?.objective?.targetLB
            ?? LiveSessionCatalog.objectiveTargetLB
        guard gameCenter.isActive else {
            if state.isAvailable || state.targetLB != target {
                state = .unavailable(targetLB: target)
                onStateChanged?(state)
            }
            return
        }
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let now = Date()
        do {
            try await loadBoardIfNeeded(now: now)
            guard let board else { return }
            var entries: [GKLeaderboard.Entry] = []
            var total = 0
            var location = 1
            while location <= Self.maxEntries {
                let (_, page, players) = try await board.loadEntries(for: .global, timeScope: .allTime,
                                                                     range: NSRange(location: location, length: Self.pageSize))
                total = players
                entries.append(contentsOf: page)
                if page.count < Self.pageSize { break }
                location += Self.pageSize
            }
            let leaders = entries
                .filter { $0.score > 0 }
                .prefix(10)
                .map { SessionContributor(id: $0.player.gamePlayerID, alias: $0.player.displayName, volumeLB: Double($0.score)) }
            state = SessionObjectiveState(
                targetLB: target,
                totalLB: Double(entries.reduce(0) { $0 + max(0, $1.score) }),
                contributors: total,
                isAvailable: true,
                updatedAt: now,
                leaders: Array(leaders)
            )
            lastError = nil
            onStateChanged?(state)
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("Failed to read \(GameCenterCatalog.sessionVolume): \(error.localizedDescription)")
        }
    }
}
