import Foundation
import os

@Observable
@MainActor
final class WorkoutManager {
    private static let logger = Logger(subsystem: "com.whussey.momentary", category: "WorkoutManager")

    let workoutStore: WorkoutStore
    let connectivity: ConnectivityService
    let transcription: TranscriptionService
    let healthKit: HealthKitService

    var activeSession: WorkoutSession?
    var isProcessingMoment = false
    var lastError: String?

    private var processor: WorkoutProcessor?
    private var endingSessionID: UUID?

    init(
        workoutStore: WorkoutStore,
        connectivity: ConnectivityService,
        transcription: TranscriptionService,
        healthKit: HealthKitService,
        processor: WorkoutProcessor
    ) {
        self.workoutStore = workoutStore
        self.connectivity = connectivity
        self.transcription = transcription
        self.healthKit = healthKit
        self.processor = processor
        setupConnectivityCallbacks()
        workoutStore.migrateFromLegacyTranscriptions()
    }

    // MARK: - Workout Lifecycle

    func startWorkout() {
        let session = WorkoutSession()
        activeSession = session
        workoutStore.saveSession(session)

        let message = WorkoutMessage(command: .start, workoutID: session.id)
        connectivity.sendWorkoutMessage(message)
        connectivity.updateWorkoutContext(workoutID: session.id, isActive: true, startedAt: session.startedAt)

        Self.logger.info("Started workout \(session.id)")
    }

    func endWorkout() {
        guard var session = activeSession else { return }
        session.endedAt = Date()
        workoutStore.saveSession(session)
        endingSessionID = session.id
        activeSession = nil

        let message = WorkoutMessage(command: .stop, workoutID: session.id)
        connectivity.sendWorkoutMessage(message)
        connectivity.updateWorkoutContext(workoutID: nil, isActive: false, startedAt: nil)

        Self.logger.info("Ended workout \(session.id)")

        Task {
            try? await Task.sleep(for: .seconds(5))
            self.finalizeEnd(workoutID: session.id)
        }
    }

    private func handleRemoteStop(workoutID: UUID, healthWorkoutUUID: UUID? = nil) {
        guard activeSession?.id == workoutID else { return }
        guard var session = activeSession else { return }
        session.endedAt = Date()
        if let healthWorkoutUUID { session.healthWorkoutUUID = healthWorkoutUUID }
        workoutStore.saveSession(session)
        endingSessionID = session.id
        activeSession = nil
        connectivity.updateWorkoutContext(workoutID: nil, isActive: false, startedAt: nil)

        Task {
            try? await Task.sleep(for: .seconds(5))
            self.finalizeEnd(workoutID: session.id)
        }
    }

    private func finalizeEnd(workoutID: UUID) {
        guard endingSessionID == workoutID else { return }
        let finalSession = workoutStore.loadSession(id: workoutID)
        endingSessionID = nil
        if let finalSession {
            Task { await processor?.processWorkout(finalSession) }
        }
    }

    // MARK: - Moment Management

    func addMoment(audioURL: URL, source: MomentSource, momentID: UUID? = nil) async {
        let workoutID: UUID
        if let active = activeSession {
            workoutID = active.id
        } else if let ending = endingSessionID {
            workoutID = ending
        } else {
            return
        }
        await processAudioMoment(audioURL: audioURL, source: source, momentID: momentID, workoutID: workoutID)
    }

    private func processAudioMoment(audioURL: URL, source: MomentSource, momentID: UUID?, workoutID: UUID) async {
        isProcessingMoment = true
        defer { isProcessingMoment = false }

        let mID = momentID ?? UUID()
        _ = workoutStore.storeAudioFile(from: audioURL, momentID: mID, workoutID: workoutID)
        let result = await transcription.transcribe(audioURL: audioURL)

        var moment = Moment(id: mID, timestamp: Date(), transcript: "", source: source)

        switch result {
        case .success(let text):
            moment.transcript = text
        case .failure(let error):
            moment.transcript = "[Transcription failed]"
            moment.confidence = 0
            lastError = error.localizedDescription
        }

        guard var session = workoutStore.loadSession(id: workoutID) else { return }
        session.moments.append(moment)
        workoutStore.saveSession(session)
        if activeSession?.id == workoutID { activeSession = session }

        if source == .watch, case .success(let text) = result {
            connectivity.sendTranscriptionToWatch(text, momentID: mID, workoutID: workoutID)
        } else if source == .watch, case .failure = result {
            connectivity.sendErrorToWatch(lastError ?? "Transcription failed", workoutID: workoutID)
        }

        try? FileManager.default.removeItem(at: audioURL)
    }

    // MARK: - Connectivity Callbacks

    private func setupConnectivityCallbacks() {
        connectivity.onAudioReceived = { [weak self] url, momentID, _ in
            guard let self else { return }
            await self.addMoment(audioURL: url, source: .watch, momentID: momentID)
        }

        connectivity.onWorkoutCommand = { [weak self] message in
            guard let self else { return }
            switch message.command {
            case .start:
                if self.activeSession == nil {
                    let session = WorkoutSession(id: message.workoutID, startedAt: message.timestamp)
                    self.activeSession = session
                    self.workoutStore.saveSession(session)
                    self.connectivity.updateWorkoutContext(workoutID: message.workoutID, isActive: true, startedAt: message.timestamp)
                }
            case .stop:
                if self.activeSession?.id == message.workoutID {
                    self.handleRemoteStop(workoutID: message.workoutID, healthWorkoutUUID: message.healthWorkoutUUID)
                }
            case .momentRecorded, .momentTranscribed:
                break
            }
        }

        connectivity.onReceivedWorkoutContext = { [weak self] workoutID, isActive, startedAt in
            guard let self else { return }
            if isActive, let workoutID, self.activeSession == nil, self.endingSessionID == nil {
                let session = WorkoutSession(id: workoutID, startedAt: startedAt ?? Date())
                self.activeSession = session
                self.workoutStore.saveSession(session)
            } else if !isActive, let activeID = self.activeSession?.id, activeID == workoutID {
                self.handleRemoteStop(workoutID: activeID)
            }
        }
    }
}
