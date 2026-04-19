import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenSourceKnowledgeService: OpenSourceKnowledgeProviding {
    private let session: URLSession

    public init() {
        self.session = OpenSourceKnowledgeService.makeSession()
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func answer(for query: String) async -> String? {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return nil }

        if let answer = try? await duckDuckGoAnswer(for: cleanQuery) {
            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let answer = try? await wikipediaAnswer(for: cleanQuery) {
            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        return nil
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
