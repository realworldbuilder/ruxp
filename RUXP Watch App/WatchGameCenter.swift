import Foundation
import GameKit
import os

/// Watch-side presence pings. The watch never submits XP; it only keeps this player counted as
/// "lifting now" while the phone may be suspended during a watch-run workout. Respects the
/// phone's Game Center sync toggle, which arrives over the application context.
@MainActor
final class WatchGameCenter {
    private static let logger = Logger(subsystem: "com.whussey.ruxp.watchkitapp", category: "WatchGameCenter")
    private static let syncEnabledKey = "gameCenterSyncEnabled"
    private static let heartbeatInterval: Duration = .seconds(5 * 60)

    private(set) var isAuthenticated = false
    private(set) var isSyncEnabled: Bool
    private var didInstallHandler = false
    private var heartbeat: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        isSyncEnabled = defaults.object(forKey: Self.syncEnabledKey) == nil ? true : defaults.bool(forKey: Self.syncEnabledKey)
    }

    func start() {
        guard !didInstallHandler else { return }
        didInstallHandler = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                if let error {
                    Self.logger.info("Game Center unavailable on watch: \(error.localizedDescription)")
                }
            }
        }
    }

    func setSyncEnabled(_ enabled: Bool) {
        isSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.syncEnabledKey)
        if !enabled { stopHeartbeat() }
    }

    func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                await self?.ping()
                try? await Task.sleep(for: Self.heartbeatInterval)
            }
        }
    }

    func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    private func ping() async {
        guard isSyncEnabled, GKLocalPlayer.local.isAuthenticated else { return }
        for id in GameCenterCatalog.activeBoards {
            do {
                try await GKLeaderboard.submitScore(1, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [id])
            } catch {
                Self.logger.error("Presence ping failed for \(id): \(error.localizedDescription)")
            }
        }
    }
}
