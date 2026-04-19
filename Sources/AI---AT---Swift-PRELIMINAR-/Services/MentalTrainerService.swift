import Foundation

public enum MentalTrainerError: Error, Sendable {
    case unableToGenerateUniqueQuestion
}

public struct TriviaFeedback: Sendable, Equatable {
    public let isCorrect: Bool
    public let correctOptionIndex: Int
    public let currentCorrectAnswers: Int
    public let shouldShowRetry: Bool
    public let isGameOver: Bool
    public let isWin: Bool

    public init(
        isCorrect: Bool,
        correctOptionIndex: Int,
        currentCorrectAnswers: Int,
        shouldShowRetry: Bool,
        isGameOver: Bool,
        isWin: Bool
    ) {
        self.isCorrect = isCorrect
        self.correctOptionIndex = correctOptionIndex
        self.currentCorrectAnswers = currentCorrectAnswers
        self.shouldShowRetry = shouldShowRetry
        self.isGameOver = isGameOver
        self.isWin = isWin
    }
}

public struct ActiveTriviaSession: Sendable {
    public let attempt: TriviaAttempt
    public let questions: [TriviaQuestion]
    public let usedQuestionFingerprints: Set<String>
    public let generationBatchSize: Int
    public var currentIndex: Int
    public var deadline: Date

    public init(
        attempt: TriviaAttempt,
        questions: [TriviaQuestion],
        usedQuestionFingerprints: Set<String>,
        generationBatchSize: Int,
        currentIndex: Int,
        deadline: Date
    ) {
        self.attempt = attempt
        self.questions = questions
        self.usedQuestionFingerprints = usedQuestionFingerprints
        self.generationBatchSize = generationBatchSize
        self.currentIndex = currentIndex
        self.deadline = deadline
    }
}

public actor MentalTrainerService {
    /// Puntaje mínimo (respuestas correctas) para registrar la racha diaria del trainer
    /// cuando no hay actividades agendadas en el día.
    public static let trainerScoreThresholdForDailyStreak = 8
    public static let defaultQuestionTimeoutSeconds: TimeInterval = 15
    private let trainerCategories: [TriviaCategory] = [.math, .history, .science, .popCulture]
    private let maxGenerationRetries = 10
    private static let highestScoreKey = "mental-trainer-highest-score"
    private let intelligence: AIConversationProviding
    private let dateProvider: DateProviding
    private(set) var highestGlobalScore: Int = 0
    private(set) var activeSession: ActiveTriviaSession?
    private let questionTimeout: TimeInterval = MentalTrainerService.defaultQuestionTimeoutSeconds

    public init(
        intelligence: AIConversationProviding = AIConversationService(),
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.intelligence = intelligence
        self.dateProvider = dateProvider
        self.highestGlobalScore = UserDefaults.standard.integer(forKey: Self.highestScoreKey)
    }

    public func startSession(questionCount: Int = 10) async throws -> ActiveTriviaSession {
        let now = dateProvider.now
        let batchSize = max(questionCount, 1)
        let firstQuestion = try await nextUniqueQuestion(
            excluding: [],
            batchSize: batchSize
        )
        let questions = [firstQuestion]
        let firstFingerprint = questionFingerprint(for: firstQuestion)
        let attempt = TriviaAttempt(startedAt: now, highestGlobalScore: highestGlobalScore)
        let session = ActiveTriviaSession(
            attempt: attempt,
            questions: questions,
            usedQuestionFingerprints: [firstFingerprint],
            generationBatchSize: batchSize,
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

    public func submitAnswer(optionIndex: Int, answeredAt: Date) async throws -> TriviaFeedback? {
        guard var session = activeSession, session.currentIndex < session.questions.count else { return nil }
        let question = session.questions[session.currentIndex]
        let timedOut = answeredAt > session.deadline
        let isCorrect = !timedOut && optionIndex == question.correctOptionIndex

        var attempt = session.attempt
        if isCorrect {
            attempt.correctAnswers += 1
            if attempt.correctAnswers > highestGlobalScore {
                highestGlobalScore = attempt.correctAnswers
                UserDefaults.standard.set(highestGlobalScore, forKey: Self.highestScoreKey)
            }
        } else {
            attempt.incorrectAnswers += 1
        }

        let shouldEndGame = !isCorrect
        if shouldEndGame {
            attempt.endedAt = answeredAt
            attempt.highestGlobalScore = highestGlobalScore
            activeSession = nil
        } else {
            let nextQuestion = try await nextUniqueQuestion(
                excluding: session.usedQuestionFingerprints,
                batchSize: session.generationBatchSize
            )
            let nextFingerprint = questionFingerprint(for: nextQuestion)
            let updatedQuestions = session.questions + [nextQuestion]
            let updatedFingerprints = session.usedQuestionFingerprints.union([nextFingerprint])
            session.currentIndex += 1
            session.deadline = answeredAt.addingTimeInterval(questionTimeout)
            session = ActiveTriviaSession(
                attempt: attempt,
                questions: updatedQuestions,
                usedQuestionFingerprints: updatedFingerprints,
                generationBatchSize: session.generationBatchSize,
                currentIndex: session.currentIndex,
                deadline: session.deadline
            )
            activeSession = session
        }

        return TriviaFeedback(
            isCorrect: isCorrect,
            correctOptionIndex: question.correctOptionIndex,
            currentCorrectAnswers: attempt.correctAnswers,
            shouldShowRetry: false,
            isGameOver: shouldEndGame,
            isWin: false
        )
    }

    public func qualifiesForStreak() -> Bool {
        guard let session = activeSession else { return false }
        return session.attempt.correctAnswers >= Self.trainerScoreThresholdForDailyStreak
    }

    public func bestScore() -> Int {
        highestGlobalScore
    }
}

private extension MentalTrainerService {
    func nextUniqueQuestion(excluding usedFingerprints: Set<String>, batchSize: Int) async throws -> TriviaQuestion {
        let requestedCount = max(batchSize, 3)
        var fallbackCandidate: TriviaQuestion?

        for _ in 0..<maxGenerationRetries {
            let generated = try await intelligence.triviaQuestions(
                count: requestedCount,
                categories: trainerCategories,
                difficulty: 2
            )
            for candidate in generated.shuffled() {
                guard candidate.options.count == 4 else { continue }
                if fallbackCandidate == nil {
                    fallbackCandidate = candidate
                }
                let fingerprint = questionFingerprint(for: candidate)
                if !usedFingerprints.contains(fingerprint) {
                    return candidate
                }
            }
        }
        if let fallbackCandidate {
            return fallbackCandidate
        }
        throw MentalTrainerError.unableToGenerateUniqueQuestion
    }

    func questionFingerprint(for question: TriviaQuestion) -> String {
        var hasher = Hasher()
        hasher.combine(question.category.rawValue)
        hasher.combine(question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        for option in question.options {
            hasher.combine(option.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        hasher.combine(question.correctOptionIndex)
        return String(hasher.finalize())
    }
}
