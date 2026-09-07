import Foundation
import GameKit
import Observation
import UIKit
import os

/// Game Center: sign-in, XP leaderboards, achievements, and the presence pings that make the
/// live counts real. Everything here is best-effort and never blocks the reward flow.
@Observable
@MainActor
final class GameCenterService {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "GameCenterService")

    enum AuthState: Equatable {
        case disabled
        case pending
        case authenticated(alias: String)
        case unavailable(String)
    }

    private(set) var authState: AuthState
    private(set) var lastSubmissionResult = "—"
    /// Settings toggle. Off means no scores, no achievements, no presence pings, no counts.
    private(set) var isSyncEnabled: Bool
    /// Fired after sign-in succeeds (presence starts polling, watch learns the sync flag).
    var onAuthenticated: (() -> Void)?
    /// Fired with the persistent `gamePlayerID` after sign-in (Live participations attach it).
    var onPlayerIdentified: ((String) -> Void)?
    /// Fired after a presence ping lands so the poller can refresh right away.
    var onPresenceSubmitted: (() -> Void)?
    /// Fired when the sync toggle changes (pushed to the watch).
    var onSyncEnabledChanged: ((Bool) -> Void)?

    static let syncEnabledKey = "gameCenterSyncEnabled"
    private static let cacheKey = "gameCenter.cache"

    /// DEBUG-only: launch with `-RUXPSkipGameCenter` so simulator reward-flow runs never see a
    /// login sheet. Never true in release builds.
    nonisolated static var isDisabledForTesting: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-RUXPSkipGameCenter")
        #else
        return false
        #endif
    }

    /// What was last sent, so a flush only submits what changed. Keyed to the signed-in player.
    struct SubmissionCache: Codable, Equatable {
        var playerID = ""
        var lastScores: [String: Int] = [:]
        var lastAchievements: [String: Double] = [:]
        var dirty = false
        var didSeedDisplayName = false
    }

    private let progression: ProgressionService
    private let enabled: Bool
    private var didInstallHandler = false
    private var pending: PlayerProgress?
    private var flushTask: Task<Void, Never>?
    private var inFlight = false
    private var cache: SubmissionCache
    private let dashboardDelegate = DashboardDelegate()

    init(progression: ProgressionService, enabled: Bool = !GameCenterService.isDisabledForTesting) {
        self.progression = progression
        self.enabled = enabled
        let defaults = UserDefaults.standard
        self.isSyncEnabled = defaults.object(forKey: Self.syncEnabledKey) == nil ? true : defaults.bool(forKey: Self.syncEnabledKey)
        self.cache = Self.loadCache()
        self.authState = enabled ? .pending : .disabled
    }

    // MARK: - State

    var isAuthenticated: Bool {
        if case .authenticated = authState { return true }
        return false
    }

    /// True when scores and presence can flow.
    var isActive: Bool { enabled && isSyncEnabled && isAuthenticated }

    var alias: String? {
        if case .authenticated(let alias) = authState { return alias }
        return nil
    }

    /// Persistent, app-scoped Game Center identity. Nil until signed in.
    var playerID: String? {
        guard isAuthenticated else { return nil }
        return GKLocalPlayer.local.gamePlayerID
    }

    /// One line for the Profile rows.
    var statusLine: String {
        switch authState {
        case .disabled: return "Game Center off in this build"
        case .pending: return "Connecting to Game Center…"
        case .unavailable: return "Not signed in to Game Center"
        case .authenticated(let alias): return isSyncEnabled ? "Game Center · \(alias)" : "Game Center sync is off"
        }
    }

    /// Why the live counts are hidden.
    var presenceUnavailableMessage: String {
        switch authState {
        case .disabled: return "Game Center is off in this build."
        case .pending: return "Connecting to Game Center…"
        case .unavailable: return "Sign in to Game Center to see who's lifting."
        case .authenticated: return isSyncEnabled ? "Loading who's lifting…" : "Turn on Game Center sync in Settings to see who's lifting."
        }
    }

    // MARK: - Auth

    /// Installs the authenticate handler once per launch. GameKit re-invokes it on its own when
    /// the user signs in through Settings and returns to the app; never reassign it to re-prompt.
    func start() {
        guard enabled, !didInstallHandler else { return }
        didInstallHandler = true
        // GameKit normally calls back within a second or two. If it never does (no Game Center
        // account, simulator overlay missing), stop saying "Connecting…". The handler still wins later.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.authState == .pending else { return }
            self.authState = .unavailable("Not signed in")
        }
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let viewController {
                    viewController.overrideUserInterfaceStyle = .dark
                    Self.topViewController()?.present(viewController, animated: true)
                    return
                }
                if GKLocalPlayer.local.isAuthenticated {
                    self.handleAuthenticated()
                } else {
                    let cancelled = (error as? GKError)?.code == .cancelled
                    let reason = cancelled ? "Not signed in" : (error?.localizedDescription ?? "Unavailable")
                    self.authState = .unavailable(reason)
                    Self.logger.info("Game Center unavailable: \(reason)")
                }
            }
        }
    }

    private func handleAuthenticated() {
        let player = GKLocalPlayer.local
        let alias = player.alias
        authState = .authenticated(alias: alias)
        Self.logger.info("Game Center signed in as \(alias)")

        if cache.playerID != player.gamePlayerID {
            // Different Apple ID than last time: everything must be resubmitted.
            cache = SubmissionCache(playerID: player.gamePlayerID, dirty: true)
        }
        seedDisplayNameIfNeeded()
        cache.dirty = true
        pending = progression.progress
        persistCache()
        scheduleFlush(after: .zero)
        onAuthenticated?()
        onPlayerIdentified?(player.gamePlayerID)
    }

    /// First sign-in only: a card that still says PLAYER takes the Game Center nickname.
    private func seedDisplayNameIfNeeded() {
        guard !cache.didSeedDisplayName else { return }
        cache.didSeedDisplayName = true
        let alias = GKLocalPlayer.local.alias
        if progression.progress.displayName == "PLAYER", !alias.isEmpty {
            progression.setDisplayName(alias)
        }
    }

    // MARK: - Progress → Game Center

    /// Hook target for `ProgressionService.onProgressChanged`. Debounced so the completion award
    /// and the PR bonus that follows AI parsing collapse into one submission.
    func noteProgressChanged(_ progress: PlayerProgress) {
        pending = progress
        cache.dirty = true
        persistCache()
        scheduleFlush(after: .seconds(8))
    }

    func flushNow() {
        scheduleFlush(after: .zero)
    }

    func setSyncEnabled(_ on: Bool) {
        guard on != isSyncEnabled else { return }
        isSyncEnabled = on
        UserDefaults.standard.set(on, forKey: Self.syncEnabledKey)
        onSyncEnabledChanged?(on)
        if on {
            cache.dirty = true
            persistCache()
            flushNow()
        }
    }

    /// "Delete All Data": forget what was sent so a rebuilt profile resubmits. Game Center itself
    /// keeps the best scores already posted; the client cannot remove them.
    func clearLocalCache() {
        cache = SubmissionCache(playerID: cache.playerID, dirty: true)
        if isAuthenticated { seedDisplayNameIfNeeded() }
        persistCache()
    }

    private func scheduleFlush(after delay: Duration) {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            await self.flush()
        }
    }

    private func flush() async {
        guard isActive, cache.dirty, !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let progress = pending ?? progression.progress
        let season = progression.season
        var failures: [String] = []

        // One ID per call so an unconfigured board cannot block the others.
        for score in GameCenterCatalog.scores(for: progress, season: season)
        where cache.lastScores[score.leaderboardID] != score.value {
            do {
                try await GKLeaderboard.submitScore(score.value, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [score.leaderboardID])
                cache.lastScores[score.leaderboardID] = score.value
                Self.logger.info("Submitted \(score.value) to \(score.leaderboardID)")
            } catch {
                failures.append(score.leaderboardID)
                Self.logger.error("Score submit failed for \(score.leaderboardID): \(error.localizedDescription)")
            }
        }

        // One achievement per call: an ID missing from App Store Connect fails the whole batch
        // otherwise, and would block every other achievement forever.
        let reports = GameCenterCatalog.achievements(for: progress, season: season)
            .filter { (cache.lastAchievements[$0.id] ?? 0) < $0.percent }
        for report in reports {
            let achievement = GKAchievement(identifier: report.id)
            achievement.percentComplete = report.percent
            achievement.showsCompletionBanner = true
            do {
                try await GKAchievement.report([achievement])
                cache.lastAchievements[report.id] = report.percent
                Self.logger.info("Reported \(report.id) at \(report.percent)%")
            } catch {
                failures.append(report.id)
                Self.logger.error("Achievement report failed for \(report.id): \(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            // Only clean if nothing changed while we were submitting.
            if pending == progress { cache.dirty = false }
            lastSubmissionResult = "OK \(Date.now.formatted(date: .omitted, time: .shortened))"
        } else {
            lastSubmissionResult = "Failed: \(failures.joined(separator: ", "))"
        }
        persistCache()
    }

    // MARK: - Presence

    /// Score 1 to each board so this player is counted in the board's current window.
    func submitPresence(boards: [String]) async {
        guard isActive, !boards.isEmpty else { return }
        var landed = false
        for id in boards {
            do {
                try await GKLeaderboard.submitScore(1, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [id])
                landed = true
            } catch {
                Self.logger.error("Presence ping failed for \(id): \(error.localizedDescription)")
            }
        }
        if landed { onPresenceSubmitted?() }
    }

    // MARK: - Friends

    /// A Game Center friend who has played RUXP this season. Level is derived from their
    /// season XP score, the same way the local level is.
    struct LiveFriend: Identifiable, Equatable {
        let id: String
        let displayName: String
        let level: Int
        let seasonXP: Int
    }

    /// Friends with a score on the season XP board. Best-effort: signed out, no friends, or a
    /// board that is not configured yet all yield an empty list, never an error in the UI.
    func loadFriendsOnSeasonBoard() async -> [LiveFriend] {
        guard isActive else { return [] }
        let boardID = GameCenterCatalog.seasonXP(progression.season)
        do {
            guard let board = try await GKLeaderboard.loadLeaderboards(IDs: [boardID]).first else { return [] }
            let (_, entries, _) = try await board.loadEntries(for: .friendsOnly, timeScope: .allTime, range: NSRange(location: 1, length: 50))
            let me = GKLocalPlayer.local.gamePlayerID
            return entries
                .filter { $0.player.gamePlayerID != me }
                .map { LiveFriend(id: $0.player.gamePlayerID, displayName: $0.player.displayName, level: LevelCurve.level(forSeasonXP: $0.score), seasonXP: $0.score) }
                .sorted { $0.level > $1.level }
        } catch {
            Self.logger.info("Friends on \(boardID) unavailable: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Standing

    /// The local player's line on a classic board, plus how many players are on it.
    struct LocalStanding: Equatable {
        let boardID: String
        /// Nil when the player has no score on the board yet.
        let rank: Int?
        let score: Int?
        let totalPlayers: Int
    }

    /// One call: a one-entry read returns the local player's entry (rank) and the board's player
    /// count. Best-effort, nil on any error.
    func loadLocalStanding(boardID: String) async -> LocalStanding? {
        guard isActive else { return nil }
        do {
            guard let board = try await GKLeaderboard.loadLeaderboards(IDs: [boardID]).first else { return nil }
            let (local, _, total) = try await board.loadEntries(for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 1))
            let rank = local.map(\.rank).flatMap { $0 > 0 ? $0 : nil }
            return LocalStanding(boardID: boardID, rank: rank, score: local.map(\.score), totalPlayers: total)
        } catch {
            Self.logger.info("Standing on \(boardID) unavailable: \(error.localizedDescription)")
            return nil
        }
    }


    // MARK: - Presentation

    func presentLeaderboard(id: String) {
        let controller = GKGameCenterViewController(leaderboardID: id, playerScope: .global, timeScope: .allTime)
        controller.gameCenterDelegate = dashboardDelegate
        controller.overrideUserInterfaceStyle = .dark
        Self.topViewController()?.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: - Cache

    private static func loadCache() -> SubmissionCache {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(SubmissionCache.self, from: data) else { return SubmissionCache() }
        return cache
    }

    private func persistCache() {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }
}

private final class DashboardDelegate: NSObject, GKGameCenterControllerDelegate {
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
