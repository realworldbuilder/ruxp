import Foundation

// MARK: - Routes

/// Every link the app understands. Parsed once at the root; views switch on it.
///
/// Custom scheme and Universal Link forms are equivalent:
///   ruxp://join/live                    https://ruxp.app/join/live
///   ruxp://join/fridayNight-2026-09-18  https://ruxp.app/join/fridayNight-2026-09-18
///   ruxp://event/<id>                   (alias of join)
/// Reserved, parsed so the site can claim the paths now; no view handles them yet:
///   /squad/<id>  /player/<id>  /challenge/<id>  /discord/callback (OAuth return)
enum AppRoute: Hashable {
    enum JoinTarget: Hashable {
        /// Whatever is featured right now: live, else next, else Home.
        case live
        /// One occurrence: `LiveEvent.id`, "fridayNight-2026-09-18".
        case event(id: String)
    }

    case join(JoinTarget)
    case squad(id: String)
    case player(id: String)
    case challenge(id: String)
    case discordCallback(URL)

    /// Hosts whose https links belong to the app.
    static let universalHosts: Set<String> = ["ruxp.app", "www.ruxp.app"]
    /// The GitHub Pages project site: no Universal Links there, but the bridge page mints these.
    static let pagesHost = "realworldbuilder.github.io"

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        var parts: [String]
        switch scheme {
        case "ruxp":
            // ruxp://join/live → host "join", path "/live".
            parts = [url.host?.lowercased()].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        case "https", "http":
            guard let host = url.host?.lowercased() else { return nil }
            parts = url.pathComponents.filter { $0 != "/" }
            if host == Self.pagesHost, parts.first == "ruxp" {
                parts.removeFirst()
            } else if !Self.universalHosts.contains(host) {
                return nil
            }
        default:
            return nil
        }
        let head = parts.first?.lowercased()
        let tail = parts.dropFirst().first
        switch (head, tail) {
        case ("join", nil), ("join", "live"), ("event", nil), ("event", "live"):
            self = .join(.live)
        case ("join", let id?), ("event", let id?):
            guard Self.isEventID(id) else { return nil }
            self = .join(.event(id: id))
        case ("squad", let id?):
            self = .squad(id: id)
        case ("player", let id?):
            self = .player(id: id)
        case ("challenge", let id?):
            self = .challenge(id: id)
        case ("discord", "callback"):
            self = .discordCallback(url)
        default:
            return nil
        }
    }

    /// "fridayNight-2026-09-18": a kind, a dash, a date. Anything else is dropped.
    static func isEventID(_ id: String) -> Bool {
        guard let dash = id.firstIndex(of: "-") else { return false }
        let kind = String(id[..<dash])
        let date = String(id[id.index(after: dash)...])
        guard LiveEventKind(rawValue: kind) != nil, date.count == 10 else { return false }
        return date.allSatisfy { $0.isNumber || $0 == "-" }
    }
}

// MARK: - Links the app hands out

/// The https links that go into Discord messages and share sheets. Universal Links once the
/// domain serves the association file; until then the same path lands on the site's bridge page,
/// which offers the `ruxp://` form. `origin` is replaced by the community directory when it
/// names one (the Pages site while ruxp.app is not live).
enum AppLinks {
    static let defaultOrigin = "https://ruxp.app"
    nonisolated(unsafe) static var origin = defaultOrigin

    static func join(eventID: String) -> URL {
        URL(string: "\(origin)/join/\(eventID)")!
    }

    static var joinLive: URL {
        URL(string: "\(origin)/join/live")!
    }
}
