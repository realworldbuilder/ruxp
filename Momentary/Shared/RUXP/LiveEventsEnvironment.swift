import SwiftUI

/// Environment access to the event provider so views can ask "what is happening right now?".
private struct LiveEventsKey: EnvironmentKey {
    static let defaultValue: LiveEventProviding = ScheduledEventService()
}

extension EnvironmentValues {
    var liveEvents: LiveEventProviding {
        get { self[LiveEventsKey.self] }
        set { self[LiveEventsKey.self] = newValue }
    }
}
