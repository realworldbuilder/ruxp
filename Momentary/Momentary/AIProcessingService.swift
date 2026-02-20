import Foundation
import os

// MARK: - Unified AI Service

@Observable
@MainActor
final class AIService {
    private static let logger = Logger(subsystem: "com.whussey.momentary", category: "AIService")

    private let chatEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let whisperEndpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    // TODO: Cost audit — consider gpt-4o-mini for insights/analysis, keep gpt-4o for Trainer chat
    private let model = "gpt-4o"

    // MARK: - Chat Completion

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        try await complete(messages: [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ])
    }

    func complete(messages: [[String: String]], jsonMode: Bool = true) async throws -> String {
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

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
            throw AIError.rateLimited(retryAfter: Double(retryAfter ?? "") ?? 5.0)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

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

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Self.logger.error("Whisper API error \(httpResponse.statusCode): \(errorBody)")
            throw AIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw AIError.invalidResponse
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.emptyResult }

        return trimmed
    }
}

// MARK: - AI Error

enum AIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case emptyResult
    case rateLimited(retryAfter: Double)
    case apiError(statusCode: Int, message: String)
    case parsingFailed(String)
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "No OpenAI API key configured."
        case .invalidResponse: "Invalid response from OpenAI"
        case .emptyResult: "No speech detected"
        case .rateLimited(let retryAfter): "Rate limited. Retrying in \(Int(retryAfter))s."
        case .apiError(let code, let message): "API error (\(code)): \(message)"
        case .parsingFailed(let detail): "Failed to parse AI response: \(detail)"
        case .networkUnavailable: "No network connection."
        }
    }
}
