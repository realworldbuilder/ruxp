import Foundation

// MARK: - Where the community lives

/// One Discord text channel. Snowflake ids are strings on the wire and in Swift.
struct DiscordChannelRef: Codable, Equatable {
    let guildID: String
    let channelID: String
    /// "#friday-night". Shown on the card; never used for routing.
    var label: String? = nil
    /// A permanent invite for players who are not in the server yet.
    var invite: URL? = nil

    /// Opens the Discord app straight into the channel when it is installed.
    var appURL: URL { URL(string: "discord://discord.com/channels/\(guildID)/\(channelID)")! }
    /// The same channel on the web; Discord's own Universal Link when the app is installed.
    var webURL: URL { URL(string: "https://discord.com/channels/\(guildID)/\(channelID)")! }
    var displayLabel: String { label ?? "Discord" }
}

/// Who is hosting. A gym, a creator, a brand: "GOLD'S GYM VENICE presents". The seam for
/// hosted events; nothing else about hosting is wired.
struct CommunityHost: Codable, Equatable {
    let name: String
    var url: URL? = nil
}

/// The community attached to one event: a Discord channel, optionally a host.
struct EventCommunity: Codable, Equatable {
    var discord: DiscordChannelRef? = nil
    var host: CommunityHost? = nil
}

// MARK: - Directory

/// Event → community mapping plus the relay the app posts moments to. The bundled copy is the
/// offline truth (empty: no card, no posts); a validated `docs/community.json` replaces it.
struct CommunityDirectory: Codable, Equatable {
    let version: Int
    /// Where `CommunityMoment`s are POSTed. Nil means moments stay on the phone.
    var relayURL: URL? = nil
    /// Origin for the links the app hands out (`AppLinks.origin`). Nil keeps ruxp.app.
    var linkOrigin: String? = nil
    /// The server-wide channel when an event has nothing more specific.
    var home: DiscordChannelRef? = nil
    /// By `LiveEventKind` raw value: "fridayNight", "sundayReset", "nightly", "season".
    var byKind: [String: EventCommunity] = [:]
    /// By occurrence id ("fridayNight-2026-10-30"): a hosted one-off beats its kind.
    var byEventID: [String: EventCommunity] = [:]

    func community(for event: LiveEvent) -> EventCommunity? {
        if let exact = byEventID[event.id] { return exact }
        if let kind = byKind[event.kind.rawValue] { return kind }
        if let home { return EventCommunity(discord: home) }
        return nil
    }

    var isEmpty: Bool { home == nil && byKind.isEmpty && byEventID.isEmpty }

    // MARK: Validation

    /// Why a directory must not be used. Empty means it is safe.
    func validationErrors() -> [String] {
        var errors: [String] = []
        if version < 1 { errors.append("version must be ≥ 1") }
        if byKind.count + byEventID.count > 64 { errors.append("more than 64 entries") }
        if let relayURL, relayURL.scheme != "https" { errors.append("relayURL must be https") }
        if let linkOrigin, !linkOrigin.hasPrefix("https://") || linkOrigin.hasSuffix("/") {
            errors.append("linkOrigin must be https with no trailing slash")
        }
        if let home { errors += Self.errors(in: home, at: "home") }
        for (kind, community) in byKind {
            if LiveEventKind(rawValue: kind) == nil { errors.append("byKind: unknown kind \(kind)") }
            errors += Self.errors(in: community, at: "byKind.\(kind)")
        }
        for (id, community) in byEventID {
            if !AppRoute.isEventID(id) { errors.append("byEventID: malformed id \(id)") }
            errors += Self.errors(in: community, at: "byEventID.\(id)")
        }
        return errors
    }

    private static func errors(in community: EventCommunity, at path: String) -> [String] {
        var errors: [String] = []
        if let discord = community.discord { errors += Self.errors(in: discord, at: path) }
        if let host = community.host, host.name.isEmpty || host.name.count > 40 {
            errors.append("\(path): host name must be 1…40 characters")
        }
        return errors
    }

    private static func errors(in ref: DiscordChannelRef, at path: String) -> [String] {
        var errors: [String] = []
        if !isSnowflake(ref.guildID) { errors.append("\(path): guildID is not a snowflake") }
        if !isSnowflake(ref.channelID) { errors.append("\(path): channelID is not a snowflake") }
        if let label = ref.label, label.isEmpty || label.count > 40 { errors.append("\(path): label must be 1…40 characters") }
        if let invite = ref.invite {
            let hosts: Set<String> = ["discord.gg", "discord.com", "www.discord.com"]
            if invite.scheme != "https" || !hosts.contains(invite.host?.lowercased() ?? "") {
                errors.append("\(path): invite must be an https discord.gg or discord.com link")
            }
        }
        return errors
    }

    static func isSnowflake(_ s: String) -> Bool {
        (15...22).contains(s.count) && s.allSatisfy(\.isNumber)
    }

    static func decode(_ data: Data) throws -> CommunityDirectory {
        try JSONDecoder().decode(CommunityDirectory.self, from: data)
    }

    init(version: Int, relayURL: URL? = nil, linkOrigin: String? = nil, home: DiscordChannelRef? = nil,
         byKind: [String: EventCommunity] = [:], byEventID: [String: EventCommunity] = [:]) {
        self.version = version
        self.relayURL = relayURL
        self.linkOrigin = linkOrigin
        self.home = home
        self.byKind = byKind
        self.byEventID = byEventID
    }

    private enum CodingKeys: String, CodingKey { case version, relayURL, linkOrigin, home, byKind, byEventID }

    /// Every key but `version` may be absent: a default value does not make a synthesized
    /// decoder tolerant of a missing key, so this is spelled out.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        relayURL = try c.decodeIfPresent(URL.self, forKey: .relayURL)
        linkOrigin = try c.decodeIfPresent(String.self, forKey: .linkOrigin)
        home = try c.decodeIfPresent(DiscordChannelRef.self, forKey: .home)
        byKind = try c.decodeIfPresent([String: EventCommunity].self, forKey: .byKind) ?? [:]
        byEventID = try c.decodeIfPresent([String: EventCommunity].self, forKey: .byEventID) ?? [:]
    }
}

// MARK: - Catalog

enum CommunityCatalog {
    /// What the app believes right now. The iOS `CommunityService` replaces it with a validated
    /// remote directory; the watch and previews keep the bundled one. Same pattern as
    /// `LiveOpsCatalog.current`.
    nonisolated(unsafe) static var current: CommunityDirectory = bundled

    /// Nothing until the server exists: no card, no posts. Mirrors docs/community.json v1
    /// minus the ids, which are pasted on the site once the Discord server is created.
    static let bundled = CommunityDirectory(version: 1)
}

extension LiveEventProviding {
    func community(for event: LiveEvent) -> EventCommunity? {
        CommunityCatalog.current.community(for: event)
    }
}
