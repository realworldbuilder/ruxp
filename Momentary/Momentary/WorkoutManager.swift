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

    private static let activeWorkoutKey = "com.m2m.activeWorkoutID"

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
        restoreActiveWorkout()
    }

    // MARK: - Workout Restoration

    /// Restores an active workout from disk if the app was killed mid-workout
    private func restoreActiveWorkout() {
        guard let idString = UserDefaults.standard.string(forKey: Self.activeWorkoutKey),
              let id = UUID(uuidString: idString),
              let session = workoutStore.loadSession(id: id),
              session.endedAt == nil else {
            // Clean up stale key
            UserDefaults.standard.removeObject(forKey: Self.activeWorkoutKey)
            return
        }

        activeSession = session
        Self.logger.info("Restored active workout \(id) with \(session.moments.count) moments")
    }

    /// Call this when app returns to foreground to ensure session is fresh from disk
    func refreshActiveSession() {
        guard let id = activeSession?.id,
              let session = workoutStore.loadSession(id: id) else { return }
        if session.endedAt != nil {
            // Workout was ended (maybe by watch) while we were in background
            activeSession = nil
            UserDefaults.standard.removeObject(forKey: Self.activeWorkoutKey)
        } else {
            activeSession = session
        }
    }

    private func persistActiveWorkoutID(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: Self.activeWorkoutKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeWorkoutKey)
        }
    }

    // MARK: - Workout Lifecycle

    func startWorkout() {
        // Reset stale state from previous workout
        isProcessingMoment = false
        lastError = nil

        let session = WorkoutSession()
        activeSession = session
        workoutStore.saveSession(session)
        persistActiveWorkoutID(session.id)

        let message = WorkoutMessage(command: .start, workoutID: session.id)
        connectivity.sendWorkoutMessage(message)
        connectivity.updateWorkoutContext(workoutID: session.id, isActive: true, startedAt: session.startedAt)

        Self.logger.info("Started workout \(session.id)")
    }

    func discardWorkout() {
        guard let session = activeSession else { return }
        activeSession = nil
        isProcessingMoment = false
        persistActiveWorkoutID(nil)

        // Delete the session file entirely
        workoutStore.deleteSession(id: session.id)

        let message = WorkoutMessage(command: .stop, workoutID: session.id)
        connectivity.sendWorkoutMessage(message)
        connectivity.updateWorkoutContext(workoutID: nil, isActive: false, startedAt: nil)

        Self.logger.info("Discarded workout \(session.id)")
    }

    func endWorkout() {
        guard var session = activeSession else { return }
        session.endedAt = Date()
        workoutStore.saveSession(session)
        endingSessionID = session.id
        activeSession = nil
        isProcessingMoment = false
        persistActiveWorkoutID(nil)

        let message = WorkoutMessage(command: .stop, workoutID: session.id)
        connectivity.sendWorkoutMessage(message)
        connectivity.updateWorkoutContext(workoutID: nil, isActive: false, startedAt: nil)

        Self.logger.info("Ended workout \(session.id)")

        // Fetch HealthKit data after a short delay (let Apple Health sync)
        let sessionID = session.id
        let startDate = session.startedAt
        let endDate = session.endedAt ?? Date()
        Task {
            try? await Task.sleep(for: .seconds(5))
            await self.attachHealthData(workoutID: sessionID, start: startDate, end: endDate)
            self.finalizeEnd(workoutID: sessionID)
        }
    }

    private func attachHealthData(workoutID: UUID, start: Date, end: Date) async {
        let (avgHR, calories) = await healthKit.fetchWorkoutHealthData(start: start, end: end)
        guard avgHR != nil || calories != nil else { return }

        guard var session = workoutStore.loadSession(id: workoutID) else { return }
        session.averageHeartRate = avgHR
        session.activeCalories = calories
        workoutStore.saveSession(session)
        Self.logger.info("Attached health data: HR=\(avgHR ?? 0), Cal=\(calories ?? 0)")
    }

    private func handleRemoteStop(workoutID: UUID, healthWorkoutUUID: UUID? = nil, avgHeartRate: Double? = nil, activeCalories: Double? = nil) {
        guard activeSession?.id == workoutID else { return }
        guard var session = activeSession else { return }
        session.endedAt = Date()
        if let healthWorkoutUUID { session.healthWorkoutUUID = healthWorkoutUUID }
        // Use health data sent directly from watch (immediate, no sync delay)
        if let avgHeartRate, avgHeartRate > 0 { session.averageHeartRate = avgHeartRate }
        if let activeCalories, activeCalories > 0 { session.activeCalories = activeCalories }
        workoutStore.saveSession(session)
        endingSessionID = session.id
        activeSession = nil
        persistActiveWorkoutID(nil)
        connectivity.updateWorkoutContext(workoutID: nil, isActive: false, startedAt: nil)

        // Still try HealthKit query as fallback (in case watch didn't send data)
        let start = session.startedAt
        let end = session.endedAt ?? Date()
        let needsHealth = session.averageHeartRate == nil && session.activeCalories == nil
        Task {
            if needsHealth {
                try? await Task.sleep(for: .seconds(5))
                await self.attachHealthData(workoutID: session.id, start: start, end: end)
            }
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
        // Only show processing indicator if this workout is still active
        let isActiveWorkout = activeSession?.id == workoutID || endingSessionID == workoutID
        if isActiveWorkout { isProcessingMoment = true }
        defer {
            // Only clear if we're the ones who set it
            if isActiveWorkout { isProcessingMoment = false }
        }

        let mID = momentID ?? UUID()
        let storedURL = workoutStore.storeAudioFile(from: audioURL, momentID: mID, workoutID: workoutID)
        // Clean up temp recording file (audio is now safely in persistent storage)
        if source == .phone { try? FileManager.default.removeItem(at: audioURL) }
        // Transcribe from the persistent copy if available, otherwise original
        let transcribeURL = storedURL ?? audioURL
        let result = await transcription.transcribe(audioURL: transcribeURL)

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

        // Sync moment count to watch
        connectivity.updateMomentCount(session.moments.count, workoutID: workoutID)

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
                    self.handleRemoteStop(workoutID: message.workoutID, healthWorkoutUUID: message.healthWorkoutUUID, avgHeartRate: message.avgHeartRate, activeCalories: message.activeCalories)
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
