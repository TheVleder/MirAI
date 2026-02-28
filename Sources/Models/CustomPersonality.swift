import Foundation
import SwiftData

/// User-created custom personality stored in SwiftData.
@Model
final class CustomPersonality {
    var id: String = UUID().uuidString
    var name: String = ""
    var emoji: String = "🤖"
    var personalityDescription: String = ""
    var systemPrompt: String = ""
    var createdAt: Date = Date()

    init(name: String, emoji: String, description: String, systemPrompt: String) {
        self.id = UUID().uuidString
        self.name = name
        self.emoji = emoji
        self.personalityDescription = description
        self.systemPrompt = systemPrompt
        self.createdAt = Date()
    }

    /// Convert to a Personality struct for LLMManager compatibility
    func toPersonality() -> Personality {
        Personality(
            id: id,
            name: name,
            emoji: emoji,
            description: personalityDescription,
            systemPrompt: systemPrompt
        )
    }
}
