import Foundation
import os

@Observable
@MainActor
final class WorkoutManager {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "WorkoutManager")

    let workoutStore: WorkoutStore
    let connectivity: ConnectivityService
    let transcription: TranscriptionService
    let healthKit: HealthKitService
    let plannedWorkoutStore: PlannedWorkoutStore
    let progression: ProgressionService
    let events: LiveEventProviding

    var activeSession: WorkoutSession?
    var isProcessingMoment = false
    var lastError: String?

    private var processor: WorkoutProcessor?
    /// Presence pings ("lifting now", "trained today"). Set after init; nil in previews.
    var gameCenter: GameCenterService? {
        didSet { if activeSession != nil { startPresenceHeartbeat() } }
    }
    /// RUXP Live participation. Set after init; nil in previews.
    var liveSessions: LiveSessionService?
    /// Fired once a workout has been rewarded and cleared (used to close the Training Room).
    var onWorkoutEnded: (() -> Void)?
    private var heartbeatTask: Task<Void, Never>?
    private static let heartbeatInterval: Duration = .seconds(5 * 60)
    /// The workout ID currently being finalized (AI processing). Publicly readable so the UI can present a completion sheet.
    var completedWorkoutID: UUID?
    private var endingSessionID: UUID?

    private static let activeWorkoutKey = "com.whussey.ruxp.activeWorkoutID"

    init(
        workoutStore: WorkoutStore,
        connectivity: ConnectivityService,
        transcription: TranscriptionService,
        healthKit: HealthKitService,
        processor: WorkoutProcessor,
        plannedWorkoutStore: PlannedWorkoutStore,
        progression: ProgressionService,
        events: LiveEventProviding
    ) {
        self.workoutStore = workoutStore
        self.connectivity = connectivity
        self.transcription = transcription
        self.healthKit = healthKit
        self.processor = processor
        self.plannedWorkoutStore = plannedWorkoutStore
        self.progression = progression
        self.events = events
        connectivity.progressionContext = progression.context.toDictionary()
        progression.onRewardChanged = { [weak self] reward in
            guard let self else { return }
            self.connectivity.progressionContext = self.progression.context.toDictionary()
            self.connectivity.sendWorkoutReward(reward)
        }
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
        startPresenceHeartbeat()
    }

    /// Call this when app returns to foreground to ensure session is fresh from disk
    func refreshActiveSession() {
        guard let id = activeSession?.id,
              let session = workoutStore.loadSession(id: id) else { return }
        if session.endedAt != nil {
            // Workout was ended (maybe by watch) while we were in background
            activeSession = nil
            UserDefaults.standard.removeObject(forKey: Self.activeWorkoutKey)
            stopPresenceHeartbeat()
        } else {
            activeSession = session
            startPresenceHeartbeat()
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

    func startWorkout(plan: PlannedWorkout? = nil) {
        // A workout is already running — starting another would orphan it
        guard activeSession == nil else { return }

        // Reset stale state from previous workout
        isProcessingMoment = false
        lastError = nil

        var session = WorkoutSession()
        session.plannedWorkout = plan
        activeSession = session
        workoutStore.saveSession(session)
        persistActiveWorkoutID(session.id)

        let message = WorkoutMessage(command: .start, workoutID: session.id)
        connectivity.sendWorkoutMessage(message)
        connectivity.updateWorkoutContext(workoutID: session.id, isActive: true, startedAt: session.startedAt, plan: plan)

        // Start HealthKit tracking (on phone, just records start time for manual save)
        Task { await healthKit.startWorkout() }
        startPresenceHeartbeat()
        liveSessions?.noteWorkoutStarted()

        Self.logger.info("Started workout \(session.id)")
    }

    func discardWorkout() {
        guard let session = activeSession else { return }
        activeSession = nil
        isProcessingMoment = false
        persistActiveWorkoutID(nil)
        clearPlanIfUsed(by: session)
        stopPresenceHeartbeat()

        // Delete the session file entirely
        workoutStore.deleteSession(id: session.id)

        let message = WorkoutMessage(command: .stop, workoutID: session.id)
        connectivity.sendWorkoutMessage(message)
        connectivity.updateWorkoutContext(workoutID: nil, isActive: false, startedAt: nil)

        Self.logger.info("Discarded workout \(session.id)")
    }

    func endWorkout() {
        guard var session = activeSession else { return }

        // RUXP: every ended workout counts, voice notes or not. Discard is an explicit choice.
        session.endedAt = Date()
        workoutStore.saveSession(session)
        endingSessionID = session.id
        rewardCompletion(for: session)
        // Invariant: completedWorkoutID must be set BEFORE activeSession is cleared so the
        // single workout cover crossfades to the completion screen instead of dismissing.
        completedWorkoutID = session.id
        activeSession = nil
        isProcessingMoment = false
        persistActiveWorkoutID(nil)
        clearPlanIfUsed(by: session)
        stopPresenceHeartbeat()

        let message = WorkoutMessage(command: .stop, workoutID: session.id)
        connectivity.sendWorkoutMessage(message)
        connectivity.updateWorkoutContext(workoutID: nil, isActive: false, startedAt: nil)

        Self.logger.info("Ended workout \(session.id)")

        // Save workout to Apple Health + fetch health data
        let sessionID = session.id
        let startDate = session.startedAt
        let endDate = session.endedAt ?? Date()
        Task {
            // Save manual workout to HealthKit (phone-side, covers no-watch case)
            await healthKit.endWorkout()
            try? await Task.sleep(for: .seconds(3))
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
        rewardCompletion(for: session)
        // See endWorkout(): completedWorkoutID before activeSession = nil.
        completedWorkoutID = session.id
        activeSession = nil
        persistActiveWorkoutID(nil)
        clearPlanIfUsed(by: session)
        stopPresenceHeartbeat()
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

    /// Awards completion XP synchronously (offline, no AI). PR XP arrives later from the processor.
    private func rewardCompletion(for session: WorkoutSession) {
        let end = session.endedAt ?? ScheduledEventService.now()
        let overlapping = events.events(overlapping: session.startedAt, end: end)
        let modifiers = events.modifiers(overlapping: session.startedAt, end: end)
        let reward = progression.rewardWorkoutCompletion(session: session, events: overlapping, modifiers: modifiers)

        recordCompletionPresence(reward: reward, events: overlapping)
        liveSessions?.recordCompletion(session: session, reward: reward, events: overlapping)
        onWorkoutEnded?()
    }

    // MARK: - Presence

    /// While a workout is active, ping the "lifting now" windows every few minutes (plus the
    /// live event's board) so this player is counted. The watch pings on its own when the phone
    /// is suspended during a watch-run workout.
    private func startPresenceHeartbeat() {
        guard gameCenter != nil else { return }
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.activeSession != nil else { return }
                await self.pingActivePresence()
                try? await Task.sleep(for: Self.heartbeatInterval)
            }
        }
    }

    private func stopPresenceHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func pingActivePresence() async {
        guard let gameCenter else { return }
        var boards = GameCenterCatalog.activeBoards
        if let event = events.activeEvent(at: ScheduledEventService.now()), let id = GameCenterCatalog.eventBoard(for: event) {
            boards.append(id)
        }
        await gameCenter.submitPresence(boards: boards)
    }

    /// A rewarded workout counts toward "trained today" and any event it overlapped.
    private func recordCompletionPresence(reward: WorkoutRewardSummary, events overlapping: [LiveEvent]) {
        guard let gameCenter, !reward.isEmpty else { return }
        var boards = [GameCenterCatalog.trainedToday]
        boards += overlapping.compactMap(GameCenterCatalog.eventBoard(for:))
        Task { await gameCenter.submitPresence(boards: boards) }
    }

    /// The plan slot is one-shot: once its workout ends (or is discarded), clear it.
    private func clearPlanIfUsed(by session: WorkoutSession) {
        if let planID = session.plannedWorkout?.id, plannedWorkoutStore.currentPlan?.id == planID {
            plannedWorkoutStore.clearPlan()
        }
    }

    private func finalizeEnd(workoutID: UUID) {
        guard endingSessionID == workoutID else { return }
        Task {
            // A moment that failed to transcribe seconds ago gets one more chance to make the log.
            await retryPendingTranscriptions()
            guard endingSessionID == workoutID else { return }
            let finalSession = workoutStore.loadSession(id: workoutID)
            endingSessionID = nil
            if let finalSession {
                await processor?.processWorkout(finalSession)
            }
        }
    }

    // MARK: - Moment Management

    func addMoment(audioURL: URL, source: MomentSource, momentID: UUID? = nil, forWorkoutID: UUID? = nil) async {
        let workoutID: UUID
        if let explicit = forWorkoutID {
            // Trust the workoutID from file metadata — moment belongs to this workout
            // even if the session is no longer active (stop arrived before transfer)
            workoutID = explicit
        } else if let active = activeSession {
            workoutID = active.id
        } else if let ending = endingSessionID {
            workoutID = ending
        } else {
            return
        }
        // Verify the workout exists on disk (handles late-arriving transfers after stop)
        if activeSession?.id != workoutID && endingSessionID != workoutID {
            guard workoutStore.loadSession(id: workoutID) != nil else { return }
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
        defer { try? FileManager.default.removeItem(at: audioURL) }
        // Only a stored copy can be retried later; without one this is a single shot.
        let canRetry = storedURL != nil

        // The moment exists the instant the audio lands. Whisper fills in the text afterwards,
        // so a network blip never costs the recording, only the wait.
        let moment = Moment(id: mID, timestamp: Date(), transcript: Moment.pendingTranscript,
                            source: source, transcriptionPending: canRetry)
        guard var session = workoutStore.loadSession(id: workoutID) else { return }
        session.moments.append(moment)
        workoutStore.saveSession(session)
        if activeSession?.id == workoutID { activeSession = session }
        connectivity.updateMomentCount(session.moments.count, workoutID: workoutID)

        // Plainly offline: don't sit on a 60 s timeout. The retry path picks it up when the network returns.
        if canRetry, processor?.isNetworkAvailable == false {
            if source == .watch { connectivity.sendErrorToWatch(Self.savedForRetryMessage, workoutID: workoutID) }
            return
        }

        inFlightMomentIDs.insert(mID)
        let outcome = await transcribeWithRetry(url: storedURL ?? audioURL)
        inFlightMomentIDs.remove(mID)
        apply(outcome, to: mID, in: workoutID, source: source, canRetry: canRetry)

        // We are clearly online: earlier moments still waiting get their turn now.
        if case .transcribed = outcome { await retryPendingTranscriptions() }
    }

    // MARK: - Transcription retry

    /// What the watch shows when a moment is stored but not yet transcribed. Honest, not alarming.
    static let savedForRetryMessage = "Saved. Transcribes when iPhone is online."
    private static let transcriptionAttempts = 2
    private var isRetryingTranscriptions = false
    /// Moments mid-transcription in `processAudioMoment`; the retry sweep leaves these alone.
    private var inFlightMomentIDs: Set<UUID> = []

    private enum TranscriptionOutcome {
        case transcribed(String)
        /// Worth trying again later (offline, timeout, rate limit, server error). The moment stays pending.
        case transient(Error)
        /// Nothing a retry can fix. Carries the placeholder text to store.
        case permanent(placeholder: String, Error)
    }

    /// One Whisper call with a single short retry for transient failures. The offline sweep handles the rest,
    /// so this stays short: a flaky gym connection must not stall the feed for minutes.
    private func transcribeWithRetry(url: URL) async -> TranscriptionOutcome {
        var lastFailure: Error = AIError.networkUnavailable
        for attempt in 0..<Self.transcriptionAttempts {
            if attempt > 0 {
                var delay: Double = 2
                if case .rateLimited(let retryAfter)? = lastFailure as? AIError { delay = min(retryAfter, 10) }
                try? await Task.sleep(for: .seconds(delay))
            }
            switch await transcription.transcribe(audioURL: url) {
            case .success(let text):
                return .transcribed(text)
            case .failure(let error):
                lastFailure = error
                if error.isAPIKeyProblem {
                    return .permanent(placeholder: "[Not transcribed — add an OpenAI API key in Settings]", error)
                }
                if case .emptyResult? = error as? AIError {
                    return .permanent(placeholder: Moment.noSpeechTranscript, error)
                }
                if !error.isTransientAIFailure {
                    return .permanent(placeholder: Moment.failedTranscript, error)
                }
            }
        }
        return .transient(lastFailure)
    }

    /// Writes an outcome into the stored moment and tells the watch. Reloads the session first so a
    /// moment appended while Whisper was running is never clobbered.
    private func apply(_ outcome: TranscriptionOutcome, to momentID: UUID, in workoutID: UUID, source: MomentSource, canRetry: Bool) {
        switch outcome {
        case .transcribed(let text):
            updateMoment(momentID, in: workoutID) { moment in
                moment.transcript = text
                moment.transcriptionPending = nil
                moment.confidence = 1.0
            }
            if source == .watch { connectivity.sendTranscriptionToWatch(text, momentID: momentID, workoutID: workoutID) }
        case .transient(let error) where canRetry:
            lastError = error.localizedDescription
            Self.logger.info("Moment \(momentID) kept pending for retry: \(error.localizedDescription)")
            if source == .watch { connectivity.sendErrorToWatch(Self.savedForRetryMessage, workoutID: workoutID) }
        case .transient(let error):
            lastError = error.localizedDescription
            updateMoment(momentID, in: workoutID) { moment in
                moment.transcript = Moment.failedTranscript
                moment.transcriptionPending = nil
                moment.confidence = 0
            }
            if source == .watch { connectivity.sendErrorToWatch(error.localizedDescription, workoutID: workoutID) }
        case .permanent(let placeholder, let error):
            lastError = error.localizedDescription
            updateMoment(momentID, in: workoutID) { moment in
                moment.transcript = placeholder
                moment.transcriptionPending = nil
                moment.confidence = 0
            }
            if source == .watch { connectivity.sendErrorToWatch(error.localizedDescription, workoutID: workoutID) }
        }
    }

    private func updateMoment(_ momentID: UUID, in workoutID: UUID, _ change: (inout Moment) -> Void) {
        guard var session = workoutStore.loadSession(id: workoutID),
              let index = session.moments.firstIndex(where: { $0.id == momentID }) else { return }
        change(&session.moments[index])
        workoutStore.saveSession(session)
        if activeSession?.id == workoutID { activeSession = session }
    }

    /// Transcribes every moment still marked pending from its stored audio. Runs on foreground, on the
    /// offline → online edge, after a successful in-workout transcription, and right before a workout is
    /// parsed. A finished workout that recovers speech is parsed again so its log includes it.
    func retryPendingTranscriptions() async {
        guard !isRetryingTranscriptions, processor?.isNetworkAvailable != false, APIKeyProvider.hasKey else { return }
        isRetryingTranscriptions = true
        defer { isRetryingTranscriptions = false }

        for entry in workoutStore.index {
            guard let session = workoutStore.loadSession(id: entry.id) else { continue }
            let pending = session.moments.filter { $0.transcriptionPending == true && !inFlightMomentIDs.contains($0.id) }
            guard !pending.isEmpty else { continue }
            var recovered = false

            for moment in pending {
                let url = workoutStore.audioFileURL(momentID: moment.id, workoutID: session.id)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    // The audio is gone; stop scanning this one forever.
                    updateMoment(moment.id, in: session.id) { m in
                        m.transcript = Moment.failedTranscript
                        m.transcriptionPending = nil
                        m.confidence = 0
                    }
                    continue
                }
                let outcome = await transcribeWithRetry(url: url)
                switch outcome {
                case .transcribed:
                    recovered = true
                    let isLive = activeSession?.id == session.id || endingSessionID == session.id
                    apply(outcome, to: moment.id, in: session.id, source: isLive ? moment.source : .phone, canRetry: true)
                case .transient:
                    // Still not reachable. Leave the rest for the next network edge or foreground.
                    Self.logger.info("Transcription retry paused; network still unreliable")
                    return
                case .permanent(_, let error):
                    apply(outcome, to: moment.id, in: session.id, source: .phone, canRetry: true)
                    if error.isAPIKeyProblem { return }
                }
            }

            // A workout that already ended was parsed without this speech (or not at all). Parse it again.
            // finalizeEnd handles the one currently ending; PR XP is idempotent per workout.
            if recovered, session.endedAt != nil, session.id != activeSession?.id, session.id != endingSessionID,
               let refreshed = workoutStore.loadSession(id: session.id) {
                await processor?.processWorkout(refreshed)
            }
        }
    }

    // MARK: - Connectivity Callbacks

    private func setupConnectivityCallbacks() {
        connectivity.onAudioReceived = { [weak self] url, momentID, workoutID in
            guard let self else { return }
            await self.addMoment(audioURL: url, source: .watch, momentID: momentID, forWorkoutID: workoutID)
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
                    self.startPresenceHeartbeat()
                    self.liveSessions?.noteWorkoutStarted(at: message.timestamp)
                }
            case .stop:
                if self.activeSession?.id == message.workoutID {
                    self.handleRemoteStop(workoutID: message.workoutID, healthWorkoutUUID: message.healthWorkoutUUID, avgHeartRate: message.avgHeartRate, activeCalories: message.activeCalories)
                }
            case .momentRecorded, .momentTranscribed, .workoutReward:
                break
            }
        }

        connectivity.onReceivedWorkoutContext = { [weak self] workoutID, isActive, startedAt in
            guard let self else { return }
            if isActive, let workoutID, self.activeSession == nil, self.endingSessionID == nil {
                let session = WorkoutSession(id: workoutID, startedAt: startedAt ?? Date())
                self.activeSession = session
                self.workoutStore.saveSession(session)
                self.startPresenceHeartbeat()
                self.liveSessions?.noteWorkoutStarted(at: session.startedAt)
            } else if !isActive, let activeID = self.activeSession?.id, activeID == workoutID {
                self.handleRemoteStop(workoutID: activeID)
            }
        }
    }
}
