import Foundation
import Observation
import os

/// RUXP Live: who joined which event, and whether they showed up. XP is never granted here;
/// `ProgressionService` pays the event bonus exactly once per occurrence, and this service
/// records that completion against the participation. Persisted to Documents/live_sessions.json.
@Observable
@MainActor
final class LiveSessionService {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "LiveSessionService")

    private(set) var participations: [LiveSessionParticipation] = []

    let events: LiveEventProviding
    /// Real participant counts. Isolated so a presence backend can replace Game Center later.
    private weak var presence: (any LivePresenceProviding)?
    /// Game Center identity at join time; nil when signed out.
    var playerIDProvider: () -> String? = { nil }
    /// Phase 3: how many players were in the room when a workout completes.
    var roomPeerCountProvider: () -> Int? = { nil }
    /// Fired on a first-time join so the player can be counted in the event's presence window.
    var onJoined: ((LiveEvent) -> Void)?

    private let fileURL: URL

    init(events: LiveEventProviding, presence: (any LivePresenceProviding)? = nil, fileURL: URL? = nil) {
        self.events = events
        self.presence = presence
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = fileURL ?? docs.appendingPathComponent("live_sessions.json")
        load()
    }

    // MARK: - Current event

    func currentSession(at date: Date = ScheduledEventService.now()) -> LiveEvent? {
        events.activeEvent(at: date)
    }

    func nextSession(at date: Date = ScheduledEventService.now()) -> LiveEvent? {
        events.nextEvent(at: date)
    }

    /// Real Game Center players in this occurrence. 0 when presence is unavailable; never inflated.
    func participantCount(for event: LiveEvent) -> Int {
        presence?.participantCount(for: event) ?? 0
    }

    // MARK: - Participation

    func participation(for event: LiveEvent) -> LiveSessionParticipation? {
        participations.first { $0.sessionID == event.id }
    }

    func isJoined(_ event: LiveEvent) -> Bool {
        participation(for: event) != nil
    }

    func hasCompleted(_ event: LiveEvent) -> Bool {
        participation(for: event)?.completed ?? false
    }

    /// Join an event. Idempotent: returns the existing record if already joined.
    @discardableResult
    func join(_ event: LiveEvent, now: Date = ScheduledEventService.now()) -> LiveSessionParticipation {
        if let existing = participation(for: event) { return existing }
        let record = LiveSessionParticipation(
            sessionID: event.id,
            title: event.title,
            gameCenterPlayerID: playerIDProvider(),
            joinedAt: now
        )
        participations.append(record)
        save()
        Self.logger.info("Joined \(event.id)")
        onJoined?(event)
        return record
    }

    /// Starting any workout during a live event counts as joining it (no gate).
    func noteWorkoutStarted(at date: Date = ScheduledEventService.now()) {
        guard let event = currentSession(at: date), !event.isSeasonWide else { return }
        join(event, now: date)
    }

    /// Called after `ProgressionService` rewards a workout. Every event bonus in the reward marks
    /// its participation completed (creating one if the player never tapped JOIN). No-op for
    /// participations that are already complete, so a second workout can never double-count.
    func recordCompletion(session: WorkoutSession, reward: WorkoutRewardSummary, events overlapping: [LiveEvent]) {
        let completedAt = session.endedAt ?? ScheduledEventService.now()
        var changed = false
        for award in reward.eventAwards {
            let event = overlapping.first { $0.id == award.eventID } ?? overlapping.first { $0.title == award.label }
            let sessionID = award.eventID ?? event?.id
            guard let sessionID else { continue }

            if let index = participations.firstIndex(where: { $0.sessionID == sessionID }) {
                guard !participations[index].completed else { continue }
                participations[index].completedAt = completedAt
                participations[index].associatedWorkoutID = session.id
                participations[index].xpEarned = award.amount
                participations[index].roomPeerCount = roomPeerCountProvider()
                if participations[index].gameCenterPlayerID == nil {
                    participations[index].gameCenterPlayerID = playerIDProvider()
                }
            } else {
                participations.append(LiveSessionParticipation(
                    sessionID: sessionID,
                    title: event?.title ?? award.label,
                    gameCenterPlayerID: playerIDProvider(),
                    joinedAt: session.startedAt,
                    completedAt: completedAt,
                    associatedWorkoutID: session.id,
                    xpEarned: award.amount,
                    roomPeerCount: roomPeerCountProvider()
                ))
            }
            changed = true
            Self.logger.info("Completed \(sessionID) with workout \(session.id): +\(award.amount) XP")
        }
        if changed { save() }
    }

    /// Game Center signed in after some participations were recorded: attach the identity.
    func attachPlayerID(_ playerID: String) {
        var changed = false
        for index in participations.indices where participations[index].gameCenterPlayerID == nil {
            participations[index].gameCenterPlayerID = playerID
            changed = true
        }
        if changed { save() }
    }

    // MARK: - History

    /// Completed sessions, newest first.
    var history: [LiveSessionParticipation] {
        participations
            .filter(\.completed)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var completedCount: Int { history.count }

    /// Upgraders and sample data: the progression ledger already knows which occurrences were
    /// paid. Create completed participations for any it has that we do not.
    func backfill(from progress: PlayerProgress, sessions: [WorkoutSession]) {
        var changed = false
        for (sessionID, paidAt) in progress.eventsJoined where !participations.contains(where: { $0.sessionID == sessionID }) {
            let kind = sessionID.split(separator: "-").first.flatMap { LiveEventKind(rawValue: String($0)) }
            let title: String
            let xp: Int
            switch kind {
            case .fridayNight: title = "FRIDAY NIGHT"; xp = 500
            case .sundayReset: title = "SUNDAY RESET"; xp = 500
            default: continue
            }
            let workout = sessions.first { session in
                guard let end = session.endedAt else { return false }
                return abs(end.timeIntervalSince(paidAt)) < 60
            }
            participations.append(LiveSessionParticipation(
                sessionID: sessionID,
                title: title,
                gameCenterPlayerID: playerIDProvider(),
                joinedAt: workout?.startedAt ?? paidAt,
                completedAt: paidAt,
                associatedWorkoutID: workout?.id,
                xpEarned: xp
            ))
            changed = true
        }
        if changed {
            save()
            Self.logger.info("Backfilled live history: \(self.participations.count) participation(s)")
        }
    }

    func resetAll() {
        participations = []
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(participations).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save live sessions: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            participations = try decoder.decode([LiveSessionParticipation].self, from: Data(contentsOf: fileURL))
        } catch {
            Self.logger.error("Failed to load live sessions: \(error)")
        }
    }
}
