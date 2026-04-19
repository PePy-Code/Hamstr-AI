import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenSourceKnowledgeService: OpenSourceKnowledgeProviding {
    private let session: URLSession
    private let groqAPIKey: String?
    private let groqModel: String

    public init() {
        self.session = OpenSourceKnowledgeService.makeSession()
        self.groqAPIKey = OpenSourceKnowledgeService.resolveGroqAPIKey()
        self.groqModel = "llama-3.3-70b-versatile"
    }

    public init(session: URLSession) {
        self.session = session
        self.groqAPIKey = OpenSourceKnowledgeService.resolveGroqAPIKey()
        self.groqModel = "llama-3.3-70b-versatile"
    }

    init(session: URLSession, groqAPIKey: String?, groqModel: String = "llama-3.3-70b-versatile") {
        self.session = session
        self.groqAPIKey = groqAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.groqModel = groqModel
    }

    public func answer(for query: String) async -> String? {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return nil }

        let queryCandidates = normalizedQueryCandidates(from: cleanQuery)
        let webEvidence = await collectWebEvidence(from: queryCandidates)
        let webLinks = extractLinks(from: webEvidence)

        if let answer = try? await groqAnswer(for: cleanQuery, webEvidence: webEvidence) {
            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return ensureHyperlinks(in: trimmed, links: webLinks)
            }
        }

        for candidate in queryCandidates {
            if let answer = try? await duckDuckGoAnswer(for: candidate) {
                let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return ensureSpanishResponse(trimmed) }
            }
        }

        for candidate in queryCandidates {
            if let answer = try? await wikipediaAnswer(for: candidate) {
                let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return ensureSpanishResponse(trimmed) }
            }
        }

        return nil
    }

    private func groqAnswer(for query: String, webEvidence: [String]) async throws -> String? {
        guard let key = groqAPIKey, !key.isEmpty else { return nil }
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else { return nil }
        let normalizedEvidence = webEvidence
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let evidenceBlock: String
        if normalizedEvidence.isEmpty {
            evidenceBlock = "No se recuperaron fuentes web en tiempo real para esta consulta."
        } else {
            evidenceBlock = normalizedEvidence.prefix(3).enumerated().map { index, item in
                "\(index + 1). \(item)"
            }.joined(separator: "\n")
        }

        let requestPayload = GroqChatRequest(
            model: groqModel,
            messages: [
                .init(
                    role: "system",
                    content: """
                    Eres Roedor, la mascota IA de este app — un roedor amigable, curioso y directo que apoya a estudiantes.
                    Tu tono es cercano y natural, como un amigo que sabe del tema, no un asistente corporativo.
                    Responde siempre en español. Sé breve y concreto: di lo esencial sin relleno innecesario.
                    Deja una línea en blanco entre párrafos o bloques de ideas para que sea fácil de leer.
                    Usa listas cortas (•) solo cuando realmente ayude a organizar la información.
                    No resuelvas tareas, ejercicios, exámenes o trabajos completos — orienta al estudiante con pistas y fuentes.
                    Si el usuario pide resolver algo directamente, rechaza con amabilidad y ofrece fuentes directas de estudio (URLs completas).
                    Si cuentas con enlaces de fuentes, inclúyelos en formato markdown: [texto](https://...).
                    Si no sabes algo, dilo con honestidad y sugiere dónde buscar.
                    """
                ),
                .init(
                    role: "user",
                    content: """
                    Consulta del usuario: \(query)

                    Contexto de navegación web recuperado:
                    \(evidenceBlock)

                    Si en el contexto hay URLs, inclúyelas al responder.
                    """
                )
            ],
            temperature: 0.2,
            maxTokens: nil
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestPayload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        let payload = try JSONDecoder().decode(GroqChatResponse.self, from: data)
        return payload.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func duckDuckGoAnswer(for query: String) async throws -> String? {
        var components = URLComponents(string: "https://api.duckduckgo.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
            URLQueryItem(name: "no_redirect", value: "1")
        ]
        guard let url = components?.url else { return nil }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        let payload = try JSONDecoder().decode(DuckDuckGoInstantAnswerPayload.self, from: data)
        let abstract = payload.abstractText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !abstract.isEmpty {
            let source = payload.abstractURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceSuffix = source.isEmpty ? "" : "\n\nFuente abierta: \(source)"
            return "\(abstract)\(sourceSuffix)"
        }
        if let topic = payload.relatedTopics.firstFlatTopic {
            let text = topic.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = topic.firstURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sourceSuffix = source.isEmpty ? "" : "\n\nFuente abierta: \(source)"
            return "\(text)\(sourceSuffix)"
        }
        return nil
    }

    private func wikipediaAnswer(for query: String) async throws -> String? {
        var components = URLComponents(string: "https://es.wikipedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "namespace", value: "0"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { return nil }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        let payload = try JSONDecoder().decode(WikipediaOpenSearchPayload.self, from: data)
        let title = payload.titles.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let extract = payload.extracts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let link = payload.links.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !extract.isEmpty else { return nil }
        let sourceSuffix = link.isEmpty ? "" : "\n\nFuente abierta: \(link)"
        if title.isEmpty {
            return "\(extract)\(sourceSuffix)"
        }
        return "\(title): \(extract)\(sourceSuffix)"
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        // Keep external API calls responsive in chat UX while allowing short network delays.
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }

    private static func resolveGroqAPIKey() -> String? {
        let envKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let envKey, !envKey.isEmpty { return envKey }

        let localKey = LocalSecrets.groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return localKey.isEmpty ? nil : localKey
    }

    private func normalizedQueryCandidates(from query: String) -> [String] {
        let punctuationStripped = query
            .replacingOccurrences(of: "[¿?¡!.,;:()\\[\\]{}\"'`]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let keywordQuery = compactKeywords(from: punctuationStripped)

        var candidates: [String] = [query]
        if !punctuationStripped.isEmpty { candidates.append(punctuationStripped) }
        if !keywordQuery.isEmpty { candidates.append(keywordQuery) }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.lowercased()).inserted }
    }

    private func compactKeywords(from sentence: String) -> String {
        let stopwords: Set<String> = [
            "quien", "quién", "que", "qué", "cual", "cuál", "como", "cómo", "donde", "dónde",
            "cuando", "cuándo", "por", "para", "de", "del", "la", "el", "los", "las", "un", "una",
            "unos", "unas", "es", "fue", "son", "era", "me", "mi", "mis", "tu", "tus", "su", "sus",
            "al", "a", "en", "y", "o", "se", "lo"
        ]
        let keywords = sentence
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty && !stopwords.contains($0) }
        return keywords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ensureSpanishResponse(_ text: String) -> String {
        guard let groqAPIKey, !groqAPIKey.isEmpty else { return text }
        let spanishCue = [" el ", " la ", " los ", " las ", " de ", " que ", " y ", " en ", "¿", "¡"]
        let normalized = " \(text.lowercased()) "
        if spanishCue.contains(where: { normalized.contains($0) }) {
            return text
        }
        return text + "\n\nNota: Si prefieres, puedo reformular esta respuesta en español."
    }

    private func collectWebEvidence(from candidates: [String]) async -> [String] {
        var evidence: [String] = []
        for candidate in candidates {
            if let ddg = try? await duckDuckGoAnswer(for: candidate) {
                let cleaned = ddg.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    evidence.append(cleaned)
                    break
                }
            }
        }
        for candidate in candidates {
            if let wiki = try? await wikipediaAnswer(for: candidate) {
                let cleaned = wiki.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    evidence.append(cleaned)
                    break
                }
            }
        }
        return evidence
    }

    private func extractLinks(from evidence: [String]) -> [String] {
        let pattern = #"https?://[^\s\)\]\}>,]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        var links: [String] = []
        for entry in evidence {
            let range = NSRange(entry.startIndex..<entry.endIndex, in: entry)
            for match in regex.matches(in: entry, options: [], range: range) {
                guard let swiftRange = Range(match.range, in: entry) else { continue }
                links.append(String(entry[swiftRange]))
            }
        }
        var seen = Set<String>()
        return links.filter { seen.insert($0).inserted }
    }

    private func ensureHyperlinks(in response: String, links: [String]) -> String {
        guard !links.isEmpty else { return response }
        let hasAnyLink = response.contains("http://") || response.contains("https://")
        if hasAnyLink { return response }
        let markdownLinks = links.prefix(3).map { "- [Fuente web](\($0))" }.joined(separator: "\n")
        return response + "\n\nFuentes web:\n" + markdownLinks
    }
}

