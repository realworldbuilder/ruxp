import SwiftUI

// MARK: - Models

/// The only things players can say to each other in a Training Room. No text.
enum LiveReaction: UInt8, CaseIterable, Identifiable {
    case fire = 1
    case salute = 2
    case skull = 3
    case w = 4

    var id: UInt8 { rawValue }

    var glyph: String {
        switch self {
        case .fire: return "🔥"
        case .salute: return "🫡"
        case .skull: return "💀"
        case .w: return "W"
        }
    }
}

/// A real Game Center player connected to the room. Never fabricated.
struct LiveRoomMember: Identifiable, Equatable {
    /// `GKPlayer.gamePlayerID` (session-scoped for non-friends; do not persist).
    let id: String
    let displayName: String
}

enum LiveRoomState: Equatable {
    case idle
    case unavailable(String)
    case searching
    case connecting
    case live
    case failed(String)

    var isBusy: Bool { self == .searching || self == .connecting }
    var isLive: Bool { self == .live }
}

/// One incoming reaction, for the ticker.
struct LiveRoomReactionEvent: Identifiable, Equatable {
    let id = UUID()
    let reaction: LiveReaction
    let senderName: String
    let receivedAt: Date
}

// MARK: - Provider

/// Small real-time room for players in the same Live Session. The phone implements this with
/// GameKit (`LiveRoomService`); views only see this protocol so Phase 3 cannot leak GameKit.
@MainActor
protocol LiveRoomProviding: AnyObject {
    var state: LiveRoomState { get }
    /// Remote players currently connected (the local player is not included).
    var members: [LiveRoomMember] { get }
    var reactionCounts: [LiveReaction: Int] { get }
    var recentReactions: [LiveRoomReactionEvent] { get }
    /// Most remote players connected at once during this room.
    var peakPeerCount: Int { get }
    /// The event this room was opened for.
    var eventID: String? { get }
    /// True when Game Center is signed in and multiplayer is allowed for this account.
    var isAvailable: Bool { get }

    func join(event: LiveEvent)
    func leave()
    func send(_ reaction: LiveReaction)
}

// MARK: - Environment

private struct LiveRoomKey: EnvironmentKey {
    static let defaultValue: (any LiveRoomProviding)? = nil
}

extension EnvironmentValues {
    var liveRoom: (any LiveRoomProviding)? {
        get { self[LiveRoomKey.self] }
        set { self[LiveRoomKey.self] = newValue }
    }
}
