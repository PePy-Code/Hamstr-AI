import Foundation

public enum ActivityType: String, Codable, Sendable, CaseIterable {
    case task
    case study
    case other
}

public enum ActivityStatus: String, Codable, Sendable {
    case notStarted
    case pending
    case inProgress
    case completed
    case failed
}

public struct Activity: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public var title: String
    public var topic: String
    public var type: ActivityType
    public var status: ActivityStatus
    public var scheduledAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        topic: String,
        type: ActivityType,
        status: ActivityStatus = .notStarted,
        scheduledAt: Date
    ) {
        self.id = id
        self.title = title
        self.topic = topic
        self.type = type
        self.status = status
        self.scheduledAt = scheduledAt
    }
}

public struct ActivitySession: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let activityID: UUID
    public let startedAt: Date
    public var endedAt: Date?
    public let pomodoroLengthMinutes: Int
    public let supportMaterial: [String]

    public init(
        id: UUID = UUID(),
        activityID: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        pomodoroLengthMinutes: Int = 25,
        supportMaterial: [String] = []
    ) {
        self.id = id
        self.activityID = activityID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pomodoroLengthMinutes = pomodoroLengthMinutes
        self.supportMaterial = supportMaterial
    }
}

public enum TriviaCategory: String, Codable, Sendable, CaseIterable {
    case math
    case history
    case science
    case popCulture
}

public struct TriviaQuestion: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let category: TriviaCategory
    public let prompt: String
    public let options: [String]
    public let correctOptionIndex: Int
    public let imageURL: URL?

    public init(
        id: UUID = UUID(),
        category: TriviaCategory,
        prompt: String,
        options: [String],
        correctOptionIndex: Int,
        imageURL: URL? = nil
    ) {
        self.id = id
        self.category = category
        self.prompt = prompt
        self.options = options
        self.correctOptionIndex = correctOptionIndex
        self.imageURL = imageURL
    }
}

public struct TriviaAttempt: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let startedAt: Date
    public var endedAt: Date?
    public var correctAnswers: Int
    public var incorrectAnswers: Int
    public var highestGlobalScore: Int

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        correctAnswers: Int = 0,
        incorrectAnswers: Int = 0,
        highestGlobalScore: Int = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.correctAnswers = correctAnswers
        self.incorrectAnswers = incorrectAnswers
        self.highestGlobalScore = highestGlobalScore
    }
}

public enum StreakValidationReason: String, Codable, Sendable {
    case allScheduledActivitiesCompleted
    case mentalTrainingOnNoAgendaDay
    case incompleteDay
}

public struct StreakState: Codable, Sendable, Equatable {
    public var days: Int
    public var lastValidatedDay: Date?
    public var reason: StreakValidationReason

    public init(days: Int = 0, lastValidatedDay: Date? = nil, reason: StreakValidationReason = .incompleteDay) {
        self.days = days
        self.lastValidatedDay = lastValidatedDay
        self.reason = reason
    }
}

public struct DailyEvaluationInput: Sendable {
    public let day: Date
    public let scheduledActivities: [Activity]
    public let validMentalTrainingCompletions: Int

    public init(day: Date, scheduledActivities: [Activity], validMentalTrainingCompletions: Int) {
        self.day = day
        self.scheduledActivities = scheduledActivities
        self.validMentalTrainingCompletions = validMentalTrainingCompletions
    }
}

public struct NotificationMessage: Sendable, Equatable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}
