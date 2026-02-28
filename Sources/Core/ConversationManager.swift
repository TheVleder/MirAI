import Foundation
import Observation
import SwiftData

/// CRUD manager for conversations and messages using SwiftData.
@Observable
@MainActor
final class ConversationManager {

    var activeConversation: Conversation?

    private var modelContext: ModelContext?

    /// Inject the SwiftData model context
    func setContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Conversation CRUD

    /// Fetch all conversations ordered by most recent
    func fetchAll() -> [Conversation] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Create a new conversation
    @discardableResult
    func createConversation(personalityID: String = "friend") -> Conversation {
        let conversation = Conversation(personalityID: personalityID)
        modelContext?.insert(conversation)
        save()
        activeConversation = conversation
        return conversation
    }

    /// Delete a conversation
    func delete(_ conversation: Conversation) {
        if activeConversation?.id == conversation.id {
            activeConversation = nil
        }
        modelContext?.delete(conversation)
        save()
    }

    /// Rename a conversation
    func rename(_ conversation: Conversation, to newTitle: String) {
        conversation.title = newTitle
        conversation.updatedAt = Date()
        save()
    }

    // MARK: - Message Operations

    /// Add a message to the active conversation
    func addMessage(role: String, content: String) {
        guard let conversation = activeConversation else { return }
        let message = Message(role: role, content: content)
        message.conversation = conversation
        conversation.messages.append(message)
        conversation.updatedAt = Date()

        // Auto-title on first user message
        if role == "user" && conversation.messages.filter({ $0.role == "user" }).count == 1 {
            conversation.autoTitle()
        }

        save()
    }

    /// Get sorted messages for the active conversation
    var currentMessages: [Message] {
        activeConversation?.sortedMessages ?? []
    }

    /// Delete a single message
    func deleteMessage(_ message: Message) {
        if let conversation = message.conversation {
            conversation.messages.removeAll { $0.id == message.id }
        }
        modelContext?.delete(message)
        save()
    }

    // MARK: - Persistence

    private func save() {
        try? modelContext?.save()
    }

    // MARK: - User Memory

    /// Save a memory fact
    func saveMemory(key: String, value: String) {
        guard let context = modelContext else { return }
        // Update existing or create new
        let descriptor = FetchDescriptor<UserMemory>()
        if let existing = (try? context.fetch(descriptor))?.first(where: { $0.key == key }) {
            existing.value = value
        } else {
            context.insert(UserMemory(key: key, value: value))
        }
        save()
    }

    /// Fetch all memories
    func fetchAllMemories() -> [UserMemory] {
        guard let context = modelContext else { return [] }
        return (try? context.fetch(FetchDescriptor<UserMemory>())) ?? []
    }

    /// Delete a memory
    func deleteMemory(_ memory: UserMemory) {
        modelContext?.delete(memory)
        save()
    }

    /// Build memory context string for LLM system prompt
    func memoryContext() -> String {
        let memories = fetchAllMemories()
        guard !memories.isEmpty else { return "" }
        let facts = memories.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
        return "\n\nThings you remember about the user:\n\(facts)"
    }
}
