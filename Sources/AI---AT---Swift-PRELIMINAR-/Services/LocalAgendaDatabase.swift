import Foundation

public struct LocalAgendaDatabase: AgendaPersistenceProviding {
    private let fileURL: URL

    public init(
        fileURL: URL? = nil
    ) {
        self.init(fileURL: fileURL, fileManager: .default)
    }

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager
    ) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent("AcademicTrainer", isDirectory: true)
        self.fileURL = fileURL ?? directoryURL.appendingPathComponent("agenda.json")
    }

    public func load() throws -> AgendaStorageSnapshot? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgendaStorageSnapshot.self, from: data)
    }

    public func save(_ snapshot: AgendaStorageSnapshot) throws {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
