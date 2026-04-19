import Foundation

// MARK: - Conversation history

public struct ConversationTurn: Sendable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - AI protocols

public protocol OpenSourceKnowledgeProviding: Sendable {
    func answer(for query: String) async -> String?
    func answer(for query: String, history: [ConversationTurn]) async -> String?
}

public extension OpenSourceKnowledgeProviding {
    func answer(for query: String, history: [ConversationTurn]) async -> String? {
        await answer(for: query)
    }
}

public protocol AIConversationProviding: Sendable {
    func supportMaterial(for topic: String, type: ActivityType) async throws -> [String]
    func chatReply(
        userMessage: String,
        history: [ConversationTurn],
        activityTitle: String,
        topic: String,
        type: ActivityType
    ) async throws -> String
    func triviaQuestions(
        count: Int,
        categories: [TriviaCategory],
        difficulty: Int
    ) async throws -> [TriviaQuestion]
}

public extension AIConversationProviding {
    /// Convenience overload for callers that don't supply conversation history.
    func chatReply(
        userMessage: String,
        activityTitle: String,
        topic: String,
        type: ActivityType
    ) async throws -> String {
        try await chatReply(
            userMessage: userMessage,
            history: [],
            activityTitle: activityTitle,
            topic: topic,
            type: type
        )
    }
}

public protocol NotificationScheduling: Sendable {
    func schedule(_ message: NotificationMessage, id: String, on day: Date) async
}

public protocol DateProviding: Sendable {
    var now: Date { get }
}

public struct SystemDateProvider: DateProviding {
    public init() {}
    public var now: Date { Date() }
}

public struct AgendaStorageSnapshot: Codable, Sendable, Equatable {
    public let activities: [Activity]
    public let sessions: [ActivitySession]

    public init(activities: [Activity], sessions: [ActivitySession]) {
        self.activities = activities
        self.sessions = sessions
    }
}

public protocol AgendaPersistenceProviding: Sendable {
    func load() throws -> AgendaStorageSnapshot?
    func save(_ snapshot: AgendaStorageSnapshot) throws
}
