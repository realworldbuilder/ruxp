import SwiftUI

/// Environment access to the event provider so views can ask "what is happening right now?".
private struct LiveEventsKey: EnvironmentKey {
    static let defaultValue: LiveEventProviding = ScheduledEventService()
}

/// Environment access to live presence. Optional so previews and the watch can run without one.
private struct LivePresenceKey: EnvironmentKey {
    static let defaultValue: (any LivePresenceProviding)? = nil
}

extension EnvironmentValues {
    var liveEvents: LiveEventProviding {
        get { self[LiveEventsKey.self] }
        set { self[LiveEventsKey.self] = newValue }
    }

    var livePresence: (any LivePresenceProviding)? {
        get { self[LivePresenceKey.self] }
        set { self[LivePresenceKey.self] = newValue }
    }
}
