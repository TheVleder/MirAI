import Foundation
import SwiftData

/// SwiftData model representing a single message within a conversation.
@Model
final class Message {
    var id: UUID
    var role: String   // "user" or "assistant"
    var content: String
    var timestamp: Date

    var conversation: Conversation?

    init(role: String, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}
