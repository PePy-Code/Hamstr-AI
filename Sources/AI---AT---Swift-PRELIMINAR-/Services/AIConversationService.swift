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
        guard !safeTopic.isEmpty else { return [friendlyGreeting()] }

        if let openAnswer = await openSourceKnowledge.answer(for: startSupportPrompt(for: safeTopic)) {
            let directSources = extractDirectSources(from: openAnswer)
            if !directSources.isEmpty { return Array(directSources.prefix(3)) }
        }

        if let openAnswer = await openSourceKnowledge.answer(for: safeTopic) {
            let directSources = extractDirectSources(from: openAnswer)
            if !directSources.isEmpty { return Array(directSources.prefix(3)) }
        }

        switch type {
        case .task, .study:
            return [friendlyGreeting()]
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
        let fallbackQuery = [cleanedTitle, cleanedTopic]
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        let query = cleanedMessage.isEmpty ? fallbackQuery : cleanedMessage
        let displayContext = query.isEmpty ? "tu actividad actual" : query
        let asksToSolveDirectly = isDirectSolveRequest(cleanedMessage)
        if asksToSolveDirectly {
            let sourceQuery = sourceOnlyPrompt(for: displayContext)
            if let sourceAnswer = await openSourceKnowledge.answer(for: sourceQuery) {
                let directSources = extractDirectSources(from: sourceAnswer)
                if !directSources.isEmpty {
                    return refusalWithSources(directSources)
                }
                let cleanedSourceAnswer = sourceAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanedSourceAnswer.isEmpty {
                    return refusalWithoutSources(context: displayContext) + "\n\n" + cleanedSourceAnswer
                }
            }
            return refusalWithoutSources(context: displayContext)
        }

        let guardedQuery = guidedChatPrompt(for: query, activityTitle: cleanedTitle, topic: cleanedTopic)
        if let openAnswer = await openSourceKnowledge.answer(for: query),
           !openAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return openAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let guardedOpenAnswer = await openSourceKnowledge.answer(for: guardedQuery),
           !guardedOpenAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return guardedOpenAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
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

        let prompt = triviaGenerationPrompt(
            count: validatedCount,
            categories: validatedCategories,
            difficulty: validatedDifficulty
        )
        if let generated = await openSourceKnowledge.answer(for: prompt) {
            let parsed = LocalAgentResponseParser.parseTriviaQuestions(
                from: generated,
                categories: validatedCategories,
                limit: validatedCount
            )
            if parsed.count == validatedCount {
                return parsed.shuffled()
            }
        }

        return fallback.defaultQuestions(
            count: validatedCount,
            categories: validatedCategories,
            difficulty: validatedDifficulty
        )
    }
}

private extension AIConversationService {
    func startSupportPrompt(for context: String) -> String {
        """
        Inicio de actividad de estudio: \(context).
        Devuelve hasta 3 fuentes directas confiables (URL completas) para estudiar ese tema.
        Formato preferido por línea: "Fuente directa: https://...".
        Si no encuentras fuentes directas, responde solo: SALUDO_AMIGABLE.
        """
    }

