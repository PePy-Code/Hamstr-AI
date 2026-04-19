import Foundation

public protocol OpenSourceKnowledgeProviding: Sendable {
    func answer(for query: String) async -> String?
}

public struct AIConversationService: AIConversationProviding {
    private let fallback = LocalFallbackGenerator()
    private let openSourceKnowledge: OpenSourceKnowledgeProviding

    public init(
        openSourceKnowledge: OpenSourceKnowledgeProviding = OpenSourceKnowledgeService()
    ) {
        self.openSourceKnowledge = openSourceKnowledge
    }

    public func supportMaterial(for topic: String, type: ActivityType) async throws -> [String] {
        let safeTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeTopic.isEmpty else { return fallback.defaultSupportMaterial(for: "tema general") }

        if let openAnswer = await openSourceKnowledge.answer(for: "Material de apoyo para: \(safeTopic)") {
            let suggestions = openAnswer
                .components(separatedBy: CharacterSet(charactersIn: ".\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !suggestions.isEmpty {
                return Array(suggestions.prefix(3))
            }
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
        let query = cleanedMessage.isEmpty ? [cleanedTitle, cleanedTopic]
            .filter { !$0.isEmpty }
            .joined(separator: " - ") : cleanedMessage
        let displayContext = query.isEmpty ? "tu actividad actual" : query
        if let openAnswer = await openSourceKnowledge.answer(for: query),
           !openAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return openAnswer
        }

        return fallbackChatReply(title: cleanedTitle, context: displayContext)
    }

    public func triviaQuestions(
        count: Int,
        categories: [TriviaCategory],
        difficulty: Int
    ) async throws -> [TriviaQuestion] {
        let validatedCount = max(1, count)
        let validatedCategories = categories.isEmpty ? TriviaCategory.allCases : categories
        let validatedDifficulty = min(max(difficulty, 1), 5)

        return fallback.defaultQuestions(
            count: validatedCount,
            categories: validatedCategories,
            difficulty: validatedDifficulty
        )
    }
}

private extension AIConversationService {
    func fallbackChatReply(title: String, context: String) -> String {
        let safeTitle = title.isEmpty ? "tu actividad" : title
        return """
        Entendido. Puedo ayudarte con "\(safeTitle)" y responder directamente tu consulta sobre "\(context)".
        Si quieres, dime la pregunta exacta o comparte más contexto para darte una respuesta más precisa.
        """
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
