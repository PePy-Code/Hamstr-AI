import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenSourceKnowledgeService: OpenSourceKnowledgeProviding {
    public init() {}

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
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            guard
                let payload = try JSONSerialization.jsonObject(with: data) as? [Any],
                payload.count >= 4,
                let titles = payload[1] as? [String],
                let extracts = payload[2] as? [String],
                let links = payload[3] as? [String]
            else {
                return nil
            }

            let title = titles.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let extract = extracts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let link = links.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Wikipedia"
            guard !extract.isEmpty else { return nil }
            if title.isEmpty {
                return "\(extract)\n\nFuente abierta: \(link)"
            }
            return "\(title): \(extract)\n\nFuente abierta: \(link)"
        } catch {
            return nil
        }
    }
}
