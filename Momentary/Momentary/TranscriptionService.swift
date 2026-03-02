import Foundation
import os

/// Thin wrapper around AIService for transcription — maintains backward compat interface
@Observable
@MainActor
final class TranscriptionService {
    private static let logger = Logger(subsystem: "com.williamhussey.mind2muscle", category: "TranscriptionService")

    var isProcessing = false

    private let aiService = AIService()

    func transcribe(audioURL: URL) async -> Result<String, Error> {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let text = try await aiService.transcribe(audioURL: audioURL)
            return .success(text)
        } catch {
            Self.logger.error("Transcription failed: \(error)")
            return .failure(error)
        }
    }
}