private struct DuckDuckGoInstantAnswerPayload: Decodable {
    let abstractText: String
    let abstractURL: String
    let relatedTopics: [DuckDuckGoRelatedTopic]

    enum CodingKeys: String, CodingKey {
        case abstractText = "AbstractText"
        case abstractURL = "AbstractURL"
        case relatedTopics = "RelatedTopics"
    }
}

private struct DuckDuckGoRelatedTopic: Decodable {
    let text: String
    let firstURL: String?
    let topics: [DuckDuckGoRelatedTopic]?

    enum CodingKeys: String, CodingKey {
        case text = "Text"
        case firstURL = "FirstURL"
        case topics = "Topics"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        firstURL = try container.decodeIfPresent(String.self, forKey: .firstURL)
        topics = try container.decodeIfPresent([DuckDuckGoRelatedTopic].self, forKey: .topics)
    }
}

private extension Array where Element == DuckDuckGoRelatedTopic {
    var firstFlatTopic: DuckDuckGoRelatedTopic? {
        for item in self {
            if !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return item
            }
            if let nested = item.topics?.firstFlatTopic {
                return nested
            }
        }
        return nil
    }
}

private struct WikipediaOpenSearchPayload: Decodable {
    let titles: [String]
    let extracts: [String]
    let links: [String]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        // Wikipedia OpenSearch returns the original query as the first array element.
        _ = try container.decode(String.self)
        titles = try container.decode([String].self)
        extracts = try container.decode([String].self)
        links = try container.decode([String].self)
    }
}

private struct GroqChatRequest: Encodable {
    let model: String
    let messages: [GroqChatMessage]
    let temperature: Double
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct GroqChatMessage: Codable {
    let role: String
    let content: String
}

private struct GroqChatResponse: Decodable {
    let choices: [GroqChatChoice]
}

private struct GroqChatChoice: Decodable {
    let message: GroqChatMessage
}
