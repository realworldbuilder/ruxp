import Foundation
import os

@Observable
@MainActor
final class ChatEngine {
    private static let logger = Logger(subsystem: "com.whussey.momentary", category: "ChatEngine")

    var messages: [ChatMessage] = []
    var isResponding = false
    var lastError: String?

    private let workoutStore: WorkoutStore
    private let insightsEngine: InsightsEngine
    private let aiService: AIService
    private let maxHistoryMessages = 20

    init(workoutStore: WorkoutStore, insightsEngine: InsightsEngine, aiService: AIService) {
        self.workoutStore = workoutStore
        self.insightsEngine = insightsEngine
        self.aiService = aiService
    }

    // MARK: - Send Message

    func send(_ userText: String) async {
        let userMessage = ChatMessage(
            role: .user,
            blocks: [ChatBlock(type: .text, payload: ChatBlockPayload(text: userText))]
        )
        messages.append(userMessage)

        let loadingMessage = ChatMessage(role: .assistant, isLoading: true)
        messages.append(loadingMessage)
        let loadingID = loadingMessage.id

        isResponding = true
        lastError = nil

        do {
            let systemPrompt = ChatPromptBuilder.buildSystemPrompt(
                workoutStore: workoutStore,
                insightsEngine: insightsEngine
            )

            let conversationMessages = buildConversationMessages(systemPrompt: systemPrompt)
            let responseJSON = try await aiService.complete(messages: conversationMessages)
            let blocks = parseResponse(responseJSON)

            let assistantMessage = ChatMessage(role: .assistant, blocks: blocks)
            if let idx = messages.firstIndex(where: { $0.id == loadingID }) {
                messages[idx] = assistantMessage
            }
        } catch {
            Self.logger.error("Chat error: \(error.localizedDescription)")
            lastError = error.localizedDescription

            let errorBlock = ChatBlock(
                type: .text,
                payload: ChatBlockPayload(text: "Sorry, I couldn't process that request. \(error.localizedDescription)")
            )
            let errorMessage = ChatMessage(role: .assistant, blocks: [errorBlock])
            if let idx = messages.firstIndex(where: { $0.id == loadingID }) {
                messages[idx] = errorMessage
            }
        }

        isResponding = false
    }

    func clearConversation() {
        messages = []
        lastError = nil
    }

    // MARK: - Build Messages

    private func buildConversationMessages(systemPrompt: String) -> [[String: String]] {
        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        let recentMessages = messages.suffix(maxHistoryMessages)
        for msg in recentMessages {
            if msg.isLoading { continue }
            let role = msg.role == .user ? "user" : "assistant"
            let content: String
            if msg.role == .user {
                content = msg.blocks.first?.payload.text ?? ""
            } else {
                let blockDicts = msg.blocks.map { block -> [String: Any] in
                    var dict: [String: Any] = ["type": block.type.rawValue]
                    if let text = block.payload.text { dict["text"] = text }
                    return dict
                }
                if let jsonData = try? JSONSerialization.data(withJSONObject: ["blocks": blockDicts]) {
                    content = String(data: jsonData, encoding: .utf8) ?? ""
                } else {
                    content = ""
                }
            }
            apiMessages.append(["role": role, "content": content])
        }

        return apiMessages
    }

    // MARK: - Parse Response

    private func parseResponse(_ json: String) -> [ChatBlock] {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let data = cleaned.data(using: .utf8) else {
            return [ChatBlock(type: .text, payload: ChatBlockPayload(text: cleaned))]
        }

        // Try standard decode first
        if let response = try? JSONDecoder().decode(ChatAPIResponse.self, from: data),
           let blocks = response.blocks?.compactMap({ $0.toChatBlock() }),
           !blocks.isEmpty {
            return blocks
        }

        // Fallback: try to manually parse the JSON structure
        if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let blocksArray = jsonObj["blocks"] as? [[String: Any]] {
            var result: [ChatBlock] = []
            for blockDict in blocksArray {
                // Handle both { "type": "text", "payload": { "text": "..." } }
                // and { "text": "payload", "type": { ... } } (malformed)
                if let typeStr = blockDict["type"] as? String,
                   let blockType = ChatBlockType(rawValue: typeStr) {
                    if let payloadDict = blockDict["payload"] as? [String: Any],
                       let payloadData = try? JSONSerialization.data(withJSONObject: payloadDict),
                       let payload = try? JSONDecoder().decode(ChatBlockPayload.self, from: payloadData) {
                        result.append(ChatBlock(type: blockType, payload: payload))
                    } else {
                        // Type is valid but payload failed — try to extract text from the block itself
                        let text = blockDict["text"] as? String
                            ?? (blockDict["payload"] as? [String: Any])?["text"] as? String
                        if let text {
                            result.append(ChatBlock(type: .text, payload: ChatBlockPayload(text: text)))
                        }
                    }
                }
            }
            if !result.isEmpty { return result }
        }

        // Last resort: if it looks like JSON but we can't parse blocks, extract any "text" values
        if cleaned.contains("\"text\"") {
            let textPattern = /"text"\s*:\s*"([^"]+)"/
            var extractedTexts: [String] = []
            // Simple extraction — find all text values
            if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                extractTextsRecursive(from: jsonObj, into: &extractedTexts)
            }
            if !extractedTexts.isEmpty {
                return extractedTexts.map { ChatBlock(type: .text, payload: ChatBlockPayload(text: $0)) }
            }
        }

        Self.logger.warning("Failed to parse chat response, showing as text")
        return [ChatBlock(type: .text, payload: ChatBlockPayload(text: cleaned))]
    }

    private func extractTextsRecursive(from obj: Any, into texts: inout [String]) {
        if let dict = obj as? [String: Any] {
            // If this dict has a "type" of "text" and a text payload, grab it
            if let type = dict["type"] as? String, type == "text",
               let payload = dict["payload"] as? [String: Any],
               let text = payload["text"] as? String {
                texts.append(text)
                return
            }
            // If this dict has a direct "text" key and looks like a text block
            if let text = dict["text"] as? String,
               dict["type"] == nil || (dict["type"] as? String) == "text" {
                if !text.isEmpty && text.count > 5 { // skip tiny fragments
                    texts.append(text)
                }
            }
            for value in dict.values {
                extractTextsRecursive(from: value, into: &texts)
            }
        } else if let array = obj as? [Any] {
            for item in array {
                extractTextsRecursive(from: item, into: &texts)
            }
        }
    }
}
