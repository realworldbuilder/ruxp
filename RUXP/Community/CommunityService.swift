import Foundation
import Observation
import os

/// The event → Discord directory, and the player's sharing choice. The bundled directory is
/// the offline truth (empty); a copy of `docs/community.json` on the site replaces it once it
/// validates. Same shape as `LiveOpsService`: no network, a bad file, or a rejected file leaves
/// the current directory in place.
@Observable
@MainActor
final class CommunityService {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "CommunityService")

    enum Source: Equatable { case bundled, remote(version: Int), file(String), off }

    private(set) var directory: CommunityDirectory
    private(set) var source: Source
    private(set) var lastFetch: Date?
    private(set) var lastError: String?

    /// Served next to live.json. Pages redirects to the custom domain once it exists.
    static let remoteURL = URL(string: "https://realworldbuilder.github.io/ruxp/community.json")!
    static let minimumFetchInterval: TimeInterval = 60 * 60
    static let shareMomentsKey = "community.shareMoments"

    /// Off by default. Player moments (joins, PRs, level-ups) leave the phone only when this is on.
    var shareMoments: Bool {
        didSet { UserDefaults.standard.set(shareMoments, forKey: Self.shareMomentsKey) }
    }
    var sharing: CommunitySharing { CommunitySharing(shareMoments: shareMoments) }
    var relayURL: URL? { directory.relayURL }

    private let fileURL: URL
    private var disabled = false
    private var fetchTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = fileURL ?? docs.appendingPathComponent("community.json")
        shareMoments = UserDefaults.standard.bool(forKey: Self.shareMomentsKey)
        directory = CommunityCatalog.bundled
        source = .bundled

        #if DEBUG
        // -RUXPCommunity off | <path to a JSON file>: no directory at all, or a local one (no fetch).
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-RUXPCommunity"), idx + 1 < args.count {
            let value = args[idx + 1]
            if value == "off" {
                source = .off
                disabled = true
            } else if let data = FileManager.default.contents(atPath: value) {
                if let loaded = Self.validated(data) {
                    directory = loaded
                    source = .file(value)
                    disabled = true
                } else {
                    lastError = "Rejected \(value)"
                }
            } else {
                lastError = "Unreadable \(value)"
            }
            apply(directory)
            return
        }
        #endif

        if let data = FileManager.default.contents(atPath: self.fileURL.path),
           let cached = Self.validated(data), cached.version >= CommunityCatalog.bundled.version {
            directory = cached
            source = .remote(version: cached.version)
        }
        apply(directory)
    }

    private func apply(_ directory: CommunityDirectory) {
        CommunityCatalog.current = directory
        AppLinks.origin = directory.linkOrigin ?? AppLinks.defaultOrigin
    }

    // MARK: - Fetch

    /// Call on foreground. Throttled; safe to call as often as you like.
    func refresh(force: Bool = false) {
        guard !disabled, fetchTask == nil else { return }
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < Self.minimumFetchInterval { return }
        fetchTask = Task { [weak self] in
            await self?.fetch()
            self?.fetchTask = nil
        }
    }

    private func fetch() async {
        lastFetch = Date()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession(configuration: config).data(from: Self.remoteURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                lastError = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                return
            }
            guard let fetched = Self.validated(data) else {
                lastError = "Remote directory rejected"
                return
            }
            guard fetched.version >= CommunityCatalog.bundled.version else {
                lastError = "Remote version \(fetched.version) is older than bundled \(CommunityCatalog.bundled.version)"
                return
            }
            lastError = nil
            if fetched != directory {
                directory = fetched
                source = .remote(version: fetched.version)
                apply(fetched)
                Self.logger.info("Community directory v\(fetched.version): \(fetched.byKind.count + fetched.byEventID.count) entries")
            }
            try? data.write(to: fileURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
            Self.logger.info("Community fetch skipped: \(error.localizedDescription)")
        }
    }

    /// Decodes with the app's own decoder and applies the caps. Nil means "do not use".
    static func validated(_ data: Data) -> CommunityDirectory? {
        guard let directory = try? CommunityDirectory.decode(data) else { return nil }
        let errors = directory.validationErrors()
        if !errors.isEmpty {
            logger.error("Community directory rejected: \(errors.joined(separator: "; "))")
            return nil
        }
        return directory
    }

    var sourceLabel: String {
        switch source {
        case .bundled: return "bundled v\(directory.version)"
        case .remote(let version): return "remote v\(version)"
        case .file(let path): return "file \((path as NSString).lastPathComponent)"
        case .off: return "off"
        }
    }

    /// "Discord connected" is the wrong claim for a directory; this is what is honest.
    var statusLine: String {
        if directory.isEmpty { return "No channels configured" }
        let count = directory.byKind.count + directory.byEventID.count + (directory.home == nil ? 0 : 1)
        return "\(count) channel\(count == 1 ? "" : "s") · relay \(relayURL == nil ? "off" : "on")"
    }
}
