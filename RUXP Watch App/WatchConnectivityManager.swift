import Foundation
import os
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    private static let logger = Logger(subsystem: "com.whussey.ruxp.watchkitapp", category: "WatchConnectivityManager")

    @Published var lastTranscription: String?
    @Published var lastError: String?
    @Published var isSending = false

    var onWorkoutCommand: ((WorkoutMessage) async -> Void)?
    var onReceivedWorkoutContext: ((_ workoutID: UUID?, _ isActive: Bool, _ startedAt: Date?) -> Void)?
    var onMomentCountUpdated: ((_ count: Int) -> Void)?
    var onPlanReceived: ((PlanWirePayload?) -> Void)?
    var onProgressionReceived: ((ProgressionContext) -> Void)?
    var onPresenceReceived: ((LiveSnapshot) -> Void)?
    var onGameCenterSyncReceived: ((Bool) -> Void)?

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

    /// `healthSession` tells the phone this watch owns the Health workout, so the phone must
    /// not write its own.
    func updateWorkoutContext(workoutID: UUID?, isActive: Bool, startedAt: Date?, healthSession: Bool = false) {
        var context: [String: Any] = [ConnectivityConstants.contextIsActiveKey: isActive]
        if let workoutID { context[ConnectivityConstants.contextWorkoutIDKey] = workoutID.uuidString }
        if let startedAt { context[ConnectivityConstants.contextStartedAtKey] = startedAt.timeIntervalSince1970 }
        context[ConnectivityConstants.contextWatchHealthSessionKey] = healthSession
        try? session.updateApplicationContext(context)
    }

    /// Applies a phone context: workout state first, then the moment count, so a cold join
    /// can reset its counters before the phone's true total lands on top.
    private func applyWorkoutContext(_ context: [String: Any]) {
        let (workoutID, isActive, startedAt) = parseWorkoutContext(context)
        onReceivedWorkoutContext?(workoutID, isActive, startedAt)
        if let count = context[ConnectivityConstants.contextMomentCountKey] as? Int {
            onMomentCountUpdated?(count)
        }
    }

    private func parseWorkoutContext(_ context: [String: Any]) -> (UUID?, Bool, Date?) {
        let isActive = context[ConnectivityConstants.contextIsActiveKey] as? Bool ?? false
        let workoutID = (context[ConnectivityConstants.contextWorkoutIDKey] as? String).flatMap(UUID.init)
        let startedAt = (context[ConnectivityConstants.contextStartedAtKey] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }

        // Level / season XP snapshot (phone pushes it with every context update)
        if let progression = ProgressionContext.from(context) {
            onProgressionReceived?(progression)
        }

        // Live counts mirrored from the phone, and whether the watch may ping presence itself
        if let presence = LiveSnapshot.from(context) {
            onPresenceReceived?(presence)
        }
        if let sync = context[ConnectivityConstants.contextGameCenterSyncKey] as? Bool {
            onGameCenterSyncReceived?(sync)
        }

        // Sync planned workout if present (absent = no plan for this workout)
        if let planData = context[ConnectivityConstants.contextPlanDataKey] as? Data {
            onPlanReceived?(try? JSONDecoder().decode(PlanWirePayload.self, from: planData))
        } else if !isActive {
            onPlanReceived?(nil)
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
            self.applyWorkoutContext(ctx)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyWorkoutContext(applicationContext)
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
