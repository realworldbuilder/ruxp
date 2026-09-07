import Foundation
import Observation
import os

/// Rules that can change without a build. The bundled calendar is the offline truth; a copy of
/// `docs/live.json` on the site replaces it once it validates. Everything here is best-effort:
/// no network, a bad file, or a rejected file leaves the current calendar in place.
@Observable
@MainActor
final class LiveOpsService {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "LiveOpsService")

    enum Source: Equatable { case bundled, remote(version: Int), file(String), off }

    private(set) var calendar: LiveOpsCalendar
    private(set) var source: Source
    private(set) var lastFetch: Date?
    private(set) var lastError: String?

    static let remoteURL = URL(string: "https://realworldbuilder.github.io/ruxp/live.json")!
    /// At most one fetch per hour; a rule change reaches players on their next foreground after that.
    static let minimumFetchInterval: TimeInterval = 60 * 60

    private let fileURL: URL
    /// A debug override is in force: never fetch.
    private var disabled = false
    private var fetchTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = fileURL ?? docs.appendingPathComponent("live_ops.json")
        calendar = LiveOpsCatalog.bundled
        source = .bundled

        #if DEBUG
        // -RUXPLiveOps off | <path to a JSON file>: no rules at all, or a local calendar (no fetch).
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-RUXPLiveOps"), idx + 1 < args.count {
            let value = args[idx + 1]
            if value == "off" {
                calendar = LiveOpsCalendar(version: LiveOpsCatalog.bundled.version, modifiers: [])
                source = .off
                disabled = true
            } else if let data = FileManager.default.contents(atPath: value) {
                if let loaded = Self.validated(data) {
                    calendar = loaded
                    source = .file(value)
                    disabled = true
                } else {
                    lastError = "Rejected \(value)"
                }
            }
            LiveOpsCatalog.current = calendar
            return
        }
        #endif


        if let data = FileManager.default.contents(atPath: self.fileURL.path),
           let cached = Self.validated(data), cached.version >= LiveOpsCatalog.bundled.version {
            calendar = cached
            source = .remote(version: cached.version)
        }
        LiveOpsCatalog.current = calendar
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
                lastError = "Remote calendar rejected"
                return
            }
            guard fetched.version >= LiveOpsCatalog.bundled.version else {
                lastError = "Remote version \(fetched.version) is older than bundled \(LiveOpsCatalog.bundled.version)"
                return
            }
            lastError = nil
            if fetched != calendar {
                calendar = fetched
                source = .remote(version: fetched.version)
                LiveOpsCatalog.current = fetched
                Self.logger.info("Live ops calendar v\(fetched.version): \(fetched.modifiers.count) rules")
            }
            try? data.write(to: fileURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
            Self.logger.info("Live ops fetch skipped: \(error.localizedDescription)")
        }
    }

    /// Decodes with the app's own decoder and applies the caps. Nil means "do not use".
    static func validated(_ data: Data) -> LiveOpsCalendar? {
        guard let calendar = try? LiveOpsCalendar.decode(data) else { return nil }
        let errors = calendar.validationErrors()
        if !errors.isEmpty {
            logger.error("Live ops calendar rejected: \(errors.joined(separator: "; "))")
            return nil
        }
        return calendar
    }

    // MARK: - Queries

    func activeModifiers(at date: Date = ScheduledEventService.now()) -> [LiveModifier] {
        calendar.activeModifiers(at: date)
    }

    var sourceLabel: String {
        switch source {
        case .bundled: return "bundled v\(calendar.version)"
        case .remote(let version): return "remote v\(version)"
        case .file(let path): return "file \((path as NSString).lastPathComponent)"
        case .off: return "off"
        }
    }

    #if DEBUG
    /// Developer: does the bundled catalog survive its own wire format? (Catches a JSON shape drift.)
    static func bundledRoundTripReport() -> String {
        do {
            let data = try JSONEncoder().encode(LiveOpsCatalog.bundled)
            let back = try LiveOpsCalendar.decode(data)
            let errors = back.validationErrors()
            if back != LiveOpsCatalog.bundled { return "Mismatch after round trip" }
            return errors.isEmpty ? "OK · \(back.modifiers.count) rules" : errors.joined(separator: "; ")
        } catch {
            return "Failed: \(error.localizedDescription)"
        }
    }
    #endif
}
