import Foundation
import SwiftData

/// Persistent user memory — stores facts the AI should remember across conversations.
@Model
final class UserMemory {
    var key: String
    var value: String
    var createdAt: Date

    init(key: String, value: String) {
        self.key = key
        self.value = value
        self.createdAt = Date()
    }
}