    func guidedChatPrompt(for query: String, activityTitle: String, topic: String) -> String {
        let safeQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = activityTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Contexto de actividad:
        - Título: \(safeTitle.isEmpty ? "sin título" : safeTitle)
        - Tema: \(safeTopic.isEmpty ? "sin tema" : safeTopic)
        Consulta del usuario: \(safeQuery.isEmpty ? "sin consulta explícita" : safeQuery)
        """
    }

    func sourceOnlyPrompt(for context: String) -> String {
        """
        El usuario pidió que le resuelvan una tarea/ejercicio sobre: \(context).
        No resuelvas el trabajo. Devuelve solo fuentes directas de estudio (URLs completas) relacionadas.
        Formato por línea: "Fuente directa: https://...".
        """
    }

    func extractDirectSources(from text: String) -> [String] {
        let pattern = #"https?://[^\s\)\]\}>,]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        let urls = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var seen = Set<String>()
        return urls
            .filter { seen.insert($0).inserted }
            .prefix(3)
            .map { "Fuente directa: \($0)" }
    }

    func isDirectSolveRequest(_ message: String) -> Bool {
        let normalized = " \(message.lowercased()) "
        let solveTokens = [
            " resuelve ", " resuélveme ", " resuélvelo ", " hazme la tarea ", " haz la tarea ", " dame la respuesta ",
            " responde por mí ", " escribe el ensayo ", " dame el resultado ", " soluciona "
        ]
        return solveTokens.contains { normalized.contains($0) }
    }

    func friendlyGreeting() -> String {
        "¡Hola! No encontré fuentes directas ahora mismo, pero puedo ayudarte a enfocar tu estudio paso a paso."
    }

    func refusalWithSources(_ sources: [String]) -> String {
        let bulletList = sources.prefix(3).map { "• \($0)" }.joined(separator: "\n")
        return """
        No puedo resolver tareas o ejercicios por ti, pero sí puedo orientarte con fuentes directas de estudio:
        \(bulletList)
        """
    }

    func refusalWithoutSources(context: String) -> String {
        "No puedo resolver tareas o ejercicios por ti. Si quieres, te guío con un plan de estudio sobre \"\(context)\" y te comparto fuentes directas."
    }

    func fallbackChatReply(title: String, context: String) -> String {
        let safeTitle = title.isEmpty ? "tu actividad" : title
        return """
        Entendido. Puedo ayudarte con "\(safeTitle)" y responder directamente tu consulta sobre "\(context)".
        Si quieres, dime la pregunta exacta o comparte más contexto para darte una respuesta más precisa.
        """
    }

    func triviaGenerationPrompt(count: Int, categories: [TriviaCategory], difficulty: Int) -> String {
        let categoryTokens = categories.map(\.rawValue).joined(separator: ", ")
        return """
        Genera \(count) preguntas de trivia aleatorias en español.
        Categorías permitidas: \(categoryTokens).
        Dificultad aproximada de 1 a 5: \(difficulty).

        Responde ÚNICAMENTE en JSON válido con este formato exacto:
        {
          "questions": [
            {
              "category": "math|history|science|popCulture",
              "prompt": "pregunta",
              "options": ["opción 1","opción 2","opción 3","opción 4"],
              "correctOptionIndex": 0,
              "imageURL": null
            }
          ]
        }

        Reglas obligatorias:
        - Exactamente \(count) preguntas.
        - Cada pregunta con 4 opciones.
        - Solo una opción correcta.
        - correctOptionIndex entre 0 y 3.
        - No incluyas explicación ni texto fuera del JSON.
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
        let base = questionBank(difficulty: difficulty)
        let cycle = categories.isEmpty ? TriviaCategory.allCases : categories
        let available: [TriviaQuestion] = cycle.flatMap { base[$0] ?? [] }.shuffled()
        guard !available.isEmpty else { return [] }

        let targetCount = min(count, available.count)
        var result: [TriviaQuestion] = []
        for index in 0..<targetCount {
            result.append(available[index])
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
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuál es el resultado de 18 ÷ 3 + 2 * 4?",
                    options: ["14", "20", "10", "24"],
                    correctOptionIndex: 0
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuánto da 7 + 3 * (2 + 1)?",
                    options: ["30", "16", "28", "12"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuál es el resultado de 9 * 9?",
                    options: ["72", "99", "81", "90"],
                    correctOptionIndex: 2
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuánto es 144 ÷ 12?",
                    options: ["10", "11", "12", "14"],
                    correctOptionIndex: 2
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Qué valor tiene x en 2x = 18?",
                    options: ["6", "9", "8", "7"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuál es la raíz cuadrada de 64?",
                    options: ["6", "7", "8", "9"],
                    correctOptionIndex: 2
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuánto es 15% de 200?",
                    options: ["20", "30", "35", "40"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Qué número sigue en la secuencia 2, 4, 8, 16, ...?",
                    options: ["18", "20", "24", "32"],
                    correctOptionIndex: 3
                ),
                TriviaQuestion(
                    category: .math,
                    prompt: "¿Cuánto es 3³?",
                    options: ["6", "9", "27", "81"],
                    correctOptionIndex: 2
                )
            ],
            .history: [
                TriviaQuestion(
                    category: .history,
                    prompt: "¿En qué año llegó Cristóbal Colón a América?",
                    options: ["1492", "1502", "1450", "1521"],
                    correctOptionIndex: 0
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿Quién fue el primer presidente de Estados Unidos?",
                    options: ["Abraham Lincoln", "George Washington", "Thomas Jefferson", "John Adams"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿En qué país se construyó originalmente el Muro de Berlín?",
                    options: ["Alemania Oriental", "Alemania Occidental", "Polonia", "Austria"],
                    correctOptionIndex: 0
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿En qué año comenzó la Primera Guerra Mundial?",
                    options: ["1914", "1918", "1939", "1905"],
                    correctOptionIndex: 0
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿Qué civilización construyó Machu Picchu?",
                    options: ["Maya", "Azteca", "Inca", "Romana"],
                    correctOptionIndex: 2
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿Quién lideró la independencia de la India con la no violencia?",
                    options: ["Nehru", "Gandhi", "Mandela", "Churchill"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿Qué imperio fue gobernado por Julio César?",
                    options: ["Romano", "Bizantino", "Otomano", "Persa"],
                    correctOptionIndex: 0
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿En qué año cayó el Muro de Berlín?",
                    options: ["1985", "1989", "1991", "1995"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .history,
                    prompt: "¿Qué país tuvo la Revolución de 1789?",
                    options: ["Italia", "España", "Francia", "Alemania"],
                    correctOptionIndex: 2
                )
            ],
            .science: [
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Cuál es el símbolo químico del cobre?",
                    options: ["Co", "Cu", "Cr", "Cp"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Qué planeta es conocido como el planeta rojo?",
                    options: ["Venus", "Marte", "Júpiter", "Saturno"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Cuál es el órgano que bombea la sangre?",
                    options: ["Pulmón", "Hígado", "Riñón", "Corazón"],
                    correctOptionIndex: 3
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Qué gas respiramos principalmente del aire?",
                    options: ["Oxígeno", "Nitrógeno", "CO2", "Helio"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Cómo se llama el proceso por el cual las plantas producen su alimento?",
                    options: ["Fermentación", "Respiración", "Fotosíntesis", "Transpiración"],
                    correctOptionIndex: 2
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Cuántos huesos tiene un adulto aproximadamente?",
                    options: ["206", "180", "230", "250"],
                    correctOptionIndex: 0
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Qué unidad mide la fuerza en el SI?",
                    options: ["Pascal", "Joule", "Newton", "Watt"],
                    correctOptionIndex: 2
                ),
                TriviaQuestion(
                    category: .science,
                    prompt: "¿Cuál es la estrella del sistema solar?",
                    options: ["Sirio", "La Luna", "El Sol", "Polaris"],
                    correctOptionIndex: 2
                )
            ],
            .popCulture: [
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿En qué año se estrenó Star Wars: Episode IV?",
                    options: ["1972", "1977", "1980", "1983"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Qué saga incluye al personaje Harry Potter?",
                    options: ["Narnia", "Harry Potter", "Percy Jackson", "Dune"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Cuál de estos personajes pertenece a Marvel?",
                    options: ["Batman", "Spider-Man", "Shrek", "Sherlock Holmes"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Qué videojuego popular incluye bloques y construcción libre?",
                    options: ["FIFA", "Minecraft", "Pac-Man", "Tetris"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Qué banda lanzó el álbum 'Abbey Road'?",
                    options: ["Queen", "The Beatles", "Nirvana", "ABBA"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Cuál es el apellido de la familia en 'Los Simpson'?",
                    options: ["Smith", "Simpson", "Johnson", "Brown"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Qué personaje dice 'Yo soy tu padre' en Star Wars?",
                    options: ["Yoda", "Luke", "Obi-Wan", "Darth Vader"],
                    correctOptionIndex: 3
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿Qué superhéroe usa el alias de Bruce Wayne?",
                    options: ["Superman", "Batman", "Flash", "Aquaman"],
                    correctOptionIndex: 1
                ),
                TriviaQuestion(
                    category: .popCulture,
                    prompt: "¿En qué saga aparece el anillo único?",
                    options: ["Star Trek", "Harry Potter", "El Señor de los Anillos", "Matrix"],
                    correctOptionIndex: 2
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
