import Foundation
import os
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    private static let logger = Logger(subsystem: "com.whussey.momentary.watchkitapp", category: "WatchConnectivityManager")

    @Published var lastTranscription: String?
    @Published var lastError: String?
    @Published var isSending = false

    var onWorkoutCommand: ((WorkoutMessage) async -> Void)?
    var onReceivedWorkoutContext: ((_ workoutID: UUID?, _ isActive: Bool, _ startedAt: Date?) -> Void)?
    var onMomentCountUpdated: ((_ count: Int) -> Void)?

    private let session: WCSession
    private var sendingTimeout: DispatchWorkItem?

    override init() {
        self.session = WCSession.default
        super.init()
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }

    var isPhoneReachable: Bool {
        session.isReachable
    }

    func transferMomentAudio(at url: URL, momentID: UUID, workoutID: UUID) {
        guard session.activationState == .activated else {
            lastError = "Watch not connected to iPhone"
            return
        }
        isSending = true
        lastError = nil

        let metadata: [String: Any] = [
            ConnectivityConstants.fileTypeKey: ConnectivityConstants.fileTypeMomentAudio,
            ConnectivityConstants.metadataMomentIDKey: momentID.uuidString,
            ConnectivityConstants.metadataWorkoutIDKey: workoutID.uuidString
        ]
        session.transferFile(url, metadata: metadata)
        startTimeout()
    }

    func sendWorkoutCommand(_ message: WorkoutMessage) {
        let payload = message.toDictionary()
        let useReply = message.command == .start || message.command == .stop
        if session.isReachable {
            if useReply {
                session.sendMessage(payload, replyHandler: { reply in
                    Self.logger.debug("Received ack for \(message.command.rawValue)")
                }, errorHandler: { [weak self] _ in
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

        // Sync moment count if present
        if let count = context[ConnectivityConstants.contextMomentCountKey] as? Int {
            onMomentCountUpdated?(count)
        }

        return (workoutID, isActive, startedAt)
    }

    private func startTimeout() {
        sendingTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.isSending else { return }
                self.lastError = "No response from iPhone"
                self.isSending = false
            }
        }
        sendingTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }

    private func cancelTimeout() {
        sendingTimeout?.cancel()
        sendingTimeout = nil
    }

    private func handleIncoming(_ dict: [String: Any]) {
        cancelTimeout()

        if let workoutMessage = WorkoutMessage.from(dictionary: dict) {
            if workoutMessage.command == .momentTranscribed {
                if let transcript = workoutMessage.transcript {
                    lastTranscription = transcript
                    isSending = false
                } else if let error = workoutMessage.error {
                    lastError = error
                    isSending = false
                }
            }
            Task {
                await onWorkoutCommand?(workoutMessage)
            }
            return
        }

        // Legacy support
        if let transcription = dict[ConnectivityConstants.transcriptionKey] as? String {
            lastTranscription = transcription
            isSending = false
        } else if let error = dict[ConnectivityConstants.errorKey] as? String {
            lastError = error
            isSending = false
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in
                self.lastError = "Activation failed: \(error.localizedDescription)"
            }
            return
        }
        guard activationState == .activated else { return }
        let ctx = session.receivedApplicationContext
        guard !ctx.isEmpty else { return }
        Task { @MainActor in
            let (workoutID, isActive, startedAt) = self.parseWorkoutContext(ctx)
            self.onReceivedWorkoutContext?(workoutID, isActive, startedAt)
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
            self.handleIncoming(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler(["ack": true])
        Task { @MainActor in
            self.handleIncoming(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.handleIncoming(userInfo)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in
                self.cancelTimeout()
                self.lastError = "Transfer failed: \(error.localizedDescription)"
                self.isSending = false
            }
        }
    }
}
