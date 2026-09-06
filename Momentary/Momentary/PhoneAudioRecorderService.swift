import AVFoundation
import Foundation
import os

@MainActor
final class PhoneAudioRecorderService: NSObject, ObservableObject {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "PhoneAudioRecorderService")

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingStartTime: Date?

    private var currentRecordingURL: URL?

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("moment_\(UUID().uuidString).wav")
    }

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            Self.logger.error("Failed to configure audio session: \(error)")
            return
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let url = makeRecordingURL()
        currentRecordingURL = url

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
    }

    func stopRecording() -> URL? {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        stopTimer()
        
        // Deactivate audio session so other audio (music) resumes normally
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let url = currentRecordingURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        currentRecordingURL = nil
        return url
    }

    func cleanup(url: URL? = nil) {
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
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
