import Foundation
import os

@Observable
@MainActor
final class ChatEngine {
    private static let logger = Logger(subsystem: "com.williamhussey.mind2muscle", category: "ChatEngine")

    var messages: [ChatMessage] = []
    var isResponding = false
    var lastError: String?

    private let workoutStore: WorkoutStore
    private let insightsEngine: InsightsEngine
    private let aiService: AIService
    private let conversationStore: ConversationStore
    private let maxHistoryMessages = 20

    init(workoutStore: WorkoutStore, insightsEngine: InsightsEngine, aiService: AIService, conversationStore: ConversationStore) {
        self.workoutStore = workoutStore
        self.insightsEngine = insightsEngine
        self.aiService = aiService
        self.conversationStore = conversationStore

        // Resume the most recent conversation if it exists
        if let latest = conversationStore.conversations.first {
            conversationStore.activeConversationId = latest.id
            messages = conversationStore.loadMessages(for: latest.id)
        }
    }

    // MARK: - Conversation Management

    func startNewConversation() {
        // Save current first
        if !messages.isEmpty {
            conversationStore.save(messages: messages)
        }
        let id = conversationStore.newConversation()
        conversationStore.activeConversationId = id
        messages = []
        lastError = nil
    }

    func loadConversation(_ id: UUID) {
        // Save current first
        if !messages.isEmpty {
            conversationStore.save(messages: messages)
        }
        conversationStore.activeConversationId = id
        messages = conversationStore.loadMessages(for: id)
        lastError = nil
    }

    func deleteConversation(_ id: UUID) {
        let wasActive = conversationStore.activeConversationId == id
        conversationStore.delete(id: id)
        if wasActive {
            messages = []
            lastError = nil
        }
    }

    // MARK: - Send Message

    func send(_ userText: String) async {
        // Auto-create conversation if none active
        if conversationStore.activeConversationId == nil {
            _ = conversationStore.newConversation()
        }

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

            // Extract planned exercises from trainer response
            extractPlannedExercises(from: blocks)

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

        // Auto-save after each exchange
        conversationStore.save(messages: messages)
    }

