import AVFoundation
import Foundation
import os

@MainActor
final class PhoneAudioRecorderService: NSObject, ObservableObject {
    private static let logger = Logger(subsystem: "com.whussey.momentary", category: "PhoneAudioRecorderService")

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingStartTime: Date?

    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("phone_voicenote.wav")
    }

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
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

        try? FileManager.default.removeItem(at: recordingURL)

        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
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

        let url = recordingURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: recordingURL)
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
