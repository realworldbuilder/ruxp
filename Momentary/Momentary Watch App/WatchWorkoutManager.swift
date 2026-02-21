import Foundation
import os
import WatchKit

@Observable
@MainActor
final class WatchWorkoutManager {
    private static let logger = Logger(subsystem: "com.whussey.momentary.watchkitapp", category: "WatchWorkoutManager")

    let recorder = AudioRecorderService()
    let connectivity = WatchConnectivityManager()
    let extendedSession = ExtendedSessionManager()
    let healthKitService = HealthKitService()

    var isWorkoutActive = false
    var currentWorkoutID: UUID?
    var momentCount = 0
    var elapsedTime: TimeInterval = 0
    var latestTranscriptSnippet: String?
    var isRecordingMoment = false
    var lastError: String?
    var didReceiveRemoteStop = false
    
    // AI Intelligence features
    var restTimerRemaining: TimeInterval = 0
    var isRestTimerActive = false
    var postSetFeedback: String?
    var showPostSetFeedback = false

    private var workoutStartTime: Date?
    private var elapsedTimer: Timer?
    private var restTimer: Timer?

    init() {
        setupConnectivityCallbacks()
        connectivity.onMomentCountUpdated = { [weak self] count in
            guard let self else { return }
            // Always take the max — phone knows the true total
            if count > self.momentCount {
                self.momentCount = count
            }
        }
    }

    // MARK: - Workout Lifecycle

    func startWorkout() {
        let workoutID = UUID()
        currentWorkoutID = workoutID
        isWorkoutActive = true
        momentCount = 0
        elapsedTime = 0
        latestTranscriptSnippet = nil
        lastError = nil
        workoutStartTime = Date()

        extendedSession.startSession()
        startElapsedTimer()

        let message = WorkoutMessage(command: .start, workoutID: workoutID)
        connectivity.sendWorkoutCommand(message)
        connectivity.updateWorkoutContext(workoutID: workoutID, isActive: true, startedAt: workoutStartTime!)

        Task {
            await healthKitService.startWorkout()
        }

        Self.logger.info("Started workout \(workoutID)")
    }

    /// Ends the workout, waits for HealthKit stats, then signals ready for summary.
    var isEndingWorkout = false

    func endWorkout() {
        guard let workoutID = currentWorkoutID, !isEndingWorkout else { return }
        isEndingWorkout = true

        stopElapsedTimer()

        // End HealthKit workout FIRST to capture final stats, then send to phone
        Task {
            await healthKitService.endWorkout()

            let message = WorkoutMessage(
                command: .stop,
                workoutID: workoutID,
                healthWorkoutUUID: healthKitService.workoutUUID,
                avgHeartRate: healthKitService.averageHeartRate > 0 ? healthKitService.averageHeartRate : nil,
                activeCalories: healthKitService.totalActiveCalories > 0 ? healthKitService.totalActiveCalories : nil
            )
            connectivity.sendWorkoutCommand(message)
            connectivity.updateWorkoutContext(workoutID: workoutID, isActive: false, startedAt: nil)

            extendedSession.endSession()
            isEndingWorkout = false
            workoutEndReady = true

            Self.logger.info("Ended workout \(workoutID)")
        }
    }

    /// Set to true once HealthKit stats are captured and summary is safe to show.
    var workoutEndReady = false

    func completeWorkoutDismissal() {
        // Save last workout date for home view intelligence
        UserDefaults.standard.set(Date(), forKey: "lastWorkoutDate")
        
        isWorkoutActive = false
        currentWorkoutID = nil
        momentCount = 0
        elapsedTime = 0
        latestTranscriptSnippet = nil
        workoutStartTime = nil
        didReceiveRemoteStop = false
        workoutEndReady = false
        isEndingWorkout = false
        stopRestTimer()
        postSetFeedback = nil
        showPostSetFeedback = false
    }

    // MARK: - Moment Recording

    func recordMoment() {
        guard isWorkoutActive, !isRecordingMoment else { return }
        isRecordingMoment = true
        stopRestTimer() // Dismiss rest timer when recording starts
        _ = recorder.startRecording()
    }

    func stopRecordingMoment() {
        guard isRecordingMoment else { return }
        isRecordingMoment = false

        guard let (url, momentID) = recorder.stopRecording(),
              let workoutID = currentWorkoutID else { return }

        momentCount += 1
        connectivity.transferMomentAudio(at: url, momentID: momentID, workoutID: workoutID)

        let message = WorkoutMessage(
            command: .momentRecorded,
            workoutID: workoutID,
            momentID: momentID
        )
        connectivity.sendWorkoutCommand(message)

        WKInterfaceDevice.current().play(.success)
        
        // Start smart rest timer and show feedback
        startRestTimer(seconds: determineRestTime())
        showMotivationalFeedback()
    }
    
