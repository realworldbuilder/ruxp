import Foundation
import os

// MARK: - Persisted Models

struct PersistedConversation: Codable, Identifiable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [PersistedMessage]
}

struct PersistedMessage: Codable, Identifiable {
    let id: UUID
    var role: String // "user" or "assistant"
    var blocks: [PersistedBlock]
    var timestamp: Date
}

struct PersistedBlock: Codable {
    var type: String
    var payload: ChatBlockPayload
}

// MARK: - Conversation Store

@Observable
@MainActor
final class ConversationStore {
    private static let logger = Logger(subsystem: "com.williamhussey.mind2muscle", category: "ConversationStore")
    private static let maxConversations = 10

    var conversations: [PersistedConversation] = []
    var activeConversationId: UUID?

    private let directory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.directory = docs.appendingPathComponent("conversations", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadAll()
    }

    // MARK: - Public API

    /// Start a fresh conversation, returns its ID
    func newConversation() -> UUID {
        let convo = PersistedConversation(
            id: UUID(),
            title: "New Chat",
            createdAt: Date(),
            updatedAt: Date(),
            messages: []
        )
        conversations.insert(convo, at: 0)
        activeConversationId = convo.id
        trimAndSave()
        return convo.id
    }

    /// Save current messages into the active conversation
    func save(messages: [ChatMessage]) {
        guard let id = activeConversationId,
              let idx = conversations.firstIndex(where: { $0.id == id }) else { return }

        conversations[idx].messages = messages.compactMap { msg in
            guard !msg.isLoading else { return nil }
            return PersistedMessage(
                id: msg.id,
                role: msg.role == .user ? "user" : "assistant",
                blocks: msg.blocks.map { PersistedBlock(type: $0.type.rawValue, payload: $0.payload) },
                timestamp: msg.timestamp
            )
        }
        conversations[idx].updatedAt = Date()

        // Auto-title from first user message
        if conversations[idx].title == "New Chat",
           let firstUser = messages.first(where: { $0.role == .user }),
           let text = firstUser.blocks.first?.payload.text {
            let title = String(text.prefix(40))
            conversations[idx].title = title.count < text.count ? title + "…" : title
        }

        trimAndSave()
    }

    /// Load a conversation's messages back into ChatMessage format
    func loadMessages(for id: UUID) -> [ChatMessage] {
        guard let convo = conversations.first(where: { $0.id == id }) else { return [] }
        return convo.messages.map { pm in
            ChatMessage(
                id: pm.id,
                role: pm.role == "user" ? .user : .assistant,
                blocks: pm.blocks.compactMap { pb in
                    guard let type = ChatBlockType(rawValue: pb.type) else { return nil }
                    return ChatBlock(type: type, payload: pb.payload)
                },
                timestamp: pm.timestamp
            )
        }
    }

    /// Delete a conversation
    func delete(id: UUID) {
        conversations.removeAll { $0.id == id }
        if activeConversationId == id {
            activeConversationId = nil
        }
        let file = directory.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: - Persistence

    private func loadAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var loaded: [PersistedConversation] = []
        for file in files {
            if let data = try? Data(contentsOf: file),
               let convo = try? decoder.decode(PersistedConversation.self, from: data) {
                loaded.append(convo)
            }
        }
        conversations = loaded.sorted { $0.updatedAt > $1.updatedAt }
        Self.logger.info("Loaded \(self.conversations.count) conversations")
    }

    private func trimAndSave() {
        // Keep only the newest N
        if conversations.count > Self.maxConversations {
            let removed = conversations.suffix(from: Self.maxConversations)
            for convo in removed {
                let file = directory.appendingPathComponent("\(convo.id.uuidString).json")
                try? FileManager.default.removeItem(at: file)
            }
            conversations = Array(conversations.prefix(Self.maxConversations))
        }

        // Save all to disk
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for convo in conversations {
            let file = directory.appendingPathComponent("\(convo.id.uuidString).json")
            if let data = try? encoder.encode(convo) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }
}
