import Foundation

enum LocalAgentResponseParser {
    static func parseSupportMaterial(from response: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }

        for candidate in jsonPayloadCandidates(from: response) {
            guard let data = candidate.data(using: .utf8) else { continue }

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
                    if !rows.isEmpty { return Array(rows.prefix(limit)) }
                }
                if let items = payload.items, !items.isEmpty {
                    let rows = items
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if !rows.isEmpty { return Array(rows.prefix(limit)) }
                }
            }

            if let items = try? JSONDecoder().decode([String].self, from: data) {
                let rows = items
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !rows.isEmpty { return Array(rows.prefix(limit)) }
            }   
        }

        return []
    }

    static func parseTriviaQuestions(
        from response: String,
        categories: [TriviaCategory],
        limit: Int
    ) -> [TriviaQuestion] {
        guard limit > 0 else { return [] }

        var payload: TriviaQuestionsPayload?
        for candidate in jsonPayloadCandidates(from: response) {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(TriviaQuestionsPayload.self, from: data) {
                payload = decoded
                break
            }
        }
        guard let payload else { return [] }

        let categoryCycle = categories.isEmpty ? TriviaCategory.allCases : categories
        var parsed: [TriviaQuestion] = []
        for (index, item) in payload.questions.enumerated() {
            let prompt = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let options = item.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !prompt.isEmpty, options.count == 4, (0...3).contains(item.correctOptionIndex) else { continue }

            let category = normalizeCategory(item.category) ?? categoryCycle[index % categoryCycle.count]
            let imageURL = safeHTTPURL(from: item.imageURL)
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

    private static func safeHTTPURL(from raw: String?) -> URL? {
        guard
            let raw,
            !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
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
        guard let start = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }

        var stack: [Character] = []
        var inString = false
        var isEscaped = false

        for index in trimmed[start...].indices {
            let char = trimmed[index]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if char == "\\" {
                    isEscaped = true
                } else if char == "\"" {
                    inString = false
                }
                continue
            }

            if char == "\"" {
                inString = true
                continue
            }

            if char == "{" || char == "[" {
                stack.append(char)
                continue
            }

            if char == "}" || char == "]" {
                guard let last = stack.last else { return nil }
                let isMatchingPair = (last == "{" && char == "}") || (last == "[" && char == "]")
                guard isMatchingPair else { return nil }
                stack.removeLast()
                if stack.isEmpty { return String(trimmed[start...index]) }
            }
        }
        return nil
    }

    private static func extractFencedContent(from response: String) -> String? {
        guard
            let openingFence = response.range(of: "```"),
            let closingFence = response.range(of: "```", range: openingFence.upperBound..<response.endIndex)
        else { return nil }

        let content = response[openingFence.upperBound..<closingFence.lowerBound]
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("json") {
            let jsonStart = normalized.index(normalized.startIndex, offsetBy: 4)
            return normalized[jsonStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalized
    }

    private static func jsonPayloadCandidates(from response: String) -> [String] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = []
        if !trimmed.isEmpty { candidates.append(trimmed) }
        if let fenced = extractFencedContent(from: trimmed), !fenced.isEmpty { candidates.append(fenced) }
        if let extracted = extractJSONPayload(from: trimmed), !extracted.isEmpty { candidates.append(extracted) }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
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
        return LocalAgentResponseParser.parseSupportMaterial(from: response.content, limit: 3)
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
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
            from: response.content,
            categories: validatedCategories,
            limit: validatedCount
        )
    }
}
#endif