    func clearConversation() {
        if let id = conversationStore.activeConversationId {
            conversationStore.delete(id: id)
        }
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

    // MARK: - JSON Repair

    private func repairTruncatedJSON(_ json: String) -> String {
        var repaired = json
        // Count unclosed braces/brackets
        let openBraces = repaired.filter { $0 == "{" }.count
        let closeBraces = repaired.filter { $0 == "}" }.count
        let openBrackets = repaired.filter { $0 == "[" }.count
        let closeBrackets = repaired.filter { $0 == "]" }.count
        
        // Close unclosed strings (rough heuristic)
        let quoteCount = repaired.filter { $0 == "\"" }.count
        if quoteCount % 2 != 0 {
            repaired += "\""
        }
        
        // Close arrays then objects
        for _ in 0..<(openBrackets - closeBrackets) {
            repaired += "]"
        }
        for _ in 0..<(openBraces - closeBraces) {
            repaired += "}"
        }
        
        return repaired
    }

    // MARK: - Parse Response

    private func parseResponse(_ json: String) -> [ChatBlock] {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if response was truncated and remove the marker
        let wasTruncated = cleaned.hasSuffix("[TRUNCATED_RESPONSE]")
        if wasTruncated {
            cleaned = cleaned.replacingOccurrences(of: "\n\n[TRUNCATED_RESPONSE]", with: "")
                             .replacingOccurrences(of: "[TRUNCATED_RESPONSE]", with: "")
                             .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Remove code block markers
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let data = cleaned.data(using: .utf8) else {
            return [ChatBlock(type: .text, payload: ChatBlockPayload(text: stripJSONArtifacts(from: cleaned)))]
        }

        // Try normal parsing first
        if let response = try? JSONDecoder().decode(ChatAPIResponse.self, from: data),
           let blocks = response.blocks?.compactMap({ $0.toChatBlock() }),
           !blocks.isEmpty {
            return blocks
        }

        if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let blocksArray = jsonObj["blocks"] as? [[String: Any]] {
            var result: [ChatBlock] = []
            for blockDict in blocksArray {
                if let typeStr = blockDict["type"] as? String,
                   let blockType = ChatBlockType(rawValue: typeStr) {
                    if let payloadDict = blockDict["payload"] as? [String: Any],
                       let payloadData = try? JSONSerialization.data(withJSONObject: payloadDict),
                       let payload = try? JSONDecoder().decode(ChatBlockPayload.self, from: payloadData) {
                        result.append(ChatBlock(type: blockType, payload: payload))
                    } else {
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

        // If truncated or initial parsing failed, try to repair JSON
        if wasTruncated || cleaned.contains("\"text\"") {
            let repairedJSON = repairTruncatedJSON(cleaned)
            if let repairedData = repairedJSON.data(using: .utf8) {
                // Try parsing the repaired JSON
                if let response = try? JSONDecoder().decode(ChatAPIResponse.self, from: repairedData),
                   let blocks = response.blocks?.compactMap({ $0.toChatBlock() }),
                   !blocks.isEmpty {
                    return blocks
                }
                
                if let jsonObj = try? JSONSerialization.jsonObject(with: repairedData) as? [String: Any],
                   let blocksArray = jsonObj["blocks"] as? [[String: Any]] {
                    var result: [ChatBlock] = []
                    for blockDict in blocksArray {
                        if let typeStr = blockDict["type"] as? String,
                           let blockType = ChatBlockType(rawValue: typeStr) {
                            if let payloadDict = blockDict["payload"] as? [String: Any],
                               let payloadData = try? JSONSerialization.data(withJSONObject: payloadDict),
                               let payload = try? JSONDecoder().decode(ChatBlockPayload.self, from: payloadData) {
                                result.append(ChatBlock(type: blockType, payload: payload))
                            } else {
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
            }
        }

        // Try to extract text from broken JSON
        if cleaned.contains("\"text\"") {
            if let data = cleaned.data(using: .utf8),
               let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var extractedTexts: [String] = []
                extractTextsRecursive(from: jsonObj, into: &extractedTexts)
                if !extractedTexts.isEmpty {
                    return extractedTexts.map { ChatBlock(type: .text, payload: ChatBlockPayload(text: $0)) }
                }
            }
        }

        Self.logger.warning("Failed to parse chat response, showing cleaned text")
        return [ChatBlock(type: .text, payload: ChatBlockPayload(text: stripJSONArtifacts(from: cleaned)))]
    }

    private func stripJSONArtifacts(from text: String) -> String {
        var cleaned = text
        
        // Remove JSON structure characters that shouldn't appear in user-facing text
        let jsonChars = CharacterSet(charactersIn: "{}[]\"")
        let lines = cleaned.components(separatedBy: .newlines)
        let filteredLines = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip obviously JSON-looking lines
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("\"") ||
               trimmed.hasSuffix("}") || trimmed.hasSuffix("]") || trimmed.hasSuffix("\"") ||
               trimmed == "," || trimmed == "}" || trimmed == "]" {
                return nil
            }
            
            // Extract content from quoted strings
            if trimmed.hasPrefix("\"text\":") {
                let content = trimmed.replacingOccurrences(of: "\"text\":", with: "")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .trimmingCharacters(in: jsonChars)
                return content.isEmpty ? nil : content
            }
            
            return trimmed.isEmpty ? nil : trimmed
        }
        
        let result = filteredLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "I encountered an error parsing the response. Please try again." : result
    }

    private func extractTextsRecursive(from obj: Any, into texts: inout [String]) {
        if let dict = obj as? [String: Any] {
            if let type = dict["type"] as? String, type == "text",
               let payload = dict["payload"] as? [String: Any],
               let text = payload["text"] as? String {
                texts.append(text)
                return
            }
            if let text = dict["text"] as? String,
               dict["type"] == nil || (dict["type"] as? String) == "text" {
                if !text.isEmpty && text.count > 5 {
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
    
    // MARK: - Extract Planned Exercises
    
    private func extractPlannedExercises(from blocks: [ChatBlock]) {
        var exercises: [String] = []
        var planTitle = ""
        
        for block in blocks {
            switch block.type {
            case .exerciseTable:
                if let name = block.payload.exerciseName {
                    exercises.append(name)
                }
            case .actionButtons:
                if let actions = block.payload.actions {
                    for action in actions where action.actionType == .startWorkout {
                        planTitle = "Trainer Plan"
                    }
                }
            default:
                break
            }
        }
        
        // Also scan text blocks for exercise mentions in workout plans
        for block in blocks where block.type == .text {
            if let text = block.payload.text?.lowercased(),
               (text.contains("workout plan") || text.contains("today's workout") || text.contains("here's your") || text.contains("try this")) {
                planTitle = planTitle.isEmpty ? "Trainer Suggestion" : planTitle
            }
        }
        
        if !exercises.isEmpty {
            let store = PlannedWorkoutStore()
            store.setPlan(exercises: exercises, source: planTitle.isEmpty ? "" : "★ \(planTitle)")
        }
    }
}
