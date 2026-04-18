import Foundation

enum LocalAgentResponseParser {
    static func parseSupportMaterial(from response: String, limit: Int) -> [String] {
        let json = extractJSONPayload(from: response) ?? response
        guard let data = json.data(using: .utf8) else { return [] }

        if let payload = try? JSONDecoder().decode(SupportMaterialPayload.self, from: data) {
            if let material = payload.material, !material.isEmpty {
                let rows = material
                    .map { item in
                        let point = item.point.trimmingCharacters(in: .whitespacesAndNewlines)
                        let source = item.source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        guard !source.isEmpty else { return point }
                        return "\(point) Fuente: \(source)"
                    }
                    .filter { !$0.isEmpty }
                return Array(rows.prefix(limit))
            }
            if let items = payload.items, !items.isEmpty {
                let rows = items
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return Array(rows.prefix(limit))
            }
        }

        if let items = try? JSONDecoder().decode([String].self, from: data) {
            let rows = items
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Array(rows.prefix(limit))
        }

        return []
    }

    static func parseTriviaQuestions(
        from response: String,
        categories: [TriviaCategory],
        limit: Int
    ) -> [TriviaQuestion] {
        let json = extractJSONPayload(from: response) ?? response
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(TriviaQuestionsPayload.self, from: data) else {
            return []
        }

        let categoryCycle = categories.isEmpty ? TriviaCategory.allCases : categories
        var parsed: [TriviaQuestion] = []
        for (index, item) in payload.questions.enumerated() {
            let prompt = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let options = item.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !prompt.isEmpty, options.count >= 2, options.indices.contains(item.correctOptionIndex) else { continue }

            let category = normalizeCategory(item.category) ?? categoryCycle[index % categoryCycle.count]
            let imageURL = item.imageURL.flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            parsed.append(
                TriviaQuestion(
                    category: category,
                    prompt: prompt,
                    options: options,
                    correctOptionIndex: item.correctOptionIndex,
                    imageURL: imageURL
                )
            )
            if parsed.count >= limit { break }
        }
        return parsed
    }

    private static func normalizeCategory(_ raw: String) -> TriviaCategory? {
        let token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()

        switch token {
        case "math", "matematicas", "matemáticas":
            return .math
        case "history", "historia":
            return .history
        case "science", "ciencia":
            return .science
        case "popculture", "cultura", "culturapop", "pop":
            return .popCulture
        default:
            return TriviaCategory(rawValue: raw)
        }
    }

    private static func extractJSONPayload(from response: String) -> String? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let start = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }),
            let end = trimmed.lastIndex(where: { $0 == "}" || $0 == "]" }),
            start <= end
        else { return nil }
        return String(trimmed[start...end])
    }
}

private struct SupportMaterialPayload: Decodable {
    let material: [SupportMaterialItem]?
    let items: [String]?
}

private struct SupportMaterialItem: Decodable {
    let point: String
    let source: String?
}

private struct TriviaQuestionsPayload: Decodable {
    let questions: [TriviaQuestionDTO]
}

private struct TriviaQuestionDTO: Decodable {
    let category: String
    let prompt: String
    let options: [String]
    let correctOptionIndex: Int
    let imageURL: String?
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 15.0, *)
public struct FoundationModelsLocalAgent: LocalAcademicAgentProviding {
    public init() {}

    public func supportMaterial(for topic: String, type: ActivityType) async throws -> [String] {
        guard type == .study || type == .task else { return [] }
        let session = LanguageModelSession()
        let prompt = """
        Eres un asistente académico. Devuelve SOLO JSON válido sin texto adicional.
        Para el tema "\(topic)", genera 3 elementos de apoyo para \(type.rawValue).
        Requisitos:
        - Español claro para estudiante.
        - Cada elemento debe incluir una fuente útil y concreta.
        Formato estricto:
        {
          "material": [
            { "point": "explicación breve", "source": "https://..." },
            { "point": "explicación breve", "source": "https://..." },
            { "point": "explicación breve", "source": "https://..." }
          ]
        }
        """
        let response = try await session.respond(to: prompt)
        return LocalAgentResponseParser.parseSupportMaterial(from: response, limit: 3)
    }

    public func chatReply(
        userMessage: String,
        activityTitle: String,
        topic: String,
        type: ActivityType
    ) async throws -> String {
        let session = LanguageModelSession()
        let prompt = """
        Eres un tutor académico para jóvenes de 15+.
        Responde en español y en máximo 4 líneas.
        REGLAS:
        - No resuelvas tareas directamente ni entregues respuestas finales.
        - Da orientación, pasos y sugerencias prácticas.
        Contexto:
        - Actividad: "\(activityTitle)"
        - Tema: "\(topic)"
        - Tipo: "\(type.rawValue)"
        Mensaje del estudiante: "\(userMessage)"
        """
        let response = try await session.respond(to: prompt)
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func triviaQuestions(
        count: Int,
        categories: [TriviaCategory],
        difficulty: Int
    ) async throws -> [TriviaQuestion] {
        let validatedCount = max(1, count)
        let validatedDifficulty = min(max(difficulty, 1), 5)
        let validatedCategories = categories.isEmpty ? TriviaCategory.allCases : categories

        let session = LanguageModelSession()
        let categoryPrompt = validatedCategories.map(\.rawValue).joined(separator: ", ")
        let prompt = """
        Eres un generador de trivia educativa. Devuelve SOLO JSON válido sin texto adicional.
        Genera \(validatedCount) preguntas en español con dificultad \(validatedDifficulty) para categorías: \(categoryPrompt).
        Requisitos:
        - 4 opciones por pregunta.
        - Solo una opción correcta.
        - correctOptionIndex debe ser 0...3.
        - category debe ser una de: math, history, science, popCulture.
        Formato estricto:
        {
          "questions": [
            {
              "category": "math",
              "prompt": "pregunta",
              "options": ["A","B","C","D"],
              "correctOptionIndex": 1,
              "imageURL": null
            }
          ]
        }
        """
        let response = try await session.respond(to: prompt)
        return LocalAgentResponseParser.parseTriviaQuestions(
            from: response,
            categories: validatedCategories,
            limit: validatedCount
        )
    }
}
#endif
