import Foundation
import GameKit
import Observation
import os

/// Phase 3 experiment: a small Game Center real-time room (2–8 players) for one Live Session.
/// Programmatic auto-match only, reactions only, foreground only. Everything GameKit-specific
/// for multiplayer lives in this file; views see `LiveRoomProviding`.
///
/// Failure is the default state of a young player base: most joins will wait and time out.
/// The service never retries on its own and never invents members.
@Observable
@MainActor
final class LiveRoomService: LiveRoomProviding {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "LiveRoomService")

    static let minPlayers = 2
    static let maxPlayers = 8
    static let searchTimeout: Duration = .seconds(90)
    static let retryBackoff: TimeInterval = 15
    static let protocolVersion: UInt8 = 1

    private(set) var state: LiveRoomState = .idle
    private(set) var members: [LiveRoomMember] = []
    private(set) var reactionCounts: [LiveReaction: Int] = [:]
    private(set) var recentReactions: [LiveRoomReactionEvent] = []
    private(set) var peakPeerCount = 0
    private(set) var eventID: String?

    private let gameCenter: GameCenterService
    private var match: GKMatch?
    private var bridge: MatchBridge?
    private var searchTask: Task<Void, Never>?
    private var lastFailureAt: Date?

    init(gameCenter: GameCenterService) {
        self.gameCenter = gameCenter
    }

    var isAvailable: Bool {
        gameCenter.isActive && !GKLocalPlayer.local.isMultiplayerGamingRestricted
    }

    private var unavailableReason: String {
        if !gameCenter.isActive { return gameCenter.presenceUnavailableMessage }
        return "Multiplayer is restricted for this Game Center account."
    }

    // MARK: - Lifecycle

    func join(event: LiveEvent) {
        guard isAvailable else {
            state = .unavailable(unavailableReason)
            return
        }
        if let lastFailureAt, Date().timeIntervalSince(lastFailureAt) < Self.retryBackoff {
            state = .failed("Give it a moment, then try again.")
            return
        }
        leave()
        eventID = event.id
        peakPeerCount = 0
        reactionCounts = [:]
        recentReactions = []
        state = .searching

        let request = GKMatchRequest()
        request.minPlayers = Self.minPlayers
        request.maxPlayers = Self.maxPlayers
        request.playerGroup = GameCenterCatalog.roomPlayerGroup(for: event, protocolVersion: Int(Self.protocolVersion))

        searchTask = Task { [weak self] in
            let deadline = Task {
                try? await Task.sleep(for: Self.searchTimeout)
                guard !Task.isCancelled else { return }
                GKMatchmaker.shared().cancel()
            }
            do {
                let match = try await GKMatchmaker.shared().findMatch(for: request)
                deadline.cancel()
                guard let self, !Task.isCancelled else {
                    match.disconnect()
                    return
                }
                self.attach(match)
            } catch {
                deadline.cancel()
                guard let self, !Task.isCancelled else { return }
                if (error as? GKError)?.code == .cancelled {
                    // Either the user backed out or our own deadline fired.
                    self.state = self.state == .searching ? .failed("Nobody else is looking right now.") : .idle
                } else {
                    self.state = .failed(error.localizedDescription)
                }
                self.lastFailureAt = Date()
                Self.logger.info("Room search ended: \(error.localizedDescription)")
            }
            self?.searchTask = nil
        }
    }

    func leave() {
        searchTask?.cancel()
        searchTask = nil
        if state == .searching { GKMatchmaker.shared().cancel() }
        if let match {
            match.delegate = nil
            match.disconnect()
            Self.logger.info("Left room for \(self.eventID ?? "-")")
        }
        match = nil
        bridge = nil
        members = []
        if case .failed = state {} else { state = .idle }
    }

    func send(_ reaction: LiveReaction) {
        note(reaction, from: gameCenter.alias ?? "You")
        guard let match, !match.players.isEmpty else { return }
        let payload = Data([Self.protocolVersion, reaction.rawValue])
        do {
            try match.sendData(toAllPlayers: payload, with: .unreliable)
        } catch {
            Self.logger.error("Reaction send failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Match

    private func attach(_ match: GKMatch) {
        self.match = match
        let bridge = MatchBridge(owner: self)
        self.bridge = bridge
        match.delegate = bridge
        refreshMembers()
        Self.logger.info("Matched: \(match.players.count) connected, \(match.expectedPlayerCount) expected")
    }

    private func refreshMembers() {
        guard let match else { return }
        members = match.players.map { LiveRoomMember(id: $0.gamePlayerID, displayName: $0.displayName) }
        peakPeerCount = max(peakPeerCount, members.count)
        state = members.isEmpty ? .connecting : .live
    }

    private func note(_ reaction: LiveReaction, from name: String) {
        reactionCounts[reaction, default: 0] += 1
        recentReactions.append(LiveRoomReactionEvent(reaction: reaction, senderName: name, receivedAt: Date()))
        if recentReactions.count > 12 { recentReactions.removeFirst(recentReactions.count - 12) }
    }

    // MARK: Delegate entry points (already on the main actor)

    fileprivate func playerStateChanged(in match: GKMatch) {
        guard match === self.match else { return }
        refreshMembers()
    }

    fileprivate func received(_ data: Data, from player: GKPlayer, in match: GKMatch) {
        guard match === self.match, data.count >= 2, data[0] == Self.protocolVersion,
              let reaction = LiveReaction(rawValue: data[1]) else { return }
        note(reaction, from: player.displayName)
    }

    fileprivate func failed(with error: Error, in match: GKMatch) {
        guard match === self.match else { return }
        Self.logger.error("Room failed: \(error.localizedDescription)")
        leave()
        state = .failed(error.localizedDescription)
        lastFailureAt = Date()
    }
}

/// GameKit calls back on arbitrary threads; hop every event onto the main actor.
private final class MatchBridge: NSObject, GKMatchDelegate {
    private weak var owner: LiveRoomService?

    init(owner: LiveRoomService) {
        self.owner = owner
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        Task { @MainActor [weak owner] in owner?.playerStateChanged(in: match) }
    }

    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        Task { @MainActor [weak owner] in owner?.received(data, from: player, in: match) }
    }

    func match(_ match: GKMatch, didFailWithError error: Error?) {
        let error = error ?? GKError(.unknown)
        Task { @MainActor [weak owner] in owner?.failed(with: error, in: match) }
    }

    func match(_ match: GKMatch, shouldReinviteDisconnectedPlayer player: GKPlayer) -> Bool {
        false
    }
}
