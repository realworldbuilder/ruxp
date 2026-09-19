import SwiftUI

/// One slot. `.onOpenURL` fills it at the root; the view that owns the destination consumes
/// it. Holding the value until the right view exists makes cold launch and warm launch the
/// same case, and clearing it after consumption lets the same link be tapped twice.
@Observable
@MainActor
final class AppRouter {
    var pendingRoute: AppRoute?

    init() {
        #if DEBUG
        // -RUXPOpenURL ruxp://join/live: feed the router at launch (headless screenshots).
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-RUXPOpenURL"), idx + 1 < args.count,
           let url = URL(string: args[idx + 1]) {
            pendingRoute = AppRoute(url: url)
        }
        #endif
    }

    /// False for URLs the app does not understand; they are dropped, never shown.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let route = AppRoute(url: url) else { return false }
        pendingRoute = route
        return true
    }

    func consume(_ route: AppRoute) {
        if pendingRoute == route { pendingRoute = nil }
    }

    /// Which tab hosts the route. Every route lands on Home today.
    func tab(for route: AppRoute) -> AppTab { .home }
}
