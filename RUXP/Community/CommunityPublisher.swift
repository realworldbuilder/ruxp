import Foundation
import os

/// Where moments go. The phone never holds a Discord token or webhook: it posts a moment to
/// the relay (`Scripts/discord-relay`), which formats the embed and talks to Discord.
@MainActor
protocol CommunityPublishing: AnyObject {
    func publish(_ moment: CommunityMoment)
}

/// POSTs one JSON moment per call. Fire and forget: the reward screen never waits on Discord.
@Observable
@MainActor
final class RelayCommunityPublisher: CommunityPublishing {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "CommunityRelay")

    var urlProvider: () -> URL?
    private(set) var lastResult: String?
    private(set) var sentCount = 0

    init(urlProvider: @escaping () -> URL?) {
        self.urlProvider = urlProvider
    }

    func publish(_ moment: CommunityMoment) {
        guard moment.audience.leavesTheDevice else { return }
        guard let url = urlProvider() else {
            lastResult = "No relay configured · kept \(moment.id)"
            Self.logger.info("No relay; moment kept on device: \(moment.id)")
            return
        }
        Task { await post(moment, to: url) }
    }

    private func post(_ moment: CommunityMoment, to url: URL) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var request = URLRequest(url: url.appendingPathComponent("moment"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(moment)
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            let (_, response) = try await URLSession(configuration: config).data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastResult = "HTTP \(status) · \(moment.id)"
            if (200..<300).contains(status) { sentCount += 1 }
            Self.logger.info("Relay \(status) for \(moment.id)")
        } catch {
            lastResult = "\(error.localizedDescription) · \(moment.id)"
            Self.logger.info("Relay post failed: \(error.localizedDescription)")
        }
    }
}

#if DEBUG
/// Logs only. For previews and `-RUXPCommunity off`.
@MainActor
final class LoggingCommunityPublisher: CommunityPublishing {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "CommunityRelay")
    private(set) var published: [CommunityMoment] = []

    func publish(_ moment: CommunityMoment) {
        published.append(moment)
        Self.logger.info("Moment (logged only): \(moment.id)")
    }
}
#endif
