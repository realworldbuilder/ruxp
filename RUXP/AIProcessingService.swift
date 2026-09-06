import Foundation
import os

// MARK: - Unified AI Service

@Observable
@MainActor
final class AIService {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "AIService")

    private let chatEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let whisperEndpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    /// Voice note → structured log. Accuracy drives PR XP, so keep the big model.
    static let parsingModel = "gpt-4o"
    /// Insight blurbs and coach chat. Cheap is plenty.
    static let lightModel = "gpt-4o-mini"

    // MARK: - Chat Completion

    func complete(systemPrompt: String, userPrompt: String, jsonMode: Bool = true, model: String = AIService.parsingModel) async throws -> String {
        try await complete(messages: [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ], jsonMode: jsonMode, model: model)
    }

    func complete(messages: [[String: String]], jsonMode: Bool = true, model: String = AIService.parsingModel) async throws -> String {
        let apiKey = APIKeyProvider.resolvedKey
        guard !apiKey.isEmpty else { throw AIError.noAPIKey }

        var requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 16384
        ]
        if jsonMode {
            requestBody["response_format"] = ["type": "json_object"]
        }

        var request = URLRequest(url: chatEndpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.invalidResponse
        }

        // Log if response was truncated and append note to content
        if let finishReason = firstChoice["finish_reason"] as? String, finishReason == "length" {
            Self.logger.warning("Response truncated (finish_reason=length). Response may be incomplete.")
            return content + "\n\n[TRUNCATED_RESPONSE]"
        }

        return content
    }

    // MARK: - Whisper Transcription

    func transcribe(audioURL: URL) async throws -> String {
        let apiKey = APIKeyProvider.resolvedKey
        guard !apiKey.isEmpty else { throw AIError.noAPIKey }

        let audioData = try Data(contentsOf: audioURL)
        let boundary = UUID().uuidString

        var request = URLRequest(url: whisperEndpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        do {
            try Self.validate(response, data: data)
        } catch let error as AIError {
            Self.logger.error("Whisper API error: \(error.localizedDescription)")
            throw error
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw AIError.invalidResponse
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.emptyResult }

        return trimmed
    }

    // MARK: - Key Validation

    /// Checks a key against the OpenAI API without storing it. Used by the Settings "Test Key" button.
    static func validateKey(_ key: String) async -> Result<Void, AIError> {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.noAPIKey) }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.addValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response, data: data)
            return .success(())
        } catch let error as AIError {
            return .failure(error)
        } catch {
            return .failure(.networkUnavailable)
        }
    }

    // MARK: - Response Validation

    /// Single home for the HTTP status-code policy — throws the matching AIError for any failure response.
    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw AIError.invalidAPIKey
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
            throw AIError.rateLimited(retryAfter: Double(retryAfter ?? "") ?? 5.0)
        default:
            throw AIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage(from: data))
        }
    }

    /// Extracts OpenAI's `error.message` from a failure body so raw JSON never reaches the UI.
    private static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return "Unexpected server error"
    }
}

// MARK: - AI Error

enum AIError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case invalidResponse
    case emptyResult
    case rateLimited(retryAfter: Double)
    case apiError(statusCode: Int, message: String)
    case parsingFailed(String)
    case networkUnavailable

    /// True when the failure can only be fixed by the user entering a valid key — never retry or queue these.
    var isKeyProblem: Bool {
        switch self {
        case .noAPIKey, .invalidAPIKey: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "No OpenAI API key set. Add yours in Settings to enable AI features."
        case .invalidAPIKey: "Your OpenAI API key was rejected. Check it in Settings."
        case .invalidResponse: "Invalid response from OpenAI"
        case .emptyResult: "No speech detected"
        case .rateLimited(let retryAfter): "Rate limited. Retrying in \(Int(retryAfter))s."
        case .apiError(let code, let message): "API error (\(code)): \(message)"
        case .parsingFailed(let detail): "Failed to parse AI response: \(detail)"
        case .networkUnavailable: "No network connection."
        }
    }
}

extension Error {
    /// True when this is an AIError that only a valid API key can fix.
    var isAPIKeyProblem: Bool { (self as? AIError)?.isKeyProblem == true }
}