    // MARK: - AI Intelligence Features
    
    private func determineRestTime() -> TimeInterval {
        // Smart rest timer based on exercise detection from transcript
        if let transcript = latestTranscriptSnippet {
            let lowercased = transcript.lowercased()
            
            // Compound movements - longer rest
            let compoundKeywords = ["bench", "squat", "deadlift", "row", "press", "pullup", "pull up", "chin up", "dip"]
            if compoundKeywords.contains(where: { lowercased.contains($0) }) {
                return 150 // 2.5 min for compounds
            }
            
            // Isolation - shorter rest
            let isolationKeywords = ["curl", "extension", "raise", "lateral", "fly", "tricep", "bicep"]
            if isolationKeywords.contains(where: { lowercased.contains($0) }) {
                return 75 // 1:15 for isolation
            }
        }
        
        // Default to 2 minutes
        return 120
    }
    
    func startRestTimer(seconds: TimeInterval) {
        restTimerRemaining = seconds
        isRestTimerActive = true
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.restTimerRemaining -= 1
                if self.restTimerRemaining <= 0 {
                    self.stopRestTimer()
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        }
    }
    
    func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        isRestTimerActive = false
        restTimerRemaining = 0
    }
    
    private func showMotivationalFeedback() {
        postSetFeedback = generatePostSetFeedback()
        if postSetFeedback != nil {
            showPostSetFeedback = true
            
            // Auto-dismiss after 2 seconds
            Task {
                try? await Task.sleep(for: .seconds(2))
                showPostSetFeedback = false
                postSetFeedback = nil
            }
        }
    }
    
    func generatePostSetFeedback() -> String? {
        switch momentCount {
        case 1: return "First set ✓"
        case 2: return "Let's go"
        case 3: return "Getting warm 🔥"
        case 5: return "Solid session building"
        case 8: return "Beast mode 💪"
        case 10: return "Double digits 🔟"
        case 15: return "Marathon session!"
        default: return nil
        }
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.workoutStartTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - Connectivity

    private func setupConnectivityCallbacks() {
        connectivity.onWorkoutCommand = { [weak self] message in
            guard let self else { return }
            switch message.command {
            case .start:
                if !self.isWorkoutActive {
                    self.currentWorkoutID = message.workoutID
                    self.isWorkoutActive = true
                    self.momentCount = 0
                    self.elapsedTime = 0
                    self.latestTranscriptSnippet = nil
                    self.lastError = nil
                    self.workoutStartTime = message.timestamp
                    self.extendedSession.startSession()
                    self.startElapsedTimer()
                    Task { await self.healthKitService.startWorkout() }
                    self.connectivity.updateWorkoutContext(workoutID: message.workoutID, isActive: true, startedAt: message.timestamp)
                }
            case .stop:
                if self.currentWorkoutID == message.workoutID {
                    self.stopElapsedTimer()
                    self.extendedSession.endSession()
                    Task { await self.healthKitService.endWorkout() }
                    self.didReceiveRemoteStop = true
                    self.connectivity.updateWorkoutContext(workoutID: message.workoutID, isActive: false, startedAt: nil)
                }
            case .momentTranscribed:
                if let transcript = message.transcript {
                    self.latestTranscriptSnippet = transcript
                    self.connectivity.isSending = false
                    // Phone moment was transcribed — bump count if we're behind
                    // (watch-recorded moments already counted in stopRecordingMoment)
                } else if let error = message.error {
                    self.lastError = error
                    self.connectivity.isSending = false
                }
            case .momentRecorded:
                break
            }
        }

        connectivity.onReceivedWorkoutContext = { [weak self] workoutID, isActive, startedAt in
            guard let self else { return }
            if isActive, let workoutID, !self.isWorkoutActive {
                self.currentWorkoutID = workoutID
                self.isWorkoutActive = true
                self.momentCount = 0
                self.elapsedTime = 0
                self.latestTranscriptSnippet = nil
                self.lastError = nil
                self.workoutStartTime = startedAt ?? Date()
                self.extendedSession.startSession()
                self.startElapsedTimer()
                Task { await self.healthKitService.startWorkout() }
            } else if !isActive, self.isWorkoutActive, self.currentWorkoutID == workoutID {
                self.stopElapsedTimer()
                self.extendedSession.endSession()
                Task { await self.healthKitService.endWorkout() }
                self.didReceiveRemoteStop = true
            }
        }
    }
}
