import Foundation

public protocol OpenSourceKnowledgeProviding: Sendable {
    func answer(for query: String) async -> String?
}

public enum LocalAgentConfiguration: Sendable {
    case automatic
    case provided((any LocalAcademicAgentProviding)?)
}

public struct AppleIntelligenceService: AppleIntelligenceProviding {
    private let fallback = LocalFallbackGenerator()
    private let localAgent: LocalAcademicAgentProviding?
    private let openSourceKnowledge: OpenSourceKnowledgeProviding

    public init(
        localAgentConfiguration: LocalAgentConfiguration = .automatic,
        openSourceKnowledge: OpenSourceKnowledgeProviding = OpenSourceKnowledgeService()
    ) {
        switch localAgentConfiguration {
        case .automatic:
            self.localAgent = AppleIntelligenceService.makeDefaultLocalAgent()
        case let .provided(agent):
            self.localAgent = agent
        }
        self.openSourceKnowledge = openSourceKnowledge
    }

    public func supportMaterial(for topic: String, type: ActivityType) async throws -> [String] {
        let safeTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeTopic.isEmpty else { return fallback.defaultSupportMaterial(for: "tema general") }

        if let localAgent,
           let localResult = try? await localAgent.supportMaterial(for: safeTopic, type: type),
           !localResult.isEmpty {
            return localResult
        }

        switch type {
        case .task, .study:
            return fallback.defaultSupportMaterial(for: safeTopic)
        case .other:
            return []
        }
    }

    public func chatReply(
        userMessage: String,
        activityTitle: String,
        topic: String,
        type: ActivityType
    ) async throws -> String {
        let cleanedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTitle = activityTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if let localAgent,
           let reply = try? await localAgent.chatReply(
               userMessage: cleanedMessage,
               activityTitle: cleanedTitle,
               topic: cleanedTopic,
               type: type
            ),
            !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return reply
        }

        let fallbackQuery = [cleanedTitle, cleanedTopic]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        let query = cleanedMessage.isEmpty ? fallbackQuery : cleanedMessage
        if let openAnswer = await openSourceKnowledge.answer(for: query),
           !openAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return openAnswer
        }

        switch type {
        case .task:
            return "Claro. Para \"\(cleanedTitle)\", puedo ayudarte a resolver cualquier duda paso a paso, estructurar respuestas y revisar lo que escribas."
        case .study:
            return "Perfecto. Sobre \"\(cleanedTitle)\", puedo explicarte conceptos, hacer resúmenes, proponer preguntas de práctica y ayudarte con ejemplos."
        case .other:
            return "Listo. En \"\(cleanedTitle)\", puedo apoyarte con ideas, redacción, investigación y resolución de dudas en tiempo real."
        }
    }

    public func triviaQuestions(
        count: Int,
        categories: [TriviaCategory],
        difficulty: Int
    ) async throws -> [TriviaQuestion] {
        let validatedCount = max(1, count)
        let validatedCategories = categories.isEmpty ? TriviaCategory.allCases : categories
        let validatedDifficulty = min(max(difficulty, 1), 5)

        if let localAgent,
           let localQuestions = try? await localAgent.triviaQuestions(
               count: validatedCount,
               categories: validatedCategories,
               difficulty: validatedDifficulty
           ),
           !localQuestions.isEmpty {
            return localQuestions
        }

        return fallback.defaultQuestions(
            count: validatedCount,
            categories: validatedCategories,
            difficulty: validatedDifficulty
        )
    }
}

private extension AppleIntelligenceService {
    static func makeDefaultLocalAgent() -> LocalAcademicAgentProviding? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 15.0, *) {
            return FoundationModelsLocalAgent()
        }
        #endif
        return nil
    }
}

struct LocalFallbackGenerator {
    func defaultSupportMaterial(for topic: String) -> [String] {
        [
            "Resumen guiado sobre \(topic).",
            "Lista de conceptos clave para estudiar \(topic).",
            "Ejercicios de práctica progresiva para \(topic)."
        ]
    }

    func defaultQuestions(
        count: Int,
        categories: [TriviaCategory],
        difficulty: Int
    ) -> [TriviaQuestion] {
        var result: [TriviaQuestion] = []
        let base = questionBank(difficulty: difficulty)
        let cycle = categories.isEmpty ? TriviaCategory.allCases : categories

        for index in 0..<count {
            let category = cycle[index % cycle.count]
            let pool = base[category] ?? []
            if let question = pool[safe: index % max(pool.count, 1)] {
                result.append(question)
            }
        }
        return result
    }

    private func questionBank(difficulty _: Int) -> [TriviaCategory: [TriviaQuestion]] {
        return [
            .math: [
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuánto es (5 * 6) + 8 - 2?",
                    options: ["26", "36", "30", "20"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Resultado de 2 + 2 * 3?",
                    options: ["12", "8", "6", "10"],
                    correctOptionIndex: 1
                )
            ],
            .history: [
                TriviaQuestion(
                    category: .history,
                    prompt: "¿En qué año llegó Cristóbal Colón a América?",
                    options: ["1492", "1502", "1450", "1521"],
                    correctOptionIndex: 0
                )
            ],
            .science: [
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Cuál es el símbolo químico del cobre?",
                    options: ["Co", "Cu", "Cr", "Cp"],
                    correctOptionIndex: 1
                )
            ],
            .popCulture: [
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿En qué año se estrenó Star Wars: Episode IV?",
                    options: ["1972", "1977", "1980", "1983"],
                    correctOptionIndex: 1
                )
            ]
        ]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
