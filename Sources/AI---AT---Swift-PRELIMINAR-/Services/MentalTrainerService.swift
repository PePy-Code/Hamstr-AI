import Foundation

public struct TriviaFeedback: Sendable, Equatable {
    public let isCorrect: Bool
    public let correctOptionIndex: Int
    public let shouldShowRetry: Bool
    public let isGameOver: Bool

    public init(isCorrect: Bool, correctOptionIndex: Int, shouldShowRetry: Bool, isGameOver: Bool) {
        self.isCorrect = isCorrect
        self.correctOptionIndex = correctOptionIndex
        self.shouldShowRetry = shouldShowRetry
        self.isGameOver = isGameOver
    }
}

public struct ActiveTriviaSession: Sendable {
    public let attempt: TriviaAttempt
    public let questions: [TriviaQuestion]
    public var currentIndex: Int
    public var deadline: Date

    public init(attempt: TriviaAttempt, questions: [TriviaQuestion], currentIndex: Int, deadline: Date) {
        self.attempt = attempt
        self.questions = questions
        self.currentIndex = currentIndex
        self.deadline = deadline
    }
}

public actor MentalTrainerService {
    private let intelligence: AppleIntelligenceProviding
    private let dateProvider: DateProviding
    private(set) var highestGlobalScore: Int = 0
    private(set) var activeSession: ActiveTriviaSession?
    private let questionTimeout: TimeInterval = 10

    public init(
        intelligence: AppleIntelligenceProviding = AppleIntelligenceService(),
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.intelligence = intelligence
        self.dateProvider = dateProvider
    }

    public func startSession(questionCount: Int = 10) async throws -> ActiveTriviaSession {
        let now = dateProvider.now
        let generated = try await intelligence.triviaQuestions(
            count: questionCount,
            categories: TriviaCategory.allCases,
            difficulty: 2
        )
        let questions = generated.shuffled()
        let attempt = TriviaAttempt(startedAt: now, highestGlobalScore: highestGlobalScore)
        let session = ActiveTriviaSession(
            attempt: attempt,
            questions: questions,
            currentIndex: 0,
            deadline: now.addingTimeInterval(questionTimeout)
        )
        activeSession = session
        return session
    }

    public func currentQuestion() -> TriviaQuestion? {
        guard
            let session = activeSession,
            session.currentIndex < session.questions.count
        else { return nil }
        return session.questions[session.currentIndex]
    }

    public func submitAnswer(optionIndex: Int, answeredAt: Date) -> TriviaFeedback? {
        guard var session = activeSession, session.currentIndex < session.questions.count else { return nil }
        let question = session.questions[session.currentIndex]
        let timedOut = answeredAt > session.deadline
        let isCorrect = !timedOut && optionIndex == question.correctOptionIndex

        var attempt = session.attempt
        if isCorrect {
            attempt.correctAnswers += 1
            highestGlobalScore = max(highestGlobalScore, attempt.correctAnswers)
        } else {
            attempt.incorrectAnswers += 1
        }

        let shouldEndGame = !isCorrect && attempt.correctAnswers >= 5
        let shouldRetry = !isCorrect && attempt.correctAnswers < 5

        if shouldEndGame {
            attempt.endedAt = answeredAt
            attempt.highestGlobalScore = highestGlobalScore
            activeSession = nil
        } else {
            session.currentIndex += 1
            session.deadline = answeredAt.addingTimeInterval(questionTimeout)
            session = ActiveTriviaSession(
                attempt: attempt,
                questions: session.questions,
                currentIndex: session.currentIndex,
                deadline: session.deadline
            )
            activeSession = session
        }

        return TriviaFeedback(
            isCorrect: isCorrect,
            correctOptionIndex: question.correctOptionIndex,
            shouldShowRetry: shouldRetry,
            isGameOver: shouldEndGame
        )
    }

    public func qualifiesForStreak() -> Bool {
        guard let session = activeSession else { return false }
        return session.attempt.correctAnswers >= 5
    }
}
