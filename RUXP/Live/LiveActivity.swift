import SwiftUI

// MARK: - Models

/// One line on the floor: something that just happened around you.
struct LiveActivityEvent: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Someone logged a set.
        case set
        /// Someone joined the session or started a workout.
        case joined
        /// Someone finished.
        case finished
        /// The room crossed a volume milestone.
        case milestone
        /// A count of people doing something right now.
        case training
        /// A player's volume tonight.
        case moved
        /// A Training Room reaction.
        case reaction
        /// Your own line.
        case you
    }

    let id: UUID
    let at: Date
    let kind: Kind
    let text: String

    init(id: UUID = UUID(), at: Date, kind: Kind, text: String) {
        self.id = id
        self.at = at
        self.kind = kind
        self.text = text
    }
}

// MARK: - Provider

/// The floor: a passive stream of what is happening in the session. Never a chat. Shipping
/// builds compose it from real signals only (`ObservedLiveActivity`); the DEBUG simulator is
/// the other implementation. Views only ever see this protocol.
@MainActor
protocol LiveActivityProviding: AnyObject {
    /// Bounded, oldest first; the newest line is `events.last`.
    var events: [LiveActivityEvent] { get }
    func start()
    func stop()
}

// MARK: - Environment

private struct LiveActivityKey: EnvironmentKey {
    static let defaultValue: (any LiveActivityProviding)? = nil
}

extension EnvironmentValues {
    var liveActivity: (any LiveActivityProviding)? {
        get { self[LiveActivityKey.self] }
        set { self[LiveActivityKey.self] = newValue }
    }
}
