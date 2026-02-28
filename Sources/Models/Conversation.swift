import Foundation
import SwiftData

/// SwiftData model representing a conversation session.
@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var personalityID: String

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(
        title: String = "New Conversation",
        personalityID: String = "friend"
    ) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.personalityID = personalityID
        self.messages = []
    }

    /// Sorted messages by timestamp
    var sortedMessages: [Message] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }

    /// Auto-generate title from first user message
    func autoTitle() {
        if let firstUserMsg = messages.first(where: { $0.role == "user" }) {
            let preview = String(firstUserMsg.content.prefix(40))
            title = preview + (firstUserMsg.content.count > 40 ? "…" : "")
        }
    }
}
