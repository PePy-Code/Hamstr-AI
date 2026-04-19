import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct OpenSourceKnowledgeService: OpenSourceKnowledgeProviding {
    func answer(for query: String) async -> String? {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return nil }

        guard let encoded = cleanQuery.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        let urlString = "https://es.wikipedia.org/api/rest_v1/page/summary/\(encoded)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            let payload = try JSONDecoder().decode(WikipediaSummaryPayload.self, from: data)
            let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let extract = payload.extract?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !extract.isEmpty else { return nil }
            if title.isEmpty {
                return "\(extract)\n\nFuente abierta: Wikipedia"
            }
            return "\(title): \(extract)\n\nFuente abierta: Wikipedia"
        } catch {
            return nil
        }
    }
}

private struct WikipediaSummaryPayload: Decodable {
    let title: String?
    let extract: String?
}
