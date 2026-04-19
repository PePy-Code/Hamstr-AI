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

        var components = URLComponents(string: "https://es.wikipedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "search", value: cleanQuery),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "namespace", value: "0"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { return nil }

        do {
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
        } catch {
            return nil
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }
}

private struct WikipediaOpenSearchPayload: Decodable {
    let titles: [String]
    let extracts: [String]
    let links: [String]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        _ = try? container.decode(String.self)
        titles = (try? container.decode([String].self)) ?? []
        extracts = (try? container.decode([String].self)) ?? []
        links = (try? container.decode([String].self)) ?? []
    }
}
