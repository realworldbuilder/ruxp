import Foundation
import os
import WatchConnectivity

@MainActor
final class ConnectivityService: NSObject, ObservableObject {
    private static let logger = Logger(subsystem: "com.whussey.momentary", category: "ConnectivityService")

    private let session: WCSession

    var onAudioReceived: ((URL, UUID?, UUID?) async -> Void)?
    var onWorkoutCommand: ((WorkoutMessage) async -> Void)?
    var onReceivedWorkoutContext: ((_ workoutID: UUID?, _ isActive: Bool, _ startedAt: Date?) -> Void)?

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

    func updateWorkoutContext(workoutID: UUID?, isActive: Bool, startedAt: Date?) {
        var context: [String: Any] = [ConnectivityConstants.contextIsActiveKey: isActive]
        if let workoutID { context[ConnectivityConstants.contextWorkoutIDKey] = workoutID.uuidString }
        if let startedAt { context[ConnectivityConstants.contextStartedAtKey] = startedAt.timeIntervalSince1970 }
        try? session.updateApplicationContext(context)
    }

    private func parseWorkoutContext(_ context: [String: Any]) -> (UUID?, Bool, Date?) {
        let isActive = context[ConnectivityConstants.contextIsActiveKey] as? Bool ?? false
        let workoutID = (context[ConnectivityConstants.contextWorkoutIDKey] as? String).flatMap(UUID.init)
        let startedAt = (context[ConnectivityConstants.contextStartedAtKey] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        return (workoutID, isActive, startedAt)
    }

    func updateMomentCount(_ count: Int, workoutID: UUID) {
        var context = session.applicationContext
        context[ConnectivityConstants.contextMomentCountKey] = count
        context[ConnectivityConstants.contextWorkoutIDKey] = workoutID.uuidString
        context[ConnectivityConstants.contextIsActiveKey] = true
        try? session.updateApplicationContext(context)
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
        guard !ctx.isEmpty else { return }
        Task { @MainActor in
            let (workoutID, isActive, startedAt) = self.parseWorkoutContext(ctx)
            self.onReceivedWorkoutContext?(workoutID, isActive, startedAt)
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
            let (workoutID, isActive, startedAt) = self.parseWorkoutContext(applicationContext)
            self.onReceivedWorkoutContext?(workoutID, isActive, startedAt)
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
