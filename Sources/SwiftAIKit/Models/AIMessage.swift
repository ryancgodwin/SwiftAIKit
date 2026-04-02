import Foundation

/// A single message in an AI conversation.
public struct AIMessage: Sendable, Codable, Identifiable {
    public let id: UUID
    public let role: AIRole
    public let content: String

    public init(id: UUID = UUID(), role: AIRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

/// The role of a message participant.
public enum AIRole: String, Sendable, Codable {
    case system
    case user
    case assistant
}
