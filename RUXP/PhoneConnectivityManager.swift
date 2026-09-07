import Foundation
import os
import WatchConnectivity

@MainActor
final class ConnectivityService: NSObject, ObservableObject {
    nonisolated private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "ConnectivityService")

    private let session: WCSession

    var onAudioReceived: ((URL, UUID?, UUID?) async -> Void)?
    var onWorkoutCommand: ((WorkoutMessage) async -> Void)?
    var onReceivedWorkoutContext: ((_ workoutID: UUID?, _ isActive: Bool, _ startedAt: Date?) -> Void)?
    /// Watch → phone: whether the watch holds a live HealthKit session for that workout.
    var onWatchHealthSession: ((_ workoutID: UUID, _ hasSession: Bool) -> Void)?

    /// Level / season XP snapshot merged into every application-context update so the watch
    /// can show "LVL 12" cold. Set by WorkoutManager whenever progression changes.
    var progressionContext: [String: Any] = [:]
    /// Live counts and the Game Center sync flag, merged the same way so the watch mirrors them.
    var presenceContext: [String: Any] = [:]
    /// The active workout (id, active flag, start, plan, moment count). Owned here, not re-read
    /// from WCSession's last-sent dictionary: that is empty before activation and after a
    /// relaunch, and any push built on it dropped `ctx_startedAt`, so the watch's clock reset.
    private var workoutContext: [String: Any] = [ConnectivityConstants.contextIsActiveKey: false]
    /// Pushes attempted before the session activated; replayed in `activationDidCompleteWith`.
    private var hasPendingContext = false
    private var lastPresencePush: Date = .distantPast
    private static let presencePushInterval: TimeInterval = 60

    override init() {
        self.session = WCSession.default
        super.init()
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }

    var isWatchReachable: Bool {
        session.isReachable
    }

    func sendWorkoutMessage(_ message: WorkoutMessage) {
        let payload = message.toDictionary()
        let useReply = message.command == .start || message.command == .stop
        if session.isReachable {
            if useReply {
                session.sendMessage(payload, replyHandler: { _ in }, errorHandler: { [weak self] _ in
                    self?.session.transferUserInfo(payload)
                })
            } else {
                session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                    self?.session.transferUserInfo(payload)
                }
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    func updateWorkoutContext(workoutID: UUID?, isActive: Bool, startedAt: Date?, plan: PlannedWorkout? = nil) {
        var context: [String: Any] = [ConnectivityConstants.contextIsActiveKey: isActive]
        if let workoutID { context[ConnectivityConstants.contextWorkoutIDKey] = workoutID.uuidString }
        if let startedAt { context[ConnectivityConstants.contextStartedAtKey] = startedAt.timeIntervalSince1970 }
        if let plan, let planData = try? JSONEncoder().encode(PlanWirePayload(plan)) {
            context[ConnectivityConstants.contextPlanDataKey] = planData
        }
        workoutContext = context
        sendContext()
    }

    /// Every context push carries the full picture: workout state, progression, presence.
    private func sendContext() {
        var context = workoutContext
        progressionContext.forEach { context[$0.key] = $0.value }
        presenceContext.forEach { context[$0.key] = $0.value }
        do {
            try session.updateApplicationContext(context)
            hasPendingContext = false
        } catch {
            // Not activated yet (app init) or transiently unavailable; replayed on activation.
            hasPendingContext = true
            Self.logger.debug("Application context deferred: \(error.localizedDescription)")
        }
    }

    /// Phone → watch: XP earned for a finished workout (falls back to transferUserInfo when unreachable).
    func sendWorkoutReward(_ reward: WorkoutRewardSummary) {
        let message = WorkoutMessage(
            command: .workoutReward,
            workoutID: reward.workoutID,
            xpEarned: reward.totalXP,
            level: reward.levelAfter,
            levelUp: reward.didLevelUp,
            prCount: reward.prCount
        )
        sendWorkoutMessage(message)
    }

    /// Push the current progression snapshot without touching workout state.
    func pushProgressionContext() {
        sendContext()
    }

    /// Phone → watch: the latest live counts. Throttled; the next workout context carries them anyway.
    func pushPresence(_ snapshot: LiveSnapshot, force: Bool = false) {
        snapshot.toDictionary().forEach { presenceContext[$0.key] = $0.value }
        guard force || Date().timeIntervalSince(lastPresencePush) >= Self.presencePushInterval else { return }
        lastPresencePush = Date()
        sendContext()
    }

    /// Phone → watch: whether the watch may ping presence boards on its own.
    func pushGameCenterSync(_ enabled: Bool) {
        presenceContext[ConnectivityConstants.contextGameCenterSyncKey] = enabled
        sendContext()
    }

    private func parseWorkoutContext(_ context: [String: Any]) -> (UUID?, Bool, Date?) {
        let isActive = context[ConnectivityConstants.contextIsActiveKey] as? Bool ?? false
        let workoutID = (context[ConnectivityConstants.contextWorkoutIDKey] as? String).flatMap(UUID.init)
        let startedAt = (context[ConnectivityConstants.contextStartedAtKey] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        return (workoutID, isActive, startedAt)
    }

    private func applyReceivedContext(_ context: [String: Any]) {
        let (workoutID, isActive, startedAt) = parseWorkoutContext(context)
        onReceivedWorkoutContext?(workoutID, isActive, startedAt)
        if let workoutID, let hasSession = context[ConnectivityConstants.contextWatchHealthSessionKey] as? Bool {
            onWatchHealthSession?(workoutID, hasSession)
        }
    }

    /// Moment count for the active workout. A transcript that lands after the workout ended
    /// must not resurrect it on the watch, so the count only rides on a matching active context.
    func updateMomentCount(_ count: Int, workoutID: UUID) {
        guard workoutContext[ConnectivityConstants.contextIsActiveKey] as? Bool == true,
              workoutContext[ConnectivityConstants.contextWorkoutIDKey] as? String == workoutID.uuidString
        else { return }
        workoutContext[ConnectivityConstants.contextMomentCountKey] = count
        sendContext()
    }

    func sendTranscriptionToWatch(_ transcript: String, momentID: UUID, workoutID: UUID) {
        let message = WorkoutMessage(command: .momentTranscribed, workoutID: workoutID, momentID: momentID, transcript: transcript)
        sendWorkoutMessage(message)
    }

    func sendErrorToWatch(_ error: String, workoutID: UUID) {
        let message = WorkoutMessage(command: .momentTranscribed, workoutID: workoutID, error: error)
        sendWorkoutMessage(message)
    }
}

extension ConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        let ctx = session.receivedApplicationContext
        Task { @MainActor in
            if self.hasPendingContext { self.sendContext() }
            guard !ctx.isEmpty else { return }
            self.applyReceivedContext(ctx)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")
        let metadata = file.metadata
        let momentID = (metadata?[ConnectivityConstants.metadataMomentIDKey] as? String).flatMap(UUID.init)
        let workoutID = (metadata?[ConnectivityConstants.metadataWorkoutIDKey] as? String).flatMap(UUID.init)

        do {
            try FileManager.default.copyItem(at: file.fileURL, to: destURL)
            Task { @MainActor in
                await self.onAudioReceived?(destURL, momentID, workoutID)
            }
        } catch {
            Self.logger.error("Failed to copy received audio file: \(error)")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyReceivedContext(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let workoutMessage = WorkoutMessage.from(dictionary: message) {
                await self.onWorkoutCommand?(workoutMessage)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler(["ack": true])
        Task { @MainActor in
            if let workoutMessage = WorkoutMessage.from(dictionary: message) {
                await self.onWorkoutCommand?(workoutMessage)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            if let workoutMessage = WorkoutMessage.from(dictionary: userInfo) {
                await self.onWorkoutCommand?(workoutMessage)
            }
        }
    }
}
