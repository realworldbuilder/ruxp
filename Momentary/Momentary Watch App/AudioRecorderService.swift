import AVFoundation
import Foundation
import os

@MainActor
final class AudioRecorderService: NSObject, ObservableObject {
    private static let logger = Logger(subsystem: "com.whussey.momentary.watchkitapp", category: "AudioRecorderService")

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingStartTime: Date?
    private var currentMomentID: UUID?
    private var currentRecordingURL: URL?

    private func recordingURL(for momentID: UUID) -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("\(momentID.uuidString).wav")
    }

    func startRecording() -> UUID {
        let momentID = UUID()
        currentMomentID = momentID
        let url = recordingURL(for: momentID)
        currentRecordingURL = url

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            Self.logger.error("Failed to configure audio session: \(error)")
            return momentID
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        try? FileManager.default.removeItem(at: url)

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
            recordingStartTime = Date()
            recordingDuration = 0
            startTimer()
        } catch {
            Self.logger.error("Failed to start recording: \(error)")
        }

        return momentID
    }

    func stopRecording() -> (URL, UUID)? {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        stopTimer()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard
            let url = currentRecordingURL,
            let momentID = currentMomentID,
            FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }

        currentRecordingURL = nil
        currentMomentID = nil
        return (url, momentID)
    }

    func cleanup() {
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentRecordingURL = nil
        currentMomentID = nil
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
